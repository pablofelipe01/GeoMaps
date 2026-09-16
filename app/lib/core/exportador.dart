/// Arma el paquete que se entrega y lo registra.
///
/// Un entregable de GeoMaps casi nunca es un archivo suelto: es el KML del
/// lote, las fotos de los waypoints y el PDF con la ficha. Van en un KMZ (que
/// es un ZIP con el KML adentro) para que Google Earth abra las fotos sin que
/// nadie tenga que descomprimir nada.
///
/// Cada archivo que sale de aca genera una fila en `Archivos` de Airtable al
/// sincronizar, con su URL del bucket. Ese es el rastro de que se entrego, a
/// quien y cuando.
class Exportador {
  // TODO: kmz(trazado) -> File   (doc.kml + files/*.jpg)
  // TODO: gpx(trazado) -> File
  // TODO: geojson(trazado) -> File
  // TODO: registrarLocal(File, tipo) -> fila en la tabla archivos, pendiente
}
