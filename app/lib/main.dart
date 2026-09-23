import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'core/version_app.dart';
import 'state/actualizacion.dart';
import 'state/providers.dart';
import 'state/sesion.dart';
import 'ui/actualizacion_page.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';
import 'ui/theme.dart';

/// Punto de entrada.
///
/// Nada en el arranque puede esperar una respuesta del backend: si el telefono
/// abre en un lote sin senal, la sesion guardada y los trazados de ayer tienen
/// que estar ahi.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // TODO: abrir la base drift y sembrar en el primer arranque.
  runApp(
    ProviderScope(
      overrides: [
        versionLocalProvider.overrideWithValue(await _versionLocal()),
      ],
      child: const GeoMapsApp(),
    ),
  );
}

/// La version de este APK, leida del propio APK: no toca la red. Si no se
/// puede leer, la app arranca igual y simplemente no se bloquea.
Future<VersionLocal?> _versionLocal() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final code = int.tryParse(info.buildNumber);
    if (code == null) return null;
    return VersionLocal(code: code, nombre: info.version);
  } catch (_) {
    return null;
  }
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

/// Decide entre actualizar, login y home.
///
/// La decision se toma contra la sesion **guardada**, sin red. Pedir login en un
/// potrero es pedirle a alguien que no trabaje.
///
/// Una version bloqueada va antes que todo, con sesion o sin ella: lo que se
/// hiciera en ella despues no podria sincronizarse.
class _Puerta extends ConsumerWidget {
  const _Puerta();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(actualizacionProvider.select((e) => e.estado));
    if (version == EstadoVersion.bloqueada) return const ActualizacionPage();

    final estado = ref.watch(sesionProvider);

    // Solo mientras se lee el almacen seguro al arrancar. Dura milisegundos.
    if (estado.cargando && estado.sesion == null && estado.error == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return estado.autenticado ? const HomePage() : const LoginPage();
  }
}
