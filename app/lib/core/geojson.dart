import 'geo.dart';

/// GeoJSON: el formato en que el trazado sale del telefono y vive en S3.
///
/// Se eligio sobre KML como formato de **almacenamiento** (KML sigue siendo un
/// export) por dos razones: es el unico que QGIS, PostGIS, Airtable scripting y
/// cualquier libreria de JavaScript leen sin traducir, y no obliga a envolver
/// la geometria en un documento con estilos que nadie va a usar.
///
/// La trampa es la misma de KML y se paga igual de caro: el orden es
/// **[longitud, latitud]**, al reves de como se dice y de como lo guarda la
/// base. Un GeoJSON con los ejes invertidos se valida sin error y pone el lote
/// en Somalia.
class GeoJson {
  // TODO: deTrazado(vertices, tipo) -> String
  //       Un Feature con la geometria y, en `properties`, lo que hace util el
  //       archivo suelto: nombre, area, distancia, precision media y quien lo
  //       levanto. Un GeoJSON sin metadatos obliga a volver a Airtable para
  //       saber si el poligono sirve para un lindero.
  // TODO: bbox(vertices) -> "minLon,minLat,maxLon,maxLat"
  // TODO: centroide(vertices) -> PuntoGeo
}

/// Reduccion de vertices por Douglas-Peucker.
///
/// Tiene un solo uso y conviene que no se le encuentren otros: generar la
/// `Vista previa` que va a Airtable, con un tope de 50 vertices, para que
/// coordinacion vea la forma del lote sin bajar nada de S3.
///
/// **No es el dato.** Un area medida sobre la version simplificada no es el
/// area del lote. Por eso el campo en Airtable se llama `Vista previa` y no
/// `Geometria`: el nombre es la unica defensa contra que alguien la use para
/// medir dentro de seis meses.
class Simplificador {
  static const maxVerticesVistaPrevia = 50;

  // TODO: douglasPeucker(List<PuntoGeo>, toleranciaM) -> List<PuntoGeo>
  // TODO: aMaximo(List<PuntoGeo>, n) -> busca la tolerancia que deja <= n
}
