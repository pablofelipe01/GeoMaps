import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geomaps/camiones/vueltas.dart';
import 'package:geomaps/core/geo.dart';
import 'package:geomaps/data/db/app_database.dart';
import 'package:geomaps/data/trazados_repository.dart';

/// El modulo de camiones: leer el QR de SiriusFleet, resumir la lista, y que un
/// viaje a medio grabar no suba como si estuviera completo.
void main() {
  group('QR', () {
    test('reconoce el de vueltas pendientes, venga del dominio que venga', () {
      expect(
        esQrDeVueltas('https://fleet.sirius.co/despacho/pendientes'),
        isTrue,
      );
      expect(
        esQrDeVueltas('https://otro.vercel.app/despacho/pendientes/'),
        isTrue,
      );
    });

    test('no confunde otros QR', () {
      expect(esQrDeVueltas('https://fleet.sirius.co/despacho'), isFalse);
      expect(esQrDeVueltas('despacho/pendientes'), isFalse);
      expect(esQrDeVueltas('WIFI:S:Finca;T:WPA;P:123;;'), isFalse);
    });
  });

  test('resume la lista', () {
    Map<String, dynamic> vuelta(String fruto, String jornada, {double? lat}) =>
        {
          'id': '1',
          'jornada': jornada,
          'consecutivo': 9,
          'tipo_fruto': fruto,
          'reportado_en': '${jornada}T13:50:00Z',
          'origen': {
            'codigo': 'B.7-P.3 · 7',
            'bloque': '7',
            'num': '7',
            'lat': lat,
            'lon': lat == null ? null : -72.96,
          },
        };

    final lista = [
      Vuelta.deJson(vuelta('comercial', '2026-10-14', lat: 4.45)),
      Vuelta.deJson(vuelta('hibrido', '2026-10-14', lat: 4.46)),
      Vuelta.deJson(vuelta('comercial', '2026-10-13')),
    ];
    final r = ResumenVueltas(lista, DateTime(2026, 10, 14, 12));

    expect(r.total, 3);
    expect(r.comercial, 2);
    expect(r.hibrido, 1);
    expect(r.deOtroDia, 1);
    expect(r.sinCoordenada, 1);
    expect(lista.first.origen.corto, '7 · 7');
    expect(lista.first.nombreViaje, 'Vuelta #9 · 7 · 7');
  });

  group('grabacion', () {
    late AppDatabase db;
    late TrazadosRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = TrazadosRepository(db);
    });
    tearDown(() => db.close());

    const puntos = [
      PuntoGeo(4.4500, -72.9600),
      PuntoGeo(4.4510, -72.9590),
      PuntoGeo(4.4525, -72.9580),
    ];

    test('abierta no sube; cerrada si, con sus numeros', () async {
      final t = await repo.abrirGrabacion(
        usuarioCodigo: 'u1',
        nombre: 'Vuelta #9',
        propiedades: {'vuelta_id': 'abc'},
      );
      await repo.guardarAvance(t.codigo, puntos.sublist(0, 2));

      expect(await repo.pendientes('u1'), isEmpty);
      expect((await repo.grabacionAbierta('u1'))?.codigo, t.codigo);

      final cerrada = await repo.cerrarGrabacion(
        t.codigo,
        puntos,
        precisionMediaM: 6,
      );
      expect(cerrada!.terminadoEn, isNotNull);
      expect(cerrada.puntos, 3);
      expect(cerrada.distanciaM, closeTo(longitudRutaM(puntos), 0.01));
      expect(cerrada.geometria, contains('"vuelta_id":"abc"'));
      expect(await repo.grabacionAbierta('u1'), isNull);
      expect((await repo.pendientes('u1')).single.codigo, t.codigo);
    });

    test('sin puntos no queda nada', () async {
      final t = await repo.abrirGrabacion(usuarioCodigo: 'u1', nombre: 'x');
      expect(await repo.cerrarGrabacion(t.codigo, const []), isNull);
      expect(await db.select(db.trazados).get(), isEmpty);
    });
  });
}
