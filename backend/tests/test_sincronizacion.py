"""POST /v1/sync contra un Airtable y un S3 en memoria.

Lo que se prueba son las reglas que, rotas, rompen datos de alguien: que el
proyecto `local` sea uno por cuenta, que nadie pise un trazado ajeno conociendo
su UUID, que S3 vaya antes que Airtable, y que reintentar no duplique.
"""

from __future__ import annotations

import re
from typing import Any

import pytest

from app.config import get_settings
from app.schemas_sync import SyncRequest, TrazadoSync
from app.services import airtable, almacenamiento, sincronizacion
from app.services.auth import Identidad

# anyio ya viene con FastAPI: no hace falta otro plugin para correr las async.
pytestmark = pytest.mark.anyio

YO = Identidad(auth_uid="111", correo="yo@x.co", nombre="Yo", foto=None)
OTRO = Identidad(auth_uid="222", correo="otro@x.co", nombre="Otro", foto=None)


class BaseFalsa:
    """Lo minimo de Airtable que usa la sincronizacion: buscar por igualdades
    de una formula `AND({Campo}='valor', ...)` y guardar."""

    def __init__(self) -> None:
        self.tablas: dict[str, dict[str, dict[str, Any]]] = {}
        self.s3: dict[str, bytes] = {}
        self.orden: list[str] = []
        self._n = 0

    def fila(self, tabla: str, campos: dict[str, Any]) -> str:
        self._n += 1
        rid = f"rec{self._n}"
        self.tablas.setdefault(tabla, {})[rid] = dict(campos)
        return rid

    async def buscar_uno(self, settings, tabla, formula):
        condiciones = re.findall(r"\{([^}]+)\}='([^']*)'", formula)
        for rid, campos in self.tablas.get(tabla, {}).items():
            if all(str(campos.get(c)) == v for c, v in condiciones):
                return {"id": rid, "fields": campos}
        return None

    async def guardar(self, settings, tabla, campos, record_id):
        self.orden.append(f"airtable:{tabla}")
        if record_id:
            self.tablas[tabla][record_id].update(campos)
        else:
            record_id = self.fila(tabla, campos)
        return {"id": record_id, "fields": self.tablas[tabla][record_id]}

    def subir(self, settings, llave, contenido, content_type):
        self.orden.append("s3")
        self.s3[llave] = contenido
        return llave

    def de(self, tabla: str) -> list[dict[str, Any]]:
        return list(self.tablas.get(tabla, {}).values())


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.fixture
def base(monkeypatch) -> BaseFalsa:
    b = BaseFalsa()
    monkeypatch.setattr(airtable, "buscar_uno", b.buscar_uno)
    monkeypatch.setattr(airtable, "guardar", b.guardar)
    monkeypatch.setattr(almacenamiento, "subir", b.subir)
    for ident in (YO, OTRO):
        b.fila("Usuarios", {"Auth UID": ident.auth_uid})
    return b


def _ruta(codigo: str = "ruta-0001", **cambios) -> TrazadoSync:
    datos = {
        "codigo": codigo,
        "proyecto_codigo": "local",
        "nombre": "Acopio 12",
        "tipo": "ruta",
        "metodo": "calculada",
        "geometria": {
            "type": "Feature",
            "properties": {},
            "geometry": {
                "type": "LineString",
                "coordinates": [[-72.89, 4.28], [-72.888, 4.281], [-72.885, 4.283]],
            },
        },
        "distancia_m": 612.37,
        "bbox": "-72.89,4.28,-72.885,4.283",
        "centro_lat": 4.2813333,
        "centro_lon": -72.8876667,
    }
    datos.update(cambios)
    return TrazadoSync(**datos)


async def _sync(ident: Identidad, *trazados: TrazadoSync):
    return await sincronizacion.sincronizar(
        get_settings(), ident, SyncRequest(trazados=list(trazados))
    )


async def test_sube_la_ruta_con_las_opciones_de_airtable(base):
    r = await _sync(YO, _ruta())

    assert r.trazados[0].ok, r.trazados[0].error
    [fila] = base.de("Trazados")
    assert fila["Tipo"] == "Ruta"
    assert fila["Metodo"] == "Calculada", "el .name de Dart no llega crudo"
    assert fila["Puntos"] == 3
    assert fila["Distancia (m)"] == 612.4
    assert fila["Llave geometria"] == "proyectos/local-111/geometrias/ruta-0001.geojson"
    assert fila["Llave geometria"] in base.s3
    assert r.trazados[0].llave_geometria == fila["Llave geometria"]


async def test_s3_va_antes_que_la_fila(base):
    await _sync(YO, _ruta())
    assert base.orden.index("s3") < base.orden.index("airtable:Trazados")


async def test_el_proyecto_local_es_uno_por_cuenta(base):
    await _sync(YO, _ruta("ruta-yo-0001"), _ruta("ruta-yo-0002"))
    await _sync(OTRO, _ruta("ruta-otro-001"))

    proyectos = base.de("Proyectos")
    assert sorted(p["Codigo proyecto"] for p in proyectos) == ["local-111", "local-222"]
    assert {p["Dueno Auth UID"] for p in proyectos} == {"111", "222"}


async def test_reintentar_no_duplica(base):
    await _sync(YO, _ruta())
    await _sync(YO, _ruta(nombre="Acopio 12 bis"))

    [fila] = base.de("Trazados")
    assert fila["Nombre"] == "Acopio 12 bis"


async def test_no_se_pisa_un_trazado_ajeno(base):
    await _sync(YO, _ruta("ruta-compartida"))
    r = await _sync(OTRO, _ruta("ruta-compartida", nombre="Pisado"))

    assert not r.trazados[0].ok
    [fila] = base.de("Trazados")
    assert fila["Nombre"] == "Acopio 12"


async def test_un_trazado_malo_no_frena_la_tanda(base):
    malo = _ruta(
        "ruta-mala-001",
        geometria={"type": "LineString", "coordinates": [[-72.89, 4.28], [-72.8, 95.0]]},
    )
    r = await _sync(YO, malo, _ruta("ruta-buena-01"))

    assert [t.ok for t in r.trazados] == [False, True]
    [log] = base.de("Sincronizaciones")
    assert log["Estado"] == "Parcial"
    assert log["Registros fallidos"] == 1


async def test_proyecto_ajeno_o_sin_subir_se_rechaza(base):
    r = await _sync(YO, _ruta(proyecto_codigo="proyecto-de-nadie"))
    assert not r.trazados[0].ok
    assert base.de("Trazados") == []
