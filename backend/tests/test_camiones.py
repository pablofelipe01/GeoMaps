"""Confirmar una vuelta: la firma del conductor y la carrera entre dos camiones.

Airtable y Supabase se reemplazan por diccionarios: lo que se prueba es quien
puede tomar una vuelta y con que cedula, no httpx.
"""

from __future__ import annotations

import re
from typing import Any

import pytest
from fastapi import HTTPException

from app.config import get_settings
from app.schemas_camiones import ConfirmarRequest
from app.services import airtable, auth, camiones, supabase

pytestmark = pytest.mark.anyio

VUELTA = "6f1c2b9e-0000-4000-8000-000000000001"
ANA = auth.Identidad(auth_uid="pwd_ana", correo="", nombre="", foto=None, perfiles=("camiones",))
BETO = auth.Identidad(auth_uid="pwd_beto", correo="", nombre="", foto=None, perfiles=("camiones",))


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


class Mundo:
    def __init__(self) -> None:
        clave = auth.hash_clave("clave-buena")
        self.usuarios: dict[str, dict[str, Any]] = {
            "rec1": {"Auth UID": "pwd_ana", "Hash clave": clave},
            "rec2": {"Auth UID": "pwd_beto", "Hash clave": clave},
            "rec3": {"Auth UID": "1234567890"},  # Cuenta de Google: sin clave.
        }
        self.operadores = [
            {"id": "op-ana", "nombre": "ANA", "documento": "1.122.334"},
            {"id": "op-beto", "nombre": "BETO", "documento": "5566778"},
        ]
        self.salida: dict[str, str] = {}

    async def buscar_uno(self, settings, tabla, formula):
        campo, valor = re.search(r"\{([^}]+)\}='([^']*)'", formula).groups()
        for rid, f in self.usuarios.items():
            if str(f.get(campo)) == valor:
                return {"id": rid, "fields": f}
        return None

    async def guardar(self, settings, tabla, campos, record_id):
        self.usuarios[record_id].update(campos)
        return {"id": record_id, "fields": self.usuarios[record_id]}

    async def upsert(self, settings, tabla, campo, codigo, campos):
        fila = await self.buscar_uno(settings, tabla, f"{{{campo}}}='{codigo}'")
        return await self.guardar(settings, tabla, campos, fila["id"])

    async def operador_por_cedula(self, settings, cedula):
        for op in self.operadores:
            if supabase.solo_digitos(op["documento"]) == cedula:
                return op
        return None

    async def anotar_salida(self, settings, vuelta_id, operador_id):
        if vuelta_id in self.salida:
            return False
        self.salida[vuelta_id] = operador_id
        return True

    async def vuelta(self, settings, vuelta_id):
        return {
            "id": vuelta_id,
            "jornada": "2026-10-14",
            "consecutivo": 9,
            "tipo_fruto": "comercial",
            "reportado_en": "2026-10-14T14:50:00+00:00",
            "salida_en": "2026-10-14T15:00:00+00:00",
            "origen_codigo": "B.7-P.3 · 7",
            "origen_bloque": "7",
            "origen_num": "7",
            "origen_lat": 4.45,
            "origen_lon": -72.96,
            "destino_acopio_id": None,
        }


@pytest.fixture
def mundo(monkeypatch) -> Mundo:
    m = Mundo()
    for nombre in ("buscar_uno", "guardar", "upsert"):
        monkeypatch.setattr(airtable, nombre, getattr(m, nombre))
    for nombre in ("operador_por_cedula", "anotar_salida", "vuelta"):
        monkeypatch.setattr(supabase, nombre, getattr(m, nombre))
    return m


async def _confirmar(ident, cedula="1122334", clave="clave-buena", vuelta=VUELTA):
    return await camiones.confirmar(
        get_settings(), ident, vuelta, ConfirmarRequest(cedula=cedula, clave=clave)
    )


async def test_confirma_ata_la_cedula_y_anota_la_salida(mundo):
    r = await _confirmar(ANA)

    assert r.conductor == "ANA"
    assert r.vuelta.origen.lat == 4.45
    assert mundo.salida[VUELTA] == "op-ana"
    assert mundo.usuarios["rec1"]["Cedula"] == "1122334"


async def test_clave_errada_suma_al_bloqueo(mundo):
    with pytest.raises(HTTPException) as exc:
        await _confirmar(ANA, clave="otra")
    assert exc.value.status_code == 401
    assert mundo.usuarios["rec1"]["Intentos fallidos"] == 1
    assert VUELTA not in mundo.salida


async def test_cedula_que_no_esta_en_la_flota(mundo):
    with pytest.raises(HTTPException) as exc:
        await _confirmar(ANA, cedula="999999")
    assert exc.value.status_code == 404


async def test_una_cuenta_atada_no_confirma_con_otra_cedula(mundo):
    await _confirmar(ANA)
    with pytest.raises(HTTPException) as exc:
        await _confirmar(ANA, cedula="5566778", vuelta="otra-vuelta")
    assert exc.value.status_code == 403


async def test_nadie_usa_la_cedula_atada_a_otro(mundo):
    await _confirmar(ANA)
    with pytest.raises(HTTPException) as exc:
        await _confirmar(BETO, cedula="1122334", vuelta="otra-vuelta")
    assert exc.value.status_code == 409


async def test_dos_camiones_por_la_misma_vuelta(mundo):
    await _confirmar(ANA)
    with pytest.raises(HTTPException) as exc:
        await _confirmar(BETO, cedula="5566778")
    assert exc.value.status_code == 409
    assert mundo.salida[VUELTA] == "op-ana", "gana el primero"


async def test_cuenta_de_google_no_tiene_clave_para_firmar(mundo):
    google = auth.Identidad(
        auth_uid="1234567890", correo="", nombre="", foto=None, perfiles=("camiones",)
    )
    with pytest.raises(HTTPException) as exc:
        await _confirmar(google)
    assert exc.value.status_code == 409
