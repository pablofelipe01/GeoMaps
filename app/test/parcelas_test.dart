import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El asset de lotes del predio, contra lo que el plano declara.
///
/// Se lee del disco y no por `rootBundle` para que la prueba corra sin levantar
/// el binding de Flutter.
///
/// Los datos del predio son confidenciales y no estan en el repositorio, que es
/// publico: si el asset no esta, estas pruebas se saltan. Aca no se escribe
/// ninguna coordenada; lo que se verifica es la coherencia interna del archivo.
void main() {
  final archivo = File('assets/zonas/guaicaramo-parcelas.json');
  final hayDatos = archivo.existsSync();

  late List<Map<String, dynamic>> parcelas;
  late List<Map<String, dynamic>> bloques;
  late List<double> bbox;

  setUpAll(() {
    if (!hayDatos) return;
    final j = jsonDecode(archivo.readAsStringSync()) as Map<String, dynamic>;
    parcelas = (j['parcelas'] as List).cast<Map<String, dynamic>>();
    bloques = (j['bloques'] as List).cast<Map<String, dynamic>>();

    // El encuadre sale de los propios datos, no de numeros escritos aca.
    final xs = <double>[], ys = <double>[];
    for (final p in parcelas) {
      final c = (p['c'] as List).cast<num>();
      for (var i = 0; i + 1 < c.length; i += 2) {
        xs.add(c[i].toDouble());
        ys.add(c[i + 1].toDouble());
      }
    }
    bbox = [
      xs.reduce((a, b) => a < b ? a : b),
      ys.reduce((a, b) => a < b ? a : b),
      xs.reduce((a, b) => a > b ? a : b),
      ys.reduce((a, b) => a > b ? a : b),
    ];
  });

  group(
    'con los datos del predio',
    skip: hayDatos
        ? false
        : 'sin assets/zonas/guaicaramo-parcelas.json (son confidenciales; '
              'ver assets/zonas/LEEME.md para generarlos)',
    () {
      // Los conteos exactos del predio no se escriben aca: este repositorio es
      // publico. Los imprime el generador al correr, que es donde alguien los
      // mira. Lo que se verifica es que el archivo sea coherente consigo mismo.
      test('hay lotes y bloques, y los bloques son muchos menos', () {
        expect(parcelas, isNotEmpty);
        expect(bloques, isNotEmpty);
        // Un bloque agrupa varios lotes. Si hubiera casi tantos bloques como
        // lotes, el agrupamiento se rompio y el mapa rotularia de lejos una
        // maraña ilegible.
        expect(bloques.length * 4, lessThan(parcelas.length));
      });

      test('cada lote tiene una superficie plausible', () {
        for (final p in parcelas) {
          final ha = (p['h'] as num).toDouble();
          // Ni un lote de un metro cuadrado ni uno del tamaño de un municipio:
          // los dos serian sintomas de que el recorte de anillos leyo mal.
          expect(ha, greaterThan(0.1));
          expect(ha, lessThan(1000));
        }
      });

      test('los contornos estan cerrados y son poligonos de verdad', () {
        for (final p in parcelas) {
          final c = (p['c'] as List).cast<num>();
          expect(c.length.isEven, isTrue, reason: 'lon/lat despareados');
          // Cuatro pares como minimo: un triangulo cerrado.
          expect(c.length, greaterThanOrEqualTo(8));
          expect(
            c.first,
            c[c.length - 2],
            reason: 'el anillo no cierra en lon',
          );
          expect(c[1], c.last, reason: 'el anillo no cierra en lat');
        }
      });

      test('el predio entra en un encuadre de pocas decenas de kilometros', () {
        // Un predio es contiguo: si un lote quedara a medio pais de los demas, el
        // recorte del plano leyo mal la georreferencia. Se mide el encuadre de los
        // propios datos en vez de comparar contra coordenadas escritas.
        expect(bbox[2] - bbox[0], lessThan(1.0), reason: 'ancho en grados');
        expect(bbox[3] - bbox[1], lessThan(1.0), reason: 'alto en grados');
      });

      test('el punto de la etiqueta cae adentro de su propio lote', () {
        // Es lo que evita que el codigo de un lote quede escrito sobre el vecino.
        // Se usa el punto representativo, no el centroide, justamente por los lotes
        // con forma de ele.
        for (final p in parcelas) {
          final c = (p['c'] as List).cast<num>();
          final anillo = <List<double>>[];
          for (var i = 0; i + 1 < c.length; i += 2) {
            anillo.add([c[i].toDouble(), c[i + 1].toDouble()]);
          }
          final x = (p['x'] as num).toDouble();
          final y = (p['y'] as num).toDouble();
          expect(
            _dentro(x, y, anillo),
            isTrue,
            reason: 'la etiqueta de ${p['p']} cae fuera de su lote',
          );
        }
      });

      group('rotulos', () {
        final formato = RegExp(r'^B\.\d+-P\.\d+$');

        test('conviven codigos y nombres propios', () {
          final conRotulo = parcelas
              .map((p) => p['p'] as String)
              .where((c) => c.isNotEmpty);
          final codigos = conRotulo.where(formato.hasMatch).length;
          final nombres = conRotulo.length - codigos;

          // La mayoria lleva codigo B.x-P.y. Unos pocos llevan nombre propio
          // -los citricos, los frutales y los viveros, que en campo se llaman
          // asi- y si esos desaparecen, el parseo perdio los rotulos que no
          // encajan en el formato. Otros no tienen rotulo en el plano y se
          // dibujan igual: el lindero vale sin el nombre.
          expect(codigos, greaterThan(parcelas.length ~/ 2));
          expect(nombres, greaterThan(0));
        });

        test('el bloque sale del codigo, y los nombrados no tienen bloque', () {
          for (final p in parcelas) {
            final cod = p['p'] as String;
            final bloque = p['b'] as String;
            if (formato.hasMatch(cod)) {
              expect(cod.startsWith('$bloque-'), isTrue);
            } else {
              // Un lote sin codigo no pertenece a ningun bloque numerado, y
              // colgarlo de uno inventado lo pondria en la etiqueta equivocada.
              expect(bloque, isEmpty);
            }
          }
        });

        test('a lo sumo dos codigos se repiten', () {
          // El rotulo se empareja con su lote por cercania y no es perfecto: dos
          // codigos quedan en dos lotes cada uno. El propio parser de map-security
          // reporta un par repetido entre los acopios por la misma razon.
          //
          // Se tolera, pero acotado: si este numero crece, el emparejamiento se
          // desalineo y el mapa empezaria a rotular lotes con el nombre del vecino.
          final codigos = parcelas
              .map((p) => p['p'] as String)
              .where(formato.hasMatch)
              .toList();
          final repetidos = codigos.length - codigos.toSet().length;
          expect(repetidos, lessThanOrEqualTo(2));
        });
      });

      test('cada bloque conoce cuantas parcelas tiene', () {
        final contadas = <String, int>{};
        for (final p in parcelas) {
          final b = p['b'] as String;
          if (b.isNotEmpty) contadas[b] = (contadas[b] ?? 0) + 1;
        }

        for (final b in bloques) {
          expect(
            b['n'],
            contadas[b['b']],
            reason: 'el conteo de ${b['b']} no da',
          );
          expect(b['ha'], greaterThan(0));
        }
      });
    },
  );
}

/// Punto en poligono por lanzamiento de rayo, en grados.
bool _dentro(double x, double y, List<List<double>> anillo) {
  var dentro = false;
  var j = anillo.length - 1;
  for (var i = 0; i < anillo.length; i++) {
    final xi = anillo[i][0], yi = anillo[i][1];
    final xj = anillo[j][0], yj = anillo[j][1];
    if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
      dentro = !dentro;
    }
    j = i;
  }
  return dentro;
}
