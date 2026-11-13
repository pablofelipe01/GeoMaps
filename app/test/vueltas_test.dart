import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geomaps/camiones/panel_viaje.dart';
import 'package:geomaps/camiones/seguimiento.dart';
import 'package:geomaps/camiones/vueltas.dart';
import 'package:geomaps/core/api_client.dart';
import 'package:geomaps/state/grabacion.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Tomar una vuelta: lo que la app lee del backend y lo que le manda.
///
/// La cedula ya no se pide ni se manda: la vuelta queda a nombre de la cuenta,
/// firmada con su clave si tiene una.
void main() {
  Map<String, dynamic> vuelta({double? lat}) => {
    'id': 'v1',
    'jornada': '2026-11-09',
    'consecutivo': 23,
    'tipo_fruto': 'comercial',
    'reportado_en': '2026-11-09T20:40:00Z',
    'origen': {
      'codigo': 'B.3-P.4 · 11A',
      'bloque': 'B.3',
      'num': '11A',
      'lat': lat,
      'lon': lat == null ? null : -72.98,
    },
  };

  group('la lista', () {
    test('trae a nombre de quien quedan y si pide clave', () {
      final lista = ListaVueltas.deJson({
        'vueltas': [vuelta()],
        // `cedula` lo sigue mandando el backend, vacio: se ignora.
        'conductor': {'cedula': null, 'nombre': 'Ana Gomez', 'pide_clave': false},
        'control': true,
      });

      expect(lista.vueltas.single.consecutivo, 23);
      expect(lista.conductor!.nombre, 'Ana Gomez');
      expect(lista.conductor!.pideClave, isFalse);
      expect(lista.control, isTrue);
      expect(lista.viajeAbierto, isNull);
    });

    test('un servidor anterior no manda ni conductor ni control', () {
      final lista = ListaVueltas.deJson({
        'vueltas': [vuelta()],
      });
      expect(lista.vueltas.length, 1);
      expect(lista.conductor, isNull);
      expect(lista.control, isFalse);
      expect(lista.viajeAbierto, isNull);
    });

    test('por defecto a una cuenta se le pide clave', () {
      expect(Conductor.deJson({'nombre': null}).pideClave, isTrue);
    });

    test('una vuelta sin coordenada se lee: se toma igual, sin ruta', () {
      expect(Vuelta.deJson(vuelta()).origen.punto, isNull);
    });

    test('trae la vuelta sin finalizar, completa para poder continuarla', () {
      final lista = ListaVueltas.deJson({
        'vueltas': <Map<String, dynamic>>[],
        'control': true,
        'viaje_abierto': {
          'codigo': 'viaje-0001',
          'vuelta_id': 'v1',
          'nombre': 'Vuelta #23 · B.3-P.4 · 11A',
          'estado': 'en_punto',
          'tomada_en': '2026-11-09T20:45:00Z',
          'salida': {'lat': 4.40, 'lon': -72.90, 'precision_m': null},
          'llegada_en': '2026-11-09T21:05:00Z',
          'regreso_en': null,
          'vuelta': vuelta(lat: 4.49),
        },
      });

      final abierto = lista.viajeAbierto!;
      expect(abierto.codigo, 'viaje-0001');
      expect(abierto.titulo, 'Vuelta #23');
      expect(abierto.salida!.latitude, 4.40);
      expect(abierto.llegadaEn, DateTime.utc(2026, 11, 9, 21, 5));
      expect(abierto.regresoEn, isNull);
      expect(abierto.vuelta!.origen.punto!.latitude, 4.49);
    });

    test('si el renglon ya no se pudo leer, queda el nombre', () {
      final abierto = ViajeAbierto.deJson({
        'codigo': 'viaje-0001',
        'vuelta_id': 'v1',
        'nombre': 'Vuelta #23 · B.3-P.4 · 11A',
        'estado': 'en_camino',
      });
      expect(abierto.vuelta, isNull);
      expect(abierto.titulo, 'Vuelta #23 · B.3-P.4 · 11A');
    });
  });

  group('el sitio, con todas las letras', () {
    test('bloque, parcela y acopio escritos enteros', () {
      final s = Vuelta.deJson(vuelta()).origen;
      expect(s.acopio, 'Acopio 11A');
      expect(s.lugar, 'Bloque 3 · Parcela 4');
      expect(s.largo, 'Bloque 3 · Parcela 4 · Acopio 11A');
      // El corto no cambia: es como se nombran los viajes ya guardados.
      expect(s.corto, 'B.3 · 11A');
    });

    test('sin parcela en el rotulo queda el bloque', () {
      final s = Sitio.deJson({'codigo': '7 · 7', 'bloque': '7', 'num': '7'});
      expect(s.largo, 'Bloque 7 · Acopio 7');
    });

    test('sin bloque no inventa uno', () {
      final s = Sitio.deJson({'num': '5'});
      expect(s.lugar, '');
      expect(s.largo, 'Acopio 5');
    });
  });

  group('tomar', () {
    Future<Map<String, dynamic>> cuerpoDe({
      String? clave,
      Map<String, Object?>? salida,
    }) async {
      late Map<String, dynamic> enviado;
      final api = ApiClient(
        cliente: MockClient((pedido) async {
          expect(pedido.url.path, '/v1/camiones/vueltas/v1/confirmar');
          enviado = jsonDecode(pedido.body) as Map<String, dynamic>;
          return http.Response(
            '{"conductor":"Ana Gomez","viaje":"viaje-0001","vuelta":{}}',
            200,
          );
        }),
      );
      final r = await api.confirmarVuelta('v1', clave: clave, salida: salida);
      expect(r['conductor'], 'Ana Gomez');
      expect(r['viaje'], 'viaje-0001');
      return enviado;
    }

    test('una cuenta de Google no manda nada que escribir', () async {
      expect(await cuerpoDe(), isEmpty);
    });

    test('una cuenta con clave manda la clave, y nunca una cedula', () async {
      final cuerpo = await cuerpoDe(clave: 'secreta-1');
      expect(cuerpo, {'clave': 'secreta-1'});
      expect(cuerpo.containsKey('cedula'), isFalse);
    });

    test('manda de donde sale el camion', () async {
      final cuerpo = await cuerpoDe(
        clave: 'secreta-1',
        salida: {'lat': 4.40, 'lon': -72.90, 'precision_m': 8.0},
      );
      expect(cuerpo['salida'], {'lat': 4.40, 'lon': -72.90, 'precision_m': 8.0});
    });

    test('un rechazo de validacion no se muestra crudo', () async {
      // Lo que responde un backend anterior, que todavia exige la cedula:
      // una lista de campos, no un texto.
      final api = ApiClient(
        cliente: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'detail': [
                {
                  'type': 'missing',
                  'loc': ['body', 'cedula'],
                  'msg': 'Field required',
                },
              ],
            }),
            422,
          ),
        ),
      );
      await expectLater(
        api.confirmarVuelta('v1', clave: 'x'),
        throwsA(
          isA<ApiError>()
              .having((e) => e.codigo, 'codigo', 422)
              .having((e) => e.mensaje, 'mensaje', contains('desactualizados'))
              .having((e) => e.mensaje, 'mensaje', isNot(contains('loc'))),
        ),
      );
    });

    test('tener otra sin finalizar llega con su mensaje', () async {
      final api = ApiClient(
        cliente: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'detail': 'Tienes Vuelta #23 sin finalizar. Finalizala para '
                  'tomar otra.',
            }),
            423,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await expectLater(
        api.confirmarVuelta('v1'),
        throwsA(
          isA<ApiError>()
              .having((e) => e.codigo, 'codigo', 423)
              .having((e) => e.mensaje, 'mensaje', contains('sin finalizar')),
        ),
      );
    });

    test('soltar una vuelta es un POST a su renglon', () async {
      var llamado = false;
      final api = ApiClient(
        cliente: MockClient((pedido) async {
          llamado = true;
          expect(pedido.method, 'POST');
          expect(pedido.url.path, '/v1/camiones/vueltas/v1/soltar');
          return http.Response('{"vuelta":{}}', 200);
        }),
      );
      await api.soltarVuelta('v1');
      expect(llamado, isTrue);
    });

    test('la vuelta abierta se le pregunta al servidor', () async {
      final api = ApiClient(
        cliente: MockClient((pedido) async {
          expect(pedido.method, 'GET');
          expect(pedido.url.path, '/v1/camiones/viaje');
          return http.Response('{"control":true,"viaje":null}', 200);
        }),
      );
      expect(await api.miViaje(), {'control': true, 'viaje': null});
    });
  });

  group('el viaje', () {
    test('sabe de que vuelta es, donde dejar el vagon y por donde va', () {
      final g = EstadoGrabacion(
        codigo: 'abc',
        propiedades: {
          'vuelta_id': 'v1',
          'viaje': 'viaje-0001',
          // [lon, lat], como en el GeoJSON.
          'entrega': [-72.96, 4.45],
          'entrega_nombre': 'Bloque 7 · Acopio 7',
          'vagon': '163',
          'llegada': {'en': '2026-11-09T21:05:00Z'},
        },
      );
      expect(g.esVuelta, isTrue);
      expect(g.vueltaId, 'v1');
      expect(g.entrega!.latitude, 4.45);
      expect(g.entrega!.longitude, -72.96);
      expect(g.entregaNombre, 'Bloque 7 · Acopio 7');
      expect(g.vagon, '163');
      expect(g.seguimiento.viaje, 'viaje-0001');
      expect(g.seguimiento.etapa, EtapaVuelta.volviendo);
    });

    test('un recorrido cualquiera no es una vuelta', () {
      const g = EstadoGrabacion(codigo: 'abc');
      expect(g.esVuelta, isFalse);
      expect(g.vueltaId, isNull);
      expect(g.entrega, isNull);
    });
  });
}
