import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../core/api_client.dart';
import '../state/grabacion.dart';
import '../state/sesion.dart';
import '../ui/calificar_ruta.dart';
import '../ui/capa_ruta.dart';
import '../ui/mapa_page.dart';

/// Lo que un viaje sabe de la vuelta de la planilla que fue a recoger. Sale de
/// las propiedades que se guardaron con el recorrido al tomarla, asi que sigue
/// ahi si la app se cierra a mitad de camino.
extension VueltaDelViaje on EstadoGrabacion {
  /// El renglon de la planilla. Nulo si lo que se graba no es una vuelta.
  String? get vueltaId => propiedades['vuelta_id'] as String?;

  /// Donde dejar el vagon vacio de paso, si despacho lo dijo y el acopio
  /// tiene coordenada.
  LatLng? get entrega {
    final c = propiedades['entrega'];
    if (c is! List || c.length < 2) return null;
    // [lon, lat], como todo en el GeoJSON.
    return LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
  }

  String? get entregaNombre => propiedades['entrega_nombre'] as String?;
  String? get vagon => propiedades['vagon'] as String?;
}

/// La franja de arriba del mapa mientras se graba un viaje.
///
/// Dice que se esta grabando -el conductor tiene que saber que la app sigue
/// gastando bateria- y es el unico lugar desde donde se termina. Terminar pide
/// confirmacion: un toque sin querer cortaria el viaje a la mitad.
///
/// Si la vuelta trae donde dejar el vagon vacio, tambien lleva hasta ahi: son
/// dos tramos del mismo viaje, y el segundo no puede obligar a salir del mapa
/// a buscar el acopio a mano.
class PanelViaje extends ConsumerWidget {
  const PanelViaje({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(grabadorProvider);
    if (!g.grabando) return const SizedBox.shrink();
    final colores = Theme.of(context).colorScheme;
    final entrega = g.entrega;
    final destino = g.destino;

    return Material(
      color: colores.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.fiber_manual_record,
                  color: Colors.red,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        g.nombre ?? 'Grabando viaje',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Grabando · ${formatearDistancia(g.metros)}'
                        '${g.precisionUltimaM == null ? '' : ' · GPS +/- ${g.precisionUltimaM!.round()} m'}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colores.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => terminarViaje(context, ref),
                  child: const Text('Terminar'),
                ),
              ],
            ),
            if (entrega != null || destino != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (destino != null)
                      ActionChip(
                        avatar: const Icon(Icons.inventory_2, size: 16),
                        label: Text('Vagones · ${g.destinoNombre ?? ''}'),
                        onPressed: () => MapaPage.irA(
                          context,
                          LatLng(destino.latitud, destino.longitud),
                          nombre: 'Vagones en ${g.destinoNombre ?? ''}',
                        ),
                      ),
                    if (entrega != null)
                      ActionChip(
                        avatar: const Icon(Icons.flag, size: 16),
                        label: Text(
                          'Dejar vagon'
                          '${g.vagon == null ? '' : ' ${g.vagon}'}'
                          ' · ${g.entregaNombre ?? ''}',
                        ),
                        onPressed: () => MapaPage.irA(
                          context,
                          entrega,
                          nombre: 'Dejar el vagon en ${g.entregaNombre ?? ''}',
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Lo que se puede hacer con el viaje en curso.
enum _Cierre { terminar, soltar }

/// Pregunta y termina el viaje. Devuelve si se termino.
///
/// Ofrece tambien devolver la vuelta a la lista: tomar el renglon de al lado
/// por error pasa, y sin esto la vuelta quedaba como salida en la planilla
/// hasta que despacho la corrigiera a mano.
Future<bool> terminarViaje(BuildContext context, WidgetRef ref) async {
  final g = ref.read(grabadorProvider);
  final vueltaId = g.vueltaId;

  final que = await showDialog<_Cierre>(
    context: context,
    builder: (dialogo) => AlertDialog(
      title: const Text('Terminar el viaje'),
      content: const Text(
        'Se deja de grabar y el recorrido sube a la base cuando haya senal. '
        'Terminalo cuando vuelvas con los vagones, no al llegar al acopio.',
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        if (vueltaId != null)
          TextButton(
            onPressed: () => Navigator.pop(dialogo, _Cierre.soltar),
            child: const Text('No la voy a recoger'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialogo),
          child: const Text('Seguir grabando'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogo, _Cierre.terminar),
          child: const Text('Terminar'),
        ),
      ],
    ),
  );
  if (que == null || !context.mounted) return false;

  if (que == _Cierre.soltar) return _soltar(context, ref, vueltaId!);

  // Quien acaba de hacer el viaje es quien sabe como estaba la via: se le
  // pregunta antes de cerrar, y la respuesta queda con el recorrido.
  final avisos = ScaffoldMessenger.of(context);
  final calificacion = await pedirCalificacion(
    context,
    titulo: 'Viaje terminado',
    detalle: g.metros < 20
        ? null
        : 'Recorriste ${formatearDistancia(ref.read(grabadorProvider).metros)}.',
  );
  await ref
      .read(grabadorProvider.notifier)
      .terminar(propiedades: calificacion?.aPropiedades() ?? const {});
  avisos.showSnackBar(
    SnackBar(
      content: Text(
        calificacion == null
            ? 'Viaje terminado. Sube solo con senal.'
            : 'Gracias. El viaje y tu calificacion suben solos con senal.',
      ),
    ),
  );
  return true;
}

/// Devuelve la vuelta a la lista y tira lo grabado.
///
/// En ese orden: primero la planilla, que necesita senal. Si no hay, no se
/// toca nada -el viaje sigue grabando- y se puede reintentar; al reves quedaria
/// la vuelta a su nombre y sin el recorrido que lo respalda.
Future<bool> _soltar(
  BuildContext context,
  WidgetRef ref,
  String vueltaId,
) async {
  final seguro = await showDialog<bool>(
    context: context,
    builder: (dialogo) => AlertDialog(
      title: const Text('Devolver la vuelta'),
      content: const Text(
        'La vuelta vuelve a la lista de pendientes para que la tome otro '
        'conductor, y lo grabado de este viaje se descarta.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogo, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogo, true),
          child: const Text('Devolverla'),
        ),
      ],
    ),
  );
  if (seguro != true || !context.mounted) return false;

  final avisos = ScaffoldMessenger.of(context);
  try {
    await ref.read(apiProvider).soltarVuelta(vueltaId);
  } on ApiError catch (e) {
    avisos.showSnackBar(SnackBar(content: Text(e.mensaje)));
    return false;
  } catch (_) {
    avisos.showSnackBar(
      const SnackBar(
        content: Text(
          'Sin conexion: devolver la vuelta necesita senal. El viaje sigue '
          'grabando.',
        ),
      ),
    );
    return false;
  }

  await ref.read(grabadorProvider.notifier).descartar();
  avisos.showSnackBar(
    const SnackBar(content: Text('La vuelta volvio a la lista de pendientes.')),
  );
  return true;
}
