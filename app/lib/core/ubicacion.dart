/// El GPS: permisos, lecturas y los dos filtros que hacen util un trazado.
///
/// Portado de sirius_agro. Los filtros no son cosmetica:
///
/// - **Filtro de precision.** Un fix con 30 m de error bajo los arboles no
///   describe un lindero; lo descarta y lo cuenta, para que la pantalla pueda
///   decir "bajo el dosel no hay senal, sali al claro" en vez de dibujar un
///   poligono que parece bueno y no lo es.
/// - **Filtro de distancia minima.** Parado hablando, el GPS entrega puntos
///   que saltan unos metros. Sin el filtro, diez minutos de conversacion
///   agregan cientos de vertices de ruido al recorrido.
class Ubicacion {
  // TODO: pedirPermisos() -- incluye el de segundo plano en Android 10+
  // TODO: posicionActual({Duration tiempoMax}) -> lectura con su precision
  // TODO: flujo(intervalo, distanciaMinimaM, precisionMaximaM)
}
