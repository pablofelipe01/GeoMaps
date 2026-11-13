import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/waypoints_repository.dart';
import 'providers.dart';
import 'sesion.dart';
import 'sincronizador.dart';

/// Lo que la cuenta levanto en campo, listo para que el mapa y las listas lo
/// lean: los recorridos grabados, las areas medidas y los puntos marcados.
///
/// La grabacion en curso no vive aca sino en `state/grabacion.dart`, que es
/// quien escucha el GPS. Esto es lo que ya quedo guardado.

final waypointsRepositoryProvider = Provider<WaypointsRepository>(
  (ref) => WaypointsRepository(ref.watch(dbProvider)),
);

/// Recorridos grabados y areas medidas de la cuenta que esta adentro, lo mas
/// nuevo arriba.
final levantadosProvider = StreamProvider<List<Trazado>>((ref) {
  final usuario = ref.watch(
    sesionProvider.select((e) => e.sesion?.codigoUsuario),
  );
  if (usuario == null) return Stream.value(const []);
  return ref.watch(trazadosRepositoryProvider).observarLevantados(usuario);
});

/// Los puntos marcados de la cuenta que esta adentro.
final puntosProvider = StreamProvider<List<Waypoint>>((ref) {
  final usuario = ref.watch(
    sesionProvider.select((e) => e.sesion?.codigoUsuario),
  );
  if (usuario == null) return Stream.value(const []);
  return ref.watch(waypointsRepositoryProvider).observar(usuario);
});
