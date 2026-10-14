import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../core/geo.dart';
import '../core/ubicacion.dart';
import '../data/trazados_repository.dart';
import 'gps.dart';
import 'sesion.dart';
import 'sincronizador.dart';

/// Lo que la pantalla muestra de la grabacion en curso.
class EstadoGrabacion {
  const EstadoGrabacion({
    this.codigo,
    this.nombre,
    this.puntos = 0,
    this.metros = 0,
    this.precisionUltimaM,
    this.inicio,
    this.destino,
    this.destinoNombre,
    this.abiertaSinGrabar = false,
  });

  /// El trazado que se esta grabando. Nulo = no hay grabacion.
  final String? codigo;
  final String? nombre;
  final int puntos;
  final double metros;
  final double? precisionUltimaM;
  final DateTime? inicio;

  /// A donde iba el viaje, si iba a algun lado. Se guarda con el trazado para
  /// que, si la app se cierra a mitad de camino, al volver el mapa siga
  /// llevando al mismo acopio.
  final PuntoGeo? destino;
  final String? destinoNombre;

  /// Hay una grabacion abierta de antes -la app se cerro a mitad del viaje- y
  /// todavia no se retomo. La pantalla ofrece seguirla o terminarla.
  final bool abiertaSinGrabar;

  bool get grabando => codigo != null && !abiertaSinGrabar;
}

/// Graba un recorrido con el GPS: el viaje de un camion, y mas adelante el
/// lindero que camina un tecnico.
///
/// Escucha el [Gps] compartido, el mismo que dibuja la flecha en el mapa, y
/// mientras graba lo pasa a servicio en primer plano para que siga con la
/// pantalla apagada. Los puntos se guardan en la base cada tanto y no solo al
/// final: si Android mata la app en la mitad del viaje, se pierde a lo sumo el
/// ultimo tramo, y al volver la grabacion se puede retomar.
class Grabador extends StateNotifier<EstadoGrabacion> {
  Grabador(this._trazados, this._usuario, this._alCerrar)
    : super(const EstadoGrabacion()) {
    _buscarAbierta();
  }

  final TrazadosRepository _trazados;
  final String? _usuario;

  /// Que hacer con un trazado recien cerrado: subirlo.
  final void Function() _alCerrar;

  /// Un fix con mas error que esto no entra en la linea. Bajo palma cerrada el
  /// GPS da saltos de 60 m, y un viaje con esos picos mide kilometros de mas.
  static const precisionMaximaM = 40.0;

  /// Distancia minima entre dos puntos guardados. Un camion parado cargando
  /// no tiene por que sumar 1.800 puntos por media hora en el mismo lugar.
  static const separacionMinimaM = 10.0;

  /// Cada cuantos puntos nuevos se guarda el avance en la base.
  static const guardarCada = 15;

  final List<PuntoGeo> _puntos = [];
  final List<double> _precisiones = [];
  StreamSubscription<Position>? _gps;
  int _sinGuardar = 0;

  Future<void> _buscarAbierta() async {
    final usuario = _usuario;
    if (usuario == null) return;
    final abierta = await _trazados.grabacionAbierta(usuario);
    if (abierta == null || !mounted || state.codigo != null) return;
    final puntos = TrazadosRepository.puntosDe(abierta);
    final propiedades =
        (jsonDecode(abierta.geometria) as Map<String, dynamic>)['properties']
            as Map<String, dynamic>? ??
        const {};
    final destino = propiedades['destino'] as List<dynamic>?;
    _puntos
      ..clear()
      ..addAll(puntos);
    state = EstadoGrabacion(
      codigo: abierta.codigo,
      nombre: abierta.nombre,
      puntos: puntos.length,
      metros: longitudRutaM(puntos),
      inicio: abierta.iniciadoEn,
      destino: destino == null
          ? null
          : PuntoGeo(
              (destino[1] as num).toDouble(),
              (destino[0] as num).toDouble(),
            ),
      destinoNombre: propiedades['destino_nombre'] as String?,
      abiertaSinGrabar: true,
    );
  }

  /// Empieza a grabar un recorrido nuevo. Si ya habia uno, lo cierra antes:
  /// dos grabaciones a la vez serian dos copias del mismo viaje.
  Future<void> iniciar({
    required String nombre,
    PuntoGeo? destino,
    String? destinoNombre,
    Map<String, Object?> propiedades = const {},
  }) async {
    final usuario = _usuario;
    if (usuario == null) return;
    if (state.codigo != null) await terminar();

    final fila = await _trazados.abrirGrabacion(
      usuarioCodigo: usuario,
      nombre: nombre,
      propiedades: {
        ...propiedades,
        // [lon, lat], como todo en el GeoJSON.
        if (destino != null) 'destino': [destino.longitud, destino.latitud],
        'destino_nombre': destinoNombre,
      },
    );
    _puntos.clear();
    _precisiones.clear();
    if (!mounted) return;
    state = EstadoGrabacion(
      codigo: fila.codigo,
      nombre: fila.nombre,
      inicio: fila.iniciadoEn,
      destino: destino,
      destinoNombre: destinoNombre,
    );
    _escuchar();
  }

  /// Retoma la grabacion que quedo abierta, sumando a lo que ya tenia.
  void reanudar() {
    if (state.codigo == null || !state.abiertaSinGrabar) return;
    state = EstadoGrabacion(
      codigo: state.codigo,
      nombre: state.nombre,
      puntos: state.puntos,
      metros: state.metros,
      inicio: state.inicio,
      destino: state.destino,
      destinoNombre: state.destinoNombre,
    );
    _escuchar();
  }

  /// Cierra la grabacion, calcula sus numeros y la manda a subir.
  Future<void> terminar() async {
    final codigo = state.codigo;
    if (codigo == null) return;
    await _soltarGps();

    final precision = _precisiones.isEmpty
        ? null
        : _precisiones.reduce((a, b) => a + b) / _precisiones.length;
    await _trazados.cerrarGrabacion(
      codigo,
      List.of(_puntos),
      precisionMediaM: precision,
    );
    _puntos.clear();
    _precisiones.clear();
    if (mounted) state = const EstadoGrabacion();
    _alCerrar();
  }

  void _escuchar() {
    _gps?.cancel();
    Gps.instancia.grabarEnFondo(true);
    _gps = Gps.instancia.posiciones.listen(_alFix, onError: (_) {});
  }

  Future<void> _soltarGps() async {
    await _gps?.cancel();
    _gps = null;
    Gps.instancia.grabarEnFondo(false);
  }

  void _alFix(Position p) {
    if (!mounted || state.codigo == null) return;
    // La ultima conocida que se repite al reabrir el flujo no es del viaje.
    if (Ubicacion.esDeCache(p)) return;

    if (p.accuracy > precisionMaximaM) {
      state = _con(precision: p.accuracy);
      return;
    }
    final punto = PuntoGeo(p.latitude, p.longitude);
    final ultimo = _puntos.isEmpty ? null : _puntos.last;
    final paso = ultimo == null ? 0.0 : distanciaM(ultimo, punto);
    if (ultimo != null && paso < separacionMinimaM) {
      state = _con(precision: p.accuracy);
      return;
    }

    _puntos.add(punto);
    _precisiones.add(p.accuracy);
    state = _con(
      precision: p.accuracy,
      puntos: _puntos.length,
      metros: state.metros + paso,
    );

    if (++_sinGuardar >= guardarCada) {
      _sinGuardar = 0;
      unawaited(_trazados.guardarAvance(state.codigo!, List.of(_puntos)));
    }
  }

  EstadoGrabacion _con({double? precision, int? puntos, double? metros}) =>
      EstadoGrabacion(
        codigo: state.codigo,
        nombre: state.nombre,
        puntos: puntos ?? state.puntos,
        metros: metros ?? state.metros,
        precisionUltimaM: precision ?? state.precisionUltimaM,
        inicio: state.inicio,
        destino: state.destino,
        destinoNombre: state.destinoNombre,
      );

  @override
  void dispose() {
    // Salir de la cuenta a mitad de un viaje: se guarda lo que haya y la
    // grabacion queda abierta, para retomarla o cerrarla al volver.
    final codigo = state.codigo;
    if (codigo != null && _gps != null) {
      unawaited(_trazados.guardarAvance(codigo, List.of(_puntos)));
    }
    _gps?.cancel();
    if (_gps != null) Gps.instancia.grabarEnFondo(false);
    super.dispose();
  }
}

final grabadorProvider = StateNotifierProvider<Grabador, EstadoGrabacion>((
  ref,
) {
  return Grabador(
    ref.watch(trazadosRepositoryProvider),
    ref.watch(sesionProvider.select((e) => e.sesion?.codigoUsuario)),
    () => ref.read(sincronizadorProvider.notifier).sincronizar(),
  );
});
