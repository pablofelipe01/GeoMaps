import 'package:flutter_test/flutter_test.dart';

import 'package:geomaps/main.dart';

void main() {
  testWidgets('la app arranca en el mapa', (tester) async {
    await tester.pumpWidget(const GeoMapsApp());
    expect(find.byType(GeoMapsApp), findsOneWidget);
  });
}
