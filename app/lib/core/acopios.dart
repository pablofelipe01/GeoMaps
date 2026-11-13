import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';

/// Los acopios del predio: donde se deja el fruto cosechado para que lo recoja
/// el tractor.
///
/// Salen de la capa `Acopios` del plano del Departamento Agronomico via
/// `tools/acopios_guaicaramo.py`. Son puntos y no areas: lo que se necesita de
/// un acopio es **como se llega**, y para eso alcanza con la posicion.
class AcopiosPredio {
  const AcopiosPredio(this.acopios);

  /// Lee el asset y lo parsea fuera del hilo de la interfaz, como las vias y
  /// los lotes: los tres se cargan al abrir el mapa.
  static Future<AcopiosPredio> cargar(String archivo) async {
    final crudo = await rootBundle.loadString('assets/zonas/$archivo');
    return compute(deJson, crudo);
  }

  static AcopiosPredio deJson(String crudo) {
    final j = jsonDecode(crudo) as Map<String, dynamic>;
    final acopios = (j['acopios'] as List)
        .map((a) {
          final m = a as Map<String, dynamic>;
          return Acopio(
            numero: m['n'] as String,
            lote: m['l'] as String,
            punto: LatLng(
              (m['y'] as num).toDouble(),
              (m['x'] as num).toDouble(),
            ),
          );
        })
        .toList(growable: false);
    return AcopiosPredio(acopios);
  }

  final List<Acopio> acopios;

  /// El numero de acopio que se esta buscando en [texto], si lo que se
  /// escribio empieza por uno: `38`, `30a`. Nulo si se busca solo por lote.
  static String? numeroBuscado(String texto) {
    for (final p in _palabras(texto)) {
      if (_esNumero.hasMatch(p)) return p;
    }
    return null;
  }

  /// Los que coinciden con lo que se escribio en el buscador.
  ///
  /// Lo primero que se escribe es **el numero del acopio**, y se busca como
  /// numero y nada mas: "38" trae los acopios 38, uno por lote. Antes tambien
  /// traia todo lo que tuviera un 38 en el nombre del lote -la parcela 38, el
  /// bloque 338-, y entre eso los seis acopios que se buscaban no se
  /// encontraban.
  ///
  /// Lo que se escribe despues acota:
  ///
  /// - otro numero es el **bloque** o la **parcela**: "38 9" es el acopio 38
  ///   del bloque 9;
  /// - algo con letras se busca en el nombre del lote, sin importar puntos ni
  ///   guiones: "b9", "b.9-p.2", "chiguiros".
  ///
  /// Primero van los de numero exacto y despues los que empiezan por el: el 38
  /// antes que el 38A. Sin numero -solo el lote- van todos los del lote.
  List<Acopio> buscar(String texto) {
    final palabras = _palabras(texto);
    if (palabras.isEmpty) return acopios;

    String? numero;
    final acotan = <String>[];
    final enLote = <String>[];
    for (final p in palabras) {
      if (!_esNumero.hasMatch(p)) {
        final limpia = _sinSignos(p);
        if (limpia.isNotEmpty) enLote.add(limpia);
      } else if (numero == null) {
        numero = p;
      } else {
        acotan.add(p);
      }
    }

    // Se separa en dos listas y no se ordena porque `sort` no garantiza
    // conservar el orden del plano entre iguales.
    final exactos = <Acopio>[];
    final resto = <Acopio>[];
    for (final a in acopios) {
      final n = a.numero.toLowerCase();
      if (numero != null && !n.startsWith(numero)) continue;

      final bloque = a.bloque?.toLowerCase();
      final parcela = a.parcela?.toLowerCase();
      final cumpleNumeros = acotan.every(
        (p) =>
            (bloque != null && bloque.startsWith(p)) ||
            (parcela != null && parcela.startsWith(p)),
      );
      if (!cumpleNumeros) continue;

      final lote = _sinSignos(a.lote.toLowerCase());
      if (!enLote.every(lote.contains)) continue;

      (numero == null || n == numero ? exactos : resto).add(a);
    }
    return [...exactos, ...resto];
  }

  static List<String> _palabras(String texto) => texto
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();

  /// Un numero de acopio: digitos y, a veces, una letra al final (`30A`).
  static final _esNumero = RegExp(r'^\d+[a-z]?$');

  /// Sin puntos, guiones ni espacios: "B.9-P.2" y "b9p2" son lo mismo para
  /// quien escribe con un dedo.
  static String _sinSignos(String texto) =>
      texto.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

class Acopio {
  const Acopio({required this.numero, required this.lote, required this.punto});

  /// Como esta rotulado en el plano: `30`, `30A`. Puede venir vacio.
  ///
  /// Se repite entre lotes -hay un acopio 30 en muchos-, asi que a secas no
  /// identifica: lo que lo vuelve unico es el numero junto con el [lote].
  final String numero;

  /// El lote donde cae (`B.9-P.2`), o vacio si cae fuera de todo lote.
  final String lote;

  final LatLng punto;

  static final _bloqueYParcela = RegExp(r'^B\.(\w+)-P\.(\w+)$');

  /// El bloque (`9` de `B.9-P.2`). Nulo si el lote no es de bloque y parcela:
  /// los lotes con nombre propio, o un acopio fuera de todo lote.
  String? get bloque => _bloqueYParcela.firstMatch(lote)?.group(1);

  /// La parcela (`2` de `B.9-P.2`). Nula en los mismos casos que [bloque].
  String? get parcela => _bloqueYParcela.firstMatch(lote)?.group(2);

  /// Donde queda, con todas las letras: "Bloque 9 · Parcela 2". Es lo que
  /// distingue a un acopio 38 de los otros cinco, y `B.9-P.2` escrito chico no
  /// lo lee de un vistazo quien no ve bien.
  String get lugar {
    final b = bloque;
    final p = parcela;
    if (b != null && p != null) return 'Bloque $b · Parcela $p';
    return lote;
  }

  /// Como se lo nombra en pantalla: "Acopio 30".
  String get nombre => numero.isEmpty ? 'Acopio sin numero' : 'Acopio $numero';

  /// El nombre completo, con el lote: "Acopio 30 · B.9-P.2".
  String get etiqueta => lote.isEmpty ? nombre : '$nombre · $lote';

  /// El nombre completo sin abreviar: "Acopio 30 · Bloque 9 · Parcela 2".
  String get etiquetaLarga => lugar.isEmpty ? nombre : '$nombre · $lugar';
}

/// Los mismos acopios, el mas cercano a [desde] primero.
///
/// Entre varios acopios con el mismo numero, el que se busca casi siempre es
/// el que queda cerca. Devuelve una lista nueva; la original no se toca.
List<Acopio> porCercania(List<Acopio> acopios, LatLng desde) {
  const distancia = Distance();
  final medidos = [
    for (final a in acopios)
      (a, distancia.as(LengthUnit.Meter, desde, a.punto)),
  ]..sort((x, y) => x.$2.compareTo(y.$2));
  return [for (final m in medidos) m.$1];
}

/// Para ordenar bloques y parcelas como numeros y no como texto: el 9 antes
/// que el 10. Lo que no es numero va al final, por orden alfabetico.
int compararNumerico(String a, String b) {
  final na = int.tryParse(a);
  final nb = int.tryParse(b);
  if (na != null && nb != null) return na.compareTo(nb);
  if (na != null) return -1;
  if (nb != null) return 1;
  return a.compareTo(b);
}
