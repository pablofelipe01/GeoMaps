import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Si hay conexion.
///
/// No sirve para bloquear nada: sirve para que el indicador de la barra diga
/// la verdad y para que el sincronizador sepa cuando intentar.
///
/// Ojo con lo que significa: `connectivity_plus` dice si el telefono esta
/// **enganchado** a una red, no si esa red llega a internet. Un wifi de finca
/// sin salida aparece como conectado. Por eso nada critico se decide con esto;
/// la prueba real es que la llamada al backend responda.
class RedState {
  const RedState(this.tipos);

  final List<ConnectivityResult> tipos;

  bool get hayRed =>
      tipos.any((t) => t != ConnectivityResult.none) && tipos.isNotEmpty;

  bool get porWifi => tipos.contains(ConnectivityResult.wifi);

  bool get porDatos => tipos.contains(ConnectivityResult.mobile);

  /// Como mostrarlo. "Wifi" y "Datos" se distinguen porque descargar un mapa de
  /// 300 MB por datos moviles es una decision, no un detalle.
  String get etiqueta {
    if (!hayRed) return 'Sin conexion';
    if (porWifi) return 'Wifi';
    if (porDatos) return 'Datos moviles';
    return 'En linea';
  }
}

/// El estado de red en vivo.
///
/// Arranca con lo que diga `checkConnectivity()` y despues sigue el flujo: sin
/// la primera lectura, la app muestra "sin conexion" hasta que la red cambie,
/// que puede ser nunca.
final redProvider = StreamProvider<RedState>((ref) async* {
  final conectividad = Connectivity();
  yield RedState(await conectividad.checkConnectivity());
  yield* conectividad.onConnectivityChanged.map(RedState.new);
});
