import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Si ya se le explico a la persona para que se usa su ubicacion.
///
/// Play pide que, antes del dialogo de permiso de Android, la app diga en sus
/// propias palabras que dato toma, para que y si sale del telefono. El dialogo
/// del sistema solo dice "permitir ubicacion"; no dice que los recorridos se
/// suben a la cuenta ni que un viaje sigue grabando con la pantalla apagada.
///
/// `null` mientras se lee; despues, `true` si ya no hace falta mostrarlo: lo
/// vio, o el permiso ya estaba dado (quien actualiza desde una version sin
/// aviso no tiene por que verlo ahora).
class AvisoUbicacionNotifier extends StateNotifier<bool?> {
  AvisoUbicacionNotifier() : super(null) {
    _leer();
  }

  static const _llave = 'aviso_ubicacion_visto';

  Future<void> _leer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_llave) ?? false) {
        state = true;
        return;
      }
      final permiso = await Geolocator.checkPermission();
      state =
          permiso == LocationPermission.always ||
          permiso == LocationPermission.whileInUse;
    } catch (_) {
      // Un aviso que no se pudo evaluar no puede dejar la app sin abrir. El
      // GPS pide el permiso igual al arrancar.
      state = true;
    }
  }

  /// La persona leyo el aviso y toco Continuar: ahora si, el dialogo de
  /// Android. Lo que conteste ahi lo maneja el GPS como siempre.
  Future<void> continuar() async {
    try {
      await Geolocator.requestPermission();
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_llave, true);
    } catch (_) {}
    state = true;
  }
}

final avisoUbicacionProvider =
    StateNotifierProvider<AvisoUbicacionNotifier, bool?>(
      (ref) => AvisoUbicacionNotifier(),
    );
