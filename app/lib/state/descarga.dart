import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/teselas.dart';

/// La descarga de una zona del mapa base, con su progreso.
///
/// Lo que hace es adelantar el trabajo que el mapa haria solo al mirarlo: pide
/// cada imagen de la zona y la deja en la **misma cache** que usa el mapa
/// (`BuiltInMapCachingProvider`, que `main.dart` configura al arrancar). No
/// hay un segundo almacen ni un formato propio: lo que se baja aca es
/// exactamente lo que el mapa va a encontrar sin senal.
///
/// Sobre red rural se corta, y esta pensado para eso: volver a pedir la misma
/// zona saltea lo que ya quedo guardado y baja solo lo que falta.
class EstadoDescarga {
  const EstadoDescarga({
    this.corriendo = false,
    this.total = 0,
    this.bajadas = 0,
    this.yaEstaban = 0,
    this.fallidas = 0,
    this.sinImagen = 0,
    this.bytes = 0,
    this.aviso,
  });

  final bool corriendo;

  /// Cuantas imagenes tiene la zona pedida.
  final int total;

  /// Las que se bajaron en esta tanda.
  final int bajadas;

  /// Las que ya estaban en el telefono y no hubo que pedir.
  final int yaEstaban;

  /// Las que el servidor no entrego. Se pueden reintentar pidiendo de nuevo.
  final int fallidas;

  /// Las que el satelite no tiene: en vez de imagen manda un cartel, y no se
  /// guarda. No es un fallo ni se arregla reintentando.
  final int sinImagen;

  /// Lo que pesaron las bajadas en esta tanda.
  final int bytes;

  /// Como termino, en palabras: nulo mientras corre o si nunca se pidio nada.
  final String? aviso;

  int get hechas => bajadas + yaEstaban + fallidas + sinImagen;
  double get progreso => total == 0 ? 0 : hechas / total;

  /// Todo lo que existe de la zona quedo en el telefono.
  bool get completa => total > 0 && bajadas + yaEstaban + sinImagen == total;
}

class Descargador extends StateNotifier<EstadoDescarga> {
  Descargador() : super(const EstadoDescarga());

  /// Mas alla de esto no se baja de una sola vez: son unos 200 MB, y una zona
  /// mas grande que eso casi siempre es un dedo de mas en el zoom. Se parte en
  /// dos zonas, o se baja con menos detalle.
  static const maximoTeselas = 12000;

  /// Pedidos a la vez. Pocos a proposito: es un servidor publico y gratuito, y
  /// en red rural mas pedidos en paralelo no bajan mas rapido, se pisan.
  static const _enParalelo = 4;

  /// Con tantos fallos seguidos no es una imagen rota, es que se fue la red:
  /// se corta en vez de recorrer miles de pedidos que van a fallar igual.
  static const _fallosParaCortar = 24;

  /// Desde que nivel se pregunta si el satelite tiene imagen. Por debajo
  /// siempre hay; por encima, en zona rural, se acaba pronto.
  static const _nivelDeSondeo = 16;

  bool _cancelada = false;

  /// Baja las imagenes de [zona] entre los niveles [zMin] y [zMax].
  ///
  /// [plantilla] y [paquete] tienen que ser los mismos que usa la capa del
  /// mapa: la cache guarda cada imagen bajo su direccion.
  Future<void> bajar({
    required ZonaTeselas zona,
    required int zMin,
    required int zMax,
    required String plantilla,
    required String paquete,
  }) async {
    if (state.corriendo) return;
    if (zona.contar(zMin, zMax) == 0) return;
    if (zona.contar(zMin, zMax) > maximoTeselas) {
      state = const EstadoDescarga(
        aviso:
            'La zona es demasiado grande para bajarla de una vez. Acerca el '
            'mapa o baja el nivel de detalle.',
      );
      return;
    }

    final MapCachingProvider cache;
    try {
      cache = BuiltInMapCachingProvider.getOrCreateInstance();
    } catch (_) {
      state = const EstadoDescarga(
        aviso: 'No se pudo abrir el almacen de mapas del telefono.',
      );
      return;
    }
    if (!cache.isSupported) {
      state = const EstadoDescarga(
        aviso: 'Este dispositivo no puede guardar mapas para usar sin senal.',
      );
      return;
    }

    _cancelada = false;
    state = EstadoDescarga(corriendo: true, total: zona.contar(zMin, zMax));

    final cliente = http.Client();
    final cabeceras = {'User-Agent': 'flutter_map ($paquete)'};

    // Antes de bajar, hasta donde tiene imagen el satelite en esta zona. En
    // una plantacion se acaba en el nivel 18: pedir el 19 serian miles de
    // pedidos que vuelven con el mismo cartel.
    final tope = await _hastaDondeHay(
      zona: zona,
      zMin: zMin,
      zMax: zMax,
      plantilla: plantilla,
      cliente: cliente,
      cabeceras: cabeceras,
    );
    if (!mounted) {
      cliente.close();
      return;
    }

    final total = zona.contar(zMin, tope);
    var bajadas = 0, yaEstaban = 0, fallidas = 0, sinImagen = 0;
    var bytes = 0, seguidos = 0;
    var sinRed = false;

    void avisar() {
      if (!mounted) return;
      state = EstadoDescarga(
        corriendo: true,
        total: total,
        bajadas: bajadas,
        yaEstaban: yaEstaban,
        fallidas: fallidas,
        sinImagen: sinImagen,
        bytes: bytes,
      );
    }

    avisar();
    final cola = zona.teselas(zMin, tope).iterator;

    Future<void> obrero() async {
      // Entre `moveNext` y `current` no hay ningun `await`: los obreros corren
      // en el mismo hilo y no se pisan la cola.
      while (!_cancelada && !sinRed && mounted && cola.moveNext()) {
        final url = cola.current.url(plantilla);

        try {
          final guardada = await cache.getTile(url);
          if (guardada != null) {
            // Un cartel guardado de antes no cuenta como imagen.
            if (esRellenoEsri(guardada.bytes, etag: guardada.metadata.etag)) {
              sinImagen++;
              if ((bajadas + yaEstaban + fallidas + sinImagen) % 25 == 0) {
                avisar();
              }
              continue;
            }
            if (!guardada.metadata.isStale) {
              yaEstaban++;
              if ((bajadas + yaEstaban + fallidas + sinImagen) % 25 == 0) {
                avisar();
              }
              continue;
            }
          }
        } catch (_) {
          // Una copia ilegible se vuelve a bajar encima.
        }

        try {
          final r = await cliente
              .get(Uri.parse(url), headers: cabeceras)
              .timeout(const Duration(seconds: 20));
          if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
            seguidos = 0;
            if (esRellenoEsri(r.bodyBytes, etag: r.headers['etag'])) {
              sinImagen++;
            } else {
              await cache.putTile(
                url: url,
                // La vigencia la pisa la cache con la suya (60 dias, ver
                // `main.dart`); el ETag es lo que despues deja revalidar
                // barato.
                metadata: CachedMapTileMetadata(
                  staleAt: DateTime.timestamp().add(const Duration(days: 60)),
                  lastModified: null,
                  etag: r.headers['etag'],
                ),
                bytes: r.bodyBytes,
              );
              bajadas++;
              bytes += r.bodyBytes.length;
            }
          } else if (r.statusCode == 404) {
            seguidos = 0;
            sinImagen++;
          } else {
            fallidas++;
            seguidos++;
          }
        } catch (_) {
          fallidas++;
          seguidos++;
        }

        if (seguidos >= _fallosParaCortar) sinRed = true;
        if ((bajadas + yaEstaban + fallidas + sinImagen) % 10 == 0) avisar();
      }
    }

    try {
      await Future.wait([for (var i = 0; i < _enParalelo; i++) obrero()]);
    } finally {
      cliente.close();
    }
    if (!mounted) return;

    final faltan = total - bajadas - yaEstaban - sinImagen;
    final String aviso;
    if (sinRed) {
      aviso =
          'Se corto la conexion. Lo que alcanzo a bajar quedo guardado: '
          'vuelve a pedir la zona con senal y sigue desde donde quedo.';
    } else if (_cancelada) {
      aviso =
          'Descarga cancelada. Lo que alcanzo a bajar quedo guardado y sirve '
          'sin senal.';
    } else if (faltan > 0) {
      aviso =
          'Quedaron $faltan imagenes sin bajar. Vuelve a pedir la zona para '
          'reintentar solo esas.';
    } else if (tope < zMax) {
      aviso =
          'La zona quedo guardada. Aca el satelite solo tiene imagen hasta el '
          'nivel $tope: mas cerca que eso el mapa la muestra ampliada.';
    } else {
      aviso = 'La zona quedo guardada: ya se puede ver sin senal.';
    }
    state = EstadoDescarga(
      total: total,
      bajadas: bajadas,
      yaEstaban: yaEstaban,
      fallidas: fallidas,
      sinImagen: sinImagen,
      bytes: bytes,
      aviso: aviso,
    );
  }

  /// El nivel mas fino, entre [zMin] y [zMax], del que el satelite tiene
  /// imagen en [zona].
  ///
  /// Se prueban cinco puntos de la zona por nivel -las esquinas y el centro-,
  /// y un nivel se descarta solo si **los cinco** vuelven con el cartel: si la
  /// zona tiene imagen fina en una parte, se baja el nivel y las que falten se
  /// saltean de a una. Sin red no se descarta nada: se sabra al bajar.
  Future<int> _hastaDondeHay({
    required ZonaTeselas zona,
    required int zMin,
    required int zMax,
    required String plantilla,
    required http.Client cliente,
    required Map<String, String> cabeceras,
  }) async {
    for (
      var z = zMin < _nivelDeSondeo ? _nivelDeSondeo : zMin;
      z <= zMax;
      z++
    ) {
      final (x0, x1, y0, y1) = zona.rango(z);
      final muestras = {
        Tesela(z, x0, y0),
        Tesela(z, x1, y0),
        Tesela(z, x0, y1),
        Tesela(z, x1, y1),
        Tesela(z, (x0 + x1) ~/ 2, (y0 + y1) ~/ 2),
      };
      try {
        final respuestas = await Future.wait([
          for (final t in muestras)
            cliente
                .get(Uri.parse(t.url(plantilla)), headers: cabeceras)
                .timeout(const Duration(seconds: 15)),
        ]);
        final ninguna = respuestas.every(
          (r) =>
              r.statusCode == 404 ||
              (r.statusCode == 200 &&
                  esRellenoEsri(r.bodyBytes, etag: r.headers['etag'])),
        );
        if (ninguna) return z - 1 < zMin ? zMin : z - 1;
      } catch (_) {
        return zMax;
      }
      if (_cancelada) break;
    }
    return zMax;
  }

  /// Corta la descarga en curso. Lo ya bajado se queda.
  void cancelar() => _cancelada = true;
}

/// No es `autoDispose` a proposito: la descarga sigue aunque se salga de la
/// pantalla, y al volver se ve por donde va.
final descargadorProvider = StateNotifierProvider<Descargador, EstadoDescarga>(
  (ref) => Descargador(),
);
