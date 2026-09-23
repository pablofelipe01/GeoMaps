import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/parcelas.dart';
import '../core/vias.dart';
import '../core/zona.dart';
import 'ubicacion_provider.dart';

/// El perimetro de la plantacion de Guaicaramo, cargado del asset.
///
/// Se lee una vez por arranque y queda en memoria: son 16 KB y la respuesta se
/// consulta con cada fix del GPS, que en campo llega cada pocos segundos.
final zonaGuaicaramoProvider = FutureProvider<Zona>((ref) {
  return Zona.cargar('guaicaramo.json');
});

/// Por que el mapa de Guaicaramo esta habilitado o no.
///
/// Son cuatro estados y no un booleano a proposito. "No podes abrirlo" sin
/// decir por que es lo que hace que alguien reinstale la app en un lote: no
/// sabe si le falta permiso, si el GPS no engancho o si simplemente todavia no
/// llego al predio.
enum MotivoZona {
  /// Adentro del predio. El mapa se abre.
  dentro,

  /// El GPS funciona y la posicion cae afuera.
  fuera,

  /// Todavia no hay un fix. No es lo mismo que estar afuera.
  buscandoGps,

  /// Sin permiso de ubicacion o con la ubicacion apagada.
  sinUbicacion,

  /// El APK se compilo sin los datos del predio, que son confidenciales y no
  /// viven en el repositorio. Es un caso de compilacion, no de campo: alguien
  /// clono y compilo sin pedir las fuentes a coordinacion.
  sinDatos,
}

class EstadoZona {
  const EstadoZona({required this.motivo, this.metrosAlBorde, this.detalle});

  final MotivoZona motivo;

  /// A que distancia queda el borde del predio, si esta afuera y se sabe.
  final double? metrosAlBorde;

  /// El motivo en castellano cuando falta el permiso: los tres modos de fallar
  /// piden acciones distintas de la persona.
  final String? detalle;

  bool get habilitado => motivo == MotivoZona.dentro;

  /// Lo que se muestra debajo del nombre del mapa.
  String get explicacion {
    switch (motivo) {
      case MotivoZona.dentro:
        return 'Estas en la plantacion';
      case MotivoZona.fuera:
        final m = metrosAlBorde;
        if (m == null) return 'Estas fuera de la plantacion';
        if (m < 1000) return 'A ${m.toStringAsFixed(0)} m de la plantacion';
        return 'A ${(m / 1000).toStringAsFixed(1)} km de la plantacion';
      case MotivoZona.buscandoGps:
        return 'Buscando senal GPS...';
      case MotivoZona.sinUbicacion:
        return detalle ?? 'Sin permiso de ubicacion';
      case MotivoZona.sinDatos:
        return 'Este APK se compilo sin los datos del predio';
    }
  }
}

/// Si el telefono esta parado adentro de Guaicaramo, ahora mismo.
///
/// Se recalcula con cada fix. No se guarda ni se cachea entre arranques: una
/// respuesta de ayer sobre donde esta alguien hoy no vale nada, y guardarla
/// seria la forma mas facil de habilitar el mapa a 200 km del predio.
final estadoGuaicaramoProvider = Provider.autoDispose<EstadoZona>((ref) {
  final zona = ref.watch(zonaGuaicaramoProvider);
  final posicion = ref.watch(posicionProvider);

  // El asset no esta: este APK se compilo sin los datos del predio. Se dice
  // asi y no "buscando GPS", que dejaria a alguien esperando en un lote una
  // respuesta que no va a llegar nunca.
  if (zona.hasError) {
    return const EstadoZona(motivo: MotivoZona.sinDatos);
  }

  // Mientras el asset se lee del disco se muestra lo mismo que sin fix: dura
  // milisegundos y no merece un estado propio en la pantalla.
  final perimetro = zona.valueOrNull;
  if (perimetro == null) {
    return const EstadoZona(motivo: MotivoZona.buscandoGps);
  }

  return posicion.when(
    data: (p) {
      final punto = PuntoLatLon(lat: p.latitude, lon: p.longitude);
      if (perimetro.contiene(punto)) {
        return const EstadoZona(motivo: MotivoZona.dentro);
      }
      return EstadoZona(
        motivo: MotivoZona.fuera,
        metrosAlBorde: perimetro.metrosAlBorde(punto),
      );
    },
    loading: () => const EstadoZona(motivo: MotivoZona.buscandoGps),
    error: (e, _) => EstadoZona(
      motivo: MotivoZona.sinUbicacion,
      detalle: e is PermisoUbicacionDenegado ? e.motivo : null,
    ),
  );
});

/// Las vias de un predio, leidas del asset.
///
/// `family` por nombre de archivo para que el dia que haya un segundo predio no
/// haya que tocar nada: la pantalla del mapa pide el suyo. Se cachea mientras
/// haya alguien mirandolo; volver a entrar al mapa no vuelve a parsear 353 KB.
final viasPredioProvider = FutureProvider.family<ViasPredio, String>((
  ref,
  archivo,
) {
  return ViasPredio.cargar(archivo);
});

/// Los lotes de un predio (bloques y parcelas), leidos del asset.
final parcelasPredioProvider = FutureProvider.family<ParcelasPredio, String>((
  ref,
  archivo,
) {
  return ParcelasPredio.cargar(archivo);
});
