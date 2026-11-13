"""El modulo de camiones: tomar una vuelta pendiente de la planilla de vagones.

## Como se confirma una vuelta

El conductor elige una vuelta y la firma. Lo que se le pide depende de lo que
la cuenta ya tenga, y cada cosa prueba algo distinto:

- **La cedula** dice que conductor de SiriusFleet es (`operadores.documento`),
  que es lo que queda anotado en la planilla. Se pide **una sola vez**: la
  primera que confirma bien queda guardada en `Usuarios.Cedula`.
- **La clave** dice que quien tiene el telefono en la mano es el dueno de la
  cuenta, y no alguien que lo encontro desbloqueado en la cabina. Se pide en
  cada vuelta, a las cuentas que tienen una.

**Las cuentas de Google no tienen clave**, y antes de este cambio no podian
confirmar nada: la unica cuenta con el perfil de camiones era de Google y la
lista se veia pero ninguna vuelta se dejaba tomar. Para ellas la firma es la
sesion: Google ya verifico quien es, y no hay una segunda cosa que pedirle que
no sea volver a abrir Google, que sin senal no anda.

**La cedula queda atada a la cuenta.** De ahi en adelante esa cuenta solo
confirma con esa, y esa cedula no la puede usar otra cuenta. Sin esto, un
conductor podria salir a nombre de otro escribiendo su cedula. Si de verdad hay
que cambiarla, se borra a mano en Airtable.

La clave errada suma al mismo contador de fallos que el login: si no, esta
seria una segunda puerta para probar claves sin limite.
"""

from __future__ import annotations

import asyncio

from fastapi import HTTPException

from ..config import Settings
from ..schemas_camiones import (
    Conductor,
    ConfirmarRequest,
    ConfirmarResponse,
    Vuelta,
    VueltasResponse,
)
from . import airtable, auth, supabase


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


async def conductor(settings: Settings, identidad: auth.Identidad) -> Conductor:
    """Que hace falta pedirle a esta cuenta para confirmar una vuelta."""
    campos = (await _fila_de(settings, identidad)).get("fields", {})
    atada = supabase.solo_digitos(campos.get("Cedula"))
    operador = await supabase.operador_por_cedula(settings, atada) if atada else None
    return Conductor(
        cedula=atada or None,
        nombre=operador["nombre"] if operador else None,
        pide_clave=bool(campos.get("Hash clave")),
    )


async def pendientes(
    settings: Settings, identidad: auth.Identidad | None = None
) -> VueltasResponse:
    """La lista, y de paso como esta la cuenta para tomar una.

    Las dos cosas van en una respuesta porque el telefono las necesita juntas y
    esta en el patio, con poca senal: un viaje de ida y vuelta, no dos.

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

    filas, quien = await asyncio.gather(
        supabase.vueltas_pendientes(settings), _conductor()
    )
    return VueltasResponse(
        vueltas=[Vuelta.de_fila(f) for f in filas], conductor=quien
    )


async def confirmar(
    settings: Settings,
    identidad: auth.Identidad,
    vuelta_id: str,
    req: ConfirmarRequest,
) -> ConfirmarResponse:
    tabla = settings.airtable_tabla_usuarios
    fila = await _fila_de(settings, identidad)
    campos = fila.get("fields", {})

    if campos.get("Estado") == "Suspendida":
        raise HTTPException(
            status_code=403,
            detail="Esta cuenta esta suspendida. Escribinos para reactivarla.",
        )

    # La clave, solo a quien tiene una. Una cuenta de Google firma con la
    # sesion: ver el encabezado del archivo.
    if campos.get("Hash clave"):
        auth.revisar_bloqueo(campos)
        if not req.clave:
            raise HTTPException(
                status_code=401, detail="Escribi tu clave de GeoMaps para confirmar."
            )
        if not auth.verificar_clave(req.clave, campos.get("Hash clave")):
            await auth.anotar_intento_fallido(settings, campos)
            raise HTTPException(
                status_code=401,
                detail="La clave no es correcta. Es la misma con la que entras "
                "a GeoMaps.",
            )

    atada = supabase.solo_digitos(campos.get("Cedula"))
    cedula = supabase.solo_digitos(req.cedula) or atada
    if not cedula:
        raise HTTPException(
            status_code=422,
            detail="Escribi tu cedula: hace falta la primera vez para saber que "
            "conductor sos.",
        )
    if not 5 <= len(cedula) <= 12:
        raise HTTPException(
            status_code=422, detail="La cedula tiene que ser solo el numero."
        )
    if atada and atada != cedula:
        raise HTTPException(
            status_code=403,
            detail="Esta cuenta esta registrada con otra cedula. Si cambio, "
            "pedile a soporte que la actualice.",
        )

    operador = await supabase.operador_por_cedula(settings, cedula)
    if not operador:
        raise HTTPException(
            status_code=404,
            detail="Esa cedula no esta en el registro de conductores de "
            "SiriusFleet. Pedile a despacho que te agregue.",
        )

    if not atada:
        otra = await airtable.buscar_uno(
            settings, tabla, airtable.formula_codigo("Cedula", cedula)
        )
        if otra and otra.get("fields", {}).get("Auth UID") != identidad.auth_uid:
            raise HTTPException(
                status_code=409,
                detail="Esa cedula ya esta registrada en otra cuenta de GeoMaps.",
            )

    # Se ata la cedula (si hacia falta) y se limpia el contador de fallos en
    # una sola escritura: ya se probo la clave.
    cambios: dict = {}
    if not atada:
        cambios["Cedula"] = cedula
    if campos.get("Intentos fallidos"):
        cambios["Intentos fallidos"] = 0
    if cambios:
        await airtable.guardar(settings, tabla, cambios, fila["id"])

    if not await supabase.anotar_salida(settings, vuelta_id, operador["id"]):
        raise HTTPException(
            status_code=409,
            detail="Esta vuelta ya la tomo otro camion. Actualiza la lista.",
        )

    tomada = await supabase.vuelta(settings, vuelta_id)
    if tomada is None:  # La borraron entre el UPDATE y la lectura.
        raise HTTPException(status_code=404, detail="La vuelta ya no existe.")
    return ConfirmarResponse(vuelta=Vuelta.de_fila(tomada), conductor=operador["nombre"])


async def soltar(
    settings: Settings, identidad: auth.Identidad, vuelta_id: str
) -> Vuelta:
    """Devuelve a la lista una vuelta que este conductor tomo y no va a hacer.

    Sin esto, una vuelta tomada por error -el dedo en el renglon de al lado-
    quedaba como salida en la planilla hasta que despacho la corrigiera a mano,
    y mientras tanto nadie mas iba por esos vagones.

    Solo la suelta quien la tomo: el filtro por conductor va en el mismo UPDATE,
    asi que una cuenta no puede devolver la vuelta de otro.
    """
    campos = (await _fila_de(settings, identidad)).get("fields", {})
    atada = supabase.solo_digitos(campos.get("Cedula"))
    operador = await supabase.operador_por_cedula(settings, atada) if atada else None
    if not operador:
        raise HTTPException(
            status_code=403,
            detail="Tu cuenta no tiene un conductor asociado: no hay vuelta "
            "tuya que soltar.",
        )

    if not await supabase.anular_salida(settings, vuelta_id, operador["id"]):
        raise HTTPException(
            status_code=409,
            detail="Esa vuelta no esta a tu nombre. Si hay que corregirla, "
            "pedile a despacho.",
        )
    suelta = await supabase.vuelta(settings, vuelta_id)
    if suelta is None:
        raise HTTPException(status_code=404, detail="La vuelta ya no existe.")
    return Vuelta.de_fila(suelta)
