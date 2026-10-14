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
