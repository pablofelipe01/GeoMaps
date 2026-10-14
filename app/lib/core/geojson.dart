import 'geo.dart';

/// GeoJSON: el formato en que el trazado sale del telefono y vive en S3.
///
/// Se eligio sobre KML como formato de **almacenamiento** (KML sigue siendo un
/// export) por dos razones: es el unico que QGIS, PostGIS, Airtable scripting y
/// cualquier libreria de JavaScript leen sin traducir, y no obliga a envolver
/// la geometria en un documento con estilos que nadie va a usar.
///
/// La trampa es la misma de KML y se paga igual de caro: el orden es
/// **[longitud, latitud]**, al reves de como se dice y de como lo guarda la
/// base. Un GeoJSON con los ejes invertidos se valida sin error y pone el lote
/// en Somalia. Por eso se arma solo aca, y la prueba lo vigila.
///
/// La `Vista previa` simplificada que va a Airtable no se arma en el telefono:
/// la hace el backend (`services/geometria.py`) sobre este mismo archivo, para
/// que cambiar su tope no pida un APK nuevo.
abstract final class GeoJson {
  /// Un Feature con la linea y, en `properties`, lo que hace util el archivo
  /// suelto. Un GeoJSON sin metadatos obliga a volver a Airtable para saber que
  /// es.
  static Map<String, dynamic> linea(
    List<PuntoGeo> puntos, {
    Map<String, Object?> propiedades = const {},
  }) {
    return {
      'type': 'Feature',
      'properties': {
        for (final e in propiedades.entries)
          if (e.value != null) e.key: e.value,
      },
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          // Seis decimales son 10 cm: el GPS no sabe mas que eso.
          for (final p in puntos) [_seis(p.longitud), _seis(p.latitud)],
        ],
      },
    };
  }

  /// Los vertices de una linea guardada con [linea], en el orden de la app.
  static List<PuntoGeo> puntosDeLinea(Map<String, dynamic> geojson) {
    final geometria = geojson['type'] == 'Feature'
        ? geojson['geometry'] as Map<String, dynamic>
        : geojson;
    final coordenadas = geometria['coordinates'] as List<dynamic>;
    return [
      for (final c in coordenadas.cast<List<dynamic>>())
        PuntoGeo((c[1] as num).toDouble(), (c[0] as num).toDouble()),
    ];
  }

  /// `minLon,minLat,maxLon,maxLat`, el orden del bbox de GeoJSON y de Airtable.
  static String bbox(List<PuntoGeo> puntos) {
    var minLat = double.infinity, minLon = double.infinity;
    var maxLat = -double.infinity, maxLon = -double.infinity;
    for (final p in puntos) {
      if (p.latitud < minLat) minLat = p.latitud;
      if (p.latitud > maxLat) maxLat = p.latitud;
      if (p.longitud < minLon) minLon = p.longitud;
      if (p.longitud > maxLon) maxLon = p.longitud;
    }
    return [minLon, minLat, maxLon, maxLat].map(_seis).join(',');
  }

  /// El promedio de los vertices. No es el centroide geometrico, y no hace
  /// falta: sirve para abrir la fila en Google Maps cerca del trazado, no para
  /// medir nada.
  static PuntoGeo centroide(List<PuntoGeo> puntos) {
    var lat = 0.0, lon = 0.0;
    for (final p in puntos) {
      lat += p.latitud;
      lon += p.longitud;
    }
    return PuntoGeo(lat / puntos.length, lon / puntos.length);
  }

  static double _seis(double v) => (v * 1e6).roundToDouble() / 1e6;
}
