/// Traer un mapa al telefono.
///
/// Dos caminos, y conviene no mezclarlos en la cabeza del usuario:
///
/// 1. **Descargar** un mapa que coordinacion ya subio y el backend ya
///    convirtio. Es el camino normal: llega listo y pesa lo que dice.
/// 2. **Importar** un archivo del telefono. Si es un MBTiles se usa tal cual;
///    si es un GeoPDF o un GeoTIFF hay que subirlo para que el backend lo
///    convierta, porque GDAL no corre aca.
///
/// La pantalla tiene que decir cual de los dos esta pasando. Un usuario que
/// cree que importo un GeoPDF y en realidad lo subio a convertir va a salir a
/// campo sin mapa.
class ImportarMapaPage {
  // TODO
}
