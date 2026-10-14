"""Lo que viaja en `POST /v1/sync`.

Los enumerados llegan con el `.name` de Dart (`ruta`, `calculada`) y se
traducen aca a la opcion del Single select de Airtable (`Ruta`, `Calculada`).
La traduccion vive en un solo diccionario por campo porque el upsert usa
`typecast: true`: un valor sin traducir no falla, crea en silencio una opcion
nueva al lado de la buena (`ruta` junto a `Ruta`) y parte los filtros en dos.
Por eso aca solo entra lo que esta en el diccionario; lo demas es un 422.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field

TIPOS_TRAZADO: dict[str, str] = {"ruta": "Ruta", "poligono": "Poligono"}

METODOS_CAPTURA: dict[str, str] = {
    "automatico": "Automatico",
    "manual": "Manual",
    "mixto": "Mixto",
    # Una ruta que calculo el ruteo por las vias del predio, no que alguien
    # camino. Tiene que distinguirse: no lleva precision de GPS y no sirve
    # como lindero.
    "calculada": "Calculada",
}


class TrazadoSync(BaseModel):
    """Un trazado tal como lo tiene el telefono.

    `puntos` no viaja: lo cuenta el backend sobre la geometria que recibe, que
    es la que queda en S3. Un conteo que dijera otra cosa que el archivo seria
    un dato mas en que no confiar.
    """

    codigo: str = Field(min_length=8, max_length=64)
    proyecto_codigo: str = Field(min_length=1, max_length=64)
    nombre: str = Field(min_length=1, max_length=200)
    tipo: Literal["ruta", "poligono"]
    metodo: Literal["automatico", "manual", "mixto", "calculada"]

    # El GeoJSON completo: Feature o geometria LineString, en [lon, lat].
    geometria: dict[str, Any]

    distancia_m: float | None = None
    area_ha: float | None = None
    precision_media_m: float | None = None
    bbox: str | None = Field(default=None, max_length=200)
    centro_lat: float | None = None
    centro_lon: float | None = None
    iniciado_en: datetime | None = None
    terminado_en: datetime | None = None


class SyncRequest(BaseModel):
    """Lo pendiente del telefono, en tandas.

    El tope es por el tiempo de la funcion serverless y por el limite de 5
    requests por segundo de Airtable: cada trazado son tres llamadas, y una
    tanda grande que se corta a la mitad por timeout es peor que tres chicas.
    """

    trazados: list[TrazadoSync] = Field(default_factory=list, max_length=10)


class ResultadoItem(BaseModel):
    """Que paso con cada UUID. El telefono marca como subido solo los `ok`."""

    codigo: str
    ok: bool
    llave_geometria: str | None = None
    error: str | None = None


class SyncResponse(BaseModel):
    trazados: list[ResultadoItem]
