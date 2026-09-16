/// Bajar una region del mapa base (Esri / OSM) para usarla sin senal.
///
/// Es distinto de importar un MBTiles: aca se cachean teselas de un servidor
/// publico con FMTC, dibujando un recuadro sobre el mapa y eligiendo hasta que
/// zoom.
///
/// La pantalla tiene que estimar el peso ANTES de empezar. El conteo crece por
/// cuatro con cada nivel de zoom, y una region que a z14 pesa 20 MB a z18 pesa
/// varios GB. Sin la estimacion a la vista, alguien va a llenar el telefono.
class DescargarRegionPage {
  // TODO
}
