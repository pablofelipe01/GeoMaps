/// Cliente HTTP contra el backend.
///
/// Regla que ordena este archivo: **ningun metodo de aca puede ser necesario
/// para que la app funcione en campo.** Todos sirven para sincronizar,
/// descargar mapas o validar el login con red. Si uno falla, la pantalla que
/// lo llamo sigue andando con lo que tiene en la base local.
class ApiClient {
  // TODO: GET  /v1/proyectos            -> espejo del directorio
  // TODO: GET  /v1/mapas?proyecto=       -> fichas de mapas listos
  // TODO: GET  /v1/mapas/{id}/descarga   -> URL firmada del MBTiles
  // TODO: POST /v1/sync                  -> upsert por UUID de todo lo pendiente
  // TODO: POST /v1/archivos              -> sube KML/GPX/PDF/foto al bucket
  // TODO: POST /v1/login                 -> valida contra nomina, devuelve hash
}
