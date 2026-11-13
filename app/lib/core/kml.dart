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

/// Arma un documento KML.
///
/// [puntos] es la geometria principal, segun [geometria]:
///
/// - [GeometriaKml.poligono]: un `Polygon` con su anillo cerrado. Si el ultimo
///   punto no repite al primero, se repite aca: un anillo abierto no es KML
///   valido y Google Earth lo dibuja como linea, sin decir por que.
/// - [GeometriaKml.ruta]: un `LineString`.
/// - [GeometriaKml.punto]: un `Placemark` por punto, con su nombre y su nota.
///
/// [marcas] son puntos sueltos que acompanan a la geometria -los que se
/// marcaron durante el recorrido-: salen como `Placemark` aparte en el mismo
/// documento, para que el archivo que se entrega sea uno solo.
///
/// Los nombres y las notas los escribe una persona: pasan por [escaparXml],
/// porque un `&` suelto en "Lote 3 & 4" deja el archivo entero sin abrir.
String armarKml({
  required String nombre,
  required GeometriaKml geometria,
  required List<PuntoKml> puntos,
  List<PuntoKml> marcas = const [],
  String? descripcion,
}) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<kml xmlns="http://www.opengis.net/kml/2.2">')
    ..writeln('<Document>')
    ..writeln('  <name>${escaparXml(nombre)}</name>');
  if (descripcion != null && descripcion.isNotEmpty) {
    b.writeln('  <description>${escaparXml(descripcion)}</description>');
  }
  // El color de KML es aabbggrr, no rrggbb: el azul de la ruta arriba, y el
  // mismo al 30% para el relleno.
  b
    ..writeln('  <Style id="trazo">')
    ..writeln(
      '    <LineStyle><color>ffff7929</color><width>4</width></LineStyle>',
    )
    ..writeln('    <PolyStyle><color>4dff7929</color></PolyStyle>')
    ..writeln('  </Style>');

  final coordenadas = puntos.map(_coordenada).join(' ');
  switch (geometria) {
    case GeometriaKml.punto:
      _marcas(b, puntos);
    case GeometriaKml.ruta:
      b
        ..writeln('  <Placemark>')
        ..writeln('    <name>${escaparXml(nombre)}</name>')
        ..writeln('    <styleUrl>#trazo</styleUrl>')
        ..writeln('    <LineString>')
        ..writeln('      <tessellate>1</tessellate>')
        ..writeln('      <coordinates>$coordenadas</coordinates>')
        ..writeln('    </LineString>')
        ..writeln('  </Placemark>');
    case GeometriaKml.poligono:
      final abierto =
          puntos.length > 1 &&
          (puntos.first.latitud != puntos.last.latitud ||
              puntos.first.longitud != puntos.last.longitud);
      final anillo = abierto
          ? '$coordenadas ${_coordenada(puntos.first)}'
          : coordenadas;
      b
        ..writeln('  <Placemark>')
        ..writeln('    <name>${escaparXml(nombre)}</name>')
        ..writeln('    <styleUrl>#trazo</styleUrl>')
        ..writeln('    <Polygon>')
        ..writeln('      <tessellate>1</tessellate>')
        ..writeln('      <outerBoundaryIs><LinearRing>')
        ..writeln('        <coordinates>$anillo</coordinates>')
        ..writeln('      </LinearRing></outerBoundaryIs>')
        ..writeln('    </Polygon>')
        ..writeln('  </Placemark>');
  }
  if (geometria != GeometriaKml.punto) _marcas(b, marcas);

  b
    ..writeln('</Document>')
    ..writeln('</kml>');
  return b.toString();
}

void _marcas(StringBuffer b, List<PuntoKml> puntos) {
  for (var i = 0; i < puntos.length; i++) {
    final p = puntos[i];
    b
      ..writeln('  <Placemark>')
      ..writeln('    <name>${escaparXml(p.nombre ?? 'Punto ${i + 1}')}</name>');
    final detalle = [
      if (p.nota != null && p.nota!.isNotEmpty) p.nota!,
      if (p.precisionM != null) 'Precision +/- ${p.precisionM!.round()} m',
    ].join('\n');
    if (detalle.isNotEmpty) {
      b.writeln('    <description>${escaparXml(detalle)}</description>');
    }
    final momento = p.momento;
    if (momento != null) {
      b.writeln(
        '    <TimeStamp><when>${momento.toUtc().toIso8601String()}'
        '</when></TimeStamp>',
      );
    }
    b
      ..writeln(
        '    <Point><coordinates>${_coordenada(p)}</coordinates></Point>',
      )
      ..writeln('  </Placemark>');
  }
}

/// `lon,lat[,alt]`. **Longitud primero**: es la regla del encabezado.
String _coordenada(PuntoKml p) {
  final base =
      '${p.longitud.toStringAsFixed(6)},${p.latitud.toStringAsFixed(6)}';
  final altitud = p.altitud;
  return altitud == null ? base : '$base,${altitud.toStringAsFixed(1)}';
}

/// Escapa lo que rompe un XML. El orden importa: el `&` va primero, o escapa
/// los que el mismo acaba de escribir.
String escaparXml(String texto) => texto
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
