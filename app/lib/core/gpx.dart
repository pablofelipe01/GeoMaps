import 'kml.dart' show PuntoKml, escaparXml;

/// Armador de GPX 1.1.
///
/// Es el unico export que no viene de sirius_agro: agro entrega a un agronomo,
/// que abre Google Earth; GeoMaps entrega tambien a topografia y a quien anda
/// con un GPS de mano, y eso habla GPX.
///
/// Al reves que KML, GPX pone los ejes como atributos nombrados
/// (`<trkpt lat=".." lon="..">`), asi que no se pueden invertir por descuido.
/// Lo que si cuesta: el tiempo va en **UTC con sufijo Z**. Un GPX con hora de
/// Bogota sin zona hace que cualquier lector sume cinco horas al recorrido.
///
/// Tres elementos cubren todo lo que la app genera:
///   `<wpt>` waypoint suelto - `<trk>` recorrido grabado - `<rte>` ruta planeada
abstract final class Gpx {
  /// Un documento GPX con un recorrido (`<trk>`), puntos sueltos (`<wpt>`), o
  /// las dos cosas.
  ///
  /// El [recorrido] va en un solo `<trkseg>`: la app no guarda donde se corto
  /// la senal, asi que partirlo seria inventar los cortes.
  static String armar({
    required String nombre,
    List<PuntoKml> recorrido = const [],
    List<PuntoKml> puntos = const [],
  }) {
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="GeoMaps" '
        'xmlns="http://www.topografix.com/GPX/1/1">',
      )
      ..writeln('  <metadata><name>${escaparXml(nombre)}</name></metadata>');

    // El esquema de GPX fija el orden: primero los wpt, despues los trk.
    for (var i = 0; i < puntos.length; i++) {
      final p = puntos[i];
      b.writeln('  <wpt ${_ejes(p)}>');
      _cuerpo(b, p, sangria: '    ');
      b.writeln('    <name>${escaparXml(p.nombre ?? 'Punto ${i + 1}')}</name>');
      final nota = p.nota;
      if (nota != null && nota.isNotEmpty) {
        b.writeln('    <desc>${escaparXml(nota)}</desc>');
      }
      b.writeln('  </wpt>');
    }

    if (recorrido.isNotEmpty) {
      b
        ..writeln('  <trk>')
        ..writeln('    <name>${escaparXml(nombre)}</name>')
        ..writeln('    <trkseg>');
      for (final p in recorrido) {
        if (p.altitud == null && p.momento == null) {
          b.writeln('      <trkpt ${_ejes(p)}/>');
        } else {
          b.writeln('      <trkpt ${_ejes(p)}>');
          _cuerpo(b, p, sangria: '        ');
          b.writeln('      </trkpt>');
        }
      }
      b
        ..writeln('    </trkseg>')
        ..writeln('  </trk>');
    }

    b.writeln('</gpx>');
    return b.toString();
  }

  static String _ejes(PuntoKml p) =>
      'lat="${p.latitud.toStringAsFixed(6)}" '
      'lon="${p.longitud.toStringAsFixed(6)}"';

  /// Altitud y hora, en ese orden: tambien lo fija el esquema.
  static void _cuerpo(StringBuffer b, PuntoKml p, {required String sangria}) {
    final altitud = p.altitud;
    if (altitud != null) {
      b.writeln('$sangria<ele>${altitud.toStringAsFixed(1)}</ele>');
    }
    final momento = p.momento;
    if (momento != null) {
      // UTC con Z: es la regla del encabezado.
      b.writeln('$sangria<time>${momento.toUtc().toIso8601String()}</time>');
    }
  }
}
