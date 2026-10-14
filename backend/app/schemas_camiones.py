"""Lo que viaja entre el modulo de camiones de la app y el backend."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any

from pydantic import BaseModel, Field


class Sitio(BaseModel):
    """Un acopio de la planilla, como lo nombra despacho: bloque y numero."""

    codigo: str | None = None
    bloque: str | None = None
    lote: str | None = None
    num: str | None = None
    lat: float | None = None
    lon: float | None = None


class Vuelta(BaseModel):
    """Una vuelta pendiente por recoger: donde estan los vagones llenos."""

    id: str
    jornada: date
    consecutivo: int
    tipo_fruto: str
    reportado_en: datetime
    salida_en: datetime | None = None
    origen: Sitio
    # Donde dejar el vagon vacio de paso, si despacho lo dijo.
    destino: Sitio | None = None
    vagon: str | None = None
    observaciones: str | None = None
    operador_nombre: str | None = None

    @classmethod
    def de_fila(cls, f: dict[str, Any]) -> "Vuelta":
        def sitio(prefijo: str) -> Sitio:
            return Sitio(
                **{c: f.get(f"{prefijo}_{c}") for c in Sitio.model_fields}
            )

        return cls(
            id=f["id"],
            jornada=f["jornada"],
            consecutivo=f["consecutivo"],
            tipo_fruto=f["tipo_fruto"],
            reportado_en=f["reportado_en"],
            salida_en=f.get("salida_en"),
            origen=sitio("origen"),
            destino=sitio("destino") if f.get("destino_acopio_id") else None,
            vagon=f.get("vagon"),
            observaciones=f.get("observaciones"),
            operador_nombre=f.get("operador_nombre"),
        )


class VueltasResponse(BaseModel):
    vueltas: list[Vuelta]


class ConfirmarRequest(BaseModel):
    """La firma del conductor: su cedula y la clave de su cuenta de GeoMaps."""

    cedula: str = Field(min_length=1, max_length=30)
    clave: str = Field(min_length=1, max_length=200)


class ConfirmarResponse(BaseModel):
    vuelta: Vuelta
    conductor: str
