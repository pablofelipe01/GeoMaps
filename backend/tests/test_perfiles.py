"""Los perfiles: que llegan al JWT y que una cuenta vieja no pierde nada."""

from __future__ import annotations

import anyio
import pytest
from fastapi import HTTPException

from app.config import get_settings
from app.services import auth


def test_campo_vacio_es_plantacion():
    assert auth.perfiles_de_campos({}) == ("plantacion",)
    assert auth.perfiles_de_campos({"Perfiles": []}) == ("plantacion",)


def test_traduce_e_ignora_opciones_desconocidas():
    campos = {"Perfiles": ["Camiones", "Opcion nueva"]}
    assert auth.perfiles_de_campos(campos) == ("camiones",)


def test_los_perfiles_viajan_en_el_jwt(monkeypatch):
    monkeypatch.setattr(get_settings(), "jwt_secret", "secreto-de-prueba")
    identidad = auth.Identidad(
        auth_uid="111",
        correo="c@x.co",
        nombre="C",
        foto=None,
        perfiles=("plantacion", "camiones"),
    )
    token, _ = auth.emitir_jwt(identidad, get_settings())

    vuelta = anyio.run(auth.identidad_de_request, f"Bearer {token}")
    assert vuelta.perfiles == ("plantacion", "camiones")


def test_exigir_perfil():
    camionero = auth.Identidad(
        auth_uid="1", correo="", nombre="", foto=None, perfiles=("camiones",)
    )
    auth.exigir_perfil(camionero, "camiones")
    with pytest.raises(HTTPException) as exc:
        auth.exigir_perfil(camionero, "plantacion")
    assert exc.value.status_code == 403


# --- Renovar la sesion -----------------------------------------------------


def _renovar(monkeypatch, campos: dict | None):
    """Llama a `renovar_sesion` con Airtable reemplazado por una fila."""
    from app import main
    from app.services import airtable

    monkeypatch.setattr(get_settings(), "jwt_secret", "secreto-de-prueba-bien-largo-para-hs256")

    async def buscar_uno(settings, tabla, formula):
        return None if campos is None else {"id": "rec1", "fields": campos}

    monkeypatch.setattr(airtable, "buscar_uno", buscar_uno)
    vieja = auth.Identidad(
        auth_uid="pwd_ana",
        correo="ana@x.co",
        nombre="",
        foto=None,
        codigo_usuario="cod-ana",
        perfiles=("plantacion",),
    )
    return anyio.run(main.renovar_sesion, vieja, None)


def test_renovar_trae_los_perfiles_que_la_cuenta_tiene_hoy(monkeypatch):
    """Darle el perfil de camiones en Airtable le llega sin cerrar sesion."""
    r = _renovar(
        monkeypatch,
        {
            "Auth UID": "pwd_ana",
            "Nombre": "Ana",
            "Correo": "ana@x.co",
            "Codigo usuario": "cod-ana",
            "Proveedor": "Correo",
            "Perfiles": ["Plantacion", "Camiones"],
        },
    )
    assert r.perfiles == ["plantacion", "camiones"]
    assert r.codigo_usuario == "cod-ana"
    assert r.proveedor == "Correo"

    nueva = anyio.run(auth.identidad_de_request, f"Bearer {r.token}")
    assert nueva.perfiles == ("plantacion", "camiones")
    assert nueva.auth_uid == "pwd_ana"


def test_renovar_no_deja_pasar_a_una_cuenta_suspendida(monkeypatch):
    with pytest.raises(HTTPException) as exc:
        _renovar(monkeypatch, {"Auth UID": "pwd_ana", "Estado": "Suspendida"})
    assert exc.value.status_code == 403


def test_renovar_una_cuenta_borrada(monkeypatch):
    with pytest.raises(HTTPException) as exc:
        _renovar(monkeypatch, None)
    assert exc.value.status_code == 403
