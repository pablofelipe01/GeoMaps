/// Lectura del mapa offline del usuario.
///
/// Un MBTiles es un SQLite con una tabla `tiles(zoom_level, tile_column,
/// tile_row, tile_data)` y una tabla `metadata`. Se eligio sobre una carpeta
/// de teselas sueltas por una razon de sistema de archivos: un municipio son
/// decenas de miles de PNG de 10 KB, y Android tarda mas en abrir 40.000
/// archivos que en leer un SQLite de 400 MB. Ademas es UN archivo: se descarga
/// y o esta completo o no esta.
///
/// Dos trampas del formato que cuestan una tarde:
///
/// 1. **El eje Y va al reves.** MBTiles usa el esquema TMS (fila 0 abajo) y
///    flutter_map pide XYZ (fila 0 arriba). La conversion es
///    `y_tms = (1 << z) - 1 - y_xyz`. Un mapa con el eje sin invertir se
///    dibuja espejado en vertical y no lanza ningun error.
/// 2. **`metadata.bounds` viene en WGS84** aunque las teselas esten en Web
///    Mercator. Es lo que se usa para encuadrar y para avisar cuando el
///    usuario esta parado fuera del mapa que abrio.
class MapaOffline {
  // TODO: abrir(File) -> valida que exista la tabla tiles y lee metadata
  // TODO: bounds, zoomMin, zoomMax, formato (png/jpg/pbf)
  // TODO: proveedor de teselas para flutter_map, con la inversion del eje Y
  // TODO: cerrar() -- dejar el SQLite abierto bloquea borrar el mapa
}
