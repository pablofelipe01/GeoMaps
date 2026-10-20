import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/enlaces.dart';
import '../state/aviso_ubicacion.dart';

/// Lo que se le dice a la persona antes de pedirle la ubicacion.
///
/// Aparece una sola vez, despues de entrar y antes del inicio, que es donde el
/// GPS arranca. Cada punto responde algo que el dialogo de Android no dice:
/// para que, cuando con la pantalla apagada, y a donde va. No tiene "ahora
/// no": sin ubicacion la app no tiene para que abrir, y la negativa se da igual
/// en el dialogo del sistema.
class AvisoUbicacionPage extends ConsumerWidget {
  const AvisoUbicacionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colores = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on, size: 56, color: colores.primary),
                  const SizedBox(height: 16),
                  Text(
                    'GeoMaps usa tu ubicacion',
                    style: texto.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _Punto(
                    icono: Icons.map_outlined,
                    texto:
                        'Para mostrar donde estas en el mapa y trazar la ruta '
                        'hasta un acopio o un lote.',
                  ),
                  const _Punto(
                    icono: Icons.timeline,
                    texto:
                        'Para grabar recorridos, poligonos y viajes de camion. '
                        'Durante un viaje sigue grabando con la pantalla '
                        'apagada, siempre con una notificacion visible, y se '
                        'detiene cuando lo terminas.',
                  ),
                  const _Punto(
                    icono: Icons.cloud_upload_outlined,
                    texto:
                        'Lo que guardas se sube a tu cuenta para que no se '
                        'pierda. No se comparte con terceros ni se usa para '
                        'publicidad.',
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Enlaces.abrir(Enlaces.privacidad),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Text('Leer la politica de privacidad'),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () =>
                          ref.read(avisoUbicacionProvider.notifier).continuar(),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Continuar'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Despues Android te pregunta si das el permiso.',
                    style: texto.bodySmall?.copyWith(
                      color: colores.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Punto extends StatelessWidget {
  const _Punto({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(child: Text(texto, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }
}
