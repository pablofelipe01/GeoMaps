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

    async def anular_salida(self, settings, vuelta_id, operador_id):
        if self.salida.get(vuelta_id) != operador_id:
            return False
        del self.salida[vuelta_id]
        return True

    async def vueltas_pendientes(self, settings):
        return [await self.vuelta(settings, VUELTA)]

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
    for nombre in (
        "operador_por_cedula",
        "anotar_salida",
        "anular_salida",
        "vuelta",
        "vueltas_pendientes",
    ):
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


GOOGLE = auth.Identidad(
    auth_uid="1234567890", correo="", nombre="", foto=None, perfiles=("camiones",)
)


async def test_cuenta_de_google_firma_con_la_sesion(mundo):
    """Era el bug: la unica cuenta con perfil de camiones era de Google, y sin
    clave no podia tomar ninguna vuelta."""
    r = await _confirmar(GOOGLE, clave=None)

    assert r.conductor == "ANA"
    assert mundo.salida[VUELTA] == "op-ana"
    assert mundo.usuarios["rec3"]["Cedula"] == "1122334"


async def test_cuenta_con_clave_no_confirma_sin_ella(mundo):
    with pytest.raises(HTTPException) as exc:
        await _confirmar(ANA, clave=None)
    assert exc.value.status_code == 401
    assert VUELTA not in mundo.salida
    # No escribir nada no es un intento de adivinar: no suma al bloqueo.
    assert "Intentos fallidos" not in mundo.usuarios["rec1"]


async def test_la_cedula_se_pide_una_sola_vez(mundo):
    await _confirmar(ANA)
    r = await _confirmar(ANA, cedula=None, vuelta="otra-vuelta")

    assert r.conductor == "ANA"
    assert mundo.salida["otra-vuelta"] == "op-ana"


async def test_la_primera_vez_hace_falta_la_cedula(mundo):
    with pytest.raises(HTTPException) as exc:
        await _confirmar(ANA, cedula=None)
    assert exc.value.status_code == 422
    assert VUELTA not in mundo.salida


async def test_cuenta_suspendida_no_toma_vueltas(mundo):
    mundo.usuarios["rec1"]["Estado"] = "Suspendida"
    with pytest.raises(HTTPException) as exc:
        await _confirmar(ANA)
    assert exc.value.status_code == 403


async def test_la_lista_dice_que_pedirle_a_la_cuenta(mundo):
    antes = await camiones.pendientes(get_settings(), ANA)
    assert len(antes.vueltas) == 1
    assert antes.conductor.cedula is None
    assert antes.conductor.pide_clave is True

    await _confirmar(ANA)
    despues = await camiones.pendientes(get_settings(), ANA)
    assert despues.conductor.cedula == "1122334"
    assert despues.conductor.nombre == "ANA"

    de_google = await camiones.pendientes(get_settings(), GOOGLE)
    assert de_google.conductor.pide_clave is False


async def test_la_lista_sale_aunque_no_se_pueda_leer_la_cuenta(mundo, monkeypatch):
    async def caido(*_, **__):
        raise HTTPException(status_code=502, detail="Airtable respondio 503")

    monkeypatch.setattr(airtable, "buscar_uno", caido)
    r = await camiones.pendientes(get_settings(), ANA)
    assert len(r.vueltas) == 1
    assert r.conductor is None


async def test_soltar_devuelve_la_vuelta_a_la_lista(mundo):
    await _confirmar(ANA)
    await camiones.soltar(get_settings(), ANA, VUELTA)
    assert VUELTA not in mundo.salida

    # Y otro la puede tomar.
    await _confirmar(BETO, cedula="5566778")
    assert mundo.salida[VUELTA] == "op-beto"


async def test_nadie_suelta_la_vuelta_de_otro(mundo):
    await _confirmar(ANA)
    await _confirmar(BETO, cedula="5566778", vuelta="otra-vuelta")
    with pytest.raises(HTTPException) as exc:
        await camiones.soltar(get_settings(), BETO, VUELTA)
    assert exc.value.status_code == 409
    assert mundo.salida[VUELTA] == "op-ana"


async def test_sin_cedula_atada_no_hay_nada_que_soltar(mundo):
    with pytest.raises(HTTPException) as exc:
        await camiones.soltar(get_settings(), BETO, VUELTA)
    assert exc.value.status_code == 403
