import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../state/sesion.dart';

/// Un acopio de la planilla de vagones, como lo nombra despacho.
class Sitio {
  const Sitio({this.codigo, this.bloque, this.numero, this.punto});

  factory Sitio.deJson(Map<String, dynamic> j) {
    final lat = (j['lat'] as num?)?.toDouble();
    final lon = (j['lon'] as num?)?.toDouble();
    return Sitio(
      codigo: j['codigo'] as String?,
      bloque: j['bloque'] as String?,
      numero: j['num'] as String?,
      punto: lat == null || lon == null ? null : LatLng(lat, lon),
    );
  }

  /// `B.7-P.3 · 7`: el rotulo completo que arma SiriusFleet.
  final String? codigo;
  final String? bloque;
  /// El numero del acopio dentro del bloque.
  final String? numero;

  /// Nulo si el acopio no tiene coordenada en SiriusFleet: no hay ruta posible.
  final LatLng? punto;

  /// `7 · 7`, como se escribe en la hoja: bloque y acopio.
  String get corto => '${bloque ?? '—'} · ${numero ?? '—'}';
}

/// Una vuelta pendiente por recoger: un renglon de la planilla de vagones con
/// `vuelta_pendiente` y sin salida.
class Vuelta {
  const Vuelta({
    required this.id,
    required this.jornada,
    required this.consecutivo,
    required this.tipoFruto,
    required this.reportadoEn,
    required this.origen,
    this.destino,
    this.vagon,
    this.observaciones,
  });

  factory Vuelta.deJson(Map<String, dynamic> j) => Vuelta(
    id: j['id'] as String,
    jornada: DateTime.parse(j['jornada'] as String),
    consecutivo: (j['consecutivo'] as num).toInt(),
    tipoFruto: j['tipo_fruto'] as String,
    reportadoEn: DateTime.parse(j['reportado_en'] as String).toLocal(),
    origen: Sitio.deJson(j['origen'] as Map<String, dynamic>),
    destino: j['destino'] == null
        ? null
        : Sitio.deJson(j['destino'] as Map<String, dynamic>),
    vagon: j['vagon'] as String?,
    observaciones: j['observaciones'] as String?,
  );

  final String id;
  final DateTime jornada;

  /// El "No." de la hoja.
  final int consecutivo;

  /// `hibrido` o `comercial`.
  final String tipoFruto;
  final DateTime reportadoEn;

  /// Donde estan los vagones llenos: a donde se va.
  final Sitio origen;

  /// Donde dejar el vagon vacio de paso, si despacho lo dijo.
  final Sitio? destino;
  final String? vagon;
  final String? observaciones;

  /// La H o la C de la primera columna de la hoja.
  String get letraFruto => tipoFruto == 'hibrido' ? 'H' : 'C';
  String get nombreFruto => tipoFruto == 'hibrido' ? 'Hibrido' : 'Comercial';

  /// Como se nombra el viaje grabado: se lee en Airtable sin abrir nada.
  String get nombreViaje => 'Vuelta #$consecutivo · ${origen.corto}';

  bool esDeOtroDia(DateTime hoy) =>
      jornada.year != hoy.year ||
      jornada.month != hoy.month ||
      jornada.day != hoy.day;
}

/// Lo que cabe en un vistazo antes de leer la lista.
class ResumenVueltas {
  ResumenVueltas(List<Vuelta> vueltas, DateTime hoy)
    : total = vueltas.length,
      hibrido = vueltas.where((v) => v.tipoFruto == 'hibrido').length,
      comercial = vueltas.where((v) => v.tipoFruto == 'comercial').length,
      deOtroDia = vueltas.where((v) => v.esDeOtroDia(hoy)).length,
      sinCoordenada = vueltas.where((v) => v.origen.punto == null).length,
      masVieja = vueltas.isEmpty
          ? null
          : vueltas
                .map((v) => v.reportadoEn)
                .reduce((a, b) => a.isBefore(b) ? a : b);

  final int total;
  final int hibrido;
  final int comercial;

  /// Las que siguen ahi desde ayer o antes: las que mas urgen.
  final int deOtroDia;

  /// Sin coordenada no hay ruta: hay que preguntar en despacho donde es.
  final int sinCoordenada;

  /// El reporte mas viejo que sigue sin recoger.
  final DateTime? masVieja;
}

/// Si lo que leyo la camara es el QR de vueltas pendientes de SiriusFleet.
///
/// El QR trae la URL de la lista web (`https://<dominio>/despacho/pendientes`).
/// Se reconoce por la ruta y no por el dominio: SiriusFleet arma la URL con el
/// dominio desde donde se imprimio, y ese puede cambiar. La lista no se baja
/// de esa URL: viene del backend de GeoMaps, que es el que tiene la llave.
bool esQrDeVueltas(String leido) {
  final uri = Uri.tryParse(leido.trim());
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
    return false;
  }
  final ruta = uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  return ruta.endsWith('/despacho/pendientes');
}

/// Las vueltas pendientes, recien pedidas. Se piden al abrir la lista y con
/// "Actualizar"; no se guardan en el telefono, porque una lista vieja manda a
/// un camion por una vuelta que ya recogio otro.
final vueltasProvider = FutureProvider.autoDispose<List<Vuelta>>((ref) async {
  final datos = await ref.watch(apiProvider).vueltasPendientes();
  return [
    for (final v in (datos['vueltas'] as List).cast<Map<String, dynamic>>())
      Vuelta.deJson(v),
  ];
});
