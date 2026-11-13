import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/db/app_database.dart';
import '../data/db/enums.dart';
import 'geojson.dart';
import 'gpx.dart';
import 'kml.dart';

/// En que formato sale lo que se entrega.
enum FormatoEntrega {
  /// Para Google Earth y QGIS: lo que abre un agronomo.
  kml('KML', 'kml', 'application/vnd.google-earth.kml+xml'),

  /// Para topografia y GPS de mano.
  gpx('GPX', 'gpx', 'application/gpx+xml'),

  /// Para quien lo va a procesar: QGIS, PostGIS, un script.
  geojson('GeoJSON', 'geojson', 'application/geo+json');

  const FormatoEntrega(this.titulo, this.extension, this.mime);

  final String titulo;
  final String extension;
  final String mime;
}

/// Arma el archivo que se entrega y lo comparte.
///
/// Todo se arma en el telefono, sin red: el que termino de levantar un lote lo
/// manda por WhatsApp ahi mismo si tiene una raya de senal, o lo guarda para
/// despues. El archivo queda en la carpeta temporal de la app; Android la
/// limpia solo.
abstract final class Exportador {
  /// El texto del archivo de [trazado] en [formato], con sus [marcas]: los
  /// puntos que se marcaron mientras se lo grababa.
  ///
  /// Aparte de [compartir] porque es lo que se puede probar sin telefono.
  static String contenido(
    Trazado trazado,
    FormatoEntrega formato, {
    List<Waypoint> marcas = const [],
  }) {
    final geojson = jsonDecode(trazado.geometria) as Map<String, dynamic>;
    if (formato == FormatoEntrega.geojson) {
      return const JsonEncoder.withIndent('  ').convert(geojson);
    }

    final esPoligono = trazado.tipo == TipoTrazado.poligono.name;
    final vertices = [
      for (final v in GeoJson.puntosDeLinea(geojson))
        PuntoKml(latitud: v.latitud, longitud: v.longitud),
    ];
    final puntos = [for (final w in marcas) puntoDe(w)];

    return switch (formato) {
      FormatoEntrega.kml => armarKml(
        nombre: trazado.nombre,
        geometria: esPoligono ? GeometriaKml.poligono : GeometriaKml.ruta,
        puntos: vertices,
        marcas: puntos,
        descripcion: descripcion(trazado),
      ),
      _ => Gpx.armar(
        nombre: trazado.nombre,
        recorrido: vertices,
        puntos: puntos,
      ),
    };
  }

  /// Los numeros del trazado en un renglon, para la descripcion del KML y el
  /// texto que acompana al archivo al compartirlo.
  static String descripcion(Trazado t) {
    final partes = <String>[
      if (t.areaHa != null) 'Area ${_decimal(t.areaHa!, 2)} ha',
      if (t.distanciaM != null)
        t.tipo == TipoTrazado.poligono.name
            ? 'Perimetro ${t.distanciaM!.round()} m'
            : 'Distancia ${t.distanciaM!.round()} m',
      if (t.precisionMediaM != null)
        'Precision media +/- ${t.precisionMediaM!.round()} m',
      if (t.metodo == MetodoCaptura.manual.name)
        'Marcado a mano sobre el mapa, sin GPS',
    ];
    return partes.join(' · ');
  }

  static PuntoKml puntoDe(Waypoint w) => PuntoKml(
    latitud: w.latitud,
    longitud: w.longitud,
    altitud: w.altitudM,
    precisionM: w.precisionM,
    momento: w.marcadoEn,
    nota: w.nota,
    nombre: w.nombre,
  );

  /// Escribe el archivo y abre la hoja de compartir del telefono.
  static Future<void> compartir(
    Trazado trazado,
    FormatoEntrega formato, {
    List<Waypoint> marcas = const [],
  }) {
    return _compartir(
      nombre: trazado.nombre,
      formato: formato,
      texto: contenido(trazado, formato, marcas: marcas),
      detalle: descripcion(trazado),
    );
  }

  /// Comparte puntos sueltos, sin recorrido: la lista de puntos marcados.
  static Future<void> compartirPuntos(
    List<Waypoint> puntos,
    FormatoEntrega formato, {
    String nombre = 'Puntos GeoMaps',
  }) {
    final marcas = [for (final w in puntos) puntoDe(w)];
    final texto = switch (formato) {
      FormatoEntrega.kml => armarKml(
        nombre: nombre,
        geometria: GeometriaKml.punto,
        puntos: marcas,
      ),
      FormatoEntrega.gpx => Gpx.armar(nombre: nombre, puntos: marcas),
      FormatoEntrega.geojson => const JsonEncoder.withIndent('  ').convert({
        'type': 'FeatureCollection',
        'features': [
          for (final w in puntos)
            {
              'type': 'Feature',
              'properties': {
                'nombre': w.nombre,
                'simbolo': w.simbolo,
                if (w.nota != null) 'nota': w.nota,
                if (w.precisionM != null) 'precision_m': w.precisionM,
                'marcado_en': w.marcadoEn.toUtc().toIso8601String(),
              },
              'geometry': {
                'type': 'Point',
                // [lon, lat]: la regla de GeoJSON.
                'coordinates': [w.longitud, w.latitud],
              },
            },
        ],
      }),
    };
    return _compartir(
      nombre: nombre,
      formato: formato,
      texto: texto,
      detalle: puntos.length == 1 ? '1 punto' : '${puntos.length} puntos',
    );
  }

  static Future<void> _compartir({
    required String nombre,
    required FormatoEntrega formato,
    required String texto,
    required String detalle,
  }) async {
    final carpeta = await getTemporaryDirectory();
    final archivo = File(
      p.join(carpeta.path, '${nombreDeArchivo(nombre)}.${formato.extension}'),
    );
    await archivo.writeAsString(texto, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(archivo.path, mimeType: formato.mime)],
        subject: nombre,
        text: detalle.isEmpty ? nombre : '$nombre · $detalle',
      ),
    );
  }

  /// Un nombre que cualquier sistema de archivos acepta: sin tildes, sin
  /// barras, sin los dos puntos de una hora. "Vuelta #9 · 7 · 7" tal cual no
  /// se puede guardar en Windows, que es donde lo van a abrir.
  static String nombreDeArchivo(String nombre) {
    const con = 'áéíóúüñÁÉÍÓÚÜÑ';
    const sin = 'aeiouunAEIOUUN';
    final b = StringBuffer();
    for (final c in nombre.trim().split('')) {
      final i = con.indexOf(c);
      b.write(i >= 0 ? sin[i] : c);
    }
    final limpio = b
        .toString()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (limpio.isEmpty) return 'geomaps';
    return limpio.length > 60 ? limpio.substring(0, 60) : limpio;
  }

  static String _decimal(double v, int decimales) =>
      v.toStringAsFixed(decimales).replaceAll('.', ',');
}
