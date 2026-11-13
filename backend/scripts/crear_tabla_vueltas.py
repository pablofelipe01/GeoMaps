"""Crea en Airtable la tabla `Vueltas`: el seguimiento de las vueltas de camiones.

Sin esta tabla el backend deja tomar vueltas pero no lleva el control: no
impide tomar una segunda sin finalizar la primera, ni guarda cuando se llego a
los vagones y cuando se volvio. Ver `app/services/viajes.py`.

    python scripts/crear_tabla_vueltas.py            # solo dice que haria
    python scripts/crear_tabla_vueltas.py --aplicar  # la crea

Se puede correr las veces que haga falta: si la tabla ya existe, agrega solo
los campos que le falten y no toca nada de lo que hay. Nunca borra ni renombra.

Necesita un token de Airtable con el permiso `schema.bases:write` sobre la
base. Si el del `.env` no lo tiene, Airtable responde 403 y el script lo dice:
se crea a mano con los campos de `docs/airtable-schema.md`, o con otro token.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.config import get_settings  # noqa: E402

API = "https://api.airtable.com/v0/meta/bases"

_FECHA_HORA = {
    "type": "dateTime",
    "options": {
        "dateFormat": {"name": "iso"},
        "timeFormat": {"name": "24hour"},
        "timeZone": "America/Bogota",
    },
}


def _numero(decimales: int) -> dict[str, Any]:
    return {"type": "number", "options": {"precision": decimales}}


def campos(tabla_usuarios_id: str) -> list[dict[str, Any]]:
    """Los campos, en el orden en que se leen. El primero es el primario."""
    texto = {"type": "singleLineText"}
    return [
        {"name": "Codigo viaje", **texto},
        {"name": "Nombre", **texto},
        {
            "name": "Estado",
            "type": "singleSelect",
            "options": {
                "choices": [
                    {"name": "En camino", "color": "yellowBright"},
                    {"name": "En el punto", "color": "blueBright"},
                    {"name": "Finalizada", "color": "greenBright"},
                    {"name": "Devuelta", "color": "grayBright"},
                ]
            },
        },
        {"name": "Conductor", **texto},
        {"name": "Jornada", "type": "date", "options": {"dateFormat": {"name": "iso"}}},
        {"name": "Consecutivo", **_numero(0)},
        {"name": "Acopio", **texto},
        {"name": "Tomada en", **_FECHA_HORA},
        {"name": "Llegada en", **_FECHA_HORA},
        {"name": "Regreso en", **_FECHA_HORA},
        {"name": "Finalizada en", **_FECHA_HORA},
        {"name": "Devuelta en", **_FECHA_HORA},
        {"name": "Distancia al punto (m)", **_numero(0)},
        {"name": "Distancia a la salida (m)", **_numero(0)},
        {"name": "Recorrido (m)", **_numero(0)},
        {"name": "Salida lat", **_numero(6)},
        {"name": "Salida lon", **_numero(6)},
        {"name": "Avisos", "type": "multilineText"},
        {"name": "Codigo trazado", **texto},
        {"name": "Vuelta ID", **texto},
        {
            "name": "Usuario",
            "type": "multipleRecordLinks",
            "options": {"linkedTableId": tabla_usuarios_id},
        },
        {"name": "Auth UID", **texto},
    ]


DESCRIPCION = (
    "Seguimiento de las vueltas de camiones: una fila por vuelta tomada desde "
    "GeoMaps, con la hora en que se tomo, se llego a los vagones, se volvio y "
    "se finalizo. Mientras una cuenta tenga una en 'En camino' o 'En el "
    "punto' no puede tomar otra."
)


def main() -> int:
    aplicar = "--aplicar" in sys.argv
    s = get_settings()
    if not s.airtable_token or not s.airtable_base_id:
        print("Falta AIRTABLE_TOKEN o AIRTABLE_BASE_ID en el .env.")
        return 1
    nombre = s.airtable_tabla_vueltas
    base = f"{API}/{s.airtable_base_id}/tables"

    with httpx.Client(
        timeout=30, headers={"Authorization": f"Bearer {s.airtable_token}"}
    ) as c:
        r = c.get(base)
        if r.status_code != 200:
            print(f"No se pudo leer el esquema ({r.status_code}): {r.text[:300]}")
            return 1
        tablas = {t["name"]: t for t in r.json()["tables"]}
        usuarios = tablas.get(s.airtable_tabla_usuarios)
        if usuarios is None:
            print(f"No existe la tabla '{s.airtable_tabla_usuarios}' en la base.")
            return 1
        quiero = campos(usuarios["id"])

        existente = tablas.get(nombre)
        if existente is None:
            print(f"La tabla '{nombre}' no existe. Se crea con {len(quiero)} campos:")
            for f in quiero:
                print(f"  + {f['name']}  ({f['type']})")
            if not aplicar:
                print("\nNo se toco nada. Con --aplicar se crea.")
                return 0
            r = c.post(
                base,
                json={"name": nombre, "description": DESCRIPCION, "fields": quiero},
            )
            return _resultado(r, f"Tabla '{nombre}' creada.")

        hay = {f["name"] for f in existente["fields"]}
        faltan = [f for f in quiero if f["name"] not in hay]
        if not faltan:
            print(f"La tabla '{nombre}' ya existe y tiene todos los campos.")
            return 0
        print(f"La tabla '{nombre}' existe. Le faltan {len(faltan)} campos:")
        for f in faltan:
            print(f"  + {f['name']}  ({f['type']})")
        if not aplicar:
            print("\nNo se toco nada. Con --aplicar se agregan.")
            return 0
        for f in faltan:
            r = c.post(f"{base}/{existente['id']}/fields", json=f)
            if _resultado(r, f"  campo '{f['name']}' agregado."):
                return 1
        return 0


def _resultado(r: httpx.Response, bien: str) -> int:
    if r.status_code in (200, 201):
        print(bien)
        return 0
    print(f"Airtable respondio {r.status_code}: {r.text[:400]}")
    if r.status_code in (401, 403):
        print(
            "El token no tiene permiso para cambiar el esquema "
            "(schema.bases:write). Crea la tabla a mano con los campos de "
            "docs/airtable-schema.md, o corre esto con un token que lo tenga."
        )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
