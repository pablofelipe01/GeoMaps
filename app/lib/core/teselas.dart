import 'dart:math' as math;

import 'package:crypto/crypto.dart' show md5;

/// La cuenta de teselas de una zona, para bajarla y usarla sin senal.
///
/// Un mapa de teselas parte el mundo en cuadrados de 256 px: uno solo en el
/// zoom 0, cuatro en el 1, y asi, cuatro veces mas por cada nivel. Bajar una
/// zona es bajar los cuadrados que la tocan en cada nivel que se quiera ver.
/// Vive aparte de la pantalla porque es pura aritmetica y es donde se decide
/// cuanto pesa la descarga: un error aca son 40.000 archivos de mas.

/// Una tesela: nivel de zoom, columna y fila.
class Tesela {
  const Tesela(this.z, this.x, this.y);

  final int z;
  final int x;
  final int y;

  /// La direccion de esta tesela en un servidor, a partir de su plantilla
  /// (`.../{z}/{y}/{x}`).
  ///
  /// Tiene que quedar **identica** a la que arma `flutter_map` al dibujar: la
  /// cache guarda cada imagen bajo su direccion, y una que difiera en un
  /// caracter queda guardada donde el mapa nunca la va a buscar.
  String url(String plantilla) => plantilla
      .replaceAll('{z}', '$z')
      .replaceAll('{x}', '$x')
      .replaceAll('{y}', '$y');

  /// La tesela que contiene a esta, [saltos] niveles mas arriba: la misma
  /// zona vista con menos detalle. En el nivel 0 no hay mas arriba.
  Tesela ancestro(int saltos) {
    final s = saltos > z ? z : saltos;
    return Tesela(z - s, x >> s, y >> s);
  }

  /// Que pedazo de [ancestro] ocupa esta tesela, en pixeles de una imagen de
  /// [lado] por [lado]: `(izquierda, arriba, tamano)`.
  ///
  /// Es lo que permite mostrar una zona con la imagen del nivel anterior
  /// estirada cuando la de este nivel no existe: borrosa, pero el terreno, en
  /// vez de un cartel o un hueco.
  (double, double, double) recorteEn(Tesela ancestro, {double lado = 256}) {
    final saltos = z - ancestro.z;
    final tamano = lado / (1 << saltos);
    return (
      (x - (ancestro.x << saltos)) * tamano,
      (y - (ancestro.y << saltos)) * tamano,
      tamano,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Tesela && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);

  @override
  String toString() => '$z/$x/$y';
}

/// Un rectangulo en grados. Sin dependencias de `flutter_map`, para poder
/// probar la cuenta sin levantar un mapa.
class ZonaTeselas {
  const ZonaTeselas({
    required this.sur,
    required this.oeste,
    required this.norte,
    required this.este,
  });

  final double sur;
  final double oeste;
  final double norte;
  final double este;

  /// Las columnas y filas que tocan la zona en el nivel [z]:
  /// `(xMin, xMax, yMin, yMax)`, las dos puntas incluidas.
  (int, int, int, int) rango(int z) {
    final n = 1 << z;
    int col(double lon) => ((lon + 180) / 360 * n).floor().clamp(0, n - 1);
    int fila(double lat) {
      // Web Mercator no llega a los polos: se corta donde corta el mapa.
      final r = lat.clamp(-85.0511, 85.0511) * math.pi / 180;
      final y = (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n;
      return y.floor().clamp(0, n - 1);
    }

    // La fila crece hacia el sur: el norte es la fila chica.
    return (col(oeste), col(este), fila(norte), fila(sur));
  }

  /// Cuantas teselas son entre los niveles [zMin] y [zMax]. Se calcula sin
  /// armar la lista: es lo que la pantalla muestra mientras se mueve el mapa.
  int contar(int zMin, int zMax) {
    var total = 0;
    for (var z = zMin; z <= zMax; z++) {
      final (x0, x1, y0, y1) = rango(z);
      total += (x1 - x0 + 1) * (y1 - y0 + 1);
    }
    return total;
  }

  /// Todas las teselas entre [zMin] y [zMax], de lo general a lo fino: si la
  /// descarga se corta, lo que ya bajo deja ver la zona entera aunque borrosa,
  /// en vez de un rincon nitido y el resto en blanco.
  Iterable<Tesela> teselas(int zMin, int zMax) sync* {
    for (var z = zMin; z <= zMax; z++) {
      final (x0, x1, y0, y1) = rango(z);
      for (var x = x0; x <= x1; x++) {
        for (var y = y0; y <= y1; y++) {
          yield Tesela(z, x, y);
        }
      }
    }
  }
}

/// Si lo que devolvio el servidor del satelite es su cartel de "Map data not
/// yet available" y no una imagen del terreno.
///
/// Esri no responde 404 donde no tiene imagen: responde 200 con un JPG que
/// dice eso, y en una plantacion pasa en cuanto se acerca el mapa mas alla del
/// nivel 18. El cartel es **siempre el mismo archivo** en todo el mundo -2521
/// bytes, el mismo ETag y la misma huella-, asi que se reconoce sin mirarlo.
///
/// Se comprueba de las dos formas: el ETag sale gratis cuando la imagen viene
/// de la cache, y la huella cubre el caso de una copia guardada sin ETag. Si
/// algun dia Esri cambia el cartel, esto deja de reconocerlo y el mapa vuelve
/// a mostrarlo: se nota enseguida y se actualizan las tres constantes.
bool esRellenoEsri(List<int> bytes, {String? etag}) {
  if (etag == _etagRelleno) return true;
  if (bytes.length != _largoRelleno) return false;
  return md5.convert(bytes).toString() == _huellaRelleno;
}

const _etagRelleno = '"vvvvvvvvvvvvf"';
const _largoRelleno = 2521;
const _huellaRelleno = 'f27d9de7f80c13501f470595e327aa6d';

/// Lo que pesa, en promedio, una tesela satelital. Sale de medir las de
/// Guaicaramo: el JPG de un cultivo pesa mas que el de una ciudad, que tiene
/// techos lisos. Es para avisar el orden de magnitud, no para facturar.
const double kbPorTeselaSatelite = 18;

/// El peso estimado de [teselas] imagenes, en megas.
double megasEstimadas(int teselas) => teselas * kbPorTeselaSatelite / 1024;
