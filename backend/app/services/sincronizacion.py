"""El endpoint POST /v1/sync: recibe todo lo que el telefono hizo sin senal.

Orden de escritura, que no es arbitrario porque Airtable necesita los enlaces
resueltos:

    Proyectos -> Mapas -> Trazados -> Waypoints -> Archivos -> Sincronizaciones

Hoy suben los trazados (empezando por las rutas calculadas que se guardan desde
el mapa); el resto de las tablas se suma en este mismo recorrido.

Lo que devuelve importa tanto como lo que escribe: por cada UUID enviado, si
quedo o no y por que. El telefono marca `sincronizado = true` solo los que el
backend confirmo, asi que una subida a medias reintenta exactamente lo que
falto y nada mas.

## El proyecto `local`

El mapa hoy se abre sin proyecto, y lo que se guarda en el telefono cae en el
proyecto `local`, que es una cadena fija y la misma en todos los telefonos. En
Airtable no puede ser una sola fila: mezclaria las rutas de todas las cuentas y
el prefijo de S3 de todas. Por eso se traduce a un proyecto por cuenta,
`local-<Auth UID>`, que se crea la primera vez con el dueno puesto. Asi el
aislamiento sigue colgando de `Dueno Auth UID` como en el resto de la base.
"""

from __future__ import annotations

import asyncio
import json
import uuid
from datetime import datetime, timezone
from typing import Any

from fastapi import HTTPException

from ..config import Settings
from ..schemas_sync import (
    METODOS_CAPTURA,
    TIPOS_TRAZADO,
    ResultadoItem,
    SyncRequest,
    SyncResponse,
    TrazadoSync,
)
from . import airtable, almacenamiento, geometria
from .auth import Identidad, formula_del_duenno

PROYECTO_LOCAL = "local"


class RechazoItem(Exception):
    """Un trazado que no se puede guardar, con el motivo para el telefono.

    Corta ese trazado y no la tanda: que uno venga mal no puede dejar sin subir
    los otros nueve.
    """


async def sincronizar(
    settings: Settings, identidad: Identidad, req: SyncRequest
) -> SyncResponse:
    inicio = datetime.now(timezone.utc)
    usuario = await airtable.buscar_uno(
        settings,
        settings.airtable_tabla_usuarios,
        airtable.formula_codigo("Auth UID", identidad.auth_uid),
    )
    if not usuario:
        # El JWT es valido pero la fila no esta: la borraron a mano. Sin ella no
        # hay a quien colgarle el trabajo, y subirlo huerfano es peor.
        raise HTTPException(
            status_code=403,
            detail="Tu cuenta no esta en la base. Escribinos para revisarla.",
        )

    proyectos: dict[str, tuple[str, str]] = {}
    resultados: list[ResultadoItem] = []
    for t in req.trazados:
        try:
            if t.proyecto_codigo not in proyectos:
                proyectos[t.proyecto_codigo] = await _proyecto(
                    settings, identidad, usuario["id"], t.proyecto_codigo
                )
            codigo_proyecto, proyecto_id = proyectos[t.proyecto_codigo]
            llave = await _trazado(
                settings, t, codigo_proyecto, proyecto_id, usuario["id"]
            )
            resultados.append(ResultadoItem(codigo=t.codigo, ok=True, llave_geometria=llave))
        except (RechazoItem, geometria.GeometriaInvalida) as exc:
            resultados.append(ResultadoItem(codigo=t.codigo, ok=False, error=str(exc)))
        except HTTPException as exc:
            resultados.append(
                ResultadoItem(codigo=t.codigo, ok=False, error=str(exc.detail))
            )
        except Exception as exc:  # noqa: BLE001 -- boto3, red: reintentable.
            resultados.append(
                ResultadoItem(
                    codigo=t.codigo,
                    ok=False,
                    error=f"No se pudo guardar la geometria ({type(exc).__name__}). "
                    "Se reintenta en la proxima sincronizacion.",
                )
            )

    await _anotar(settings, usuario["id"], inicio, resultados)
    return SyncResponse(trazados=resultados)


async def _proyecto(
    settings: Settings, identidad: Identidad, usuario_id: str, codigo: str
) -> tuple[str, str]:
    """El codigo real del proyecto y su record id, verificando que sea suyo."""
    real = _codigo_local(identidad.auth_uid) if codigo == PROYECTO_LOCAL else codigo
    tabla = settings.airtable_tabla_proyectos
    fila = await airtable.buscar_uno(
        settings,
        tabla,
        f"AND({airtable.formula_codigo('Codigo proyecto', real)}, "
        f"{formula_del_duenno(identidad.auth_uid)})",
    )
    if fila:
        return real, fila["id"]

    if codigo != PROYECTO_LOCAL:
        # Mismo mensaje exista o no con otro dueno: no se confirma a nadie que
        # un codigo ajeno existe.
        raise RechazoItem(
            "El proyecto de este trazado todavia no esta en la base. Se reintenta "
            "cuando suba el proyecto."
        )

    creada = await airtable.guardar(
        settings,
        tabla,
        {
            "Codigo proyecto": real,
            "Nombre": "Sin proyecto",
            "Estado": "Activo",
            "Dueno Auth UID": identidad.auth_uid,
            "Dueno": [usuario_id],
        },
        None,
    )
    return real, creada["id"]


def _codigo_local(auth_uid: str) -> str:
    # El Auth UID es el `sub` de Google (digitos) o `pwd_<uuid4>`: ya es seguro
    # como pedazo de llave de S3 y de formula. Se limpia igual por si acaso.
    limpio = "".join(c for c in auth_uid if c.isalnum() or c in "-_")
    return f"{PROYECTO_LOCAL}-{limpio}"


async def _trazado(
    settings: Settings,
    t: TrazadoSync,
    codigo_proyecto: str,
    proyecto_id: str,
    usuario_id: str,
) -> str:
    """Sube un trazado: primero el GeoJSON a S3, despues la fila. Devuelve la llave."""
    puntos = geometria.coordenadas_de_linea(t.geometria)

    tabla = settings.airtable_tabla_trazados
    existente = await airtable.buscar_uno(
        settings, tabla, airtable.formula_codigo("Codigo trazado", t.codigo)
    )
    # El UUID lo genera el telefono, asi que el backend no puede creerle que sea
    # suyo: sin esto, alguien que conozca el codigo de un trazado ajeno lo pisa.
    if existente and proyecto_id not in existente.get("fields", {}).get("Proyecto", []):
        raise RechazoItem("Ese codigo de trazado ya esta usado por otro registro.")

    # Primero S3. Una fila con `Llave geometria` apuntando a un objeto que no
    # existe es un trazado que en la base parece estar y al abrirlo no esta.
    llave = almacenamiento.llave_geometria(codigo_proyecto, t.codigo)
    contenido = json.dumps(t.geometria, separators=(",", ":")).encode()
    await asyncio.to_thread(
        almacenamiento.subir, settings, llave, contenido, "application/geo+json"
    )

    campos: dict[str, Any] = {
        "Codigo trazado": t.codigo,
        "Nombre": t.nombre.strip(),
        "Tipo": TIPOS_TRAZADO[t.tipo],
        "Metodo": METODOS_CAPTURA[t.metodo],
        "Llave geometria": llave,
        "Vista previa": geometria.vista_previa(puntos),
        "Puntos": len(puntos),
        "Proyecto": [proyecto_id],
        "Capturado por": [usuario_id],
    }
    opcionales = {
        "Distancia (m)": _redondeo(t.distancia_m, 1),
        "Area (ha)": _redondeo(t.area_ha, 4),
        "Precision media (m)": _redondeo(t.precision_media_m, 1),
        "Bbox": t.bbox,
        "Centro lat": _redondeo(t.centro_lat, 6),
        "Centro lon": _redondeo(t.centro_lon, 6),
        "Iniciado en": t.iniciado_en.isoformat() if t.iniciado_en else None,
        "Terminado en": t.terminado_en.isoformat() if t.terminado_en else None,
    }
    campos.update({k: v for k, v in opcionales.items() if v is not None})

    await airtable.guardar(settings, tabla, campos, existente["id"] if existente else None)
    return llave


def _redondeo(valor: float | None, decimales: int) -> float | None:
    return None if valor is None else round(valor, decimales)


async def _anotar(
    settings: Settings,
    usuario_id: str,
    inicio: datetime,
    resultados: list[ResultadoItem],
) -> None:
    """La fila de `Sincronizaciones`. Nunca hace fallar la subida.

    Es lo que permite responder "el trazado del martes no aparece" sin adivinar,
    pero si Airtable no la acepta, lo que ya se subio quedo subido igual y el
    telefono tiene que enterarse.
    """
    if not resultados:
        return
    fallidos = [r for r in resultados if not r.ok]
    estado = "Ok" if not fallidos else ("Fallida" if len(fallidos) == len(resultados) else "Parcial")
    try:
        await airtable.guardar(
            settings,
            settings.airtable_tabla_sincronizaciones,
            {
                "Codigo sync": str(uuid.uuid4()),
                "Inicio": inicio.isoformat(),
                "Fin": datetime.now(timezone.utc).isoformat(),
                "Registros enviados": len(resultados),
                "Registros fallidos": len(fallidos),
                "Estado": estado,
                "Detalle": "\n".join(f"{r.codigo}: {r.error}" for r in fallidos) or None,
                "Usuario": [usuario_id],
            },
            None,
        )
    except Exception:  # noqa: BLE001
        pass
