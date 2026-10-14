/// Los enumerados que comparten la base local y Airtable.
///
/// En la base local se guarda el `.name` de Dart (`ruta`, `calculada`). En
/// Airtable la opcion del Single select es otra (`Ruta`, `Calculada`), y la
/// traduccion la hace el backend en `schemas_sync.py`, que rechaza lo que no
/// conoce: con `typecast` un valor sin traducir no falla, crea una opcion nueva
/// al lado de la buena. Agregar un valor aca pide agregarlo alla.
library;

enum TipoTrazado { ruta, poligono }

enum MetodoCaptura {
  automatico,
  manual,
  mixto,

  /// La ruta que calculo el ruteo por las vias del predio y alguien guardo
  /// desde el mapa. Nadie la camino: no tiene precision de GPS y no sirve como
  /// lindero, y por eso no puede confundirse con un recorrido grabado.
  calculada,
}

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

/// Como termino un intento de subida, en la tabla local `Sincronizaciones`.
enum ResultadoSync { ok, parcial, fallida }
