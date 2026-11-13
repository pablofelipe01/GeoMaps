import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geomaps/core/api_client.dart';
import 'package:geomaps/core/geo.dart';
import 'package:geomaps/data/db/app_database.dart';
import 'package:geomaps/data/trazados_repository.dart';
import 'package:geomaps/state/sincronizador.dart';
import 'package:geomaps/ui/calificar_ruta.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Calificar la ruta por donde se paso: que la nota quede guardada con el
/// recorrido que se grabo, que suba con el, y que el dialogo no obligue a
/// contestar.
void main() {
  const linea = [
    PuntoGeo(4.4500, -72.9600),
    PuntoGeo(4.4510, -72.9590),
    PuntoGeo(4.4525, -72.9580),
  ];

  group('la calificacion', () {
    test('lo que no se contesto no viaja', () {
      expect(const CalificacionRuta(estrellas: 5).aPropiedades(), {
        'calificacion': 5,
      });
      expect(
        const CalificacionRuta(
          estrellas: 2,
          motivos: [MotivoRuta.barro, MotivoRuta.cerrada],
          comentario: '  El paso del cano  ',
        ).aPropiedades(),
        {
          'calificacion': 2,
          'calificacion_motivos': ['barro', 'cerrada'],
          'calificacion_comentario': 'El paso del cano',
        },
      );
      expect(
        const CalificacionRuta(estrellas: 3, comentario: '   ').aPropiedades(),
        {'calificacion': 3},
      );
    });
  });

  group('con el recorrido', () {
    late AppDatabase db;
    late TrazadosRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = TrazadosRepository(db);
    });
    tearDown(() => db.close());

    test('queda adentro del recorrido, junto a lo que ya llevaba', () async {
      final t = await repo.abrirGrabacion(
        usuarioCodigo: 'u1',
        nombre: 'Ruta a Acopio 30',
        propiedades: {'tipo': 'navegacion', 'ruta_sugerida_m': 1200},
      );
      final cerrada = await repo.cerrarGrabacion(
        t.codigo,
        linea,
        propiedades: const CalificacionRuta(
          estrellas: 2,
          motivos: [MotivoRuta.barro],
        ).aPropiedades(),
      );

      final propiedades =
          (jsonDecode(cerrada!.geometria) as Map)['properties'] as Map;
      expect(propiedades['calificacion'], 2);
      expect(propiedades['calificacion_motivos'], ['barro']);
      expect(propiedades['tipo'], 'navegacion');
      expect(propiedades['ruta_sugerida_m'], 1200);

      // La lista lee las estrellas sin decodificar el recorrido entero.
      expect(CalificacionRuta.estrellasDe(cerrada.geometria), 2);
    });

    test('un recorrido sin calificar no tiene estrellas', () async {
      final t = await repo.abrirGrabacion(usuarioCodigo: 'u1', nombre: 'x');
      final cerrada = await repo.cerrarGrabacion(t.codigo, linea);
      expect(CalificacionRuta.estrellasDe(cerrada!.geometria), isNull);
    });

    test('sube con el recorrido, aparte del GeoJSON', () async {
      final t = await repo.abrirGrabacion(
        usuarioCodigo: 'u1',
        nombre: 'Ruta a Acopio 30',
      );
      await repo.cerrarGrabacion(
        t.codigo,
        linea,
        propiedades: const CalificacionRuta(
          estrellas: 4,
          comentario: 'Bien, salvo el puente',
        ).aPropiedades(),
      );

      late Map<String, dynamic> enviado;
      final api = ApiClient(
        cliente: MockClient((pedido) async {
          enviado = jsonDecode(pedido.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'trazados': [
                {'codigo': t.codigo, 'ok': true, 'llave_geometria': 'k'},
              ],
            }),
            200,
          );
        }),
      )..token = 'jwt';
      final sync = Sincronizador(db, repo, api, 'u1');

      await sync.sincronizar();

      final trazado = (enviado['trazados'] as List).single as Map;
      expect(trazado['calificacion'], 4);
      expect(trazado['calificacion_comentario'], 'Bien, salvo el puente');
      expect(trazado.containsKey('calificacion_motivos'), isFalse);
      expect(
        ((trazado['geometria'] as Map)['properties'] as Map)['calificacion'],
        4,
      );
      sync.dispose();
    });
  });

  group('el dialogo', () {
    Future<CalificacionRuta?> Function() abrir(WidgetTester tester) {
      CalificacionRuta? resultado;
      var cerrado = false;
      return () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () async {
                      resultado = await pedirCalificacion(
                        context,
                        titulo: 'Llegaste: Acopio 30',
                        detalle: 'Recorriste 1,2 km.',
                      );
                      cerrado = true;
                    },
                    child: const Text('abrir'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();
        expect(cerrado, isFalse);
        return resultado;
      };
    }

    testWidgets('no deja guardar sin elegir una estrella, pero si omitir', (
      tester,
    ) async {
      await abrir(tester)();

      expect(find.text('Llegaste: Acopio 30'), findsOneWidget);
      final guardar = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Guardar'),
      );
      expect(guardar.onPressed, isNull);
      // Los motivos y el comentario no aparecen hasta que hay una nota.
      expect(find.byType(FilterChip), findsNothing);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Omitir'));
      await tester.pumpAndSettle();
      expect(find.text('Llegaste: Acopio 30'), findsNothing);
    });

    testWidgets('con nota baja pregunta que paso', (tester) async {
      await abrir(tester)();

      await tester.tap(find.byKey(const ValueKey('estrella-2')));
      await tester.pumpAndSettle();

      expect(find.text('Mala'), findsOneWidget);
      expect(find.byType(FilterChip), findsNWidgets(MotivoRuta.values.length));
      expect(find.text('Barro o agua'), findsOneWidget);
    });

    testWidgets('con nota alta no pregunta motivos', (tester) async {
      await abrir(tester)();

      await tester.tap(find.byKey(const ValueKey('estrella-5')));
      await tester.pumpAndSettle();

      expect(find.text('Muy buena'), findsOneWidget);
      expect(find.byType(FilterChip), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('devuelve la nota, los motivos y el comentario', (
      tester,
    ) async {
      CalificacionRuta? resultado;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  resultado = await pedirCalificacion(context, titulo: 'Fin');
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('estrella-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paso cerrado'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'El cano crecio');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      expect(resultado!.estrellas, 2);
      expect(resultado!.motivos, [MotivoRuta.cerrada]);
      expect(
        resultado!.aPropiedades()['calificacion_comentario'],
        'El cano crecio',
      );
    });

    testWidgets('subir la nota descarta los motivos que se habian marcado', (
      tester,
    ) async {
      CalificacionRuta? resultado;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  resultado = await pedirCalificacion(context, titulo: 'Fin');
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('estrella-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Barro o agua'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('estrella-5')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      expect(resultado!.estrellas, 5);
      expect(resultado!.motivos, isEmpty);
    });
  });
}
