import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/parcelas.dart';

/// Los lotes del predio dibujados sobre el mapa.
///
/// El relleno es casi transparente a proposito. Lo que se va a mirar es la
/// imagen satelital -como esta el cultivo, donde se encharco, donde falta
/// resiembra-, y un relleno opaco la tapa justo donde hace falta verla. Lo que
/// se necesita del lote es **donde termina**, y eso lo da el borde.
///
/// ## Los rotulos cambian con el zoom
///
/// Los lotes son cientos y los bloques, decenas. Dibujar todos los codigos
/// siempre deja la pantalla ilegible de lejos, asi que:
///
/// - **de lejos** (z < 14): solo el bloque. Son pocos y se leen.
/// - **de cerca** (z >= 14): el codigo de la parcela, y solo de las que entran
///   en pantalla.
///
/// Es el mismo criterio que usa el visor de map-security sobre el mismo predio.
class CapaParcelas extends StatelessWidget {
  const CapaParcelas({
    required this.parcelas,
    required this.zoom,
    required this.visible,
    super.key,
  });

  final ParcelasPredio parcelas;

  /// El zoom actual del mapa. Decide que rotulos se dibujan.
  final double zoom;

  /// El area visible, para no rotular todos los lotes cuando se ven diez.
  final LatLngBounds? visible;

  /// A partir de aca se rotula la parcela en vez del bloque. Por debajo, los
  /// codigos se encimarian.
  static const zoomParcela = 14.0;

  @override
  Widget build(BuildContext context) {
    final conCodigo = zoom >= zoomParcela;

    return PolygonLayer(
      // `polygonLabels` dibuja los rotulos que traen los poligonos; el borde
      // se dibuja siempre.
      polygons: [
        for (final p in parcelas.parcelas)
          Polygon(
            points: p.contorno,
            // Un tinte apenas perceptible: marca que ahi hay un lote sin tapar
            // el cultivo. Sin nada de relleno, un lote sin borde visible a
            // contraluz se pierde del todo.
            color: Colors.white.withValues(alpha: 0.06),
            borderColor: Colors.white.withValues(alpha: 0.65),
            borderStrokeWidth: 1.4,
            label: conCodigo && _seVe(p.centro) ? p.rotulo : null,
            labelStyle: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              shadows: [
                // La sombra no es decoracion: un rotulo blanco sobre palma
                // clara al mediodia no se lee sin ella.
                Shadow(blurRadius: 3, color: Colors.black87),
                Shadow(blurRadius: 6, color: Colors.black54),
              ],
            ),
            rotateLabel: true,
          ),
      ],
    );
  }

  bool _seVe(LatLng punto) => visible?.contains(punto) ?? true;
}

/// Los rotulos de bloque, que van por encima de los lotes.
///
/// Son una capa aparte y no el `label` de un poligono porque un bloque no es un
/// poligono: es el conjunto de sus parcelas, y su etiqueta va en el centro de
/// todas ellas ponderado por area.
class RotulosBloque extends StatelessWidget {
  const RotulosBloque({required this.parcelas, required this.zoom, super.key});

  final ParcelasPredio parcelas;
  final double zoom;

  /// Por debajo de esto ni el bloque se lee: son decenas de etiquetas sobre un
  /// predio que a z10 entra entero en la pantalla de un telefono.
  static const zoomMinimo = 11.0;

  @override
  Widget build(BuildContext context) {
    // El bloque se deja de rotular cuando aparece la parcela, con un solapamiento
    // de un nivel: al acercarse conviene ver los dos un momento para entender
    // que P.9 es del B.10.
    if (zoom < zoomMinimo || zoom > CapaParcelas.zoomParcela + 1) {
      return const SizedBox.shrink();
    }

    return MarkerLayer(
      markers: [
        for (final b in parcelas.bloques)
          Marker(
            point: b.centro,
            width: 62,
            height: 22,
            child: _RotuloBloque(nombre: b.nombre),
          ),
      ],
    );
  }
}

class _RotuloBloque extends StatelessWidget {
  const _RotuloBloque({required this.nombre});

  final String nombre;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          nombre,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
