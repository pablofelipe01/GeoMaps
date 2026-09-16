/// Los enumerados que comparten la base local y Airtable.
///
/// Los nombres en Airtable van sin tildes, asi que el `.name` de Dart sirve
/// tal cual como valor del Single select. Si alguien renombra una opcion en
/// Airtable sin tocar esto, el upsert empieza a fallar con typecast: por eso
/// el valor vive aca y no escrito a mano en cada servicio.

enum TipoTrazado { ruta, poligono }

enum MetodoCaptura { automatico, manual, mixto }

/// De donde salio el mapa antes de ser MBTiles. Importa para saber si se puede
/// volver a generar y con que parametros.
enum FormatoMapa { geoPdf, geoTiff, kmz, mbtiles }

enum EstadoMapa { procesando, listo, fallido }

/// Los simbolos de waypoint. Son pocos a proposito: una lista de cuarenta
/// iconos hace que nadie elija ninguno y todos queden en generico.
enum SimboloWaypoint {
  generico,
  muestra,
  arbol,
  fuenteDeAgua,
  infraestructura,
  riesgo,
}

enum TipoArchivo { kml, kmz, gpx, geojson, pdf, foto }

enum RolUsuario { campo, coordinador, admin }
