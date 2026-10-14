import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/grabacion.dart';
import '../ui/capa_ruta.dart';

/// La franja de arriba del mapa mientras se graba un viaje.
///
/// Dice que se esta grabando -el conductor tiene que saber que la app sigue
/// gastando bateria- y es el unico lugar desde donde se termina. Terminar pide
/// confirmacion: un toque sin querer cortaria el viaje a la mitad.
class PanelViaje extends ConsumerWidget {
  const PanelViaje({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(grabadorProvider);
    if (!g.grabando) return const SizedBox.shrink();
    final colores = Theme.of(context).colorScheme;

    return Material(
      color: colores.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Row(
          children: [
            const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
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
      ),
    );
  }
}

/// Pregunta y termina el viaje. Devuelve si se termino.
Future<bool> terminarViaje(BuildContext context, WidgetRef ref) async {
  final si = await showDialog<bool>(
    context: context,
    builder: (dialogo) => AlertDialog(
      title: const Text('Terminar el viaje'),
      content: const Text(
        'Se deja de grabar y el recorrido sube a la base cuando haya senal. '
        'Terminalo cuando vuelvas con los vagones, no al llegar al acopio.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogo, false),
          child: const Text('Seguir grabando'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogo, true),
          child: const Text('Terminar'),
        ),
      ],
    ),
  );
  if (si != true) return false;
  await ref.read(grabadorProvider.notifier).terminar();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Viaje terminado. Sube solo con senal.')),
    );
  }
  return true;
}
