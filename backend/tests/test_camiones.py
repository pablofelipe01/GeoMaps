"""Tomar, seguir y cerrar una vuelta.

Airtable y Supabase se reemplazan por diccionarios: lo que se prueba es quien
puede tomar una vuelta, con que se firma, que no se toman dos a la vez y que no
se finaliza una sin haber ido, no httpx.
"""

from __future__ import annotations

import re
from datetime import datetime, timezone
from typing import Any

import pytest
from fastapi import HTTPException

from app.config import get_settings
from app.schemas_camiones import (
    ConfirmarRequest,
    Movimiento,
    Posicion,
    SeguimientoRequest,
)
from app.services import airtable, auth, camiones, supabase, viajes

pytestmark = pytest.mark.anyio

V1 = "6f1c2b9e-0000-4000-8000-000000000001"
V2 = "6f1c2b9e-0000-4000-8000-000000000002"


def _cuenta(uid: str, nombre: str) -> auth.Identidad:
    return auth.Identidad(
        auth_uid=uid, correo="", nombre=nombre, foto=None, perfiles=("camiones",)
    )


ANA = _cuenta("pwd_ana", "Ana Gomez")
BETO = _cuenta("pwd_beto", "Beto Ruiz")
GOOGLE = _cuenta("1234567890", "Carla Diaz")

PATIO = Posicion(lat=4.40, lon=-72.90, precision_m=8)


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


class Mundo:
    """Las dos bases en memoria: `Usuarios` y `Vueltas` de Airtable, y la
    planilla y el registro de conductores de SiriusFleet."""

    def __init__(self) -> None:
        clave = auth.hash_clave("clave-buena")
        self.usuarios: dict[str, dict[str, Any]] = {
            "rec1": {"Auth UID": "pwd_ana", "Nombre": "Ana Gomez", "Hash clave": clave},
            "rec2": {"Auth UID": "pwd_beto", "Nombre": "Beto Ruiz", "Hash clave": clave},
            # Cuenta de Google: sin clave.
            "rec3": {"Auth UID": "1234567890", "Nombre": "Carla Diaz"},
        }
        self.vueltas: dict[str, dict[str, Any]] = {}
        self.operadores = [
            {"id": "op-luis", "nombre": "PATARROYO CUFINO LUIS ALFONSO", "documento": "1.122.334"},
            {"id": "op-jesus", "nombre": "ROMERO LOPEZ JESUS JAVIER", "documento": "5566778"},
            {"id": "op-javier", "nombre": "JAVIER", "documento": None},
        ]
        # El renglon de la planilla: quien salio y que dice Observaciones.
        self.planilla: dict[str, dict[str, Any]] = {
            V1: {"consecutivo": 23, "observaciones": None},
            V2: {"consecutivo": 24, "observaciones": None},
        }
        # Como falla Airtable con la tabla `Vueltas`, si falla.
        self.falla_vueltas: HTTPException | None = None
        self._n = 0

    # ----------------------------- Airtable -----------------------------

    def _tabla(self, tabla: str) -> dict[str, dict[str, Any]]:
        if tabla == "Usuarios":
            return self.usuarios
        if self.falla_vueltas is not None:
            raise self.falla_vueltas
        return self.vueltas

    @staticmethod
    def _cumple(campos: dict[str, Any], formula: str) -> bool:
        # `AND({A}='x', OR({Estado}='p', {Estado}='q'))`: las igualdades del
        # mismo campo son alternativas, las de campos distintos se suman.
        por_campo: dict[str, set[str]] = {}
        for campo, valor in re.findall(r"\{([^}]+)\}='([^']*)'", formula):
            por_campo.setdefault(campo, set()).add(valor)
        return all(str(campos.get(c)) in v for c, v in por_campo.items())

    async def buscar_uno(self, settings, tabla, formula):
        for rid, f in self._tabla(tabla).items():
            if self._cumple(f, formula):
                return {"id": rid, "fields": f}
        return None

    async def listar(self, settings, tabla, formula):
        return [
            {"id": rid, "fields": f}
            for rid, f in self._tabla(tabla).items()
            if self._cumple(f, formula)
        ]

    async def guardar(self, settings, tabla, campos, record_id):
        filas = self._tabla(tabla)
        if record_id is None:
            self._n += 1
            record_id = f"via{self._n}"
            filas[record_id] = {}
        filas[record_id].update(campos)
        return {"id": record_id, "fields": filas[record_id]}

    # ---------------------------- SiriusFleet ----------------------------

    async def operadores_activos(self, settings):
        return self.operadores

    async def anotar_salida(self, settings, vuelta_id, operador_id, observaciones=supabase.NO_TOCAR):
        renglon = self.planilla[vuelta_id]
        if renglon.get("salio"):
            return False
        renglon.update(salio=True, operador_id=operador_id)
        if observaciones is not supabase.NO_TOCAR:
            renglon["observaciones"] = observaciones
        return True

    async def anular_salida(self, settings, vuelta_id, operador_id, observaciones=supabase.NO_TOCAR):
        renglon = self.planilla[vuelta_id]
        if not renglon.get("salio") or renglon.get("operador_id") != operador_id:
            return False
        renglon.update(salio=False, operador_id=None)
        if observaciones is not supabase.NO_TOCAR:
            renglon["observaciones"] = observaciones
        return True

    async def vueltas_pendientes(self, settings):
        return [
            await self.vuelta(settings, v)
            for v, r in self.planilla.items()
            if not r.get("salio")
        ]

    async def vuelta(self, settings, vuelta_id):
        renglon = self.planilla.get(vuelta_id)
        if renglon is None:
            return None
        return {
            "id": vuelta_id,
            "jornada": "2026-10-14",
            "consecutivo": renglon["consecutivo"],
            "tipo_fruto": "comercial",
            "reportado_en": "2026-10-14T14:50:00+00:00",
            "salida_en": "2026-10-14T15:00:00+00:00" if renglon.get("salio") else None,
            "observaciones": renglon.get("observaciones"),
            "origen_codigo": "B.7-P.3 · 7",
            "origen_bloque": "7",
            "origen_num": "7",
            "origen_lat": 4.45,
            "origen_lon": -72.96,
            "destino_acopio_id": None,
        }

    def viaje(self, codigo: str | None) -> dict[str, Any]:
        return next(f for f in self.vueltas.values() if f["Codigo viaje"] == codigo)


@pytest.fixture
def mundo(monkeypatch) -> Mundo:
    m = Mundo()
    for nombre in ("buscar_uno", "listar", "guardar"):
        monkeypatch.setattr(airtable, nombre, getattr(m, nombre))
    for nombre in (
        "operadores_activos",
        "anotar_salida",
        "anular_salida",
        "vuelta",
        "vueltas_pendientes",
    ):
        monkeypatch.setattr(supabase, nombre, getattr(m, nombre))
    return m


async def _tomar(ident, vuelta=V1, clave="clave-buena", **mas):
    return await camiones.confirmar(
        get_settings(), ident, vuelta, ConfirmarRequest(clave=clave, **mas)
    )


def _paso(minuto: int, **mas) -> Movimiento:
    return Movimiento(
        en=datetime(2026, 10, 14, 15, minuto, tzinfo=timezone.utc), **mas
    )


async def _seguir(ident, codigo, **pasos):
    return await camiones.seguimiento(
        get_settings(), ident, codigo, SeguimientoRequest(**pasos)
    )


# ------------------------------- La firma -------------------------------


async def test_se_toma_solo_con_la_clave(mundo):
    """Lo que se pidio: ni cedula ni registro de conductores, la clave."""
    r = await _tomar(ANA, salida=PATIO)

    assert r.conductor == "Ana Gomez"
    assert mundo.planilla[V1]["salio"] is True
    # Sin conductor de SiriusFleet, queda dicho en la planilla quien fue.
    assert mundo.planilla[V1]["operador_id"] is None
    assert mundo.planilla[V1]["observaciones"] == "GeoMaps: Ana Gomez"
    assert "Cedula" not in mundo.usuarios["rec1"]


async def test_una_app_anterior_que_manda_cedula_no_se_rechaza(mundo):
    r = await _tomar(ANA, cedula="999999")
    assert r.conductor == "Ana Gomez"
    assert "Cedula" not in mundo.usuarios["rec1"]


async def test_clave_errada_suma_al_bloqueo(mundo):
    with pytest.raises(HTTPException) as exc:
        await _tomar(ANA, clave="otra")
    assert exc.value.status_code == 401
    assert mundo.usuarios["rec1"]["Intentos fallidos"] == 1
    assert not mundo.planilla[V1].get("salio")


async def test_cuenta_con_clave_no_confirma_sin_ella(mundo):
    with pytest.raises(HTTPException) as exc:
        await _tomar(ANA, clave=None)
    assert exc.value.status_code == 401
    assert not mundo.planilla[V1].get("salio")
    # No escribir nada no es un intento de adivinar: no suma al bloqueo.
    assert "Intentos fallidos" not in mundo.usuarios["rec1"]


async def test_cuenta_de_google_firma_con_la_sesion(mundo):
    r = await _tomar(GOOGLE, clave=None)
    assert r.conductor == "Carla Diaz"
    assert mundo.planilla[V1]["salio"] is True


async def test_cuenta_suspendida_no_toma_vueltas(mundo):
    mundo.usuarios["rec1"]["Estado"] = "Suspendida"
    with pytest.raises(HTTPException) as exc:
        await _tomar(ANA)
    assert exc.value.status_code == 403


async def test_dos_camiones_por_la_misma_vuelta(mundo):
    await _tomar(ANA)
    with pytest.raises(HTTPException) as exc:
        await _tomar(BETO)
    assert exc.value.status_code == 409
    assert mundo.planilla[V1]["observaciones"] == "GeoMaps: Ana Gomez", "gana el primero"
    assert not any(f["Auth UID"] == "pwd_beto" for f in mundo.vueltas.values())


# ---------------------- El conductor en la planilla ----------------------


async def test_con_la_cedula_cargada_queda_el_conductor_de_siriusfleet(mundo):
    """La carga un administrador en Airtable; al conductor no se le pregunta."""
    mundo.usuarios["rec1"]["Cedula"] = "1122334"
    r = await _tomar(ANA)

    assert r.conductor == "PATARROYO CUFINO LUIS ALFONSO"
    assert mundo.planilla[V1]["operador_id"] == "op-luis"
    assert mundo.planilla[V1]["observaciones"] is None


async def test_el_mismo_nombre_completo_enlaza_sin_cedula(mundo):
    mundo.usuarios["rec1"]["Nombre"] = "Luis Alfonso Patarroyo Cufiño"
    mundo.operadores[0]["nombre"] = "PATARROYO CUFIÑO LUIS ALFONSO"
    await _tomar(ANA)
    assert mundo.planilla[V1]["operador_id"] == "op-luis"


async def test_un_nombre_parecido_no_alcanza(mundo):
    """Anotarle la vuelta a otro Javier es peor que dejar la columna en blanco."""
    mundo.usuarios["rec1"]["Nombre"] = "Javier Romero"
    await _tomar(ANA)
    assert mundo.planilla[V1]["operador_id"] is None
    assert mundo.planilla[V1]["observaciones"] == "GeoMaps: Javier Romero"

    mundo.usuarios["rec2"]["Nombre"] = "Javier"
    await _tomar(BETO, vuelta=V2)
    assert mundo.planilla[V2]["operador_id"] is None


async def test_las_observaciones_de_despacho_se_conservan(mundo):
    mundo.planilla[V1]["observaciones"] = "Urgente"
    await _tomar(ANA)
    assert mundo.planilla[V1]["observaciones"] == "Urgente · GeoMaps: Ana Gomez"

    await camiones.soltar(get_settings(), ANA, V1)
    assert mundo.planilla[V1]["observaciones"] == "Urgente"


# --------------------------- Una vuelta a la vez ---------------------------


async def test_tomar_abre_el_seguimiento(mundo):
    r = await _tomar(ANA, salida=PATIO)
    fila = mundo.viaje(r.viaje)

    assert fila["Estado"] == "En camino"
    assert fila["Nombre"] == "Vuelta #23 · B.7-P.3 · 7"
    assert fila["Vuelta ID"] == V1
    assert fila["Conductor"] == "Ana Gomez"
    assert fila["Usuario"] == ["rec1"]
    assert (fila["Salida lat"], fila["Salida lon"]) == (4.40, -72.90)
    assert fila["Tomada en"]


async def test_no_se_toma_otra_sin_finalizar_la_primera(mundo):
    await _tomar(ANA)
    with pytest.raises(HTTPException) as exc:
        await _tomar(ANA, vuelta=V2)

    assert exc.value.status_code == 423
    assert "Vuelta #23" in exc.value.detail
    assert not mundo.planilla[V2].get("salio"), "la segunda sigue libre"


async def test_la_de_otro_no_me_frena(mundo):
    await _tomar(ANA)
    await _tomar(BETO, vuelta=V2)
    assert mundo.planilla[V2]["salio"] is True


async def test_finalizar_deja_tomar_la_siguiente(mundo):
    r = await _tomar(ANA)
    cierre = await _seguir(
        ANA,
        r.viaje,
        llegada=_paso(20, lat=4.45, lon=-72.96, distancia_m=31.4),
        regreso=_paso(50, lat=4.40, lon=-72.90, distancia_m=12),
        fin=_paso(52, lat=4.40, lon=-72.90, distancia_m=9.6),
        recorrido_m=11842.7,
        trazado="trazado-0001",
    )

    assert (cierre.estado, cierre.abierto) == ("finalizada", False)
    fila = mundo.viaje(r.viaje)
    assert fila["Estado"] == "Finalizada"
    assert fila["Llegada en"] == "2026-10-14T15:20:00+00:00"
    assert fila["Regreso en"] == "2026-10-14T15:50:00+00:00"
    assert fila["Finalizada en"] == "2026-10-14T15:52:00+00:00"
    assert fila["Distancia al punto (m)"] == 31
    assert fila["Distancia a la salida (m)"] == 10
    assert fila["Recorrido (m)"] == 11843
    assert fila["Codigo trazado"] == "trazado-0001"

    await _tomar(ANA, vuelta=V2)
    assert mundo.planilla[V2]["salio"] is True


async def test_no_se_finaliza_sin_haber_llegado(mundo):
    r = await _tomar(ANA)
    with pytest.raises(HTTPException) as exc:
        await _seguir(ANA, r.viaje, fin=_paso(5))

    assert exc.value.status_code == 409
    assert mundo.viaje(r.viaje)["Estado"] == "En camino"
    with pytest.raises(HTTPException):
        await _tomar(ANA, vuelta=V2)


async def test_llegar_se_anota_y_la_vuelta_sigue_abierta(mundo):
    r = await _tomar(ANA)
    paso = await _seguir(ANA, r.viaje, llegada=_paso(20, distancia_m=40))

    assert (paso.estado, paso.abierto) == ("en_punto", True)
    # El fin puede llegar despues, solo: la llegada ya esta guardada.
    cierre = await _seguir(ANA, r.viaje, fin=_paso(55))
    assert cierre.estado == "finalizada"


async def test_repetir_el_aviso_no_cambia_nada(mundo):
    r = await _tomar(ANA)
    pasos = {"llegada": _paso(20), "fin": _paso(55)}
    await _seguir(ANA, r.viaje, **pasos)
    antes = dict(mundo.viaje(r.viaje))
    await _seguir(ANA, r.viaje, **pasos)
    assert mundo.viaje(r.viaje) == antes


async def test_una_llegada_marcada_a_mano_queda_avisada(mundo):
    r = await _tomar(ANA)
    await _seguir(ANA, r.viaje, llegada=_paso(20, verificado=False))
    assert "a mano" in mundo.viaje(r.viaje)["Avisos"]


async def test_nadie_escribe_el_viaje_de_otro(mundo):
    r = await _tomar(ANA)
    with pytest.raises(HTTPException) as exc:
        await _seguir(BETO, r.viaje, llegada=_paso(20), fin=_paso(30))
    assert exc.value.status_code == 404
    assert mundo.viaje(r.viaje)["Estado"] == "En camino"


async def test_cerrarla_a_mano_en_airtable_libera_al_conductor(mundo):
    """La salida para un conductor trabado: coordinacion cambia el `Estado`."""
    r = await _tomar(ANA)
    mundo.viaje(r.viaje)["Estado"] = "Cerrada por coordinacion"

    mio = await camiones.mi_viaje(get_settings(), ANA)
    assert (mio.control, mio.viaje) == (True, None)
    await _tomar(ANA, vuelta=V2)

    # Y lo que el telefono mande despues no la vuelve a abrir.
    tarde = await _seguir(ANA, r.viaje, llegada=_paso(20))
    assert tarde.abierto is False
    assert mundo.viaje(r.viaje)["Estado"] == "Cerrada por coordinacion"


# ------------------------------- Devolver -------------------------------


async def test_devolver_la_deja_libre_y_me_libera(mundo):
    r = await _tomar(ANA)
    await camiones.soltar(get_settings(), ANA, V1)

    assert mundo.planilla[V1]["salio"] is False
    assert mundo.planilla[V1]["observaciones"] is None
    fila = mundo.viaje(r.viaje)
    assert fila["Estado"] == "Devuelta" and fila["Devuelta en"]

    # Otro la puede tomar, y yo puedo tomar otra.
    await _tomar(BETO)
    await _tomar(ANA, vuelta=V2)


async def test_no_se_devuelve_despues_de_llegar(mundo):
    r = await _tomar(ANA)
    await _seguir(ANA, r.viaje, llegada=_paso(20))
    with pytest.raises(HTTPException) as exc:
        await camiones.soltar(get_settings(), ANA, V1)

    assert exc.value.status_code == 409
    assert mundo.planilla[V1]["salio"] is True


async def test_nadie_devuelve_la_vuelta_de_otro(mundo):
    await _tomar(ANA)
    with pytest.raises(HTTPException) as exc:
        await camiones.soltar(get_settings(), BETO, V1)
    assert exc.value.status_code == 409
    assert mundo.planilla[V1]["salio"] is True


async def test_devolver_con_conductor_enlazado(mundo):
    mundo.usuarios["rec1"]["Cedula"] = "1122334"
    await _tomar(ANA)
    await camiones.soltar(get_settings(), ANA, V1)
    assert mundo.planilla[V1]["salio"] is False
    assert mundo.planilla[V1]["operador_id"] is None


# -------------------------------- La lista --------------------------------


async def test_la_lista_dice_a_nombre_de_quien_y_si_pide_clave(mundo):
    r = await camiones.pendientes(get_settings(), ANA)
    assert len(r.vueltas) == 2
    assert r.conductor.nombre == "Ana Gomez"
    assert r.conductor.pide_clave is True
    assert (r.control, r.viaje_abierto) == (True, None)

    de_google = await camiones.pendientes(get_settings(), GOOGLE)
    assert de_google.conductor.pide_clave is False


async def test_la_lista_trae_la_vuelta_sin_finalizar(mundo):
    """Con ella un telefono recien instalado la puede continuar."""
    tomada = await _tomar(ANA, salida=PATIO)
    r = await camiones.pendientes(get_settings(), ANA)

    abierto = r.viaje_abierto
    assert abierto.codigo == tomada.viaje
    assert abierto.estado == "en_camino"
    assert abierto.vuelta.id == V1
    assert abierto.vuelta.origen.lat == 4.45
    assert (abierto.salida.lat, abierto.salida.lon) == (4.40, -72.90)
    assert [v.id for v in r.vueltas] == [V2]

    assert (await camiones.pendientes(get_settings(), BETO)).viaje_abierto is None


async def test_la_lista_sale_aunque_no_se_pueda_leer_la_cuenta(mundo, monkeypatch):
    async def caido(*_, **__):
        raise HTTPException(status_code=502, detail="Airtable respondio 503")

    monkeypatch.setattr(airtable, "buscar_uno", caido)
    monkeypatch.setattr(airtable, "listar", caido)
    r = await camiones.pendientes(get_settings(), ANA)
    assert len(r.vueltas) == 2
    assert r.conductor is None
    assert r.control is False


# ------------------------- Si falta la tabla Vueltas -------------------------

SIN_TABLA = HTTPException(
    status_code=502,
    detail='Airtable respondio 403: {"error":{"type":'
    '"INVALID_PERMISSIONS_OR_MODEL_NOT_FOUND"}}',
)


async def test_sin_la_tabla_se_toma_igual_pero_sin_control(mundo):
    """Una tabla sin crear no puede dejar a los camiones parados."""
    mundo.falla_vueltas = SIN_TABLA

    r = await _tomar(ANA)
    assert r.viaje is None
    assert mundo.planilla[V1]["salio"] is True

    lista = await camiones.pendientes(get_settings(), ANA)
    assert (lista.control, lista.viaje_abierto) == (False, None)

    # Sin control no hay candado, y devolver se apoya en la nota.
    await _tomar(ANA, vuelta=V2)
    with pytest.raises(HTTPException):
        await camiones.soltar(get_settings(), BETO, V1)
    await camiones.soltar(get_settings(), ANA, V1)
    assert mundo.planilla[V1]["salio"] is False


async def test_si_el_seguimiento_no_queda_la_salida_se_deshace(mundo, monkeypatch):
    """Airtable caido a mitad de camino: las dos bases tienen que decir lo
    mismo, y lo mismo es que la vuelta sigue libre."""
    mundo.planilla[V1]["observaciones"] = "Urgente"
    guardar = mundo.guardar

    async def se_cae(settings, tabla, campos, record_id):
        if tabla == "Vueltas":
            raise HTTPException(status_code=502, detail="Airtable respondio 503")
        return await guardar(settings, tabla, campos, record_id)

    monkeypatch.setattr(airtable, "guardar", se_cae)
    with pytest.raises(HTTPException) as exc:
        await _tomar(ANA)

    assert exc.value.status_code == 502
    assert mundo.planilla[V1]["salio"] is False
    assert mundo.planilla[V1]["observaciones"] == "Urgente"


def test_que_errores_de_airtable_son_falta_de_tabla():
    def es(detalle: str) -> bool:
        return viajes._falta_la_tabla(HTTPException(status_code=500, detail=detalle))

    assert es(SIN_TABLA.detail)
    assert es("Airtable rechazo los campos de 'Vueltas': UNKNOWN_FIELD_NAME")
    assert es("The formula for filtering records is invalid: Unknown field names: estado")
    assert not es("Airtable respondio 503: Service Unavailable")
    assert not es("Airtable respondio 429: RATE_LIMIT")
