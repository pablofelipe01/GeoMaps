import 'geo.dart';

/// Armador de KML 2.2, el formato que abre Google Earth, QGIS y casi cualquier
/// cosa que dibuje mapas. Portado de sirius_agro.
///
/// Se escribe a mano y no con una libreria a proposito: KML es XML plano y lo
/// que la app necesita son tres geometrias. Una dependencia mas en el APK para
/// concatenar texto no se paga.
///
/// Regla del formato que cuesta una tarde si se olvida: las coordenadas van
/// **longitud,latitud,altitud**, al reves de como se dicen y de como las
/// guarda la base. Un KML con los ejes invertidos abre sin error y pone el
/// lote en Somalia.

enum GeometriaKml { poligono, ruta, punto }

/// Un punto tal como sale al KML, con lo que se sabe de como se capturo.
class PuntoKml {
  const PuntoKml({
    required this.latitud,
    required this.longitud,
    this.altitud,
    this.precisionM,
    this.momento,
    this.nota,
    this.nombre,
  });

  final double latitud;
  final double longitud;
  final double? altitud;
  final double? precisionM;
  final DateTime? momento;
  final String? nota;
  final String? nombre;

  PuntoGeo get geo => PuntoGeo(latitud, longitud);
}

/// TODO: portar el armador de sirius_agro/app/lib/core/kml.dart.
String armarKml({
  required String nombre,
  required GeometriaKml geometria,
  required List<PuntoKml> puntos,
}) {
  throw UnimplementedError('portar de sirius_agro/app/lib/core/kml.dart');
}
