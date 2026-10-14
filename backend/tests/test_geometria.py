"""Validacion y vista previa de las lineas que suben del telefono."""

from __future__ import annotations

import json
import math

import pytest

from app.services import geometria


def _linea(n: int) -> list[list[float]]:
    # Una curva en Guaicaramo: cada punto aporta forma, nada es colineal.
    return [
        [-72.89 + i * 0.0001, 4.28 + 0.002 * math.sin(i / 7)] for i in range(n)
    ]


def test_acepta_feature_y_geometria_suelta():
    linea = {"type": "LineString", "coordinates": _linea(3)}
    feature = {"type": "Feature", "geometry": linea, "properties": {}}
    assert len(geometria.coordenadas_de_linea(linea)) == 3
    assert len(geometria.coordenadas_de_linea(feature)) == 3


def test_rechaza_puntos_fuera_de_rango():
    fuera = {"type": "LineString", "coordinates": [[-72.89, 4.28], [-72.88, 95.0]]}
    with pytest.raises(geometria.GeometriaInvalida, match="fuera de rango"):
        geometria.coordenadas_de_linea(fuera)


@pytest.mark.parametrize(
    "malo",
    [
        {"type": "Point", "coordinates": [-72.8, 4.2]},
        {"type": "LineString", "coordinates": [[-72.8, 4.2]]},
        {"type": "LineString", "coordinates": [[-72.8, "4.2"], [-72.7, 4.2]]},
    ],
)
def test_rechaza_lo_que_no_es_una_linea(malo):
    with pytest.raises(geometria.GeometriaInvalida):
        geometria.coordenadas_de_linea(malo)


def test_vista_previa_topa_en_50_y_conserva_las_puntas():
    puntos = [tuple(p) for p in _linea(800)]
    previa = json.loads(geometria.vista_previa(puntos))
    coords = previa["coordinates"]
    assert 2 < len(coords) <= geometria.MAX_VERTICES_VISTA_PREVIA
    assert coords[0] == [round(puntos[0][0], 6), round(puntos[0][1], 6)]
    assert coords[-1] == [round(puntos[-1][0], 6), round(puntos[-1][1], 6)]


def test_vista_previa_no_toca_una_linea_corta():
    puntos = [tuple(p) for p in _linea(12)]
    assert len(json.loads(geometria.vista_previa(puntos))["coordinates"]) == 12
