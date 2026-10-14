import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geomaps/core/api_client.dart';
import 'package:geomaps/core/geo.dart';
import 'package:geomaps/core/geojson.dart';
import 'package:geomaps/data/db/app_database.dart';
import 'package:geomaps/data/trazados_repository.dart';
import 'package:geomaps/state/sincronizador.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Las rutas que se guardan desde el mapa: que queden bien en el telefono y
/// que solo se marquen subidas las que el backend confirmo.
void main() {
  const linea = [
    PuntoGeo(4.2800, -72.8900),
    PuntoGeo(4.2810, -72.8880),
    PuntoGeo(4.2830, -72.8850),
  ];

  late AppDatabase db;
  late TrazadosRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TrazadosRepository(db);
  });

  tearDown(() => db.close());

  test('el GeoJSON va en [longitud, latitud]', () {
    final g = GeoJson.linea(linea);
    final coords = (g['geometry'] as Map)['coordinates'] as List;
    expect(coords.first, [-72.89, 4.28]);

    final vuelta = GeoJson.puntosDeLinea(g);
    expect(vuelta.last.latitud, 4.283);
    expect(vuelta.last.longitud, -72.885);
    expect(GeoJson.bbox(linea), '-72.89,4.28,-72.885,4.283');
  });

  test('guarda la ruta pendiente y la lista por usuario', () async {
    final t = await repo.guardarRuta(
      usuarioCodigo: 'u1',
      nombre: '  Acopio 12 ',
      linea: linea,
      metros: 612.4,
    );
    await repo.guardarRuta(
      usuarioCodigo: 'u2',
      nombre: 'De otra cuenta',
      linea: linea,
      metros: 10,
    );

    expect(t.sincronizado, isFalse);
    expect(t.tipo, 'ruta');
    expect(t.metodo, 'calculada');
    expect(t.puntos, 3);

    final rutas = await repo.observarRutas('u1').first;
    expect(rutas, hasLength(1), reason: 'no se ven las de otra cuenta');
    expect(rutas.single.nombre, 'Acopio 12');
    expect(rutas.single.destino.latitud, 4.283, reason: 'va al ultimo punto');
  });

  test('solo marca subidas las que el backend confirmo', () async {
    final buena = await repo.guardarRuta(
      usuarioCodigo: 'u1',
      nombre: 'Buena',
      linea: linea,
      metros: 1,
    );
    final mala = await repo.guardarRuta(
      usuarioCodigo: 'u1',
      nombre: 'Mala',
      linea: linea,
      metros: 1,
    );

    late Map<String, dynamic> enviado;
    final api = ApiClient(
      cliente: MockClient((req) async {
        enviado = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'trazados': [
              {
                'codigo': buena.codigo,
                'ok': true,
                'llave_geometria': 'proyectos/local-1/geometrias/x.geojson',
              },
              {'codigo': mala.codigo, 'ok': false, 'error': 'no'},
            ],
          }),
          200,
        );
      }),
    )..token = 'jwt';

    final sync = Sincronizador(db, repo, api, 'u1');
    await sync.sincronizar();

    final trazados = enviado['trazados'] as List;
    expect(trazados, hasLength(2));
    expect((trazados.first as Map)['metodo'], 'calculada');

    final pendientes = await repo.pendientes('u1');
    expect(pendientes.map((t) => t.codigo), [mala.codigo]);
    expect(sync.state.subidos, 1);
    expect(sync.state.fallidos, 1);
    expect(sync.state.error, contains('Mala'));

    final log = await db.select(db.sincronizaciones).getSingle();
    expect(log.estado, 'parcial');
    sync.dispose();
  });
}
