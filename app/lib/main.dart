import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/theme.dart';

/// Punto de entrada.
///
/// Lo unico que hace antes de pintar es abrir la base local: si el telefono
/// arranca en un lote sin senal, la lista de proyectos y los trazados de ayer
/// tienen que estar ahi. Nada en el arranque puede esperar una respuesta del
/// backend.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // TODO: abrir la base drift, cargar la semilla si es el primer arranque y
  // registrar el servicio de primer plano del GPS.
  runApp(const ProviderScope(child: GeoMapsApp()));
}

class GeoMapsApp extends StatelessWidget {
  const GeoMapsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GeoMaps',
      theme: temaSirius,
      // TODO: enrutar a login_page o proyectos_page segun haya sesion.
      home: const Scaffold(body: Center(child: Text('GeoMaps'))),
    );
  }
}
