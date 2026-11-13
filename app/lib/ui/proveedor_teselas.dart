import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

import '../core/fuente_teselas.dart';
import '../core/teselas.dart';

/// El proveedor de imagenes del mapa base.
///
/// Reemplaza al de `flutter_map` por una sola razon: aquel pide la tesela y,
/// si no hay, deja el hueco -o muestra el cartel de "Map data not yet
/// available" que manda el satelite-. Este le pide la imagen a
/// [FuenteTeselas], que cuando no existe la del nivel pedido trae la del nivel
/// de arriba, y aca se recorta el pedazo que corresponde y se lo estira.
///
/// Usa la misma cache que antes, bajo las mismas direcciones: lo que el
/// telefono ya tenia guardado sigue sirviendo.
class ProveedorTeselas extends TileProvider {
  ProveedorTeselas(this.fuente);

  final FuenteTeselas fuente;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final imagen = ImagenTesela(
      Tesela(coordinates.z, coordinates.x, coordinates.y),
      fuente,
    );
    // Una tesela que se resolvio a medias por falta de red queda en la
    // memoria de imagenes de Flutter como si fuera la buena. Se la saca para
    // que este pedido vuelva a preguntar: si ya hay senal, ahora si llega.
    if (fuente.fueProvisional(imagen.tesela)) {
      PaintingBinding.instance.imageCache.evict(imagen);
    }
    return imagen;
  }
}

/// La imagen de una tesela, propia o prestada del nivel de arriba.
@immutable
class ImagenTesela extends ImageProvider<ImagenTesela> {
  const ImagenTesela(this.tesela, this.fuente);

  final Tesela tesela;
  final FuenteTeselas fuente;

  @override
  Future<ImagenTesela> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    ImagenTesela key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      _cargar(decode),
      informationCollector: () => [
        DiagnosticsProperty('Tesela', tesela),
        DiagnosticsProperty('Plantilla', fuente.plantilla),
      ],
    );
  }

  Future<ImageInfo> _cargar(ImageDecoderCallback decode) async {
    final cargada = await fuente.cargar(tesela);
    final codec = await decode(
      await ui.ImmutableBuffer.fromUint8List(cargada.bytes),
    );
    final cuadro = await codec.getNextFrame();
    codec.dispose();
    if (cargada.origen == tesela) return ImageInfo(image: cuadro.image);

    final recortada = await _recortar(cuadro.image, cargada.origen);
    cuadro.image.dispose();
    return ImageInfo(image: recortada);
  }

  /// El pedazo de [ancestro] que corresponde a esta tesela, estirado al
  /// tamano de una tesela.
  Future<ui.Image> _recortar(ui.Image imagen, Tesela ancestro) async {
    final lado = imagen.width.toDouble();
    final (x, y, tamano) = tesela.recorteEn(ancestro, lado: lado);
    final grabadora = ui.PictureRecorder();
    ui.Canvas(grabadora).drawImageRect(
      imagen,
      ui.Rect.fromLTWH(x, y, tamano, tamano),
      ui.Rect.fromLTWH(0, 0, lado, lado),
      // Suavizado: estirada a lo bruto, la imagen sale en cuadros y distrae
      // mas de lo que informa.
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final dibujo = grabadora.endRecording();
    try {
      return await dibujo.toImage(imagen.width, imagen.height);
    } finally {
      dibujo.dispose();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ImagenTesela &&
      other.tesela == tesela &&
      identical(other.fuente, fuente);

  @override
  int get hashCode => Object.hash(tesela, identityHashCode(fuente));
}

/// Un proveedor por direccion de teselas, compartido por todos los mapas de la
/// app: lo que uno aprendio -que en esta zona no hay imagen mas alla del nivel
/// 18- le sirve al otro, y no se repiten los pedidos.
ProveedorTeselas proveedorDe({
  required String plantilla,
  required String paquete,
}) {
  return _proveedores.putIfAbsent(
    plantilla,
    () => ProveedorTeselas(
      FuenteTeselas(
        plantilla: plantilla,
        paquete: paquete,
        almacen: () {
          try {
            return BuiltInMapCachingProvider.getOrCreateInstance();
          } catch (_) {
            return null;
          }
        },
      ),
    ),
  );
}

final _proveedores = <String, ProveedorTeselas>{};
