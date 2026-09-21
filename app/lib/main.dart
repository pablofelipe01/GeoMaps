import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/sesion.dart';
import 'ui/login_page.dart';
import 'ui/mapa_page.dart';
import 'ui/theme.dart';

/// Punto de entrada.
///
/// Nada en el arranque puede esperar una respuesta del backend: si el telefono
/// abre en un lote sin senal, la sesion guardada y los trazados de ayer tienen
/// que estar ahi.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // TODO: abrir la base drift y sembrar en el primer arranque.
  runApp(const ProviderScope(child: GeoMapsApp()));
}

class GeoMapsApp extends StatelessWidget {
  const GeoMapsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GeoMaps',
      theme: temaSirius,
      debugShowCheckedModeBanner: false,
      home: const _Puerta(),
    );
  }
}

/// Decide entre login y mapa.
///
/// La decision se toma contra la sesion **guardada**, sin red. Pedir login en un
/// potrero es pedirle a alguien que no trabaje.
class _Puerta extends ConsumerWidget {
  const _Puerta();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(sesionProvider);

    // Solo mientras se lee el almacen seguro al arrancar. Dura milisegundos.
    if (estado.cargando && estado.sesion == null && estado.error == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return estado.autenticado ? const MapaPage() : const LoginPage();
  }
}
