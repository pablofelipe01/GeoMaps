import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/proyectos_repository.dart';
import '../state/providers.dart';
import '../state/sesion.dart';

/// La lista de proyectos.
///
/// Cada fila dice cuantos mapas tiene descargados y cuanto ocupan. Es el unico
/// lugar donde alguien va a notar que el telefono se esta quedando sin espacio
/// antes de que la descarga falle en el campo.
///
/// Todo lo que se ve aca sale de la base local, no del backend: se crea un
/// proyecto parado en el lote, sin senal, y se sincroniza despues.
class ProyectosPage extends ConsumerWidget {
  const ProyectosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider).sesion;
    if (sesion == null) return const SizedBox.shrink();

    final proyectos = ref.watch(proyectosProvider(sesion.authUid));

    return Scaffold(
      appBar: AppBar(title: const Text('Proyectos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _crear(context, ref, sesion.authUid),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
      body: proyectos.when(
        data: (lista) => lista.isEmpty
            ? const _Vacio()
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: lista.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => _Fila(
                  resumen: lista[i],
                  alArchivar: () => _archivar(context, ref, lista[i]),
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        // Un error aca es de la base local, no de la red. Se muestra crudo a
        // proposito: es un problema del telefono y hay que poder reportarlo.
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'No se pudo leer la base del telefono.\n\n$e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _crear(
    BuildContext context,
    WidgetRef ref,
    String authUid,
  ) async {
    final datos = await showModalBottomSheet<_DatosProyecto>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FormularioProyecto(),
    );
    if (datos == null) return;

    await ref
        .read(proyectosRepositoryProvider)
        .crear(
          duenoAuthUid: authUid,
          nombre: datos.nombre,
          cliente: datos.cliente,
          municipio: datos.municipio,
        );
    // No hace falta refrescar nada: la lista escucha la tabla y se redibuja
    // sola en cuanto entra la fila.
  }

  Future<void> _archivar(
    BuildContext context,
    WidgetRef ref,
    ProyectoConResumen resumen,
  ) async {
    final mensajero = ScaffoldMessenger.of(context);
    final repo = ref.read(proyectosRepositoryProvider);
    await repo.archivar(resumen.proyecto.codigo);

    // Deshacer y no confirmar antes: archivar no destruye nada, y una pregunta
    // por cada toque cansa mas de lo que protege.
    mensajero.showSnackBar(
      SnackBar(
        content: Text('${resumen.proyecto.nombre} se archivo'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () => repo.archivar(resumen.proyecto.codigo, activo: true),
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.resumen, required this.alArchivar});

  final ProyectoConResumen resumen;
  final VoidCallback alArchivar;

  @override
  Widget build(BuildContext context) {
    final p = resumen.proyecto;
    final colores = Theme.of(context).colorScheme;

    // Lo de abajo del nombre: donde queda y que tiene bajado. Se arma con lo
    // que hay, para no dejar renglones con guiones de campos vacios.
    final lugar = [p.cliente, p.municipio].whereType<String>().join(' · ');
    final mapas = resumen.mapasDescargados == 0
        ? 'Sin mapas descargados'
        : '${resumen.mapasDescargados} '
              '${resumen.mapasDescargados == 1 ? "mapa" : "mapas"} · '
              '${resumen.megasUsadas.toStringAsFixed(0)} MB';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: colores.primaryContainer,
        child: Icon(Icons.folder_outlined, color: colores.onPrimaryContainer),
      ),
      title: Text(
        p.nombre,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lugar.isNotEmpty) Text(lugar),
          Text(
            mapas,
            style: TextStyle(
              color: resumen.mapasDescargados == 0
                  ? colores.outline
                  : colores.onSurfaceVariant,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // El punto de pendiente. Un proyecto creado en campo vive sin subir
          // hasta que haya senal, y hay que poder verlo de un vistazo.
          if (!p.sincronizado)
            Tooltip(
              message: 'Falta subirlo',
              child: Icon(Icons.cloud_off, size: 18, color: colores.outline),
            ),
          IconButton(
            tooltip: 'Archivar',
            icon: const Icon(Icons.archive_outlined),
            onPressed: alArchivar,
          ),
        ],
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio();

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 56, color: colores.outline),
            const SizedBox(height: 20),
            Text(
              'Todavia no hay proyectos',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Text(
              'Un proyecto es un predio: adentro van sus mapas, sus recorridos '
              'y sus puntos. Se puede crear aca mismo, sin senal.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colores.onSurfaceVariant, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Los tres campos de un proyecto nuevo.
///
/// Solo el nombre es obligatorio. Pedir cliente y municipio para poder empezar
/// obligaria a inventarlos a quien esta parado en el lote y solo quiere marcar
/// un lindero antes de que se vaya la luz del dia.
class _FormularioProyecto extends StatefulWidget {
  const _FormularioProyecto();

  @override
  State<_FormularioProyecto> createState() => _FormularioProyectoState();
}

class _FormularioProyectoState extends State<_FormularioProyecto> {
  final _formulario = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _cliente = TextEditingController();
  final _municipio = TextEditingController();

  @override
  void dispose() {
    _nombre.dispose();
    _cliente.dispose();
    _municipio.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formulario.currentState!.validate()) return;
    Navigator.pop(
      context,
      _DatosProyecto(
        nombre: _nombre.text,
        cliente: _cliente.text,
        municipio: _municipio.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // El teclado tapa el boton si no se corre la hoja hacia arriba.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formulario,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Nuevo proyecto',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nombre,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del predio',
                    hintText: 'Hacienda La Cabana',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Ponele un nombre para reconocerlo despues'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _cliente,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Cliente (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _municipio,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Municipio (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  onFieldSubmitted: (_) => _guardar(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _guardar,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Crear proyecto'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DatosProyecto {
  const _DatosProyecto({
    required this.nombre,
    required this.cliente,
    required this.municipio,
  });

  final String nombre;
  final String cliente;
  final String municipio;
}

/// Los proyectos de la cuenta que esta adentro, en vivo.
final proyectosProvider = StreamProvider.autoDispose
    .family<List<ProyectoConResumen>, String>((ref, authUid) {
      return ref.watch(proyectosRepositoryProvider).observar(authUid);
    });
