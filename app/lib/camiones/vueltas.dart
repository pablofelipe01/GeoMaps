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

  static final _bloqueYParcela = RegExp(r'^B\.(\w+)-P\.(\w+)');

  /// `Acopio 11A`, con la palabra: es lo que se lee de lejos.
  String get acopio => 'Acopio ${numero ?? '—'}';

  /// `Bloque 3 · Parcela 4`, con todas las letras. `B.3-P.4` escrito chico no
  /// lo distingue de un vistazo quien no ve bien. Si el rotulo no trae la
  /// parcela, queda el bloque solo.
  String get lugar {
    final m = _bloqueYParcela.firstMatch(codigo ?? '');
    if (m != null) return 'Bloque ${m[1]} · Parcela ${m[2]}';
    final b = (bloque ?? '').replaceFirst(RegExp(r'^B\.'), '');
    return b.isEmpty ? '' : 'Bloque $b';
  }

  /// `Bloque 3 · Parcela 4 · Acopio 11A`: el sitio entero en un renglon.
  String get largo => lugar.isEmpty ? acopio : '$lugar · $acopio';
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

/// A nombre de quien quedan las vueltas que tome esta cuenta. Lo manda el
/// backend con la lista. La cedula ya no se le pide a nadie: la vuelta queda
/// a nombre de la cuenta.
class Conductor {
  const Conductor({this.nombre, this.pideClave = true});

  factory Conductor.deJson(Map<String, dynamic> j) => Conductor(
    nombre: j['nombre'] as String?,
    pideClave: j['pide_clave'] as bool? ?? true,
  );

  /// Como va a figurar en la planilla.
  final String? nombre;

  /// Las cuentas de Google no tienen clave: confirman con la sesion.
  final bool pideClave;
}

/// La vuelta que esta cuenta tomo y todavia no finaliza, segun el servidor.
///
/// Mientras exista no se puede tomar otra. Viene completa para que un
/// telefono que no la tiene -se reinstalo la app, se cambio de telefono- la
/// pueda continuar en vez de quedar trabado.
class ViajeAbierto {
  const ViajeAbierto({
    required this.codigo,
    required this.vueltaId,
    this.nombre,
    this.tomadaEn,
    this.salida,
    this.llegadaEn,
    this.regresoEn,
    this.vuelta,
  });

  factory ViajeAbierto.deJson(Map<String, dynamic> j) {
    DateTime? fecha(String llave) =>
        j[llave] == null ? null : DateTime.tryParse(j[llave] as String);
    final salida = j['salida'] as Map<String, dynamic>?;
    return ViajeAbierto(
      codigo: j['codigo'] as String,
      vueltaId: j['vuelta_id'] as String,
      nombre: j['nombre'] as String?,
      tomadaEn: fecha('tomada_en'),
      salida: salida == null
          ? null
          : LatLng(
              (salida['lat'] as num).toDouble(),
              (salida['lon'] as num).toDouble(),
            ),
      llegadaEn: fecha('llegada_en'),
      regresoEn: fecha('regreso_en'),
      vuelta: j['vuelta'] == null
          ? null
          : Vuelta.deJson(j['vuelta'] as Map<String, dynamic>),
    );
  }

  /// El codigo del viaje en el seguimiento.
  final String codigo;
  final String vueltaId;

  /// `Vuelta #23 · B.3-P.4 · 11A`.
  final String? nombre;
  final DateTime? tomadaEn;

  /// Donde estaba el camion al tomarla: a donde tiene que volver.
  final LatLng? salida;
  final DateTime? llegadaEn;
  final DateTime? regresoEn;

  /// Nula si el renglon ya no esta en la planilla.
  final Vuelta? vuelta;

  /// `Vuelta #23`, o el nombre entero si no se pudo leer el renglon.
  String get titulo =>
      vuelta == null ? (nombre ?? 'Una vuelta') : 'Vuelta #${vuelta!.consecutivo}';
}

/// La respuesta de la lista: las vueltas y quien las esta mirando.
class ListaVueltas {
  const ListaVueltas({
    required this.vueltas,
    this.conductor,
    this.viajeAbierto,
    this.control = false,
  });

  factory ListaVueltas.deJson(Map<String, dynamic> j) => ListaVueltas(
    vueltas: [
      for (final v in (j['vueltas'] as List).cast<Map<String, dynamic>>())
        Vuelta.deJson(v),
    ],
    conductor: j['conductor'] == null
        ? null
        : Conductor.deJson(j['conductor'] as Map<String, dynamic>),
    viajeAbierto: j['viaje_abierto'] == null
        ? null
        : ViajeAbierto.deJson(j['viaje_abierto'] as Map<String, dynamic>),
    control: j['control'] as bool? ?? false,
  );

  final List<Vuelta> vueltas;

  /// Nulo si el backend no pudo leer la cuenta: la lista sale igual.
  final Conductor? conductor;

  /// La vuelta sin finalizar de esta cuenta, si tiene una.
  final ViajeAbierto? viajeAbierto;

  /// Si el servidor esta llevando el seguimiento de las vueltas. En falso
  /// -un servidor anterior, o sin la tabla- [viajeAbierto] no dice nada.
  final bool control;
}

/// Las vueltas pendientes, recien pedidas. Se piden al abrir la lista y con
/// "Actualizar"; no se guardan en el telefono, porque una lista vieja manda a
/// un camion por una vuelta que ya recogio otro.
final vueltasProvider = FutureProvider.autoDispose<ListaVueltas>((ref) async {
  return ListaVueltas.deJson(await ref.watch(apiProvider).vueltasPendientes());
});

/// Lo que el servidor dice de la vuelta abierta de esta cuenta: si lleva el
/// control y cual es. Nulo si no se pudo preguntar -sin senal, o un servidor
/// anterior-, que no es lo mismo que "no tiene ninguna".
final miViajeProvider =
    FutureProvider.autoDispose<({bool control, ViajeAbierto? viaje})?>((
      ref,
    ) async {
      try {
        final j = await ref.watch(apiProvider).miViaje();
        return (
          control: j['control'] as bool? ?? false,
          viaje: j['viaje'] == null
              ? null
              : ViajeAbierto.deJson(j['viaje'] as Map<String, dynamic>),
        );
      } catch (_) {
        return null;
      }
    });
