import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geomaps/core/api_client.dart';
import 'package:geomaps/core/geo.dart';
import 'package:geomaps/data/db/app_database.dart';
import 'package:geomaps/data/db/enums.dart';
import 'package:geomaps/data/trazados_repository.dart';
import 'package:geomaps/data/waypoints_repository.dart';
import 'package:geomaps/state/sincronizador.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Los puntos marcados suben a la base: despues de los trazados, solo los que
/// el backend confirmo, y sin adelantarse al recorrido al que estan atados.
void main() {
  late AppDatabase db;
  late TrazadosRepository trazados;
  late WaypointsRepository puntos;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    trazados = TrazadosRepository(db);
    puntos = WaypointsRepository(db);
  });
  tearDown(() => db.close());

  const linea = [
    PuntoGeo(4.4500, -72.9600),
    PuntoGeo(4.4510, -72.9590),
    PuntoGeo(4.4525, -72.9580),
  ];

  /// Un backend que confirma todo lo que recibe y anota las llamadas.
  ApiClient apiQueConfirma(
    List<Map<String, dynamic>> llamadas, {
    bool sabeDePuntos = true,
    Set<String> rechaza = const {},
  }) {
    return ApiClient(
      cliente: MockClient((pedido) async {
        final cuerpo = jsonDecode(pedido.body) as Map<String, dynamic>;
        llamadas.add(cuerpo);
        return http.Response(
          jsonEncode({
            'trazados': [
              for (final t in (cuerpo['trazados'] as List? ?? const []))
                {
                  'codigo': (t as Map)['codigo'],
                  'ok': true,
                  'llave_geometria': 'proyectos/x/geometrias/y.geojson',
                },
            ],
            if (sabeDePuntos)
              'waypoints': [
                for (final w in (cuerpo['waypoints'] as List? ?? const []))
                  rechaza.contains((w as Map)['nombre'])
                      ? {'codigo': w['codigo'], 'ok': false, 'error': 'no'}
                      : {'codigo': w['codigo'], 'ok': true},
              ],
          }),
          200,
        );
      }),
    )..token = 'jwt';
  }

  test('sube el punto con lo que el backend espera', () async {
    await puntos.marcar(
      usuarioCodigo: 'u1',
      nombre: 'Alcantarilla',
      punto: const PuntoGeo(4.45, -72.96),
      simbolo: SimboloWaypoint.fuenteDeAgua,
      nota: 'Rota',
      precisionM: 6,
      marcadoEn: DateTime.utc(2026, 11, 12, 14),
    );
    final llamadas = <Map<String, dynamic>>[];
    final sync = Sincronizador(db, trazados, apiQueConfirma(llamadas), 'u1');

    await sync.sincronizar();

    final enviado = (llamadas.single['waypoints'] as List).single as Map;
    expect(enviado['nombre'], 'Alcantarilla');
    // El .name de Dart: el backend lo traduce a la opcion de Airtable.
    expect(enviado['simbolo'], 'fuenteDeAgua');
    expect(enviado['latitud'], 4.45);
    expect(enviado['longitud'], -72.96);
    expect(enviado['proyecto_codigo'], 'local');
    expect(enviado['marcado_en'], '2026-11-12T14:00:00.000Z');

    expect(await puntos.pendientes('u1'), isEmpty);
    expect(sync.state.subidos, 1);
    expect(sync.state.fallidos, 0);
    expect(sync.state.error, isNull);
    sync.dispose();
  });

  test('el que el backend rechaza queda pendiente, con su motivo', () async {
    await puntos.marcar(
      usuarioCodigo: 'u1',
      nombre: 'Bueno',
      punto: const PuntoGeo(4.45, -72.96),
    );
    await puntos.marcar(
      usuarioCodigo: 'u1',
      nombre: 'Malo',
      punto: const PuntoGeo(4.46, -72.95),
    );
    final sync = Sincronizador(
      db,
      trazados,
      apiQueConfirma([], rechaza: {'Malo'}),
      'u1',
    );

    await sync.sincronizar();

    expect((await puntos.pendientes('u1')).single.nombre, 'Malo');
    expect(sync.state.subidos, 1);
    expect(sync.state.fallidos, 1);
    expect(sync.state.error, contains('Malo'));
    sync.dispose();
  });

  test(
    'un punto de un recorrido en curso espera a que el recorrido suba',
    () async {
      final grabacion = await trazados.abrirGrabacion(
        usuarioCodigo: 'u1',
        nombre: 'Lindero',
      );
      await puntos.marcar(
        usuarioCodigo: 'u1',
        nombre: 'Mojon',
        punto: const PuntoGeo(4.45, -72.96),
        trazadoCodigo: grabacion.codigo,
      );
      final llamadas = <Map<String, dynamic>>[];
      final sync = Sincronizador(db, trazados, apiQueConfirma(llamadas), 'u1');

      // Con el recorrido todavia abierto no sube nada: ni el, ni su punto.
      await sync.sincronizar();
      expect(llamadas, isEmpty);
      expect(await puntos.contarPendientes('u1').first, 1);

      // Cerrado el recorrido, van los dos en la misma pasada y en orden.
      await trazados.cerrarGrabacion(grabacion.codigo, linea);
      await sync.sincronizar();

      expect(llamadas, hasLength(2));
      expect(llamadas.first.containsKey('trazados'), isTrue);
      final punto = (llamadas.last['waypoints'] as List).single as Map;
      expect(punto['trazado_codigo'], grabacion.codigo);
      expect(await puntos.contarPendientes('u1').first, 0);
      sync.dispose();
    },
  );

  test(
    'contra un backend que todavia no recibe puntos, quedan y se dice',
    () async {
      await puntos.marcar(
        usuarioCodigo: 'u1',
        nombre: 'Mojon',
        punto: const PuntoGeo(4.45, -72.96),
      );
      final sync = Sincronizador(
        db,
        trazados,
        apiQueConfirma([], sabeDePuntos: false),
        'u1',
      );

      await sync.sincronizar();

      expect((await puntos.pendientes('u1')).single.nombre, 'Mojon');
      expect(sync.state.error, contains('todavia no recibe puntos'));
      sync.dispose();
    },
  );

  test('la tarjeta cuenta trazados y puntos juntos', () async {
    final conteo = sumarConteos(
      trazados.contarPendientes('u1'),
      puntos.contarPendientes('u1'),
    );
    final vistos = <int>[];
    final sub = conteo.listen(vistos.add);
    await pumpEventQueue();

    await trazados.guardarRuta(
      usuarioCodigo: 'u1',
      nombre: 'Ruta',
      linea: linea,
      metros: 400,
    );
    await puntos.marcar(
      usuarioCodigo: 'u1',
      nombre: 'Mojon',
      punto: const PuntoGeo(4.45, -72.96),
    );
    await pumpEventQueue();
    await sub.cancel();

    expect(vistos.first, 0);
    expect(vistos.last, 2);
  });
}
