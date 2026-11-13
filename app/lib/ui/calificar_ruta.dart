import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/grabacion.dart';
import 'capa_ruta.dart' show formatearDistancia;

/// Calificar la ruta por donde se paso.
///
/// La ruta la calcula la app sobre un plano de vias, y el plano no sabe que
/// llovio anoche ni que cerraron un paso: eso lo sabe quien acaba de pasar. La
/// calificacion queda guardada **con el recorrido que se grabo** -por donde se
/// fue de verdad, no por donde decia la ruta-, asi que una estrella sobre un
/// tramo se puede ir a mirar en el mapa.
///
/// Son cinco estrellas y no un formulario: se contesta parado al lado del
/// camion. Los motivos y el comentario son opcionales, y los motivos solo se
/// ofrecen cuando la nota es baja, que es cuando hay algo que arreglar.

/// Por que una ruta salio mal. El `id` es lo que viaja y se guarda; el titulo
/// es solo para la pantalla.
enum MotivoRuta {
  viaMala('via_mala', 'Via en mal estado'),
  barro('barro', 'Barro o agua'),
  cerrada('cerrada', 'Paso cerrado'),
  masLarga('mas_larga', 'Dio mucha vuelta'),
  equivocada('equivocada', 'Me mando por donde no era');

  const MotivoRuta(this.id, this.titulo);

  final String id;
  final String titulo;
}

/// Lo que se contesto al terminar una ruta.
class CalificacionRuta {
  const CalificacionRuta({
    required this.estrellas,
    this.motivos = const [],
    this.comentario,
  });

  /// De 1 (muy mala) a 5 (muy buena).
  final int estrellas;
  final List<MotivoRuta> motivos;
  final String? comentario;

  /// Como queda en las propiedades del GeoJSON del recorrido. Lo que no se
  /// contesto no viaja como vacio, no viaja.
  Map<String, Object?> aPropiedades() {
    final texto = comentario?.trim();
    return {
      'calificacion': estrellas,
      if (motivos.isNotEmpty)
        'calificacion_motivos': [for (final m in motivos) m.id],
      if (texto != null && texto.isNotEmpty) 'calificacion_comentario': texto,
    };
  }

  /// Las estrellas de un recorrido guardado, leidas de su GeoJSON sin
  /// decodificarlo entero: las propiedades van al principio del texto, y un
  /// recorrido de dos horas son miles de coordenadas que no hace falta leer
  /// para pintar una estrella en una lista.
  static int? estrellasDe(String geometria) {
    final m = _enGeoJson.firstMatch(geometria);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static final _enGeoJson = RegExp(r'"calificacion":\s*([1-5])\b');

  /// La nota en palabras, para debajo de las estrellas.
  static String enPalabras(int estrellas) => switch (estrellas) {
    1 => 'Muy mala',
    2 => 'Mala',
    3 => 'Regular',
    4 => 'Buena',
    5 => 'Muy buena',
    _ => 'Toca una estrella',
  };
}

/// Pregunta que tal estuvo la ruta. Devuelve la calificacion, o nulo si se
/// omitio: calificar no puede ser obligatorio, o se contesta cualquier cosa
/// para salir del paso y el dato deja de valer.
Future<CalificacionRuta?> pedirCalificacion(
  BuildContext context, {
  required String titulo,
  String? detalle,
}) {
  return showDialog<CalificacionRuta>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DialogoCalificar(titulo: titulo, detalle: detalle),
  );
}

class _DialogoCalificar extends StatefulWidget {
  const _DialogoCalificar({required this.titulo, this.detalle});

  final String titulo;
  final String? detalle;

  @override
  State<_DialogoCalificar> createState() => _DialogoCalificarState();
}

class _DialogoCalificarState extends State<_DialogoCalificar> {
  int _estrellas = 0;
  final _motivos = <MotivoRuta>{};
  final _comentario = TextEditingController();

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  void _guardar() {
    Navigator.pop(
      context,
      CalificacionRuta(
        estrellas: _estrellas,
        // Los motivos de una nota baja no se arrastran si despues se subio
        // la nota: ya no se ven, y guardarlos seria decir algo que no se dijo.
        motivos: _estrellas <= 3
            ? [
                for (final m in MotivoRuta.values)
                  if (_motivos.contains(m)) m,
              ]
            : const [],
        comentario: _comentario.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final detalle = widget.detalle;

    return AlertDialog(
      title: Text(widget.titulo),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (detalle != null) ...[
              Text(detalle, style: TextStyle(color: colores.onSurfaceVariant)),
              const SizedBox(height: 12),
            ],
            const Text(
              'Que tal estuvo la ruta por donde pasaste?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    key: ValueKey('estrella-$i'),
                    // Grandes: se tocan con el dedo sucio y de pie.
                    iconSize: 40,
                    padding: const EdgeInsets.all(4),
                    tooltip: CalificacionRuta.enPalabras(i),
                    onPressed: () => setState(() => _estrellas = i),
                    icon: Icon(
                      i <= _estrellas
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: i <= _estrellas
                          ? const Color(0xFFF9A825)
                          : colores.outline,
                    ),
                  ),
              ],
            ),
            Center(
              child: Text(
                CalificacionRuta.enPalabras(_estrellas),
                style: TextStyle(
                  color: _estrellas == 0
                      ? colores.onSurfaceVariant
                      : colores.onSurface,
                  fontWeight: _estrellas == 0 ? null : FontWeight.w700,
                ),
              ),
            ),
            if (_estrellas >= 1 && _estrellas <= 3) ...[
              const SizedBox(height: 14),
              const Text('Que paso? (opcional)'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in MotivoRuta.values)
                    FilterChip(
                      label: Text(m.titulo),
                      selected: _motivos.contains(m),
                      onSelected: (si) => setState(
                        () => si ? _motivos.add(m) : _motivos.remove(m),
                      ),
                    ),
                ],
              ),
            ],
            if (_estrellas > 0) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _comentario,
                maxLines: 2,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Comentario (opcional)',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Omitir'),
        ),
        FilledButton(
          onPressed: _estrellas == 0 ? null : _guardar,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Termina la ruta que se esta siguiendo: pregunta la calificacion y cierra el
/// recorrido con ella adentro. Devuelve si quedo cerrada.
///
/// [llego] cambia solo lo que se dice: llegar al destino y cortar antes se
/// califican igual, porque lo que se califica es el camino que se hizo.
Future<bool> terminarRutaCalificando(
  BuildContext context,
  WidgetRef ref, {
  required bool llego,
}) async {
  final g = ref.read(grabadorProvider);
  if (g.codigo == null) return false;
  final destino = g.destinoNombre;
  final avisos = ScaffoldMessenger.of(context);

  final calificacion = await pedirCalificacion(
    context,
    titulo: llego
        ? (destino == null ? 'Llegaste' : 'Llegaste: $destino')
        : 'Ruta terminada',
    detalle: g.puntos < 2
        ? null
        : 'Recorriste ${formatearDistancia(ref.read(grabadorProvider).metros)}.',
  );

  final habia = ref.read(grabadorProvider).puntos >= 2;
  await ref
      .read(grabadorProvider.notifier)
      .terminar(propiedades: calificacion?.aPropiedades() ?? const {});
  avisos.showSnackBar(
    SnackBar(
      content: Text(
        !habia
            ? 'El GPS no alcanzo a grabar el recorrido: no quedo nada guardado.'
            : calificacion == null
            ? 'Recorrido guardado sin calificar. Sube solo con senal.'
            : 'Gracias. El recorrido y tu calificacion suben solos con senal.',
      ),
    ),
  );
  return true;
}
