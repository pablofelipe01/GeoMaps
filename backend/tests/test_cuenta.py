"""Baja de cuenta: que se lleve lo suyo, en orden, y nada ajeno.

Airtable y S3 se reemplazan por diccionarios. Lo que se prueba es que se borre
lo que cuelga de la persona y de sus proyectos, que los proyectos de otro
queden intactos, y que la fila de `Usuarios` sea lo ultimo.
"""

from __future__ import annotations

import re
from typing import Any

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app import main
from app.config import get_settings
from app.services import airtable, almacenamiento, auth, cuenta

pytestmark = pytest.mark.anyio

ANA = auth.Identidad(auth_uid="pwd_ana", correo="", nombre="", foto=None)


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


class Mundo:
    def __init__(self) -> None:
        s = get_settings()
        self.tablas: dict[str, dict[str, dict[str, Any]]] = {
            s.airtable_tabla_usuarios: {
                "usu-ana": {
                    "Auth UID": "pwd_ana",
                    "Rol": "Usuario",
                    "Sincronizaciones": ["syn-1"],
                },
                "usu-beto": {"Auth UID": "pwd_beto", "Rol": "Usuario"},
            },
            s.airtable_tabla_proyectos: {
                "pro-ana": {
                    "Codigo proyecto": "local-pwd_ana",
                    "Dueno Auth UID": "pwd_ana",
                    "Trazados": ["tra-1", "tra-2"],
                },
                "pro-beto": {
                    "Codigo proyecto": "local-pwd_beto",
                    "Dueno Auth UID": "pwd_beto",
                    "Trazados": ["tra-3"],
                },
            },
            s.airtable_tabla_trazados: {"tra-1": {}, "tra-2": {}, "tra-3": {}},
            s.airtable_tabla_sincronizaciones: {"syn-1": {}, "syn-2": {}},
        }
        self.prefijos_borrados: list[str] = []
        self.orden: list[str] = []

    def _filtrar(self, tabla: str, formula: str) -> list[dict[str, Any]]:
        campo, valor = re.search(r"\{([^}]+)\}='([^']*)'", formula).groups()
        return [
            {"id": rid, "fields": f}
            for rid, f in self.tablas.get(tabla, {}).items()
            if str(f.get(campo)) == valor
        ]

    async def buscar_uno(self, settings, tabla, formula):
        filas = self._filtrar(tabla, formula)
        return filas[0] if filas else None

    async def listar(self, settings, tabla, formula):
        return self._filtrar(tabla, formula)

    async def borrar(self, settings, tabla, ids):
        for rid in ids:
            del self.tablas[tabla][rid]
            self.orden.append(rid)

    def borrar_prefijo(self, settings, prefijo):
        self.prefijos_borrados.append(prefijo)
        self.orden.append(prefijo)
        return 1


@pytest.fixture
def mundo(monkeypatch) -> Mundo:
    m = Mundo()
    for nombre in ("buscar_uno", "listar", "borrar"):
        monkeypatch.setattr(airtable, nombre, getattr(m, nombre))
    monkeypatch.setattr(almacenamiento, "borrar_prefijo", m.borrar_prefijo)
    return m


async def test_borra_lo_suyo_y_deja_lo_ajeno(mundo):
    s = get_settings()
    await cuenta.eliminar(s, ANA)

    assert mundo.prefijos_borrados == ["proyectos/local-pwd_ana/"]
    assert set(mundo.tablas[s.airtable_tabla_trazados]) == {"tra-3"}
    assert set(mundo.tablas[s.airtable_tabla_proyectos]) == {"pro-beto"}
    assert set(mundo.tablas[s.airtable_tabla_sincronizaciones]) == {"syn-2"}
    assert set(mundo.tablas[s.airtable_tabla_usuarios]) == {"usu-beto"}


async def test_s3_primero_y_la_cuenta_al_final(mundo):
    await cuenta.eliminar(get_settings(), ANA)

    assert mundo.orden[0] == "proyectos/local-pwd_ana/"
    assert mundo.orden[-1] == "usu-ana"


async def test_una_cuenta_que_ya_no_esta_no_falla(mundo):
    await cuenta.eliminar(get_settings(), ANA)
    await cuenta.eliminar(get_settings(), ANA)


async def test_soporte_no_se_da_de_baja_sola(mundo):
    s = get_settings()
    mundo.tablas[s.airtable_tabla_usuarios]["usu-ana"]["Rol"] = "Admin"

    with pytest.raises(HTTPException) as exc:
        await cuenta.eliminar(s, ANA)

    assert exc.value.status_code == 409
    assert "usu-ana" in mundo.tablas[s.airtable_tabla_usuarios]
    assert mundo.prefijos_borrados == []


def test_no_borra_un_prefijo_que_abarque_el_bucket():
    for prefijo in ("", "/", "proyectos/", "proyectos/local"):
        with pytest.raises(ValueError):
            almacenamiento.borrar_prefijo(get_settings(), prefijo)


@pytest.mark.parametrize("ruta", ["/privacidad", "/eliminar-cuenta"])
def test_paginas_publicas_sin_llave_ni_version(ruta, monkeypatch):
    # Las abre el navegador y el revisor de Play: sin X-API-Key, y aunque la
    # version de la app este bloqueada.
    async def bloqueada(settings):
        raise AssertionError("las paginas no consultan la version")

    monkeypatch.setattr(main.version_app, "manifiesto_vigente", bloqueada)
    r = TestClient(main.app).get(ruta, headers={"X-App-Version": "1"})

    assert r.status_code == 200
    assert "text/html" in r.headers["content-type"]
    assert get_settings().contacto_privacidad in r.text


def test_google_no_deja_entrar_a_una_cuenta_suspendida(monkeypatch):
    # Antes solo lo frenaba la puerta de clave: suspender a alguien que entra
    # con Google no tenia ningun efecto.
    def token_valido(id_token, settings):
        return auth.Identidad(auth_uid="111", correo="a@b.co", nombre="A", foto=None)

    async def fila_suspendida(settings, tabla, formula):
        return {"id": "usu-1", "fields": {"Auth UID": "111", "Estado": "Suspendida"}}

    async def no_escribe(*args, **kwargs):
        raise AssertionError("una cuenta suspendida no actualiza su fila")

    monkeypatch.setattr(auth, "verificar_id_token_google", token_valido)
    monkeypatch.setattr(airtable, "buscar_uno", fila_suspendida)
    monkeypatch.setattr(airtable, "upsert", no_escribe)

    r = TestClient(main.app).post(
        "/v1/sesion",
        json={"id_token": "x"},
        headers={"X-API-Key": get_settings().app_api_key},
    )

    assert r.status_code == 403
