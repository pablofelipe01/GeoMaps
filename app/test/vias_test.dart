import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geomaps/core/vias.dart';

/// El asset de vias del predio, contra lo que el KMZ de topografia declara.
///
/// Se lee del disco y no por `rootBundle` para que la prueba corra sin levantar
/// el binding de Flutter: lo que importa aca es el parseo, no el cargador.
///
/// Los datos del predio son confidenciales y no estan en el repositorio, que es
/// publico: si el asset no esta, el grupo que lo necesita se salta. Aca no se
/// escribe ninguna coordenada.
void main() {
  final archivo = File('assets/zonas/guaicaramo-vias.json');
  final hayDatos = archivo.existsSync();

  late List<Map<String, dynamic>> crudas;
  late List<String> tipos;
  late List<double> bbox;

  setUpAll(() {
    if (!hayDatos) return;
    final j = jsonDecode(archivo.readAsStringSync()) as Map<String, dynamic>;
    tipos = (j['tipos'] as List).cast<String>();
    crudas = (j['vias'] as List).cast<Map<String, dynamic>>();

    // El encuadre sale de los propios datos, no de numeros escritos aca.
    final xs = <double>[], ys = <double>[];
    for (final v in crudas) {
      final c = (v['c'] as List).cast<num>();
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
        : 'sin assets/zonas/guaicaramo-vias.json (son confidenciales; '
              'ver assets/zonas/LEEME.md para generarlos)',
    () {
      test('el asset trae las vias del KMZ', () {
        // El conteo exacto lo imprime el generador: este repositorio es publico
        // y los numeros del predio no se escriben aca.
        expect(crudas, isNotEmpty);
      });

      test('todas las vias tienen al menos dos puntos', () {
        // Una linea de un punto no se dibuja y no existe en el plano; si aparece
        // una, el parseo del KMZ se corto a la mitad.
        for (final v in crudas) {
          final coords = (v['c'] as List).length;
          expect(coords, greaterThanOrEqualTo(4));
          expect(coords.isEven, isTrue, reason: 'lon/lat quedaron despareados');
        }
      });

      test('la red de vias entra en un encuadre de un predio', () {
        // Si una via se fuera a medio pais, el KMZ trajo una geometria de otra
        // capa. Se mide contra los propios datos, sin escribir coordenadas.
        expect(bbox[2] - bbox[0], lessThan(1.0), reason: 'ancho en grados');
        expect(bbox[3] - bbox[1], lessThan(1.0), reason: 'alto en grados');
      });

      group('tipos de via', () {
        test('las balastradas partidas en tramos cuentan como balastradas', () {
          // El plano trae BalastradaP1 y BalastradaP2: una via partida en dos
          // tramos de obra, que en el terreno es la misma cosa.
          expect(TipoVia.desdeNombre('BalastradaP1'), TipoVia.balastrada);
          expect(TipoVia.desdeNombre('BalastradaP2'), TipoVia.balastrada);
          expect(TipoVia.desdeNombre('Balastrada'), TipoVia.balastrada);
        });

        test('un tipo que no conocemos no rompe el mapa', () {
          // El dia que topografia agregue una categoria, la via tiene que
          // dibujarse igual. Quedarse sin mapa por un valor nuevo seria peor.
          expect(TipoVia.desdeNombre('Destapada'), TipoVia.balastrada);
          expect(TipoVia.desdeNombre(''), TipoVia.balastrada);
        });

        test('solo la proyectada esta sin construir', () {
          expect(TipoVia.proyectada.construida, isFalse);
          expect(TipoVia.balastrada.construida, isTrue);
          expect(TipoVia.pavimentada.construida, isTrue);
          expect(TipoVia.ruta.construida, isTrue);
        });

        test('todos los tipos del asset se reconocen', () {
          for (final t in tipos) {
            expect(TipoVia.desdeNombre(t), isNotNull);
          }
          // Hay vias proyectadas y son una minoria. Si ese conteo se fuera a
          // cero, el parseo perdio el atributo y el mapa mostraria como
          // transitables vias que no estan construidas.
          final iProyectada = tipos.indexOf('Proyectada');
          expect(iProyectada, isNot(-1));
          final proyectadas = crudas.where((v) => v['t'] == iProyectada).length;
          expect(proyectadas, greaterThan(0));
          expect(proyectadas, lessThan(crudas.length ~/ 2));
        });
      });

      test('casi todas son internas del predio', () {
        final internas = crudas.where((v) => v['i'] == 1).length;
        // Las externas son un puñado: vias publicas que solo pasan cerca. Si
        // fueran muchas, el atributo CODIGO se leyo mal y el mapa dibujaria
        // apagadas las vias que la gente recorre todos los dias.
        expect(internas, greaterThan((crudas.length * 0.9).round()));
        expect(crudas.length - internas, greaterThan(0));
      });

      test('las vias traen el codigo de bloque y parcela a la que sirven', () {
        final conCodigo = crudas
            .where((v) => (v['b'] as String).isNotEmpty)
            .length;
        // No todas lo tienen -las externas no sirven a ninguna parcela- pero la
        // mayoria si, y es lo que permite decir "la via del B.10-P.9".
        expect(conCodigo, greaterThan(crudas.length ~/ 2));
      });
    },
  );
}
