/// El catalogo de capas y su estado de descarga.
///
/// Distingue tres cosas que la pantalla de capas confunde facil:
///
/// - **Registrado**: existe la ficha, el MBTiles esta en el bucket.
/// - **Descargado**: el archivo esta en el telefono (`rutaLocal != null`).
/// - **Visible**: el usuario lo tiene encendido ahora.
///
/// Un mapa en estado `procesando` no se le ofrece al telefono: descargar un
/// MBTiles a medio escribir deja la app con un mapa corrupto y sin error.
class MapasRepository {
  // TODO: delProyecto(codigo) -> ordenados por `orden`
  // TODO: registrarDescarga(codigo, rutaLocal, tamanoMb)
  // TODO: borrarDescarga(codigo) -- cerrar el SQLite antes o el borrado falla
  // TODO: espacioUsadoMb()
}
