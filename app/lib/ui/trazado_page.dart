/// Capturar un recorrido o un poligono.
///
/// Dos modos y el mixto, que es el que realmente se usa: se camina el lindero
/// con captura automatica y se corrigen a mano los vertices de las esquinas,
/// donde el GPS siempre redondea.
///
/// Mientras captura, la pantalla muestra los contadores de `state/captura.dart`
/// y la precision del ultimo fix. No se puede cerrar un poligono de menos de
/// tres vertices, y la app lo dice antes de que alguien camine media hora.
class TrazadoPage {
  // TODO
}
