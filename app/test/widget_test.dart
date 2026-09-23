import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geomaps/main.dart';
import 'package:geomaps/ui/login_page.dart';

void main() {
  // Sin `ProviderScope` la app no arranca: la puerta que decide entre login y
  // home es un ConsumerWidget.
  testWidgets('sin sesion guardada, la app abre en el login', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: GeoMapsApp()));

    // El arranque lee el almacen seguro, y eso pasa por un canal de plataforma.
    // `pump` solo no lo destraba: hace falta dejar correr el reloj de verdad
    // con `runAsync`, o la prueba se queda mirando el indicador para siempre.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    // En la prueba no hay plugin, asi que la lectura falla. Ese es justo el
    // camino que interesa: un almacen ilegible tiene que terminar en el login
    // y no dejar la app colgada del indicador de arranque.
    expect(find.byType(LoginPage), findsOneWidget);
  });
}
