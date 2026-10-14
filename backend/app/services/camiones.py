"""El modulo de camiones: tomar una vuelta pendiente de la planilla de vagones.

## Como se confirma una vuelta

El conductor elige una vuelta y la firma con su **cedula** y la **clave de su
cuenta de GeoMaps**. Las dos cosas hacen falta y no por lo mismo:

- La clave dice que quien tiene el telefono en la mano es el dueno de la
  cuenta, y no alguien que lo encontro desbloqueado en la cabina.
- La cedula dice que conductor de SiriusFleet es (`operadores.documento`), que
  es lo que queda anotado en la planilla.

**La cedula queda atada a la cuenta.** La primera que se confirma bien se
guarda en `Usuarios.Cedula`, y de ahi en adelante esa cuenta solo puede
confirmar con esa, y esa cedula no la puede usar otra cuenta. Sin esto, un
conductor podria salir a nombre de otro escribiendo su cedula. Si de verdad hay
que cambiarla, se borra a mano en Airtable.

La clave errada suma al mismo contador de fallos que el login: si no, esta
seria una segunda puerta para probar claves sin limite.
"""

from __future__ import annotations

from fastapi import HTTPException

from ..config import Settings
from ..schemas_camiones import ConfirmarRequest, ConfirmarResponse, Vuelta
from . import airtable, auth, supabase


async def pendientes(settings: Settings) -> list[Vuelta]:
    return [Vuelta.de_fila(f) for f in await supabase.vueltas_pendientes(settings)]


async def confirmar(
    settings: Settings,
    identidad: auth.Identidad,
    vuelta_id: str,
    req: ConfirmarRequest,
) -> ConfirmarResponse:
    tabla = settings.airtable_tabla_usuarios
    fila = await airtable.buscar_uno(
        settings, tabla, airtable.formula_codigo("Auth UID", identidad.auth_uid)
    )
    if not fila:
        raise HTTPException(
            status_code=403,
            detail="Tu cuenta no esta en la base. Escribinos para revisarla.",
        )
    campos = fila.get("fields", {})

    auth.revisar_bloqueo(campos)
    if not campos.get("Hash clave"):
        raise HTTPException(
            status_code=409,
            detail="Tu cuenta entra con Google y no tiene clave para confirmar. "
            "Los conductores necesitan una cuenta con correo y clave.",
        )
    if not auth.verificar_clave(req.clave, campos.get("Hash clave")):
        await auth.anotar_intento_fallido(settings, campos)
        raise HTTPException(status_code=401, detail="Cedula o clave incorrectas.")

    cedula = supabase.solo_digitos(req.cedula)
    if not 5 <= len(cedula) <= 12:
        raise HTTPException(
            status_code=422, detail="La cedula tiene que ser solo el numero."
        )

    atada = supabase.solo_digitos(campos.get("Cedula"))
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
