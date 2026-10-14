import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/trazados_repository.dart';
import '../state/sincronizador.dart';
import 'capa_ruta.dart';

/// Pide el nombre con que se guarda una ruta.
///
/// Viene escrito con lo que se sabe -el acopio, o "Ruta a ..." con la
/// distancia-: guardar tiene que poder ser un toque, y el nombre se cambia solo
/// si se quiere.
Future<String?> pedirNombreRuta(BuildContext context, String sugerido) {
  final texto = TextEditingController(text: sugerido);
  return showDialog<String>(
    context: context,
    builder: (dialogo) => AlertDialog(
      title: const Text('Guardar ruta'),
      content: TextField(
        controller: texto,
        autofocus: true,
        maxLength: 80,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Nombre'),
        onSubmitted: (v) => Navigator.pop(dialogo, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogo),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogo, texto.text),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}

/// La lista de rutas guardadas. Devuelve la que se toco, para ir hacia ella.
Future<RutaGuardada?> elegirRutaGuardada(BuildContext context) {
  return showModalBottomSheet<RutaGuardada>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (hoja) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(hoja).height * 0.7,
      ),
      child: const _ListaRutas(),
    ),
  );
}

class _ListaRutas extends ConsumerWidget {
  const _ListaRutas();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rutas = ref.watch(rutasGuardadasProvider).valueOrNull ?? const [];
    final colores = Theme.of(context).colorScheme;

    if (rutas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmarks_outlined, size: 44, color: colores.outline),
            const SizedBox(height: 14),
            Text(
              'Todavia no hay rutas guardadas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Traza una ruta y toca el marcador de la tarjeta para guardarla.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colores.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Rutas guardadas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: rutas.length,
              itemBuilder: (_, i) => _FilaRuta(ruta: rutas[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaRuta extends ConsumerWidget {
  const _FilaRuta({required this.ruta});

  final RutaGuardada ruta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colores = Theme.of(context).colorScheme;
    final metros = ruta.metros;

    return ListTile(
      leading: Icon(Icons.route, color: colores.primary),
      title: Text(ruta.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          // Si ya subio o no. Se dice en la fila porque es la pregunta que
          // aparece cuando alguien en la oficina no la encuentra.
          Icon(
            ruta.sincronizada
                ? Icons.cloud_done_outlined
                : Icons.cloud_upload_outlined,
            size: 15,
            color: ruta.sincronizada ? colores.primary : colores.outline,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              [
                if (metros != null) formatearDistancia(metros),
                _fecha(ruta.creadaEn),
                if (!ruta.sincronizada) 'sin subir',
              ].join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Borrar',
        onPressed: () => _borrar(context, ref),
      ),
      onTap: () => Navigator.pop(context, ruta),
    );
  }

  Future<void> _borrar(BuildContext context, WidgetRef ref) async {
    final si = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('Borrar ruta'),
        content: Text(
          ruta.sincronizada
              ? 'Se borra "${ruta.nombre}" de este telefono. La copia que ya '
                    'subio a la base se queda.'
              : 'Se borra "${ruta.nombre}". Todavia no subio, asi que no '
                    'queda copia en ningun lado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogo, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogo, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (si != true) return;
    await ref.read(trazadosRepositoryProvider).borrar(ruta.codigo);
  }

  static String _fecha(DateTime f) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(f.day)}/${dos(f.month)}/${f.year} ${dos(f.hour)}:${dos(f.minute)}';
  }
}
