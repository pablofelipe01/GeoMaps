/// Que capas se dibujan y en que orden.
///
/// De abajo hacia arriba: capa base (Esri o OSM) -> mapas MBTiles del usuario
/// por su campo `orden` -> trazados -> waypoints -> posicion propia. La
/// posicion va siempre arriba de todo: un mapa opaco que tape el punto azul
/// deja al tecnico sin saber donde esta, que es justo lo unico que la app
/// tiene que garantizar.
class CapasState {
  // TODO: capaBase (esri/osm/ninguna), mapasVisibles, opacidades
}
