import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geomaps/camiones/panel_viaje.dart';
import 'package:geomaps/camiones/vueltas.dart';
import 'package:geomaps/core/api_client.dart';
import 'package:geomaps/state/grabacion.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Tomar una vuelta: que la app pida solo lo que le falta a la cuenta, y que
/// el viaje sepa a donde dejar el vagon vacio.
///
/// El caso que rompia todo: la unica cuenta con el modulo de camiones era de
/// Google, el dialogo le pedia una clave que no tiene, y el backend la
/// rechazaba. La lista se veia y ninguna vuelta se dejaba tomar.
void main() {
  Map<String, dynamic> vuelta() => {
    'id': 'v1',
    'jornada': '2026-11-09',
    'consecutivo': 23,
    'tipo_fruto': 'comercial',
    'reportado_en': '2026-11-09T20:40:00Z',
    'origen': {'codigo': 'B.3-P.4 · 11A', 'bloque': '3', 'num': '11A'},
  };

  group('la lista', () {
    test('trae quien la esta mirando', () {
      final lista = ListaVueltas.deJson({
        'vueltas': [vuelta()],
        'conductor': {
          'cedula': '1122334',
          'nombre': 'ANA',
          'pide_clave': false,
        },
      });

      expect(lista.vueltas.single.consecutivo, 23);
      expect(lista.conductor!.tieneCedula, isTrue);
      expect(lista.conductor!.pideClave, isFalse);
      expect(lista.conductor!.nombre, 'ANA');
      expect(lista.conductor!.cedulaOculta, '***334');
    });

    test('sin conductor -un backend viejo, o Airtable caido- igual se lee', () {
      final lista = ListaVueltas.deJson({
        'vueltas': [vuelta()],
      });
      expect(lista.vueltas.length, 1);
      expect(lista.conductor, isNull);
    });

    test(
      'una cuenta nueva no tiene cedula, y por defecto se le pide clave',
      () {
        final c = Conductor.deJson({'cedula': null, 'nombre': null});
        expect(c.tieneCedula, isFalse);
        expect(c.pideClave, isTrue);
      },
    );

    test('una vuelta sin coordenada se lee: se toma igual, sin ruta', () {
      expect(Vuelta.deJson(vuelta()).origen.punto, isNull);
    });
  });

  group('confirmar', () {
    Future<Map<String, dynamic>> cuerpoDe({
      String? cedula,
      String? clave,
    }) async {
      late Map<String, dynamic> enviado;
      final api = ApiClient(
        cliente: MockClient((pedido) async {
          expect(pedido.url.path, '/v1/camiones/vueltas/v1/confirmar');
          enviado = jsonDecode(pedido.body) as Map<String, dynamic>;
          return http.Response('{"conductor":"ANA","vuelta":{}}', 200);
        }),
      );
      final r = await api.confirmarVuelta('v1', cedula: cedula, clave: clave);
      expect(r['conductor'], 'ANA');
      return enviado;
    }

    test('una cuenta de Google con cedula atada no manda nada', () async {
      expect(await cuerpoDe(), isEmpty);
    });

    test(
      'la primera vez de una cuenta de Google manda solo la cedula',
      () async {
        expect(await cuerpoDe(cedula: '1122334'), {'cedula': '1122334'});
      },
    );

    test('una cuenta con clave y cedula atada manda solo la clave', () async {
      expect(await cuerpoDe(clave: 'secreta-1'), {'clave': 'secreta-1'});
    });

    test('un rechazo de validacion no se muestra crudo', () async {
      // Lo que responde un backend anterior a este cambio cuando una cuenta
      // de Google confirma sin clave: una lista de campos, no un texto.
      final api = ApiClient(
        cliente: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'detail': [
                {
                  'type': 'missing',
                  'loc': ['body', 'clave'],
                  'msg': 'Field required',
                },
              ],
            }),
            422,
          ),
        ),
      );
      await expectLater(
        api.confirmarVuelta('v1', cedula: '1122334'),
        throwsA(
          isA<ApiError>()
              .having((e) => e.codigo, 'codigo', 422)
              .having((e) => e.mensaje, 'mensaje', contains('desactualizados'))
              .having((e) => e.mensaje, 'mensaje', isNot(contains('loc'))),
        ),
      );
    });

    test('el mensaje del backend llega tal cual', () async {
      final api = ApiClient(
        cliente: MockClient(
          (_) async => http.Response(
            jsonEncode({'detail': 'Esta vuelta ya la tomo otro camion.'}),
            409,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await expectLater(
        api.confirmarVuelta('v1', cedula: '1'),
        throwsA(
          isA<ApiError>()
              .having((e) => e.codigo, 'codigo', 409)
              .having((e) => e.mensaje, 'mensaje', contains('otro camion')),
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
  });

  group('el viaje', () {
    test('sabe de que vuelta es y donde dejar el vagon', () {
      const g = EstadoGrabacion(
        codigo: 'abc',
        propiedades: {
          'vuelta_id': 'v1',
          // [lon, lat], como en el GeoJSON.
          'entrega': [-72.96, 4.45],
          'entrega_nombre': '7 · 7',
          'vagon': '163',
        },
      );
      expect(g.vueltaId, 'v1');
      expect(g.entrega!.latitude, 4.45);
      expect(g.entrega!.longitude, -72.96);
      expect(g.entregaNombre, '7 · 7');
      expect(g.vagon, '163');
    });

    test('un recorrido cualquiera no es una vuelta', () {
      const g = EstadoGrabacion(codigo: 'abc');
      expect(g.vueltaId, isNull);
      expect(g.entrega, isNull);
    });
  });
}
