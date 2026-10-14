"""Lo poco de geometria que hace el backend: validar y simplificar.

**No mide.** Distancia y area las calcula el telefono con `core/geo.dart`; si
el backend las recalculara con otra formula, el numero del papel y el de la
base no coincidirian y ninguno seria creible.

Lo que si hace es la `Vista previa` de Airtable: la misma linea reducida por
Douglas-Peucker a 50 vertices como maximo. Vive aca y no en el telefono porque
es una decision de como se ve la base, no del trabajo de campo: cambiar el tope
no puede pedir un APK nuevo.
"""

from __future__ import annotations

import json
import math
from typing import Any

MAX_VERTICES_VISTA_PREVIA = 50

# Un recorrido de jornada completa grabado cada segundo ronda los 30.000
# puntos. Diez veces eso ya no es una ruta: es un error o un abuso.
MAX_VERTICES = 300_000

Coordenadas = list[tuple[float, float]]


class GeometriaInvalida(ValueError):
    """El GeoJSON no es una linea que se pueda guardar."""


def coordenadas_de_linea(geojson: dict[str, Any]) -> Coordenadas:
    """Los vertices `(lon, lat)` de un Feature o una geometria LineString.

    El rango de cada eje se valida, pero es solo un control de cordura: no caza
    el error clasico de los ejes al reves en Colombia, porque -72 tambien es una
    latitud posible. Contra eso lo que protege es que el GeoJSON lo arme un solo
    lugar del telefono (`core/geojson.dart`), con su prueba.
    """
    geometria = geojson.get("geometry") if geojson.get("type") == "Feature" else geojson
    if not isinstance(geometria, dict) or geometria.get("type") != "LineString":
        raise GeometriaInvalida("La geometria tiene que ser un LineString.")

    crudas = geometria.get("coordinates")
    if not isinstance(crudas, list) or len(crudas) < 2:
        raise GeometriaInvalida("Una linea necesita al menos dos puntos.")
    if len(crudas) > MAX_VERTICES:
        raise GeometriaInvalida(f"La linea tiene mas de {MAX_VERTICES} puntos.")

    puntos: Coordenadas = []
    for c in crudas:
        if (
            not isinstance(c, list)
            or len(c) < 2
            or not all(isinstance(v, (int, float)) for v in c[:2])
        ):
            raise GeometriaInvalida("Hay un punto que no es [longitud, latitud].")
        lon, lat = float(c[0]), float(c[1])
        if not (-180 <= lon <= 180 and -90 <= lat <= 90):
            raise GeometriaInvalida(
                "Hay un punto fuera de rango: la longitud va de -180 a 180 y la "
                "latitud de -90 a 90."
            )
        puntos.append((lon, lat))
    return puntos


def vista_previa(puntos: Coordenadas) -> str:
    """El GeoJSON de la `Vista previa`: la linea con 50 vertices como maximo.

    **No es el dato.** Sirve para ver la forma sin bajar nada de S3; nadie puede
    medir sobre ella. Por eso el campo se llama asi y no `Geometria`.
    """
    reducidos = reducir_a(puntos, MAX_VERTICES_VISTA_PREVIA)
    return json.dumps(
        {
            "type": "LineString",
            # Seis decimales son 10 cm: mas es ruido que solo alarga el texto.
            "coordinates": [[round(lon, 6), round(lat, 6)] for lon, lat in reducidos],
        },
        separators=(",", ":"),
    )


def reducir_a(puntos: Coordenadas, maximo: int) -> Coordenadas:
    """Douglas-Peucker con la tolerancia minima que deja `maximo` vertices o menos.

    La tolerancia se busca por biseccion en metros en vez de fijarla: una ruta
    de 300 m y una de 15 km necesitan tolerancias muy distintas para quedar en
    50 puntos, y una fija deja a la corta hecha una recta o a la larga sin
    reducir.
    """
    if len(puntos) <= maximo:
        return list(puntos)

    bajo, alto = 0.0, 1.0
    while len(douglas_peucker(puntos, alto)) > maximo:
        alto *= 2
        if alto > 1e7:  # Mas que la vuelta al mundo: ya son las dos puntas.
            return [puntos[0], puntos[-1]]

    mejor = douglas_peucker(puntos, alto)
    for _ in range(30):
        medio = (bajo + alto) / 2
        candidato = douglas_peucker(puntos, medio)
        if len(candidato) <= maximo:
            alto, mejor = medio, candidato
        else:
            bajo = medio
    return mejor


def douglas_peucker(puntos: Coordenadas, tolerancia_m: float) -> Coordenadas:
    """Iterativo y no recursivo: una linea de 30.000 puntos rompe el limite de
    recursion de Python en el peor caso."""
    if len(puntos) < 3:
        return list(puntos)

    # Plano local en metros alrededor de la latitud media. Para decidir que
    # vertice sobra en una vista previa sobra precision; para medir no serviria.
    lat0 = math.radians(sum(lat for _, lat in puntos) / len(puntos))
    mx = 111_320.0 * math.cos(lat0)
    my = 110_540.0
    xy = [(lon * mx, lat * my) for lon, lat in puntos]

    conservar = [False] * len(puntos)
    conservar[0] = conservar[-1] = True
    pila = [(0, len(puntos) - 1)]
    while pila:
        ini, fin = pila.pop()
        if fin - ini < 2:
            continue
        lejos, indice = -1.0, -1
        for i in range(ini + 1, fin):
            d = _distancia_a_segmento(xy[i], xy[ini], xy[fin])
            if d > lejos:
                lejos, indice = d, i
        if lejos > tolerancia_m:
            conservar[indice] = True
            pila.append((ini, indice))
            pila.append((indice, fin))

    return [p for p, sigue in zip(puntos, conservar) if sigue]


def _distancia_a_segmento(
    p: tuple[float, float], a: tuple[float, float], b: tuple[float, float]
) -> float:
    dx, dy = b[0] - a[0], b[1] - a[1]
    largo2 = dx * dx + dy * dy
    if largo2 == 0:
        return math.hypot(p[0] - a[0], p[1] - a[1])
    t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / largo2))
    return math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dy))
