import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geomaps/camiones/vueltas.dart';
import 'package:geomaps/camiones/vueltas_page.dart';

/// La pantalla que abre el QR: que tomar una vuelta pida solo lo que le falta
/// a la cuenta.
///
/// Es la pantalla del reporte "la lista no se deja asignar": a una cuenta de
/// Google se le pedia una clave de GeoMaps que no tiene, y no habia forma de
/// pasar de ahi.
void main() {
  Vuelta vuelta({double? lat}) => Vuelta.deJson({
    'id': 'v1',
    'jornada': '2026-11-09',
    'consecutivo': 23,
    'tipo_fruto': 'comercial',
    'reportado_en': '2026-11-09T20:40:00Z',
    'origen': {
      'codigo': 'B.3-P.4 · 11A',
      'bloque': '3',
      'num': '11A',
      'lat': lat,
      'lon': lat == null ? null : -72.98,
    },
  });

  Future<void> abrir(
    WidgetTester tester, {
    Conductor? conductor,
    double? lat = 4.49,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vueltasProvider.overrideWith(
            (ref) async => ListaVueltas(
              vueltas: [vuelta(lat: lat)],
              conductor: conductor,
            ),
          ),
        ],
        child: const MaterialApp(home: VueltasPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tocarTomar(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Tomar'));
    await tester.pumpAndSettle();
  }

  testWidgets('a una cuenta de Google nueva le pide la cedula y no la clave', (
    tester,
  ) async {
    await abrir(tester, conductor: const Conductor(pideClave: false));

    expect(find.textContaining('te pide la cedula'), findsOneWidget);
    await tocarTomar(tester);

    expect(find.text('Tomar vuelta #23'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Cedula'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Clave de GeoMaps'), findsNothing);
  });

  testWidgets('con la cedula ya atada, una cuenta de Google confirma sin '
      'escribir nada', (tester) async {
    await abrir(
      tester,
      conductor: const Conductor(
        cedula: '1122334',
        nombre: 'ANA',
        pideClave: false,
      ),
    );

    expect(find.textContaining('a nombre de ANA (CC ***334)'), findsOneWidget);
    await tocarTomar(tester);

    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('a nombre de ANA'), findsWidgets);
    expect(
      find.widgetWithText(FilledButton, 'Tomar la vuelta'),
      findsOneWidget,
    );
  });

  testWidgets('a una cuenta con clave y cedula atada le pide solo la clave', (
    tester,
  ) async {
    await abrir(
      tester,
      conductor: const Conductor(cedula: '1122334', nombre: 'ANA'),
    );
    await tocarTomar(tester);

    expect(find.widgetWithText(TextField, 'Cedula'), findsNothing);
    expect(find.widgetWithText(TextField, 'Clave de GeoMaps'), findsOneWidget);
  });

  testWidgets('sin escribir lo que falta no se manda nada', (tester) async {
    await abrir(tester, conductor: const Conductor(pideClave: false));
    await tocarTomar(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Tomar la vuelta'));
    await tester.pump();

    expect(find.text('Escribe tu cedula.'), findsOneWidget);
    expect(find.text('Tomar vuelta #23'), findsOneWidget);
  });

  testWidgets('una vuelta sin coordenada tambien se deja tomar', (
    tester,
  ) async {
    await abrir(
      tester,
      conductor: const Conductor(pideClave: false),
      lat: null,
    );

    expect(find.textContaining('Sin coordenada'), findsOneWidget);
    await tocarTomar(tester);

    expect(find.text('Tomar vuelta #23'), findsOneWidget);
    expect(find.textContaining('el mapa no va a trazar'), findsOneWidget);
  });
}
