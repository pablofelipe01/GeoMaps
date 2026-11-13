import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geomaps/core/exportador.dart';
import 'package:geomaps/core/geo.dart';
import 'package:geomaps/core/geojson.dart';
import 'package:geomaps/core/gpx.dart';
import 'package:geomaps/core/kml.dart';
import 'package:geomaps/core/teselas.dart';
import 'package:geomaps/data/db/app_database.dart';
import 'package:geomaps/data/db/enums.dart';
import 'package:geomaps/data/trazados_repository.dart';
import 'package:geomaps/data/waypoints_repository.dart';

/// Lo que sale del telefono: el area de un lote, y los archivos que se
/// comparten. Son las cuentas y los formatos donde un error no avisa: un area
/// mal calculada o un KML con los ejes al reves abren sin quejarse.
void main() {
  group('area', () {
    // Un cuadrado de 0,001 grados de lado sobre el ecuador: 111,32 m por lado.
    const cuadrado = [
      PuntoGeo(0, 0),
      PuntoGeo(0, 0.001),
      PuntoGeo(0.001, 0.001),
      PuntoGeo(0.001, 0),
    ];

    test('de un cuadrado conocido', () {
      // 111,32 m x 111,32 m = 12.392 m2, con el radio que usa Google Earth.
      expect(areaM2(cuadrado), closeTo(12392, 5));
      expect(areaHa(cuadrado), closeTo(1.2392, 0.001));
    });

    test('no depende del sentido ni de repetir el primer vertice', () {
      final alReves = cuadrado.reversed.toList();
      final cerrado = [...cuadrado, cuadrado.first];
      expect(areaM2(alReves), closeTo(areaM2(cuadrado), 1e-6));
      expect(areaM2(cerrado), closeTo(areaM2(cuadrado), 1e-6));
    });

    test('con menos de tres vertices no hay area', () {
      expect(areaM2(const []), 0);
      expect(areaM2(const [PuntoGeo(4, -72), PuntoGeo(4.1, -72)]), 0);
    });

    test('en la latitud de Guaicaramo un lote de 500 x 200 m', () {
      // 500 m al este y 200 m al norte desde un punto del predio.
      const lat = 4.45, lon = -72.96;
      final dLat = 200 / 110574.0;
      final dLon = 500 / (111320.0 * 0.99698); // cos(4,45 grados)
      final lote = [
        const PuntoGeo(lat, lon),
        PuntoGeo(lat, lon + dLon),
        PuntoGeo(lat + dLat, lon + dLon),
        PuntoGeo(lat + dLat, lon),
      ];
      // 10 ha, con el margen de usar una esfera en vez del elipsoide.
      expect(areaHa(lote), closeTo(10, 0.1));
      expect(perimetroM(lote), closeTo(1400, 12));
    });
  });

  group('KML', () {
    const puntos = [
      PuntoKml(latitud: 4.45, longitud: -72.96),
      PuntoKml(latitud: 4.46, longitud: -72.96),
      PuntoKml(latitud: 4.46, longitud: -72.95),
    ];

    test('escribe longitud antes que latitud', () {
      final kml = armarKml(
        nombre: 'Viaje',
        geometria: GeometriaKml.ruta,
        puntos: puntos,
      );
      expect(kml, contains('<LineString>'));
      expect(kml, contains('-72.960000,4.450000 -72.960000,4.460000'));
    });

    test(
      'cierra el anillo de un poligono abierto, y no lo cierra dos veces',
      () {
        final abierto = armarKml(
          nombre: 'Lote',
          geometria: GeometriaKml.poligono,
          puntos: puntos,
        );
        expect(
          abierto,
          contains(
            '-72.960000,4.450000 -72.960000,4.460000 -72.950000,4.460000 '
            '-72.960000,4.450000</coordinates>',
          ),
        );

        final cerrado = armarKml(
          nombre: 'Lote',
          geometria: GeometriaKml.poligono,
          puntos: [...puntos, puntos.first],
        );
        expect('-72.960000,4.450000'.allMatches(cerrado).length, 2);
      },
    );

    test('un nombre con & no rompe el archivo', () {
      final kml = armarKml(
        nombre: 'Lote 3 & 4 <norte>',
        geometria: GeometriaKml.punto,
        puntos: const [
          PuntoKml(
            latitud: 4.45,
            longitud: -72.96,
            nombre: 'Alcantarilla "rota"',
            nota: 'Revisar & reparar',
            precisionM: 6.4,
          ),
        ],
      );
      expect(kml, contains('Lote 3 &amp; 4 &lt;norte&gt;'));
      expect(kml, contains('Alcantarilla &quot;rota&quot;'));
      expect(kml, contains('Revisar &amp; reparar'));
      expect(kml, contains('Precision +/- 6 m'));
      expect(kml, isNot(contains('& ')));
    });

    test('las marcas del recorrido salen en el mismo documento', () {
      final kml = armarKml(
        nombre: 'Lindero',
        geometria: GeometriaKml.ruta,
        puntos: puntos,
        marcas: const [
          PuntoKml(latitud: 4.455, longitud: -72.958, nombre: 'Mojon'),
        ],
      );
      expect(kml, contains('<LineString>'));
      expect(kml, contains('<name>Mojon</name>'));
      expect(kml, contains('<Point><coordinates>-72.958000,4.455000'));
    });
  });

  group('GPX', () {
    test('lleva los ejes con nombre y la hora en UTC con Z', () {
      final gpx = Gpx.armar(
        nombre: 'Viaje',
        recorrido: const [
          PuntoKml(latitud: 4.45, longitud: -72.96),
          PuntoKml(latitud: 4.46, longitud: -72.95),
        ],
        puntos: [
          PuntoKml(
            latitud: 4.455,
            longitud: -72.958,
            nombre: 'Mojon',
            // Las 9 de la manana en Bogota son las 14 UTC.
            momento: DateTime.utc(2026, 11, 12, 14),
            altitud: 180.26,
          ),
        ],
      );
      expect(gpx, contains('<trkpt lat="4.450000" lon="-72.960000"/>'));
      expect(gpx, contains('<wpt lat="4.455000" lon="-72.958000">'));
      expect(gpx, contains('<time>2026-11-12T14:00:00.000Z</time>'));
      expect(gpx, contains('<ele>180.3</ele>'));
      // El esquema pide los wpt antes que el trk.
      expect(gpx.indexOf('<wpt'), lessThan(gpx.indexOf('<trk>')));
    });
  });

  group('teselas', () {
    // La plantacion entera, a grandes rasgos.
    const predio = ZonaTeselas(
      sur: 4.40,
      oeste: -73.02,
      norte: 4.52,
      este: -72.90,
    );

    test('la cuenta coincide con la lista', () {
      for (final (zMin, zMax) in [(12, 12), (12, 15), (14, 17)]) {
        expect(
          predio.teselas(zMin, zMax).length,
          predio.contar(zMin, zMax),
          reason: 'z$zMin-$zMax',
        );
      }
    });

    test('cada nivel pide unas cuatro veces mas que el anterior', () {
      final z16 = predio.contar(16, 16);
      final z17 = predio.contar(17, 17);
      expect(z17 / z16, inInclusiveRange(3.5, 4.5));
    });

    test('la tesela conocida de un punto', () {
      // Bogota (4.60971, -74.08175) en z12 cae en la columna 1205, fila 1995.
      const punto = ZonaTeselas(
        sur: 4.60971,
        oeste: -74.08175,
        norte: 4.60971,
        este: -74.08175,
      );
      expect(punto.teselas(12, 12).single, const Tesela(12, 1205, 1995));
    });

    test('arma la direccion como la arma el mapa', () {
      const t = Tesela(15, 9740, 15963);
      expect(
        t.url('https://x/tile/{z}/{y}/{x}'),
        'https://x/tile/15/15963/9740',
      );
      expect(t.url('https://o/{z}/{x}/{y}.png'), 'https://o/15/9740/15963.png');
    });

    test('va de lo general a lo fino', () {
      final niveles = predio.teselas(12, 14).map((t) => t.z).toList();
      expect(niveles, [...niveles]..sort());
      expect(niveles.first, 12);
      expect(niveles.last, 14);
    });
  });

  group('lo levantado', () {
    late AppDatabase db;
    late TrazadosRepository trazados;
    late WaypointsRepository puntos;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      trazados = TrazadosRepository(db);
      puntos = WaypointsRepository(db);
    });
    tearDown(() => db.close());

    const lote = [
      PuntoGeo(4.45, -72.96),
      PuntoGeo(4.45, -72.955),
      PuntoGeo(4.452, -72.955),
      PuntoGeo(4.452, -72.96),
    ];

    test(
      'un area medida se guarda cerrada, con su area, y lista para subir',
      () async {
        final t = await trazados.guardarPoligono(
          usuarioCodigo: 'ana',
          nombre: 'Lote 7',
          vertices: lote,
        );

        expect(t.tipo, TipoTrazado.poligono.name);
        expect(t.metodo, MetodoCaptura.manual.name);
        expect(t.areaHa, closeTo(areaHa(lote), 1e-9));
        expect(t.puntos, 4);

        // El backend recibe un LineString: el anillo va cerrado adentro.
        final geojson = jsonDecode(t.geometria) as Map<String, dynamic>;
        expect((geojson['geometry'] as Map)['type'], 'LineString');
        final vertices = GeoJson.puntosDeLinea(geojson);
        expect(vertices.length, 5);
        expect(vertices.first.latitud, vertices.last.latitud);
        expect(vertices.first.longitud, vertices.last.longitud);

        expect((await trazados.pendientes('ana')).single.codigo, t.codigo);
        expect(
          (await trazados.observarLevantados('ana').first).single.codigo,
          t.codigo,
        );
      },
    );

    test(
      'la lista de levantados no mezcla rutas calculadas ni otras cuentas',
      () async {
        await trazados.guardarPoligono(
          usuarioCodigo: 'ana',
          nombre: 'Lote',
          vertices: lote,
        );
        await trazados.guardarRuta(
          usuarioCodigo: 'ana',
          nombre: 'Ruta al acopio',
          linea: lote,
          metros: 800,
        );
        await trazados.guardarPoligono(
          usuarioCodigo: 'beto',
          nombre: 'Otro',
          vertices: lote,
        );
        // Una grabacion que todavia no se cerro tampoco aparece.
        await trazados.abrirGrabacion(usuarioCodigo: 'ana', nombre: 'En curso');

        final lista = await trazados.observarLevantados('ana').first;
        expect(lista.map((t) => t.nombre), ['Lote']);
      },
    );

    test('renombrar lo vuelve a dejar pendiente de subir', () async {
      final t = await trazados.guardarPoligono(
        usuarioCodigo: 'ana',
        nombre: 'Lote',
        vertices: lote,
      );
      await trazados.marcarSubido(t.codigo, 'llave');
      expect(await trazados.pendientes('ana'), isEmpty);

      await trazados.renombrar(t.codigo, '  Lote 7 norte ');
      final pendiente = (await trazados.pendientes('ana')).single;
      expect(pendiente.nombre, 'Lote 7 norte');
    });

    test(
      'los puntos son de cada cuenta y se pueden atar a un recorrido',
      () async {
        final grabacion = await trazados.abrirGrabacion(
          usuarioCodigo: 'ana',
          nombre: 'Lindero',
        );
        await puntos.marcar(
          usuarioCodigo: 'ana',
          nombre: 'Mojon',
          punto: const PuntoGeo(4.45, -72.96),
          simbolo: SimboloWaypoint.infraestructura,
          precisionM: 5,
          trazadoCodigo: grabacion.codigo,
        );
        await puntos.marcar(
          usuarioCodigo: 'ana',
          nombre: '  ',
          punto: const PuntoGeo(4.46, -72.95),
          nota: '  ',
        );
        await puntos.marcar(
          usuarioCodigo: 'beto',
          nombre: 'Ajeno',
          punto: const PuntoGeo(4.4, -72.9),
        );

        final deAna = await puntos.observar('ana').first;
        expect(deAna.length, 2);
        expect(deAna.map((w) => w.nombre), contains('Punto sin nombre'));
        expect(deAna.firstWhere((w) => w.nombre != 'Mojon').nota, isNull);

        final atados = await puntos.delTrazado(grabacion.codigo);
        expect(atados.single.nombre, 'Mojon');

        await puntos.borrar(atados.single.codigo);
        expect((await puntos.observar('ana').first).length, 1);
      },
    );

    test('el archivo que se comparte sale del trazado guardado', () async {
      final t = await trazados.guardarPoligono(
        usuarioCodigo: 'ana',
        nombre: 'Lote 7',
        vertices: lote,
      );
      final marca = await puntos.marcar(
        usuarioCodigo: 'ana',
        nombre: 'Portada',
        punto: const PuntoGeo(4.451, -72.958),
      );

      final kml = Exportador.contenido(t, FormatoEntrega.kml, marcas: [marca]);
      expect(kml, contains('<Polygon>'));
      expect(kml, contains('<name>Portada</name>'));
      expect(kml, contains('Marcado a mano sobre el mapa, sin GPS'));

      final gpx = Exportador.contenido(t, FormatoEntrega.gpx);
      expect('<trkpt'.allMatches(gpx).length, 5);

      final geojson = jsonDecode(
        Exportador.contenido(t, FormatoEntrega.geojson),
      );
      expect(geojson['type'], 'Feature');
    });
  });

  test('el nombre del archivo lo acepta cualquier sistema', () {
    expect(Exportador.nombreDeArchivo('Vuelta #9 · 7 · 7'), 'Vuelta-9-7-7');
    expect(
      Exportador.nombreDeArchivo('Recorrido 12/11 14:30'),
      'Recorrido-12-11-14-30',
    );
    expect(Exportador.nombreDeArchivo('Área del cañón'), 'Area-del-canon');
    expect(Exportador.nombreDeArchivo(' ··· '), 'geomaps');
  });
}
