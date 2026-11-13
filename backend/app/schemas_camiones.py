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


class Posicion(BaseModel):
    """Donde estaba el telefono, y que tan bueno era el GPS en ese momento."""

    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    precision_m: float | None = Field(default=None, ge=0)


class Movimiento(BaseModel):
    """Un paso del viaje: cuando paso y donde estaba el camion.

    Los arma el telefono, que es el que tiene el GPS y el que esta en el lote
    sin senal: el backend los recibe cuando la hay, a veces horas despues, y por
    eso cada uno trae su propia hora en vez de usar la de llegada.
    """

    en: datetime
    lat: float | None = Field(default=None, ge=-90, le=90)
    lon: float | None = Field(default=None, ge=-180, le=180)
    precision_m: float | None = Field(default=None, ge=0)
    # A cuanto quedo de donde tenia que estar: del acopio al llegar, del punto
    # de salida al volver y al finalizar.
    distancia_m: float | None = Field(default=None, ge=0)
    # Falso si lo marco la persona y no el GPS: el acopio no tenia coordenada.
    verificado: bool = True


class Conductor(BaseModel):
    """A nombre de quien quedan las vueltas que tome esta cuenta.

    `cedula` sigue en el modelo para los telefonos con una app anterior, que la
    leen; ya no se llena: la cedula no se le pide a nadie.
    """

    cedula: str | None = None
    # Como figura en la planilla: el conductor de SiriusFleet si la cuenta esta
    # enlazada a uno, y si no el nombre de la cuenta.
    nombre: str | None = None
    # Las cuentas de Google no tienen clave: confirman con la sesion.
    pide_clave: bool = True


class ViajeAbierto(BaseModel):
    """La vuelta que esta cuenta tomo y todavia no finaliza.

    Mientras exista no puede tomar otra. Viaja completa -con la vuelta y donde
    empezo- para que un telefono que no la tiene (se reinstalo la app, se
    cambio de telefono) la pueda continuar en vez de quedar trabado.
    """

    codigo: str
    vuelta_id: str
    nombre: str | None = None
    # `en_camino` o `en_punto`.
    estado: str
    tomada_en: datetime | None = None
    salida: Posicion | None = None
    llegada_en: datetime | None = None
    regreso_en: datetime | None = None
    # Nula si el renglon ya no esta en la planilla de SiriusFleet.
    vuelta: Vuelta | None = None


class VueltasResponse(BaseModel):
    vueltas: list[Vuelta]
    # Nulo si no se pudo leer la cuenta: la lista sale igual.
    conductor: Conductor | None = None
    # La vuelta sin finalizar de esta cuenta, si tiene una.
    viaje_abierto: ViajeAbierto | None = None
    # Si el backend esta llevando el seguimiento de las vueltas. En falso, la
    # tabla `Vueltas` no existe en Airtable y `viaje_abierto` no dice nada.
    control: bool = False


class ConfirmarRequest(BaseModel):
    """La firma del conductor: su clave, si la cuenta tiene una.

    `cedula` ya no se usa. Se acepta y se ignora para no rechazar a un telefono
    con una app anterior que todavia la manda.
    """

    cedula: str | None = Field(default=None, max_length=30)
    clave: str | None = Field(default=None, max_length=200)
    # Donde esta el camion al tomar la vuelta: de ahi sale y ahi tiene que
    # volver para finalizarla. Nulo si el GPS todavia no dio posicion.
    salida: Posicion | None = None


class ConfirmarResponse(BaseModel):
    vuelta: Vuelta
    conductor: str
    # El codigo del viaje en el seguimiento. Nulo si no se esta llevando.
    viaje: str | None = None


class SoltarResponse(BaseModel):
    vuelta: Vuelta


class SeguimientoRequest(BaseModel):
    """Lo que el telefono sabe del viaje hasta ahora.

    Siempre manda todo lo que tiene, no solo lo nuevo: asi reintentar no
    depende de acordarse que llego y que no, y el orden en que lleguen dos
    avisos no importa.
    """

    salida: Movimiento | None = None
    llegada: Movimiento | None = None
    regreso: Movimiento | None = None
    fin: Movimiento | None = None
    recorrido_m: float | None = Field(default=None, ge=0)
    # El `Codigo trazado` del recorrido grabado, para encontrar el GPS completo.
    trazado: str | None = Field(default=None, max_length=64)


class ViajeSync(SeguimientoRequest):
    """El mismo seguimiento, viajando con el recorrido grabado en `/v1/sync`."""

    codigo: str = Field(min_length=8, max_length=64)


class SeguimientoResponse(BaseModel):
    # `en_camino`, `en_punto`, `finalizada` o `devuelta`.
    estado: str
    abierto: bool


class MiViajeResponse(BaseModel):
    # Ver `VueltasResponse.control`.
    control: bool
    viaje: ViajeAbierto | None = None
