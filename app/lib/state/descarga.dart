/// La descarga de un mapa, con su progreso.
///
/// Un MBTiles de cientos de MB sobre red rural tarda y se corta. Por eso:
/// descarga reanudable por rangos HTTP, verificacion del tamano al terminar, y
/// el archivo se escribe con extension `.parcial` hasta que esta completo. Sin
/// eso, un corte deja un SQLite truncado que la app abre sin error y dibuja a
/// medias.
class DescargaState {
  // TODO: progreso, bytesBajados, bytesTotales, cancelar()
}
