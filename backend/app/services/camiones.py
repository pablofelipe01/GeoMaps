"""El modulo de camiones: tomar una vuelta pendiente de la planilla de vagones,
ir por ella, volver y finalizarla.

## Como se toma una vuelta

El conductor elige una vuelta y la firma **con su clave de GeoMaps**, que dice
que quien tiene el telefono en la mano es el dueno de la cuenta y no alguien
que lo encontro desbloqueado en la cabina. Las cuentas de Google no tienen
clave: para ellas la firma es la sesion, que Google ya verifico.

**La cedula ya no se pide.** Antes era lo que decia que conductor de
SiriusFleet era, y dejaba sin poder trabajar a todo el que no estuviera en ese
registro. Ahora la vuelta queda a nombre de **la cuenta**, y el enlace con el
registro de conductores se resuelve aca sin preguntarle nada a nadie:

1. si la cuenta tiene `Cedula` en Airtable -la carga un administrador-, es el
   conductor con ese documento;
2. si no, el conductor que se llame exactamente igual que la cuenta;
3. si no hay ninguno, la columna Conductor de la planilla queda en blanco y el
   nombre de la cuenta va en Observaciones (`GeoMaps: Fulano`), para que
   despacho vea quien fue.

## Una vuelta a la vez

Tomar una vuelta abre su seguimiento (`services/viajes.py`), y mientras siga
abierto la cuenta no toma otra. Se cierra de dos maneras: **finalizandola**,
que exige haber llegado a los vagones, o **devolviendola** antes de llegar. Las
reglas de distancia -que es "llegar", que es "volver"- las aplica el telefono,
que es el que tiene el GPS; aca se guarda lo que reporta y se cuida el orden.

La clave errada suma al mismo contador de fallos que el login: si no, esta
seria una segunda puerta para probar claves sin limite.
"""

from __future__ import annotations

import asyncio
import re
import unicodedata
import uuid
from datetime import datetime, timezone
from typing import Any

from fastapi import HTTPException

from ..config import Settings
from ..schemas_camiones import (
    Conductor,
    ConfirmarRequest,
    ConfirmarResponse,
    MiViajeResponse,
    SeguimientoRequest,
    SeguimientoResponse,
    ViajeAbierto,
    Vuelta,
    VueltasResponse,
)
from . import airtable, auth, supabase, viajes

# Como se marca en Observaciones quien tomo la vuelta cuando no hay conductor
# de SiriusFleet enlazado.
MARCA_NOTA = "GeoMaps: "


async def _fila_de(settings: Settings, identidad: auth.Identidad) -> dict:
    """La fila de `Usuarios` de quien llama. 403 si ya no existe."""
    fila = await airtable.buscar_uno(
        settings,
        settings.airtable_tabla_usuarios,
        airtable.formula_codigo("Auth UID", identidad.auth_uid),
    )
    if not fila:
        raise HTTPException(
            status_code=403,
            detail="Tu cuenta no esta en la base. Escribinos para revisarla.",
        )
    return fila


def _nombre_cuenta(campos: dict, identidad: auth.Identidad) -> str:
    return (campos.get("Nombre") or identidad.nombre or "").strip() or "Sin nombre"


def _palabras(nombre: str | None) -> frozenset[str]:
    """Las palabras de un nombre, sin tildes ni mayusculas ni orden.

    SiriusFleet escribe `PATARROYO CUFINO LUIS ALFONSO` y la persona se
    registra como `Luis Alfonso Patarroyo Cufino`: son el mismo nombre.
    """
    plano = unicodedata.normalize("NFD", (nombre or "").lower())
    return frozenset(re.findall(r"[a-z0-9]+", plano))


def _operador_de_cuenta(
    campos: dict, nombre: str, operadores: list[dict[str, Any]]
) -> dict[str, Any] | None:
    """El conductor de SiriusFleet que corresponde a esta cuenta, o None."""
    cedula = supabase.solo_digitos(campos.get("Cedula"))
    if cedula:
        for op in operadores:
            if supabase.solo_digitos(op.get("documento")) == cedula:
                return op

    # Por nombre solo si es el mismo nombre entero y no hay dos iguales: con
    # menos que eso -un "Javier" suelto- se le anotaria la vuelta a otro.
    buscadas = _palabras(nombre)
    if len(buscadas) < 2:
        return None
    iguales = [op for op in operadores if _palabras(op.get("nombre")) == buscadas]
    return iguales[0] if len(iguales) == 1 else None


async def _operador(
    settings: Settings, campos: dict, nombre: str
) -> dict[str, Any] | None:
    return _operador_de_cuenta(
        campos, nombre, await supabase.operadores_activos(settings)
    )


def _con_nota(observaciones: str | None, nombre: str) -> str:
    """Las observaciones de despacho, mas quien tomo la vuelta."""
    previas = _sin_nota(observaciones) or ""
    nota = f"{MARCA_NOTA}{nombre}"
    return f"{previas} · {nota}" if previas else nota


def _sin_nota(observaciones: str | None) -> str | None:
    """Las observaciones como las habia dejado despacho, sin nuestra nota."""
    limpio = re.sub(
        rf"\s*(·\s*)?{re.escape(MARCA_NOTA)}[^·]*$", "", observaciones or ""
    ).strip()
    return limpio or None


def _exigir_activa(campos: dict) -> None:
    if campos.get("Estado") == "Suspendida":
        raise HTTPException(
            status_code=403,
            detail="Esta cuenta esta suspendida. Escribinos para reactivarla.",
        )


async def _exigir_clave(settings: Settings, campos: dict, clave: str | None) -> None:
    """La clave, solo a quien tiene una. Una cuenta de Google firma con la
    sesion: ver el encabezado del archivo."""
    if not campos.get("Hash clave"):
        return
    auth.revisar_bloqueo(campos)
    if not clave:
        raise HTTPException(
            status_code=401, detail="Escribi tu clave de GeoMaps para confirmar."
        )
    if not auth.verificar_clave(clave, campos.get("Hash clave")):
        await auth.anotar_intento_fallido(settings, campos)
        raise HTTPException(
            status_code=401,
            detail="La clave no es correcta. Es la misma con la que entras "
            "a GeoMaps.",
        )


async def conductor(settings: Settings, identidad: auth.Identidad) -> Conductor:
    """A nombre de quien quedan las vueltas, y si hay que pedirle clave."""
    campos = (await _fila_de(settings, identidad)).get("fields", {})
    nombre = _nombre_cuenta(campos, identidad)
    try:
        operador = await _operador(settings, campos, nombre)
    except Exception:  # noqa: BLE001 -- sin el registro, el nombre de la cuenta.
        operador = None
    return Conductor(
        nombre=operador["nombre"] if operador else nombre,
        pide_clave=bool(campos.get("Hash clave")),
    )


async def _vuelta_de(settings: Settings, vuelta_id: str) -> Vuelta | None:
    """El renglon de la planilla, o None si no se pudo leer."""
    try:
        fila = await supabase.vuelta(settings, vuelta_id)
    except Exception:  # noqa: BLE001
        return None
    return Vuelta.de_fila(fila) if fila else None


async def _viaje_abierto(
    settings: Settings, identidad: auth.Identidad
) -> tuple[bool, ViajeAbierto | None]:
    """Si se esta llevando el seguimiento, y la vuelta abierta de la cuenta."""
    try:
        fila = await viajes.abierto(settings, identidad.auth_uid)
    except Exception:  # noqa: BLE001 -- sin tabla, o Airtable caido.
        return False, None
    if fila is None:
        return True, None
    vuelta = await _vuelta_de(settings, fila.get("fields", {}).get("Vuelta ID") or "")
    return True, viajes.a_abierto(fila, vuelta)


async def pendientes(
    settings: Settings, identidad: auth.Identidad | None = None
) -> VueltasResponse:
    """La lista, y de paso como esta la cuenta para tomar una.

    Las tres cosas van en una respuesta porque el telefono las necesita juntas
    y esta en el patio, con poca senal: un viaje de ida y vuelta, no tres.

    Si la cuenta no se puede leer -Airtable caido, o topado- la lista sale
    igual sin `conductor`: ver que hay por recoger no puede depender de eso.
    """

    async def _conductor() -> Conductor | None:
        if identidad is None:
            return None
        try:
            return await conductor(settings, identidad)
        except Exception:  # noqa: BLE001
            return None

    async def _viaje() -> tuple[bool, ViajeAbierto | None]:
        if identidad is None:
            return False, None
        return await _viaje_abierto(settings, identidad)

    filas, quien, (control, abierto) = await asyncio.gather(
        supabase.vueltas_pendientes(settings), _conductor(), _viaje()
    )
    return VueltasResponse(
        vueltas=[Vuelta.de_fila(f) for f in filas],
        conductor=quien,
        viaje_abierto=abierto,
        control=control,
    )


async def mi_viaje(settings: Settings, identidad: auth.Identidad) -> MiViajeResponse:
    """La vuelta sin finalizar de la cuenta, segun el servidor.

    El telefono lo consulta para enterarse de dos cosas que no puede saber
    solo: que tiene una vuelta abierta que no esta en este telefono, y que
    coordinacion le cerro la que tenia.
    """
    control, abierto = await _viaje_abierto(settings, identidad)
    return MiViajeResponse(control=control, viaje=abierto)


async def confirmar(
    settings: Settings,
    identidad: auth.Identidad,
    vuelta_id: str,
    req: ConfirmarRequest,
) -> ConfirmarResponse:
    fila = await _fila_de(settings, identidad)
    campos = fila.get("fields", {})
    _exigir_activa(campos)
    await _exigir_clave(settings, campos, req.clave)

    async def _abierta() -> tuple[bool, dict[str, Any] | None]:
        try:
            return True, await viajes.abierto(settings, identidad.auth_uid)
        except viajes.SinControl:
            return False, None

    # Las tres lecturas van juntas y no una detras de otra: quien toma la
    # vuelta esta en el patio con poca senal, mirando un circulito girar.
    (control, abierta), previa, operadores = await asyncio.gather(
        _abierta(),
        supabase.vuelta(settings, vuelta_id),
        supabase.operadores_activos(settings),
    )

    # Una vuelta a la vez. Si Airtable no contesta no se toma nada: sin poder
    # mirar, no se puede decir que no tiene otra abierta.
    if abierta is not None:
        cual = abierta.get("fields", {}).get("Nombre") or "una vuelta"
        raise HTTPException(
            status_code=423,
            detail=f"Tienes {cual} sin finalizar. Finalizala para tomar otra.",
        )
    if previa is None:
        raise HTTPException(
            status_code=404,
            detail="Esa vuelta ya no esta en la planilla. Actualiza la lista.",
        )

    nombre = _nombre_cuenta(campos, identidad)
    operador = _operador_de_cuenta(campos, nombre, operadores)
    operador_id = operador["id"] if operador else None
    observaciones = (
        supabase.NO_TOCAR
        if operador
        else _con_nota(previa.get("observaciones"), nombre)
    )
    if not await supabase.anotar_salida(
        settings, vuelta_id, operador_id, observaciones
    ):
        raise HTTPException(
            status_code=409,
            detail="Esta vuelta ya la tomo otro camion. Actualiza la lista.",
        )

    quien = operador["nombre"] if operador else nombre
    codigo: str | None = None
    if control:
        codigo = str(uuid.uuid4())
        try:
            await viajes.crear(
                settings,
                codigo=codigo,
                vuelta=previa,
                usuario_id=fila["id"],
                auth_uid=identidad.auth_uid,
                conductor=quien,
                salida=req.salida,
            )
        except viajes.SinControl:
            codigo = None
        except Exception as exc:  # noqa: BLE001
            # La planilla ya dice que salio y el seguimiento no quedo: una
            # vuelta tomada que nadie controla. Se deshace la salida para que
            # las dos bases digan lo mismo, y se le pide que reintente.
            try:
                await supabase.anular_salida(
                    settings,
                    vuelta_id,
                    operador_id,
                    supabase.NO_TOCAR if operador else previa.get("observaciones"),
                )
            except Exception:  # noqa: BLE001
                pass
            raise HTTPException(
                status_code=502,
                detail="No se pudo registrar el viaje. La vuelta sigue libre: "
                "vuelve a intentar.",
            ) from exc

    if campos.get("Intentos fallidos"):
        try:  # Ya se probo la clave. Que esto falle no deshace la vuelta.
            await airtable.guardar(
                settings,
                settings.airtable_tabla_usuarios,
                {"Intentos fallidos": 0},
                fila["id"],
            )
        except Exception:  # noqa: BLE001
            pass

    # El renglon como estaba al tomarlo: releerlo solo para devolverlo con la
    # hora de salida seria una ida y vuelta mas, y la app no la usa.
    return ConfirmarResponse(
        vuelta=Vuelta.de_fila(previa), conductor=quien, viaje=codigo
    )


async def soltar(
    settings: Settings, identidad: auth.Identidad, vuelta_id: str
) -> Vuelta:
    """Devuelve a la lista una vuelta que esta cuenta tomo y no va a hacer.

    Sin esto, una vuelta tomada por error -el dedo en el renglon de al lado-
    quedaba como salida en la planilla hasta que despacho la corrigiera a mano,
    y mientras tanto nadie mas iba por esos vagones.

    Solo la suelta quien la tomo, y solo **antes de llegar a los vagones**:
    despues ya los engancho, y esa vuelta se finaliza al volver.
    """
    campos = (await _fila_de(settings, identidad)).get("fields", {})
    nombre = _nombre_cuenta(campos, identidad)

    try:
        viaje = await viajes.de_vuelta(settings, identidad.auth_uid, vuelta_id)
        control = True
    except viajes.SinControl:
        viaje, control = None, False

    ajena = HTTPException(
        status_code=409,
        detail="Esa vuelta no esta a tu nombre. Si hay que corregirla, "
        "pedile a despacho.",
    )
    if control and viaje is None:
        raise ajena
    if viaje and viaje.get("fields", {}).get("Estado") == viajes.EN_PUNTO:
        raise HTTPException(
            status_code=409,
            detail="Ya llegaste a los vagones: esta vuelta se finaliza cuando "
            "vuelvas, no se devuelve.",
        )

    previa = await supabase.vuelta(settings, vuelta_id)
    if previa is None:
        raise HTTPException(status_code=404, detail="La vuelta ya no existe.")
    observaciones = previa.get("observaciones")
    operador = await _operador(settings, campos, nombre)

    suelta = False
    if operador:
        suelta = await supabase.anular_salida(settings, vuelta_id, operador["id"])
    if not suelta:
        # Tomada sin conductor enlazado: lo que dice de quien es es el
        # seguimiento y, si no lo hay, la nota que se dejo en Observaciones.
        if not control and f"{MARCA_NOTA}{nombre}" not in (observaciones or ""):
            raise ajena
        suelta = await supabase.anular_salida(
            settings, vuelta_id, None, _sin_nota(observaciones)
        )
    if not suelta:
        raise ajena

    if viaje:
        try:
            await viajes.guardar(
                settings,
                viaje["id"],
                {
                    "Estado": viajes.DEVUELTA,
                    "Devuelta en": datetime.now(timezone.utc).isoformat(),
                },
            )
        except viajes.SinControl:
            pass

    devuelta = await supabase.vuelta(settings, vuelta_id)
    if devuelta is None:
        raise HTTPException(status_code=404, detail="La vuelta ya no existe.")
    return Vuelta.de_fila(devuelta)


async def seguimiento(
    settings: Settings,
    identidad: auth.Identidad,
    codigo: str,
    req: SeguimientoRequest,
) -> SeguimientoResponse:
    """Guarda lo que el telefono sabe del viaje: llego, volvio, finalizo.

    Se puede llamar las veces que haga falta con lo mismo: escribe lo que
    trae y no deshace nada. Una vuelta que ya esta cerrada -la finalizo, la
    devolvio, o la cerro coordinacion a mano- recibe los datos que le
    faltaban pero no se vuelve a abrir.
    """
    try:
        fila = await viajes.por_codigo(settings, codigo)
    except viajes.SinControl:
        raise HTTPException(
            status_code=404, detail="No se esta llevando el seguimiento."
        ) from None
    campos = (fila or {}).get("fields", {})
    # Mismo mensaje exista o no con otro dueno: no se confirma a nadie que un
    # codigo ajeno existe.
    if not fila or campos.get("Auth UID") != identidad.auth_uid:
        raise HTTPException(status_code=404, detail="Ese viaje no existe.")

    llego = req.llegada is not None or bool(campos.get("Llegada en"))
    if req.fin is not None and not llego:
        raise HTTPException(
            status_code=409,
            detail="No se puede finalizar una vuelta sin haber llegado a los "
            "vagones.",
        )

    cambios: dict[str, Any] = {}
    avisos: list[str] = []
    if req.salida and req.salida.lat is not None and req.salida.lon is not None:
        cambios["Salida lat"] = round(req.salida.lat, 6)
        cambios["Salida lon"] = round(req.salida.lon, 6)
    if req.llegada:
        cambios["Llegada en"] = req.llegada.en.isoformat()
        if req.llegada.distancia_m is not None:
            cambios["Distancia al punto (m)"] = round(req.llegada.distancia_m)
        if not req.llegada.verificado:
            avisos.append(
                "Llegada marcada a mano: el acopio no tiene coordenada y el "
                "GPS no la pudo comprobar."
            )
    if req.regreso:
        cambios["Regreso en"] = req.regreso.en.isoformat()
    if req.fin:
        cambios["Finalizada en"] = req.fin.en.isoformat()
        if req.fin.distancia_m is not None:
            cambios["Distancia a la salida (m)"] = round(req.fin.distancia_m)
    if req.recorrido_m is not None:
        cambios["Recorrido (m)"] = round(req.recorrido_m)
    if req.trazado:
        cambios["Codigo trazado"] = req.trazado
    if avisos:
        cambios["Avisos"] = "\n".join(avisos)

    if viajes.esta_abierta(fila):
        if req.fin:
            cambios["Estado"] = viajes.FINALIZADA
        elif llego:
            cambios["Estado"] = viajes.EN_PUNTO

    if cambios:
        try:
            fila = await viajes.guardar(settings, fila["id"], cambios)
        except viajes.SinControl:
            raise HTTPException(
                status_code=404, detail="No se esta llevando el seguimiento."
            ) from None
    return SeguimientoResponse(
        estado=viajes.clave_estado(fila), abierto=viajes.esta_abierta(fila)
    )
