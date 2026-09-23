import 'package:flutter/material.dart';

/// El destino de las secciones que todavia no existen.
///
/// Es preferible a dejar la tarjeta muerta o a esconderla: el home muestra el
/// mapa completo de lo que la app va a hacer, y una pantalla que dice "todavia
/// no" es una respuesta; un boton que no reacciona parece un telefono trabado.
class EnConstruccionPage extends StatelessWidget {
  const EnConstruccionPage({
    required this.titulo,
    required this.icono,
    required this.detalle,
    super.key,
  });

  final String titulo;
  final IconData icono;

  /// Que va a hacer esta pantalla cuando exista. Se escribe en concreto para
  /// que quien la abre sepa si lo que buscaba esta en otro lado.
  final String detalle;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 56, color: colores.outline),
              const SizedBox(height: 20),
              Text(
                'Todavia no esta lista',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Text(
                detalle,
                textAlign: TextAlign.center,
                style: TextStyle(color: colores.onSurfaceVariant, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
