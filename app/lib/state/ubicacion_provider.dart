import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../core/ubicacion.dart';

/// La posicion actual, para las pantallas que solo quieren mostrarla.
///
/// Es `autoDispose` a proposito: el GPS es lo que mas bateria consume en esta
/// app, y el home no tiene por que mantenerlo prendido cuando alguien lo dejo
/// atras. En cuanto la ultima pantalla que lo mira se va, el flujo se corta.
///
/// La pantalla del mapa NO usa esto: maneja su propia suscripcion porque
/// necesita controlar el filtro de distancia mientras se captura un trazado.
final posicionProvider = StreamProvider.autoDispose<Position>((ref) async* {
  final permiso = await Ubicacion.pedirPermisos();
  if (!permiso.concedido) {
    // El motivo viaja como error del provider para que la pantalla pueda
    // mostrarlo tal cual: "activa la ubicacion" y "el permiso quedo denegado
    // para siempre" piden cosas distintas de la persona.
    throw PermisoUbicacionDenegado(
      permiso.motivo ?? 'Sin permiso de ubicacion',
    );
  }
  yield* Ubicacion.flujo();
});

class PermisoUbicacionDenegado implements Exception {
  const PermisoUbicacionDenegado(this.motivo);

  final String motivo;

  @override
  String toString() => motivo;
}
