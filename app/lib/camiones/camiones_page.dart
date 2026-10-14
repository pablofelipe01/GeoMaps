import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../state/grabacion.dart';
import '../ui/capa_ruta.dart';
import '../ui/mapa_page.dart';
import 'escanear_page.dart';
import 'panel_viaje.dart';

/// La entrada al modulo del personal de camiones.
///
/// Solo la ven las cuentas con el perfil `Camiones` (ver `Perfil` en
/// `state/sesion.dart`). Todo lo propio de camiones va en esta carpeta y usa lo
/// comun -mapa, GPS, ruteo por vias, sincronizacion- sin copiarlo: el modulo
/// suma pantallas, no una segunda app.
///
/// El flujo: escanear el QR de despacho, elegir una vuelta de la lista,
/// firmarla con cedula y clave, y salir con el mapa trazando la ruta mientras
/// el viaje se graba. Si hay un viaje en curso, esta pantalla lo pone primero.
class CamionesPage extends ConsumerWidget {
  const CamionesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(grabadorProvider);
    final colores = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Camiones')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (g.codigo != null) ...[
            _ViajeEnCurso(estado: g),
            const SizedBox(height: 16),
          ],
          SizedBox(
            height: 120,
            child: FilledButton.icon(
              // Con un viaje grabando no se toma otro: el conductor esta en
              // una vuelta, y tomar la segunda cortaria la grabacion de la
              // primera.
              onPressed: g.grabando
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const EscanearPage(),
                      ),
                    ),
              icon: const Icon(Icons.qr_code_scanner, size: 40),
              label: const Text(
                'Escanear QR de vueltas',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            g.grabando
                ? 'Termina el viaje en curso para tomar otra vuelta.'
                : 'Escanea el QR de despacho para ver las vueltas pendientes '
                      'por recoger y tomar una.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colores.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ViajeEnCurso extends ConsumerWidget {
  const _ViajeEnCurso({required this.estado});

  final EstadoGrabacion estado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = estado;
    final colores = Theme.of(context).colorScheme;

    return Card(
      color: colores.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              g.abiertaSinGrabar ? 'Viaje sin terminar' : 'Viaje en curso',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(g.nombre ?? ''),
            Text(
              g.abiertaSinGrabar
                  ? 'La app se cerro mientras grababa. Lleva '
                        '${formatearDistancia(g.metros)}.'
                  : 'Grabando · ${formatearDistancia(g.metros)}',
              style: TextStyle(color: colores.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    if (g.abiertaSinGrabar) {
                      ref.read(grabadorProvider.notifier).reanudar();
                    }
                    _abrirMapa(context, g);
                  },
                  icon: const Icon(Icons.navigation),
                  label: Text(
                    g.abiertaSinGrabar ? 'Seguir el viaje' : 'Abrir mapa',
                  ),
                ),
                OutlinedButton(
                  onPressed: () => terminarViaje(context, ref),
                  child: const Text('Terminar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _abrirMapa(BuildContext context, EstadoGrabacion g) {
    final destino = g.destino;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MapaPage.guaicaramo(
          destinoInicial: destino == null
              ? null
              : LatLng(destino.latitud, destino.longitud),
          nombreDestinoInicial: g.destinoNombre == null
              ? null
              : 'Vagones en ${g.destinoNombre}',
          panelSuperior: const PanelViaje(),
        ),
      ),
    );
  }
}
