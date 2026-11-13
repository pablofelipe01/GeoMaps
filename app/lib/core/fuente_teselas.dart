import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart'
    show CachedMapTile, CachedMapTileMetadata, MapCachingProvider;
import 'package:http/http.dart' as http;

import 'teselas.dart';

/// Lo que se consiguio para una tesela: los bytes de una imagen, y de que
/// tesela son.
class TeselaCargada {
  const TeselaCargada(this.bytes, this.origen, {this.provisional = false});

  final Uint8List bytes;

  /// La tesela de la que salio la imagen. Si no es la pedida, es una de mas
  /// arriba: hay que recortar el pedazo que corresponde y estirarlo.
  final Tesela origen;

  /// Se mostro una de mas arriba porque **no se pudo preguntar** por la
  /// pedida (sin red), no porque no exista. Vale la pena reintentarla.
  final bool provisional;
}

/// No hay imagen para esa zona ni varios niveles mas arriba.
class SinTesela implements Exception {
  const SinTesela(this.tesela);

  final Tesela tesela;

  @override
  String toString() => 'Sin imagen para la tesela $tesela';
}

/// De donde salen las imagenes del mapa base: la cache del telefono, la red,
/// y cuando ninguna de las dos tiene la que se pidio, **la del nivel de
/// arriba**.
///
/// Existe por dos huecos que el mapa mostraba y que en campo son lo mismo, no
/// ver el terreno:
///
/// - **"Map data not yet available".** El satelite no tiene imagen de una
///   plantacion mas alla de cierto nivel (el 18 en Guaicaramo), y en vez de
///   decir que no, manda un cartel. Aca se lo reconoce ([esRellenoEsri]) y se
///   muestra la imagen del ultimo nivel que si existe, estirada.
/// - **El gris sin senal.** Sin red, una zona que se guardo con menos detalle
///   del que se esta mirando quedaba en blanco. Ahora se ve con lo que haya.
///
/// No dibuja nada: entrega bytes. Quien los recorta y los pinta es
/// `ui/proveedor_teselas.dart`.
class FuenteTeselas {
  FuenteTeselas({
    required this.plantilla,
    required this.paquete,
    required this.almacen,
    http.Client? cliente,
    DateTime Function()? reloj,
  }) : _cliente = cliente ?? http.Client(),
       _reloj = reloj ?? DateTime.now;

  /// La direccion de las teselas (`.../{z}/{y}/{x}`). La misma que usa la
  /// descarga de zonas: la cache guarda cada imagen bajo su direccion.
  final String plantilla;

  /// Va en el `User-Agent`, como lo piden los servidores publicos.
  final String paquete;

  /// Se pide cada vez y no se guarda: la cache se crea al arrancar la app, y
  /// en las pruebas no hay.
  final MapCachingProvider? Function() almacen;
  final http.Client _cliente;
  final DateTime Function() _reloj;

  /// Cuantos niveles se sube a buscar una imagen. Cinco niveles es estirar la
  /// imagen 32 veces: mas alla ya no se distingue nada y es mejor el hueco.
  static const maxSaltos = 5;

  /// Despues de un pedido que fallo por la red no se vuelve a intentar por un
  /// rato: sin senal, cada intento es una espera, y son decenas por pantalla.
  static const pausaSinRed = Duration(seconds: 20);

  /// Con tantas teselas sin imagen en una misma zona y nivel, y ninguna con
  /// imagen, se da por hecho que el nivel entero falta ahi y no se pregunta
  /// mas: cada pregunta es un pedido que vuelve con el cartel.
  static const _faltasParaGeneralizar = 4;

  final _noHay = <Tesela>{};
  final _faltanEnBloque = <Tesela, int>{};
  final _hayEnBloque = <Tesela>{};
  final _provisionales = <Tesela>{};
  final _enCurso = <Tesela, Future<_Intento>>{};
  DateTime? _sinRedHasta;

  /// Consigue una imagen para [pedida]: la suya, o la del nivel mas cercano
  /// hacia arriba que exista. Lanza [SinTesela] si no hay nada.
  Future<TeselaCargada> cargar(Tesela pedida) async {
    var sinSaber = false;
    for (var s = 0; s <= maxSaltos && s <= pedida.z; s++) {
      final t = pedida.ancestro(s);
      final intento = await _una(t);
      final bytes = intento.bytes;
      if (bytes != null) {
        if (sinSaber) _provisionales.add(pedida);
        return TeselaCargada(bytes, t, provisional: sinSaber);
      }
      if (intento.sinSaber) sinSaber = true;
    }
    if (sinSaber) _provisionales.add(pedida);
    throw SinTesela(pedida);
  }

  /// Si la ultima vez [t] se resolvio a medias por falta de red. Se consulta
  /// una sola vez: quien pregunta se compromete a reintentarla.
  bool fueProvisional(Tesela t) => _provisionales.remove(t);

  /// Un intento por una tesela exacta. Los pedidos simultaneos por la misma
  /// -cuatro hijas buscando a su madre- comparten uno solo.
  Future<_Intento> _una(Tesela t) {
    final enCurso = _enCurso[t];
    if (enCurso != null) return enCurso;
    // Con llaves: si la funcion devolviera lo que saca del mapa -este mismo
    // futuro-, `whenComplete` esperaria a que termine para terminar, y no
    // terminaria nunca.
    final nuevo = _intentar(t).whenComplete(() {
      _enCurso.remove(t);
    });
    _enCurso[t] = nuevo;
    return nuevo;
  }

  Future<_Intento> _intentar(Tesela t) async {
    if (_seSabeQueFalta(t)) return const _Intento.falta();

    final url = t.url(plantilla);
    final cache = almacen();
    CachedMapTile? guardada;
    if (cache != null && cache.isSupported) {
      try {
        guardada = await cache.getTile(url);
      } catch (_) {
        // Una copia ilegible es como no tenerla.
      }
    }
    if (guardada != null) {
      // Los telefonos que ya miraron esta zona tienen el cartel guardado
      // como si fuera una imagen: tambien se lo reconoce al leerlo.
      if (esRellenoEsri(guardada.bytes, etag: guardada.metadata.etag)) {
        _anotarFalta(t);
        return const _Intento.falta();
      }
      if (!guardada.metadata.isStale) {
        _anotarHay(t);
        return _Intento.con(guardada.bytes);
      }
    }

    // Hasta aca llega lo que no esta guardado, o esta vencido. Sin red se usa
    // la copia vencida si la hay: una imagen vieja del terreno sigue siendo
    // el terreno.
    final viejo = guardada?.bytes;
    final pausa = _sinRedHasta;
    if (pausa != null && _reloj().isBefore(pausa)) {
      return viejo != null ? _Intento.con(viejo) : const _Intento.sinSaber();
    }

    try {
      final r = await _cliente
          .get(
            Uri.parse(url),
            headers: {'User-Agent': 'flutter_map ($paquete)'},
          )
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
        if (esRellenoEsri(r.bodyBytes, etag: r.headers['etag'])) {
          _anotarFalta(t);
          return const _Intento.falta();
        }
        _anotarHay(t);
        if (cache != null && cache.isSupported) {
          // Sin esperarla: guardar no puede demorar lo que se esta mirando.
          unawaited(
            cache
                .putTile(
                  url: url,
                  metadata: CachedMapTileMetadata(
                    staleAt: DateTime.timestamp().add(const Duration(days: 60)),
                    lastModified: null,
                    etag: r.headers['etag'],
                  ),
                  bytes: r.bodyBytes,
                )
                .catchError((Object _) {}),
          );
        }
        return _Intento.con(r.bodyBytes);
      }
      if (r.statusCode == 404) {
        _anotarFalta(t);
        return const _Intento.falta();
      }
      // El servidor contesto otra cosa (saturado, caido): no dice nada sobre
      // si la imagen existe.
      return viejo != null ? _Intento.con(viejo) : const _Intento.sinSaber();
    } catch (_) {
      _sinRedHasta = _reloj().add(pausaSinRed);
      return viejo != null ? _Intento.con(viejo) : const _Intento.sinSaber();
    }
  }

  /// Si ya se sabe, sin preguntar, que [t] no tiene imagen: porque falto ella,
  /// porque falto una de mas arriba que la contiene -si no hay imagen de la
  /// manzana, no la hay de la casa-, o porque en su zona ese nivel viene
  /// faltando entero.
  bool _seSabeQueFalta(Tesela t) {
    for (var s = 0; s <= 3 && s <= t.z; s++) {
      if (_noHay.contains(t.ancestro(s))) return true;
    }
    final bloque = _bloque(t);
    return (_faltanEnBloque[bloque] ?? 0) >= _faltasParaGeneralizar &&
        !_hayEnBloque.contains(bloque);
  }

  /// La zona de 16 x 16 teselas a la que pertenece [t]. Como es una tesela de
  /// cuatro niveles mas arriba, la clave es distinta para cada nivel.
  Tesela _bloque(Tesela t) => t.ancestro(4);

  void _anotarFalta(Tesela t) {
    // Un tope, para que una jornada entera mirando el mapa no acumule sin
    // fin. Vaciarlo solo cuesta volver a preguntar.
    if (_noHay.length > 20000) {
      _noHay.clear();
      _faltanEnBloque.clear();
    }
    _noHay.add(t);
    final bloque = _bloque(t);
    _faltanEnBloque[bloque] = (_faltanEnBloque[bloque] ?? 0) + 1;
  }

  void _anotarHay(Tesela t) => _hayEnBloque.add(_bloque(t));
}

/// Como termino un intento por una tesela exacta.
class _Intento {
  const _Intento.con(Uint8List this.bytes) : sinSaber = false;

  /// Se sabe que no tiene imagen.
  const _Intento.falta() : bytes = null, sinSaber = false;

  /// No se pudo averiguar: sin red y sin copia.
  const _Intento.sinSaber() : bytes = null, sinSaber = true;

  final Uint8List? bytes;
  final bool sinSaber;
}
