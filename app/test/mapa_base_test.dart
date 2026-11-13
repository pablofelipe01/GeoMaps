import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geomaps/core/fuente_teselas.dart';
import 'package:geomaps/core/teselas.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// El mapa base cuando no hay imagen del nivel que se pide.
///
/// El satelite, donde no tiene imagen, responde 200 con un cartel que dice
/// "Map data not yet available". En Guaicaramo pasa en cuanto se acerca el
/// mapa mas alla del nivel 18. Lo que se prueba es que ese cartel no se
/// muestre ni se guarde nunca, y que en su lugar salga la imagen del nivel de
/// arriba.
void main() {
  const plantilla = 'https://sat/tile/{z}/{y}/{x}';
  const etagRelleno = '"vvvvvvvvvvvvf"';

  // Una tesela del nivel 19 y su madre del 18.
  const hija = Tesela(19, 155858, 255591);
  const madre = Tesela(18, 77929, 127795);

  Uint8List imagen(int marca) => Uint8List.fromList(List.filled(64, marca));
  final relleno = Uint8List.fromList(List.filled(2521, 7));

  group('el cartel', () {
    test('se reconoce por su ETag, que es el mismo en todo el mundo', () {
      expect(esRellenoEsri(relleno, etag: etagRelleno), isTrue);
      expect(esRellenoEsri(imagen(1), etag: etagRelleno), isTrue);
    });

    test('una imagen de verdad no se confunde, aunque pese lo mismo', () {
      expect(esRellenoEsri(imagen(1), etag: '"4k2f4tvvf2evf"'), isFalse);
      // Mismo largo que el cartel, otro contenido: la huella no coincide.
      expect(esRellenoEsri(relleno), isFalse);
      expect(esRellenoEsri(imagen(1)), isFalse);
    });
  });

  group('el recorte', () {
    test('la madre de una tesela es la que la contiene', () {
      expect(hija.ancestro(1), madre);
      expect(hija.ancestro(0), hija);
      expect(const Tesela(2, 3, 1).ancestro(9), const Tesela(0, 0, 0));
    });

    test('un nivel arriba es un cuarto de la imagen', () {
      // (5,7) dentro de (2,3): columna impar y fila impar, abajo a la derecha.
      const t = Tesela(19, 5, 7);
      expect(t.recorteEn(const Tesela(18, 2, 3)), (128.0, 128.0, 128.0));
      expect(const Tesela(19, 4, 6).recorteEn(const Tesela(18, 2, 3)), (
        0.0,
        0.0,
        128.0,
      ));
    });

    test('dos niveles arriba es un dieciseisavo', () {
      const t = Tesela(19, 5, 7);
      expect(t.recorteEn(const Tesela(17, 1, 1)), (64.0, 192.0, 64.0));
    });

    test('sobre si misma es la imagen entera', () {
      expect(hija.recorteEn(hija), (0.0, 0.0, 256.0));
    });
  });

  group('la fuente', () {
    late _CacheFalsa cache;
    late List<String> pedidos;

    /// Un servidor que tiene imagen hasta el nivel [hasta] y de ahi en mas
    /// manda el cartel, como el satelite.
    FuenteTeselas fuente({int hasta = 18, bool sinRed = false, int? estado}) {
      return FuenteTeselas(
        plantilla: plantilla,
        paquete: 'prueba',
        almacen: () => cache,
        cliente: MockClient((pedido) async {
          pedidos.add(pedido.url.path);
          if (sinRed) throw const SocketException('sin red');
          if (estado != null) return http.Response('', estado);
          final z = int.parse(pedido.url.pathSegments[1]);
          return z <= hasta
              ? http.Response.bytes(imagen(z), 200, headers: {'etag': '"$z"'})
              : http.Response.bytes(
                  relleno,
                  200,
                  headers: {'etag': etagRelleno},
                );
        }),
      );
    }

    setUp(() {
      cache = _CacheFalsa();
      pedidos = [];
    });

    test('donde hay imagen, entrega la pedida y la guarda', () async {
      final r = await fuente().cargar(madre);

      expect(r.origen, madre);
      expect(r.bytes, imagen(18));
      expect(r.provisional, isFalse);
      await pumpEventQueue();
      expect(cache.guardadas.keys, [madre.url(plantilla)]);
    });

    test('donde manda el cartel, entrega la del nivel de arriba', () async {
      final r = await fuente().cargar(hija);

      expect(r.origen, madre, reason: 'la imagen es la del nivel 18');
      expect(r.bytes, imagen(18));
      expect(r.provisional, isFalse, reason: 'se sabe que no existe');
      await pumpEventQueue();
      expect(cache.guardadas.keys, [
        madre.url(plantilla),
      ], reason: 'el cartel no se guarda nunca');
    });

    test('sube varios niveles si hace falta', () async {
      const nieta = Tesela(21, 155858 * 4, 255591 * 4);
      final r = await fuente().cargar(nieta);
      expect(r.origen, madre);
    });

    test('no vuelve a preguntar por lo que ya sabe que falta', () async {
      final f = fuente();
      await f.cargar(hija);
      final antes = pedidos.length;

      await f.cargar(hija);
      // Y una tesela que cae adentro de la que falta tampoco se pregunta.
      await f.cargar(Tesela(20, hija.x * 2, hija.y * 2));

      expect(pedidos.length, antes);
    });

    test(
      'cuando un nivel viene faltando en la zona, deja de pedirlo',
      () async {
        final f = fuente();
        // Cinco vecinas del nivel 19, todas sin imagen.
        for (var i = 0; i < 5; i++) {
          await f.cargar(Tesela(19, hija.x + i, hija.y));
        }
        final antes = pedidos.where((p) => p.startsWith('/tile/19/')).length;

        for (var i = 5; i < 12; i++) {
          await f.cargar(Tesela(19, hija.x + i, hija.y));
        }

        expect(
          pedidos.where((p) => p.startsWith('/tile/19/')).length,
          antes,
          reason: 'las siguientes del mismo nivel y zona ya no se piden',
        );
      },
    );

    test('un cartel guardado de antes tambien se reconoce', () async {
      // El telefono que ya miro esta zona con la version anterior.
      cache.poner(hija.url(plantilla), relleno, etag: etagRelleno);
      cache.poner(madre.url(plantilla), imagen(18));

      final r = await fuente(sinRed: true).cargar(hija);

      expect(r.origen, madre);
      expect(r.provisional, isFalse);
      expect(pedidos, isEmpty, reason: 'todo salio de lo guardado');
    });

    test(
      'sin senal muestra lo guardado de mas arriba, y lo reintenta',
      () async {
        const abuela = Tesela(17, 38964, 63897);
        cache.poner(abuela.url(plantilla), imagen(17));
        final f = fuente(sinRed: true);

        final r = await f.cargar(madre);

        expect(r.origen, abuela);
        expect(r.provisional, isTrue, reason: 'no se pudo preguntar por ella');
        expect(f.fueProvisional(madre), isTrue);
        expect(f.fueProvisional(madre), isFalse, reason: 'se consulta una vez');
      },
    );

    test('sin senal no insiste con la red en cada tesela', () async {
      final f = fuente(sinRed: true);
      await expectLater(f.cargar(madre), throwsA(isA<SinTesela>()));
      final antes = pedidos.length;

      await expectLater(
        f.cargar(const Tesela(18, 77930, 127795)),
        throwsA(isA<SinTesela>()),
      );

      expect(antes, 1, reason: 'el primer fallo corta los intentos');
      expect(pedidos.length, antes);
    });

    test('una copia vencida sirve cuando no hay red', () async {
      cache.poner(madre.url(plantilla), imagen(18), vencida: true);

      final r = await fuente(sinRed: true).cargar(madre);

      expect(r.origen, madre);
      expect(r.bytes, imagen(18));
      expect(r.provisional, isFalse);
    });

    test('un 404 es que no hay imagen; un 503 es que no se sabe', () async {
      cache.poner(madre.url(plantilla), imagen(18));

      final con404 = await fuente(estado: 404).cargar(hija);
      expect(con404.origen, madre);
      expect(con404.provisional, isFalse);

      final con503 = await fuente(estado: 503).cargar(hija);
      expect(con503.origen, madre);
      expect(con503.provisional, isTrue);
    });
  });
}

/// Lo minimo de la cache de `flutter_map`: un mapa en memoria.
class _CacheFalsa implements MapCachingProvider {
  final guardadas = <String, CachedMapTile>{};

  void poner(
    String url,
    Uint8List bytes, {
    String? etag,
    bool vencida = false,
  }) {
    guardadas[url] = (
      bytes: bytes,
      metadata: CachedMapTileMetadata(
        staleAt: DateTime.timestamp().add(
          vencida ? const Duration(days: -1) : const Duration(days: 30),
        ),
        lastModified: null,
        etag: etag,
      ),
    );
  }

  @override
  bool get isSupported => true;

  @override
  Future<CachedMapTile?> getTile(String url) async => guardadas[url];

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    if (bytes != null) guardadas[url] = (bytes: bytes, metadata: metadata);
  }
}
