/// Trazados: rutas y poligonos.
///
/// El repositorio es el unico que escribe `areaHa`, `distanciaM`,
/// `precisionMediaM`, `bbox` y el centroide, siempre recalculandolos con
/// `core/geo.dart` al cerrar el trazado. Si esos numeros se calcularan en la
/// pantalla, un trazado editado despues quedaria con el area vieja y nadie lo
/// notaria.
///
/// ## Donde vive la geometria
///
/// En dos sitios, y no es duplicacion:
///
/// - **SQLite local** (`geometria`): completa, y es la fuente de verdad
///   mientras el telefono esta en campo. Sin red no hay otra cosa.
/// - **S3** (`llaveGeometria`): el mismo GeoJSON, subido al sincronizar. Es la
///   copia que consulta el resto del mundo.
///
/// Airtable no guarda ninguna de las dos: guarda la llave, el bbox, el
/// centroide, los numeros y una vista previa de 50 vertices.
///
/// El orden al sincronizar importa: **primero S3, despues Airtable**. Una fila
/// con `Llave geometria` apuntando a un objeto que no existe es un trazado que
/// en la base parece estar y al abrirlo no esta.
class TrazadosRepository {
  // TODO: crear(proyecto, tipo, metodo) -> UUID
  // TODO: agregarVertice(codigo, PuntoGeo, precisionM)
  // TODO: cerrar(codigo)
  //       recalcula distancia, area, precision media, bbox y centroide
  // TODO: pendientesDeSincronizar()
  // TODO: marcarSubido(codigo, llaveGeometria)
}
