import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camiones/camiones_page.dart';
import '../core/api_client.dart';
import '../core/ubicacion.dart';
import '../state/providers.dart';
import '../state/red.dart';
import '../state/sesion.dart';
import '../state/sincronizador.dart';
import '../state/ubicacion_provider.dart';
import 'actualizacion_page.dart';
import 'en_construccion.dart';
import 'mapa_guaicaramo.dart';
import 'mapa_page.dart';
import 'proyectos_page.dart';
import 'sincronizacion_page.dart';

/// La primera pantalla despues de entrar.
///
/// Existe por una razon concreta: antes de caminar un lote hay tres cosas que
/// deciden si se sale o no se sale — si el GPS engancho, si hay senal para
/// bajar lo que falte, y cuantos dias le quedan a la sesion. Abrir directo en
/// el mapa esconde las tres, y el momento de enterarse de que la sesion vence
/// manana no puede ser cuando ya se esta en el potrero.
///
/// Lo segundo que hace es mostrar la app completa, con tarjetas grandes: son
/// las que se aciertan con guantes y con el telefono en una sola mano.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider).sesion;
    // Lo que sube solo al volver la red. Se engancha aca porque el inicio queda
    // debajo de todas las pantallas mientras haya sesion.
    ref.watch(sincronizacionAutomaticaProvider);
    // Solo pasa durante el parpadeo entre cerrar sesion y que la puerta
    // reemplace esta pantalla por el login.
    if (sesion == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: const Text('GeoMaps'),
        actions: [
          IconButton(
            tooltip: 'Mi cuenta',
            onPressed: () => _mostrarCuenta(context, ref),
            icon: _Avatar(foto: sesion.foto, nombre: sesion.nombre),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _Saludo(nombre: sesion.nombre),
            const SizedBox(height: 16),
            const AvisoActualizacion(),
            const _Estado(),
            const SizedBox(height: 24),
            Text(
              'Que vas a hacer',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            const _Accesos(),
            const SizedBox(height: 24),
            Text(
              'Mapas del predio',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            const MapaGuaicaramo(),
          ],
        ),
      ),
    );
  }

  /// Quien esta conectado y cuanto le queda de sesion.
  ///
  /// Los dias restantes se muestran porque son el dato que decide si alguien
  /// puede salir tranquilo a una semana de campo. Enterarse de que la sesion
  /// vencio estando en el lote es justo lo que hay que evitar.
  void _mostrarCuenta(BuildContext context, WidgetRef ref) {
    final sesion = ref.read(sesionProvider).sesion;
    if (sesion == null) return;

    showModalBottomSheet<void>(
      context: context,
      builder: (hoja) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: _Avatar(foto: sesion.foto, nombre: sesion.nombre),
              title: Text(sesion.nombre),
              subtitle: Text(sesion.correo),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text('Sesion valida ${sesion.diasRestantes} dias mas'),
              subtitle: const Text(
                'Podes trabajar sin senal durante ese plazo.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Cerrar sesion'),
              onTap: () {
                Navigator.pop(hoja);
                ref.read(sesionProvider.notifier).salir();
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_forever,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Eliminar mi cuenta',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(hoja);
                showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const _DialogoBaja(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmar la baja de la cuenta. Play exige que se pueda hacer desde la app.
///
/// Dice que tambien se pierde lo que no se sincronizo porque es lo que de
/// verdad no se recupera: lo subido se borra igual, pero eso la persona ya lo
/// esta pidiendo.
class _DialogoBaja extends ConsumerStatefulWidget {
  const _DialogoBaja();

  @override
  ConsumerState<_DialogoBaja> createState() => _DialogoBajaState();
}

class _DialogoBajaState extends ConsumerState<_DialogoBaja> {
  bool _borrando = false;
  String? _error;

  Future<void> _eliminar() async {
    setState(() {
      _borrando = true;
      _error = null;
    });
    try {
      await ref
          .read(sesionProvider.notifier)
          .eliminarCuenta(ref.read(dbProvider));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _borrando = false;
        _error = e is ApiError
            ? e.mensaje
            : 'No se pudo conectar. Busca senal y volve a intentar.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Eliminar tu cuenta'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Se borran tu cuenta y tus recorridos y poligonos, en el servidor '
            'y en este telefono. Lo que todavia no sincronizaste tambien se '
            'pierde. No se puede deshacer.',
          ),
          if (_borrando) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: colores.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _borrando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colores.error,
            foregroundColor: colores.onError,
          ),
          onPressed: _borrando ? null : _eliminar,
          child: const Text('Eliminar'),
        ),
      ],
    );
  }
}

class _Saludo extends StatelessWidget {
  const _Saludo({required this.nombre});

  final String nombre;

  @override
  Widget build(BuildContext context) {
    // Solo el primer nombre: "Hola, David Hernandez Ramirez" ocupa dos
    // renglones en un telefono angosto y no dice nada mas.
    final partes = nombre.trim().split(RegExp(r'\s+'));
    final primero = partes.first.isEmpty ? nombre : partes.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hola, $primero',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          'Tus mapas del predio, sin senal',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// La tira de estado: GPS, red y sesion.
///
/// Los tres a la vista y siempre. Son lo que hay que mirar antes de salir, y un
/// dato que hay que ir a buscar a un menu es un dato que nadie mira.
class _Estado extends ConsumerWidget {
  const _Estado();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posicion = ref.watch(posicionProvider);
    final red = ref.watch(redProvider);
    final sesion = ref.watch(sesionProvider).sesion;

    final gps = posicion.when(
      data: (p) => Ubicacion.esDeCache(p)
          ? _Chip(
              icono: Icons.gps_not_fixed,
              texto: 'GPS: ${Ubicacion.hace(p)}',
              color: Colors.orange.shade800,
            )
          : _Chip(
              icono: Icons.gps_fixed,
              texto: '+/- ${p.accuracy.toStringAsFixed(0)} m',
              // El umbral no es cosmetico: por encima de 10 m el punto no sirve para
              // marcar un vertice de lindero.
              color: p.accuracy <= 10
                  ? Colors.green.shade700
                  : Colors.orange.shade800,
            ),
      loading: () => _Chip(
        icono: Icons.gps_not_fixed,
        texto: 'Buscando GPS',
        color: Colors.orange.shade800,
      ),
      error: (e, _) => _Chip(
        icono: Icons.gps_off,
        texto: 'GPS sin senal',
        color: Colors.red.shade700,
      ),
    );

    final estadoRed = red.maybeWhen(
      data: (r) => _Chip(
        icono: r.hayRed ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
        texto: r.etiqueta,
        color: r.hayRed ? Colors.green.shade700 : Colors.grey.shade700,
      ),
      orElse: () => _Chip(
        icono: Icons.cloud_queue,
        texto: 'Revisando',
        color: Colors.grey.shade700,
      ),
    );

    final dias = sesion?.diasRestantes ?? 0;
    final estadoSesion = _Chip(
      icono: Icons.schedule,
      texto: dias == 1 ? '1 dia' : '$dias dias',
      // Por debajo de una semana hay que avisar, antes de que alguien salga a
      // una semana de campo creyendo que tiene mes.
      color: dias <= 7 ? Colors.orange.shade800 : Colors.grey.shade700,
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [gps, estadoRed, estadoSesion],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icono, required this.texto, required this.color});

  final IconData icono;
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        // Fondo solido y no translucido: la app se usa a pleno sol.
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            texto,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// La grilla de accesos.
class _Accesos extends ConsumerWidget {
  const _Accesos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider).sesion;
    final cuantos = sesion == null
        ? const AsyncValue<int>.loading()
        : ref.watch(cantidadProyectosProvider(sesion.authUid));

    // Lo comun (mapa, sincronizar) lo ve todo el mundo; lo de cada modulo,
    // solo quien tiene el perfil. Cada tarjeta nueva decide aca de cual es.
    final plantacion = sesion?.tiene(Perfil.plantacion) ?? true;
    final camiones = sesion?.tiene(Perfil.camiones) ?? false;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      // Un poco mas altas que anchas: entran el icono grande, el titulo y el
      // renglon de detalle sin apretar nada.
      childAspectRatio: 0.95,
      children: [
        _Tarjeta(
          icono: Icons.map,
          titulo: 'Mapa',
          detalle: 'Ver donde estoy',
          destacada: true,
          alTocar: () => _ir(context, const MapaPage()),
        ),
        if (camiones)
          _Tarjeta(
            icono: Icons.local_shipping_outlined,
            titulo: 'Camiones',
            detalle: 'Herramientas de transporte',
            alTocar: () => _ir(context, const CamionesPage()),
          ),
        if (plantacion)
          _Tarjeta(
            icono: Icons.folder_outlined,
            titulo: 'Proyectos',
            detalle: cuantos.maybeWhen(
              data: (n) => n == 1 ? '1 proyecto' : '$n proyectos',
              orElse: () => 'Abrir',
            ),
            alTocar: () => _ir(context, const ProyectosPage()),
          ),
        if (plantacion)
          _Tarjeta(
            icono: Icons.download_outlined,
            titulo: 'Descargas',
            detalle: 'Mapas sin senal',
            alTocar: () => _ir(
              context,
              const EnConstruccionPage(
                titulo: 'Descargas',
                icono: Icons.download_outlined,
                detalle:
                    'Aca vas a bajar al telefono los mapas de un proyecto, '
                    'y a recortar una region del satelite para usarla sin senal.',
              ),
            ),
          ),
        _Tarjeta(
          icono: Icons.sync,
          titulo: 'Sincronizar',
          detalle: switch (ref.watch(pendientesProvider).valueOrNull ?? 0) {
            0 => 'Todo arriba',
            1 => '1 pendiente',
            final n => '$n pendientes',
          },
          alTocar: () => _ir(context, const SincronizacionPage()),
        ),
      ],
    );
  }

  void _ir(BuildContext context, Widget pagina) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => pagina));
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.alTocar,
    this.destacada = false,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final VoidCallback alTocar;

  /// La accion principal va pintada. En una grilla de cuatro iguales todas
  /// pesan lo mismo, y la que se usa el noventa por ciento de las veces se
  /// pierde entre las otras tres.
  final bool destacada;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final fondo = destacada
        ? colores.primaryContainer
        : colores.surfaceContainerHighest;
    final tinta = destacada ? colores.onPrimaryContainer : colores.onSurface;

    return Material(
      color: fondo,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: alTocar,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icono, size: 34, color: tinta),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: tinta,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detalle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: tinta.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.foto, required this.nombre});

  final String? foto;
  final String nombre;

  @override
  Widget build(BuildContext context) {
    if (foto != null) {
      return CircleAvatar(radius: 16, backgroundImage: NetworkImage(foto!));
    }
    // Sin foto, la inicial. Un icono generico hace que todas las cuentas se
    // vean iguales en un telefono que pasa de mano en mano.
    final limpio = nombre.trim();
    final inicial = limpio.isEmpty ? '?' : limpio[0].toUpperCase();
    return CircleAvatar(radius: 16, child: Text(inicial));
  }
}

/// Cuantos proyectos activos tiene la cuenta, para el contador de la tarjeta.
final cantidadProyectosProvider = StreamProvider.autoDispose
    .family<int, String>((ref, authUid) {
      return ref.watch(proyectosRepositoryProvider).contarActivos(authUid);
    });
