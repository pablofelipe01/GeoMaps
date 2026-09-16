/// El PDF que se imprime y se entrega.
///
/// Usa `pdf` + `printing` igual que sirius_agro, y carga Museo Slab a mano
/// desde los assets: el generador de PDF no lee el registro de fuentes de
/// Flutter. Roboto queda de reserva para que un caracter raro no salga como un
/// cuadro vacio en el papel que recibe el cliente.
///
/// Lo que el informe tiene que decir y casi siempre se olvida: **la precision
/// del GPS con la que se levanto**. Un area de 4,2 ha medida con 30 m de error
/// no es el mismo dato que una medida con 3 m, y en el papel se ven iguales si
/// nadie lo escribe.
class InformePdf {
  // TODO: deTrazado(trazado, mapa) -> bytes
  //       membrete Sirius, mapa estatico, tabla de vertices, area, precision
}
