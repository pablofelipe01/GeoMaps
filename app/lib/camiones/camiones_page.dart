import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/grabacion.dart';
import '../ui/capa_ruta.dart';
import 'escanear_page.dart';
import 'panel_viaje.dart';
import 'seguimiento.dart';
import 'vueltas.dart';

/// La entrada al modulo del personal de camiones.
///
/// Solo la ven las cuentas con el perfil `Camiones` (ver `Perfil` en
/// `state/sesion.dart`). Todo lo propio de camiones va en esta carpeta y usa lo
/// comun -mapa, GPS, ruteo por vias, sincronizacion- sin copiarlo: el modulo
/// suma pantallas, no una segunda app.
///
/// El flujo: escanear el QR de despacho, elegir una vuelta de la lista,
/// firmarla con la clave, ir por los vagones, volver y finalizarla. **Una a la
/// vez**: con una vuelta sin finalizar, esta pantalla la pone primero y no
/// deja escanear para tomar otra.
class CamionesPage extends ConsumerWidget {
  const CamionesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(grabadorProvider);
    final colores = Theme.of(context).colorScheme;
    // Cualquier grabacion abierta, este grabando o haya quedado a medias al
    // cerrarse la app: antes solo se miraba si grababa, y despues de reabrir
    // la app se podia tomar una segunda vuelta encima de la primera.
    final ocupado = g.codigo != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Camiones')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (ocupado) ...[
            _ViajeEnCurso(estado: g),
            const SizedBox(height: 16),
          ],
          SizedBox(
            height: 120,
            child: FilledButton.icon(
              onPressed: ocupado
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const EscanearPage(),
                      ),
                    ),
              icon: const Icon(Icons.qr_code_scanner, size: 44),
              label: const Text(
                'Escanear QR de vueltas',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            !ocupado
                ? 'Escanea el QR de despacho para ver las vueltas pendientes '
                      'por recoger y tomar una.'
                : g.esVuelta
                ? 'Finaliza la vuelta que tienes para poder tomar otra.'
                : 'Termina el recorrido que se esta grabando para poder '
                      'tomar una vuelta.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, color: colores.onSurface),
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
    final seg = g.seguimiento;

    // Lo que el servidor dice de esta vuelta. Solo se le cree cuando contesta
    // que esta llevando el control y que la abierta ya no es esta: ahi fue
    // despacho quien la cerro, que es la salida para un conductor trabado.
    final codigo = seg.viaje;
    final servidor = codigo == null
        ? null
        : ref.watch(miViajeProvider).valueOrNull;
    final cerrada =
        servidor != null && servidor.control && servidor.viaje?.codigo != codigo;

    final String paso;
    if (!g.esVuelta) {
      paso = g.abiertaSinGrabar
          ? 'La app se cerro mientras grababa.'
          : 'Grabando un recorrido.';
    } else if (cerrada) {
      paso = 'Despacho cerro esta vuelta. Cierra el viaje en este telefono '
          'para poder tomar otra.';
    } else {
      paso = switch (seg.etapa) {
        EtapaVuelta.yendo => 'Paso 1 de 3: ve por los vagones.',
        EtapaVuelta.volviendo => 'Paso 2 de 3: vuelve al punto de salida.',
        EtapaVuelta.deVuelta => 'Paso 3 de 3: ya puedes finalizarla.',
      };
    }

    final boton = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(54),
      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    );

    return Card(
      color: colores.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              g.esVuelta ? 'Tu vuelta en curso' : 'Recorrido en curso',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colores.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              g.destinoNombre ?? g.nombre ?? '',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.2,
                color: colores.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              paso,
              style: TextStyle(
                fontSize: 18,
                height: 1.3,
                color: colores.onPrimaryContainer,
              ),
            ),
            Text(
              'Llevas ${formatearDistancia(g.metros)}.',
              style: TextStyle(fontSize: 16, color: colores.onPrimaryContainer),
            ),
            const SizedBox(height: 14),
            if (cerrada)
              FilledButton.icon(
                style: boton,
                onPressed: () => ref
                    .read(grabadorProvider.notifier)
                    .terminar(propiedades: const {'cierre': 'despacho'}),
                icon: const Icon(Icons.check),
                label: const Text('Cerrar el viaje'),
              )
            else ...[
              FilledButton.icon(
                style: boton,
                onPressed: () {
                  if (g.abiertaSinGrabar) {
                    ref.read(grabadorProvider.notifier).reanudar();
                  }
                  abrirMapaDelViaje(context, ref.read(grabadorProvider));
                },
                icon: const Icon(Icons.navigation),
                label: Text(
                  g.abiertaSinGrabar ? 'Seguir el viaje' : 'Abrir el mapa',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                // Pasa por las reglas de la vuelta: si todavia no fue o no
                // volvio, dice que falta en vez de cerrarla.
                onPressed: () => terminarViaje(context, ref),
                child: Text(g.esVuelta ? 'Finalizar la vuelta' : 'Terminar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
