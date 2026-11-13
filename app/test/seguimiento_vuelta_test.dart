import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geomaps/camiones/seguimiento.dart';
import 'package:geomaps/core/api_client.dart';
import 'package:geomaps/core/geo.dart';
import 'package:geomaps/data/db/app_database.dart';
import 'package:geomaps/data/trazados_repository.dart';
import 'package:geomaps/state/sincronizador.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Las reglas de una vuelta: ir hasta los vagones, volver al punto de salida
/// y recien ahi finalizar.
///
/// Lo que se cuida: que nadie pueda dar por hecha una vuelta sin haber ido, y
/// que el estado no se pierda si la app se cierra a mitad de camino.
void main() {
  // El patio de donde sale el camion y el acopio donde estan los vagones,
  // a unos 7 km.
  const patio = PuntoGeo(4.4000, -72.9000);
  const acopio = PuntoGeo(4.4500, -72.9400);
  final t0 = DateTime.utc(2026, 11, 13, 15);

  // Un punto a [metros] al norte de otro.
  PuntoGeo alNorte(PuntoGeo p, double metros) =>
      PuntoGeo(p.latitud + metros / 111320, p.longitud);

  Map<String, Object?> recien({bool conPunto = true, bool conSalida = true}) =>
      {
        'vuelta_id': 'v1',
        'viaje': 'viaje-0001',
        if (conPunto) 'destino': [acopio.longitud, acopio.latitud],
        if (conSalida)
          'salida': Movimiento(en: t0, punto: patio, precisionM: 8).aJson(),
      };

  /// Aplica un fix y devuelve las propiedades como quedan.
  Map<String, Object?> con(
    Map<String, Object?> p,
    PuntoGeo donde, {
    double precision = 8,
    int minuto = 10,
  }) => {
    ...p,
    ...?SeguimientoVuelta.de(p).alFix(
      donde: donde,
      precisionM: precision,
      hora: t0.add(Duration(minutes: minuto)),
    ),
  };

  group('ir hasta los vagones', () {
    test('recien tomada: va de ida y no se puede finalizar', () {
      final s = SeguimientoVuelta.de(recien());
      expect(s.etapa, EtapaVuelta.yendo);
      expect(s.puedeFinalizar, isFalse);
      expect(s.puedeDevolver, isTrue);
      expect(s.faltaAlPunto(patio), closeTo(distanciaM(patio, acopio), 0.1));
    });

    test('a medio camino no llego', () {
      final p = con(recien(), alNorte(patio, 3000));
      expect(SeguimientoVuelta.de(p).etapa, EtapaVuelta.yendo);
    });

    test('llega al entrar al radio del acopio, no antes', () {
      final casi = con(recien(), alNorte(acopio, 140));
      expect(SeguimientoVuelta.de(casi).llegada, isNull);

      final llego = con(recien(), alNorte(acopio, 60), minuto: 25);
      final s = SeguimientoVuelta.de(llego);
      expect(s.etapa, EtapaVuelta.volviendo);
      expect(s.llegada!.en, t0.add(const Duration(minutes: 25)));
      expect(s.llegada!.distanciaM, closeTo(60, 1));
      expect(s.llegada!.verificado, isTrue);
      // Ya llego: se finaliza al volver, no se devuelve.
      expect(s.puedeDevolver, isFalse);
      expect(s.puedeFinalizar, isFalse);
    });

    test('un fix con mucho error no decide nada', () {
      final p = con(recien(), acopio, precision: 90);
      expect(SeguimientoVuelta.de(p).llegada, isNull);
    });
  });

  group('volver al punto de salida', () {
    final enAcopio = con(recien(), acopio, minuto: 25);

    test('haber llegado no es haber vuelto', () {
      final lejos = con(enAcopio, alNorte(patio, 2000), minuto: 40);
      final s = SeguimientoVuelta.de(lejos);
      expect(s.etapa, EtapaVuelta.volviendo);
      expect(s.faltaALaSalida(alNorte(patio, 2000)), closeTo(2000, 5));
    });

    test('vuelve al entrar al radio del punto de salida', () {
      final devuelta = con(enAcopio, alNorte(patio, 90), minuto: 55);
      final s = SeguimientoVuelta.de(devuelta);
      expect(s.etapa, EtapaVuelta.deVuelta);
      expect(s.puedeFinalizar, isTrue);
      expect(s.regreso!.en, t0.add(const Duration(minutes: 55)));
    });

    test('pasar por el patio sin haber ido a los vagones no cuenta', () {
      final p = con(recien(), alNorte(patio, 20));
      final s = SeguimientoVuelta.de(p);
      expect(s.regreso, isNull);
      expect(s.puedeFinalizar, isFalse);
    });

    test('una vez de vuelta, alejarse no lo deshace', () {
      final devuelta = con(enAcopio, patio, minuto: 55);
      final despues = con(devuelta, alNorte(patio, 800), minuto: 58);
      expect(SeguimientoVuelta.de(despues).puedeFinalizar, isTrue);
    });
  });

  group('el punto de salida', () {
    test('si el GPS no habia enganchado al tomarla, lo fija el primer fix', () {
      final p = con(recien(conSalida: false), alNorte(patio, 15), minuto: 1);
      final s = SeguimientoVuelta.de(p);
      expect(s.salida!.punto!.latitud, closeTo(alNorte(patio, 15).latitud, 1e-6));
      expect(s.etapa, EtapaVuelta.yendo);
    });

    test('un fix malo no sirve de punto de salida', () {
      final p = con(recien(conSalida: false), patio, precision: 200);
      expect(SeguimientoVuelta.de(p).salida, isNull);
    });
  });

  group('lo que no es una vuelta', () {
    test('un recorrido cualquiera no se vigila', () {
      const s = SeguimientoVuelta();
      expect(s.esVuelta, isFalse);
      expect(s.alFix(donde: acopio, precisionM: 5, hora: t0), isNull);
      expect(SeguimientoVuelta.cuerpo(const {'tipo': 'navegacion'}), isNull);
    });
  });

  group('un acopio sin coordenada', () {
    final p = recien(conPunto: false);

    test('el GPS no puede decir que llego: lo marca la persona', () {
      final s = SeguimientoVuelta.de(con(p, alNorte(patio, 5000)));
      expect(s.llegada, isNull);
      expect(s.llegadaAMano, isTrue);
    });

    test('no se marca desde el patio', () {
      final s = SeguimientoVuelta.de(p);
      expect(s.porQueNoMarcar(alNorte(patio, 40)), contains('punto de salida'));
      expect(s.porQueNoMarcar(null), contains('GPS'));
      expect(s.porQueNoMarcar(alNorte(patio, 900)), isNull);
    });

    test('marcada queda como no verificada, y despues hay que volver', () {
      final donde = alNorte(patio, 4000);
      final marcada = {
        ...p,
        ...SeguimientoVuelta.de(
          p,
        ).marcarLlegada(donde: donde, precisionM: 12, hora: t0),
      };
      final s = SeguimientoVuelta.de(marcada);
      expect(s.llegada!.verificado, isFalse);
      expect(s.etapa, EtapaVuelta.volviendo);

      final devuelta = con(marcada, patio, minuto: 50);
      expect(SeguimientoVuelta.de(devuelta).puedeFinalizar, isTrue);
    });
  });

  group('si la app se cerro a mitad de camino', () {
    test('la linea que paso por el acopio cuenta como llegada', () {
      final linea = [
        patio,
        alNorte(patio, 2500),
        alNorte(acopio, 30),
        alNorte(acopio, 900),
      ];
      final cambios = SeguimientoVuelta.de(recien()).alRetomar(linea, t0);
      expect(cambios!.keys, ['llegada']);
      final s = SeguimientoVuelta.de({...recien(), ...cambios});
      expect(s.etapa, EtapaVuelta.volviendo);
      expect(s.llegada!.distanciaM, closeTo(30, 1));
    });

    test('una linea que no llego no inventa nada', () {
      final linea = [patio, alNorte(patio, 2500)];
      expect(SeguimientoVuelta.de(recien()).alRetomar(linea, t0), isNull);
    });
  });

  group('lo que se avisa al servidor', () {
    test('manda todo lo que sabe, no solo lo nuevo', () {
      var p = con(recien(), acopio, minuto: 25);
      p = con(p, patio, minuto: 55);
      final s = SeguimientoVuelta.de(p);
      p = {
        ...p,
        'fin': s
            .fin(donde: alNorte(patio, 12), precisionM: 6, hora: t0)
            .aJson(),
      };

      final cuerpo = SeguimientoVuelta.cuerpo(
        p,
        recorridoM: 14321.6,
        trazado: 't1',
      )!;
      expect(cuerpo.keys, [
        'salida',
        'llegada',
        'regreso',
        'fin',
        'recorrido_m',
        'trazado',
      ]);
      expect((cuerpo['fin'] as Map)['distancia_m'], closeTo(12, 1));
      expect(cuerpo['recorrido_m'], 14322);
      // Va y vuelve por JSON sin perder nada.
      expect(jsonDecode(jsonEncode(cuerpo)), isA<Map<String, dynamic>>());
    });

    test('sin codigo de viaje no hay a quien avisar', () {
      final p = recien()..remove('viaje');
      expect(SeguimientoVuelta.cuerpo(p), isNull);
    });

    test('el aviso va al viaje, y sin senal no rompe nada', () async {
      final llamadas = <String>[];
      final api = ApiClient(
        cliente: MockClient((pedido) async {
          llamadas.add('${pedido.method} ${pedido.url.path}');
          expect(jsonDecode(pedido.body), contains('llegada'));
          return http.Response('{"estado":"en_punto","abierto":true}', 200);
        }),
      );
      await avisarSeguimiento(api, con(recien(), acopio));
      expect(llamadas, ['POST /v1/camiones/viajes/viaje-0001/seguimiento']);

      final sinSenal = ApiClient(
        cliente: MockClient((_) async => throw Exception('sin red')),
      );
      await avisarSeguimiento(sinSenal, con(recien(), acopio));
    });
  });

  group('con el recorrido grabado', () {
    late AppDatabase db;
    late TrazadosRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = TrazadosRepository(db);
    });
    tearDown(() => db.close());

    final linea = [patio, alNorte(patio, 3000), acopio, patio];

    test('lo anotado a mitad de camino sobrevive a que la app se cierre', () async {
      final t = await repo.abrirGrabacion(
        usuarioCodigo: 'u1',
        nombre: 'Vuelta #23',
        propiedades: recien(),
      );
      final llego = con(recien(), acopio, minuto: 25);
      await repo.guardarAvance(
        t.codigo,
        linea.sublist(0, 3),
        propiedades: llego,
      );
      // El guardado de cada tantos puntos, sin propiedades, no las borra.
      await repo.guardarAvance(t.codigo, linea);

      final abierta = await repo.grabacionAbierta('u1');
      final guardadas =
          (jsonDecode(abierta!.geometria) as Map)['properties']
              as Map<String, dynamic>;
      final s = SeguimientoVuelta.de(guardadas);
      expect(s.etapa, EtapaVuelta.volviendo);
      expect(s.viaje, 'viaje-0001');
      expect(s.punto!.latitud, acopio.latitud);
    });

    test('el seguimiento sube con el recorrido y cierra la vuelta', () async {
      final t = await repo.abrirGrabacion(
        usuarioCodigo: 'u1',
        nombre: 'Vuelta #23',
        propiedades: recien(),
      );
      var p = con(recien(), acopio, minuto: 25);
      p = con(p, patio, minuto: 55);
      final fin = SeguimientoVuelta.de(
        p,
      ).fin(donde: patio, hora: t0.add(const Duration(minutes: 56)));
      await repo.cerrarGrabacion(
        t.codigo,
        linea,
        propiedades: {...p, 'fin': fin.aJson()},
      );

      late Map<String, dynamic> enviado;
      final api = ApiClient(
        cliente: MockClient((pedido) async {
          enviado = jsonDecode(pedido.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'trazados': [
                {'codigo': t.codigo, 'ok': true, 'llave_geometria': 'k'},
              ],
            }),
            200,
          );
        }),
      )..token = 'jwt';
      final sync = Sincronizador(db, repo, api, 'u1');
      await sync.sincronizar();

      final viaje = ((enviado['trazados'] as List).single as Map)['viaje'] as Map;
      expect(viaje['codigo'], 'viaje-0001');
      expect(viaje.keys, containsAll(['salida', 'llegada', 'regreso', 'fin']));
      expect(viaje['recorrido_m'], isNotNull);
      sync.dispose();
    });

    test('un recorrido cualquiera no manda seguimiento', () async {
      final t = await repo.abrirGrabacion(usuarioCodigo: 'u1', nombre: 'x');
      await repo.cerrarGrabacion(t.codigo, linea);

      late Map<String, dynamic> enviado;
      final api = ApiClient(
        cliente: MockClient((pedido) async {
          enviado = jsonDecode(pedido.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'trazados': [
                {'codigo': t.codigo, 'ok': true, 'llave_geometria': 'k'},
              ],
            }),
            200,
          );
        }),
      )..token = 'jwt';
      final sync = Sincronizador(db, repo, api, 'u1');
      await sync.sincronizar();

      final trazado = (enviado['trazados'] as List).single as Map;
      expect(trazado.containsKey('viaje'), isFalse);
      sync.dispose();
    });
  });
}
