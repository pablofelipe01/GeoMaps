"""La planilla de vagones de SiriusFleet, en su Supabase.

GeoMaps no es dueno de estos datos: los escribe despacho desde SiriusFleet
(`map-security`, `supabase/vagones.sql` y `supabase/flota.sql`). Aca se hacen
exactamente tres cosas, por la API REST de Supabase (PostgREST):

- leer las vueltas pendientes por recoger,
- buscar un conductor por su cedula,
- anotar que un conductor salio por una vuelta.

Una vuelta pendiente es un renglon con `vuelta_pendiente = true` y `salida_en`
vacio: la misma definicion que usa la lista que abre el QR en SiriusFleet
(`fetchVueltasPendientes`). Si alla cambia, aca tiene que cambiar igual.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

import httpx
from fastapi import HTTPException

from ..config import Settings

TIMEOUT = 20

# Lo que la app necesita de cada vuelta. Se pide explicito y no `*`: si
# SiriusFleet agrega columnas a la vista, no tienen por que viajar al telefono.
COLUMNAS_VUELTA = ",".join(
    [
        "id",
        "jornada",
        "consecutivo",
        "tipo_fruto",
        "reportado_en",
        "salida_en",
        "vagon",
        "observaciones",
        "origen_codigo",
        "origen_bloque",
        "origen_lote",
        "origen_num",
        "origen_lat",
        "origen_lon",
        "destino_acopio_id",
        "destino_codigo",
        "destino_bloque",
        "destino_lote",
        "destino_num",
        "destino_lat",
        "destino_lon",
        "operador_nombre",
    ]
)


def _base(settings: Settings) -> tuple[str, dict[str, str]]:
    if not settings.supabase_url or not settings.supabase_key:
        raise HTTPException(
            status_code=500,
            detail="Falta configurar Supabase (SUPABASE_URL y SUPABASE_KEY) en "
            "el backend.",
        )
    cabeceras = {
        "apikey": settings.supabase_key,
        "Authorization": f"Bearer {settings.supabase_key}",
    }
    return f"{settings.supabase_url.rstrip('/')}/rest/v1", cabeceras


def _revisar(r: httpx.Response) -> None:
    if r.status_code >= 400:
        raise HTTPException(
            status_code=502,
            detail=f"SiriusFleet respondio {r.status_code}: {r.text[:300]}",
        )


async def vueltas_pendientes(settings: Settings) -> list[dict[str, Any]]:
    """Las vueltas por recoger que todavia no salen, la mas vieja primero."""
    base, cabeceras = _base(settings)
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        r = await client.get(
            f"{base}/v_planilla_vagones",
            headers=cabeceras,
            params={
                "select": COLUMNAS_VUELTA,
                "vuelta_pendiente": "eq.true",
                "salida_en": "is.null",
                "order": "jornada.asc,consecutivo.asc",
            },
        )
    _revisar(r)
    return r.json()


async def vuelta(settings: Settings, vuelta_id: str) -> dict[str, Any] | None:
    base, cabeceras = _base(settings)
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        r = await client.get(
            f"{base}/v_planilla_vagones",
            headers=cabeceras,
            params={"select": COLUMNAS_VUELTA, "id": f"eq.{vuelta_id}"},
        )
    _revisar(r)
    filas = r.json()
    return filas[0] if filas else None


def solo_digitos(texto: str | None) -> str:
    return "".join(c for c in (texto or "") if c.isdigit())


async def operador_por_cedula(
    settings: Settings, cedula: str
) -> dict[str, Any] | None:
    """El conductor activo con esa cedula, o None.

    Se trae la flota activa y se compara por digitos en vez de filtrar en la
    consulta: en SiriusFleet el documento se escribe a mano, a veces con puntos
    ("1.122.334") y a veces sin ellos, y PostgREST no sabe compararlos asi. Son
    unos cientos de filas, una vez por confirmacion.
    """
    base, cabeceras = _base(settings)
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        r = await client.get(
            f"{base}/operadores",
            headers=cabeceras,
            params={
                "select": "id,nombre,documento",
                "activo": "eq.true",
                "documento": "not.is.null",
            },
        )
    _revisar(r)
    buscada = solo_digitos(cedula)
    for op in r.json():
        if solo_digitos(op.get("documento")) == buscada:
            return op
    return None


async def anotar_salida(
    settings: Settings, vuelta_id: str, operador_id: str
) -> bool:
    """Anota conductor y hora de salida. Falso si la vuelta ya no estaba libre.

    El filtro `salida_en is null` va en el mismo UPDATE y no en una lectura
    previa: dos conductores confirmando a la vez leerian los dos "libre" y se
    pisarian. Asi la base deja pasar a uno solo y el otro recibe cero filas.
    """
    base, cabeceras = _base(settings)
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        r = await client.patch(
            f"{base}/viajes_vagones",
            headers={**cabeceras, "Prefer": "return=representation"},
            params={
                "id": f"eq.{vuelta_id}",
                "salida_en": "is.null",
                "vuelta_pendiente": "eq.true",
            },
            json={
                "operador_id": operador_id,
                "salida_en": datetime.now(timezone.utc).isoformat(),
            },
        )
    _revisar(r)
    return bool(r.json())
