import 'dart:math' as math;

/// Geometria sobre la esfera, sin dependencias de Flutter ni de la base.
///
/// Portado de sirius_agro tal cual, junto con sus pruebas. Vive aparte porque
/// es lo unico de la captura que se puede probar sin telefono y sin GPS: si el
/// area de un lote sale mal, el error esta aca y una prueba unitaria lo caza.

/// Radio ecuatorial WGS84. Es el mismo que usa Google Earth para calcular
/// areas, y eso importa: el KML que sale de la app se abre alli, y dos numeros
/// distintos para el mismo poligono hacen dudar de los dos.
const double radioTierraM = 6378137.0;

double _rad(double grados) => grados * math.pi / 180.0;

/// Un punto capturado, sin metadatos. Lo que necesita la geometria y nada mas.
class PuntoGeo {
  const PuntoGeo(this.latitud, this.longitud);

  final double latitud;
  final double longitud;

  @override
  String toString() =>
      '${latitud.toStringAsFixed(6)}, ${longitud.toStringAsFixed(6)}';
}

/// Distancia entre dos puntos por haversine, en metros.
double distanciaM(PuntoGeo a, PuntoGeo b) {
  final dLat = _rad(b.latitud - a.latitud);
  final dLon = _rad(b.longitud - a.longitud);
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(a.latitud)) *
          math.cos(_rad(b.latitud)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * radioTierraM * math.asin(math.min(1, math.sqrt(h)));
}

/// Largo total de una ruta, en metros.
double longitudRutaM(List<PuntoGeo> puntos) {
  var total = 0.0;
  for (var i = 1; i < puntos.length; i++) {
    total += distanciaM(puntos[i - 1], puntos[i]);
  }
  return total;
}

/// Area de un poligono en metros cuadrados, sobre la esfera.
///
/// Es la formula que usa Google Earth (la de `computeArea` de su libreria de
/// geometria): suma, lado por lado, el area del trapecio esferico entre el lado
/// y el ecuador. Importa que sea la misma y no una proyeccion plana cualquiera:
/// el KML que sale de la app se abre alli, y dos areas distintas para el mismo
/// lote hacen dudar de las dos.
///
/// No importa el sentido en que se camino el lindero ni si el ultimo vertice
/// repite al primero. Con menos de tres vertices no hay area: cero.
///
/// Lo que **no** resuelve: un lindero que se cruza a si mismo (un ocho). Ahi
/// las dos mitades se restan y el numero sale chico, sin avisar.
double areaM2(List<PuntoGeo> vertices) {
  var puntos = vertices;
  if (puntos.length > 1 &&
      puntos.first.latitud == puntos.last.latitud &&
      puntos.first.longitud == puntos.last.longitud) {
    puntos = puntos.sublist(0, puntos.length - 1);
  }
  if (puntos.length < 3) return 0;

  var suma = 0.0;
  for (var i = 0; i < puntos.length; i++) {
    final a = puntos[i];
    final b = puntos[(i + 1) % puntos.length];
    suma +=
        _rad(b.longitud - a.longitud) *
        (2 + math.sin(_rad(a.latitud)) + math.sin(_rad(b.latitud)));
  }
  return (suma * radioTierraM * radioTierraM / 2).abs();
}

/// Lo mismo en hectareas, que es como se habla de un lote.
double areaHa(List<PuntoGeo> vertices) => areaM2(vertices) / 10000.0;

/// El largo del borde de un poligono: la ruta por sus vertices mas el lado que
/// lo cierra.
double perimetroM(List<PuntoGeo> vertices) {
  if (vertices.length < 2) return 0;
  return longitudRutaM(vertices) + distanciaM(vertices.last, vertices.first);
}
