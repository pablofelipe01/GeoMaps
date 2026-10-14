import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/red.dart';
import '../state/sincronizador.dart';

/// Que falta por subir y que paso en el ultimo intento.
///
/// Existe porque la sincronizacion silenciosa es la que genera el reclamo de
/// que se perdio un dato. Aca se ve cuantos trazados estan pendientes, cuando
/// fue la ultima subida y, si fallo, con que error.
class SincronizacionPage extends ConsumerWidget {
  const SincronizacionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendientes = ref.watch(pendientesProvider).valueOrNull ?? 0;
    final estado = ref.watch(sincronizadorProvider);
    final hayRed = ref.watch(redProvider).valueOrNull?.hayRed ?? false;
    final colores = Theme.of(context).colorScheme;
    final ultima = estado.ultimaVez;

    return Scaffold(
      appBar: AppBar(title: const Text('Sincronizacion')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: Icon(
              pendientes == 0
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_upload_outlined,
              color: pendientes == 0 ? colores.primary : colores.outline,
              size: 32,
            ),
            title: Text(
              pendientes == 0
                  ? 'Todo esta en la base'
                  : pendientes == 1
                  ? '1 ruta sin subir'
                  : '$pendientes rutas sin subir',
            ),
            subtitle: Text(
              ultima == null
                  ? 'Todavia no se intento subir en esta sesion.'
                  : 'Ultimo intento: ${_hora(ultima)}. '
                        'Subidas ${estado.subidos}, fallidas ${estado.fallidos}.',
            ),
          ),
          if (estado.error != null)
            Card(
              color: colores.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  estado.error!,
                  style: TextStyle(color: colores.onErrorContainer),
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: estado.subiendo || pendientes == 0 || !hayRed
                ? null
                : () => ref.read(sincronizadorProvider.notifier).sincronizar(),
            icon: estado.subiendo
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: Text(estado.subiendo ? 'Subiendo...' : 'Subir ahora'),
          ),
          if (!hayRed)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Sin conexion. Lo pendiente sube solo cuando vuelva la senal.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colores.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  static String _hora(DateTime f) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(f.hour)}:${dos(f.minute)}';
  }
}
