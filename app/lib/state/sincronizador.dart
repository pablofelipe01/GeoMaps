import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../data/db/app_database.dart';
import '../data/db/enums.dart';
import '../data/trazados_repository.dart';
import 'providers.dart';
import 'red.dart';
import 'sesion.dart';

/// Lo que la pantalla necesita saber de la subida.
class EstadoSincronizacion {
  const EstadoSincronizacion({
    this.subiendo = false,
    this.ultimaVez,
    this.subidos = 0,
    this.fallidos = 0,
    this.error,
  });

  final bool subiendo;

  /// Cuando termino el ultimo intento, haya salido bien o no.
  final DateTime? ultimaVez;

  final int subidos;
  final int fallidos;

  /// Por que fallo el ultimo intento, en palabras para alguien en el lote.
  final String? error;
}

/// Sube a Airtable lo que se hizo sin senal.
///
/// Corre cuando hay red y hay filas con `sincronizado = false`. El orden no es
/// arbitrario: Airtable necesita los enlaces resueltos, asi que un waypoint no
/// puede subir antes que su proyecto.
///
///   Proyectos -> Mapas -> Trazados -> Waypoints -> Archivos -> Sincronizaciones
///
/// Hoy sube los trazados, que es lo unico que el telefono genera. Cada paso es
/// un upsert por UUID: si una tanda se corta, la siguiente no duplica lo que ya
/// quedo. Cada intento deja una fila en `Sincronizaciones` local, y el backend
/// deja otra en Airtable: entre las dos se explica un dato que alguien dice que
/// no aparece.
class Sincronizador extends StateNotifier<EstadoSincronizacion> {
  Sincronizador(this._db, this._trazados, this._api, this._usuario)
    : super(const EstadoSincronizacion());

  final AppDatabase _db;
  final TrazadosRepository _trazados;
  final ApiClient _api;
  final String? _usuario;

  /// Aparte de `state.subiendo` porque se marca antes del primer `await`: dos
  /// llamadas en el mismo cuadro -guardar y volver la red- verian las dos
  /// `subiendo` en falso y mandarian la misma tanda dos veces.
  bool _corriendo = false;

  /// Cuantos trazados por request. Del otro lado es una funcion serverless con
  /// tiempo limitado y Airtable a cinco escrituras por segundo: una tanda chica
  /// que se corta pierde poco.
  static const tanda = 5;

  /// Sube todo lo pendiente. Llamarlo dos veces seguidas no sube dos veces:
  /// mientras corre, la segunda llamada vuelve sin hacer nada.
  Future<void> sincronizar() async {
    final usuario = _usuario;
    if (_corriendo || usuario == null || usuario.isEmpty) return;
    if (_api.token == null) return; // Sin sesion no hay a nombre de quien.

    _corriendo = true;
    try {
      await _subir(usuario);
    } finally {
      _corriendo = false;
    }
  }

  Future<void> _subir(String usuario) async {
    final pendientes = await _trazados.pendientes(usuario);
    if (pendientes.isEmpty || !mounted) return;

    state = EstadoSincronizacion(subiendo: true, ultimaVez: state.ultimaVez);
    final inicio = DateTime.now();
    var subidos = 0;
    final errores = <String>[];

    try {
      for (var i = 0; i < pendientes.length; i += tanda) {
        final parte = pendientes.skip(i).take(tanda).toList();
        final respuesta = await _api.sincronizar({
          'trazados': [for (final t in parte) _aJson(t)],
        });
        for (final r
            in (respuesta['trazados'] as List<dynamic>)
                .cast<Map<String, dynamic>>()) {
          if (r['ok'] == true) {
            await _trazados.marcarSubido(
              r['codigo'] as String,
              r['llave_geometria'] as String,
            );
            subidos++;
          } else {
            errores.add('${_nombre(parte, r['codigo'])}: ${r['error']}');
          }
        }
      }
    } on ApiError catch (e) {
      errores.add(
        e.sesionInvalida
            ? 'La sesion vencio. Volve a entrar con senal; lo guardado no se '
                  'pierde.'
            : e.mensaje,
      );
    } on TimeoutException {
      errores.add('El servidor no contesto a tiempo. Se reintenta solo.');
    } on SocketException {
      errores.add('Sin conexion con el servidor. Se reintenta con senal.');
    } on Exception catch (e) {
      errores.add('$e');
    }

    final fallidos = pendientes.length - subidos;
    await _anotar(inicio, pendientes.length, subidos, errores);
    // Cerrar sesion a mitad de la subida descarta este notifier.
    if (!mounted) return;
    state = EstadoSincronizacion(
      ultimaVez: DateTime.now(),
      subidos: subidos,
      fallidos: fallidos,
      error: errores.isEmpty ? null : errores.join('\n'),
    );
  }

  Map<String, dynamic> _aJson(Trazado t) => {
    'codigo': t.codigo,
    'proyecto_codigo': t.proyectoCodigo,
    'nombre': t.nombre,
    'tipo': t.tipo,
    'metodo': t.metodo,
    'geometria': jsonDecode(t.geometria),
    'distancia_m': t.distanciaM,
    'area_ha': t.areaHa,
    'precision_media_m': t.precisionMediaM,
    'bbox': t.bbox,
    'centro_lat': t.centroLat,
    'centro_lon': t.centroLon,
    'iniciado_en': t.iniciadoEn?.toUtc().toIso8601String(),
    'terminado_en': t.terminadoEn?.toUtc().toIso8601String(),
  };

  String _nombre(List<Trazado> parte, Object? codigo) =>
      parte.where((t) => t.codigo == codigo).firstOrNull?.nombre ?? '$codigo';

  Future<void> _anotar(
    DateTime inicio,
    int enviados,
    int subidos,
    List<String> errores,
  ) async {
    final resultado = subidos == enviados
        ? ResultadoSync.ok
        : (subidos == 0 ? ResultadoSync.fallida : ResultadoSync.parcial);
    try {
      await _db
          .into(_db.sincronizaciones)
          .insert(
            SincronizacionesCompanion.insert(
              codigo: const Uuid().v4(),
              inicio: inicio,
              fin: Value(DateTime.now()),
              enviados: Value(enviados),
              fallidos: Value(enviados - subidos),
              estado: resultado.name,
              detalle: Value(errores.isEmpty ? null : errores.join('\n')),
            ),
          );
    } catch (_) {
      // El log no puede tumbar la subida: lo que subio, subio.
    }
  }
}

final trazadosRepositoryProvider = Provider<TrazadosRepository>(
  (ref) => TrazadosRepository(ref.watch(dbProvider)),
);

final sincronizadorProvider =
    StateNotifierProvider<Sincronizador, EstadoSincronizacion>(
      (ref) => Sincronizador(
        ref.watch(dbProvider),
        ref.watch(trazadosRepositoryProvider),
        ref.watch(apiProvider),
        ref.watch(sesionProvider.select((e) => e.sesion?.codigoUsuario)),
      ),
    );

/// Las rutas guardadas de la cuenta que esta adentro.
final rutasGuardadasProvider = StreamProvider<List<RutaGuardada>>((ref) {
  final usuario = ref.watch(
    sesionProvider.select((e) => e.sesion?.codigoUsuario),
  );
  if (usuario == null) return Stream.value(const []);
  return ref.watch(trazadosRepositoryProvider).observarRutas(usuario);
});

/// Cuantos trazados faltan por subir.
final pendientesProvider = StreamProvider<int>((ref) {
  final usuario = ref.watch(
    sesionProvider.select((e) => e.sesion?.codigoUsuario),
  );
  if (usuario == null) return Stream.value(0);
  return ref.watch(trazadosRepositoryProvider).contarPendientes(usuario);
});

/// Dispara la subida cuando vuelve la red, y una vez al arrancar.
///
/// No hace falta que nadie se acuerde de sincronizar: el que guardo una ruta en
/// el lote y volvio al pueblo la tiene arriba en cuanto el telefono engancha.
/// Lo mantiene vivo la pantalla de inicio, que esta debajo de todas las demas.
final sincronizacionAutomaticaProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<RedState>>(redProvider, (antes, ahora) {
    final habia = antes?.valueOrNull?.hayRed ?? false;
    if (ahora.valueOrNull?.hayRed == true && !habia) {
      ref.read(sincronizadorProvider.notifier).sincronizar();
    }
  }, fireImmediately: true);
});
