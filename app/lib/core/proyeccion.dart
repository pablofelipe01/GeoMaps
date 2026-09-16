/// Reproyeccion de coordenadas.
///
/// Las teselas del MBTiles ya llegan en Web Mercator (EPSG:3857) porque es lo
/// unico que flutter_map sabe dibujar; el backend las deja asi al convertir.
/// Este archivo existe para el camino contrario: cuando alguien teclea una
/// coordenada en el sistema del proyecto y hay que llevarla al mapa.
///
/// En Colombia lo que llega de topografia casi nunca es WGS84:
///
/// - `EPSG:3116`  MAGNA-SIRGAS / Colombia Bogota zone (el mas comun)
/// - `EPSG:9377`  MAGNA-SIRGAS / Origen-Nacional (el oficial desde 2020)
/// - `EPSG:21897` Bogota 1975 / Colombia Bogota zone (levantamientos viejos)
///
/// Interpretar un plano de MAGNA-SIRGAS como si fuera WGS84 lo corre unos
/// cientos de metros. Abre sin error y nadie lo nota hasta que alguien camina
/// al punto equivocado.
class Proyeccion {
  // TODO: registrar las definiciones proj4 de los EPSG de arriba
  // TODO: aWgs84(x, y, epsgOrigen) -> PuntoGeo
  // TODO: desdeWgs84(PuntoGeo, epsgDestino) -> (x, y)
}
