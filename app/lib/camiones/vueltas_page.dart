import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/geo.dart';
import '../state/gps.dart';
import '../state/grabacion.dart';
import '../state/sesion.dart';
import '../ui/capa_ruta.dart';
import '../ui/mapa_page.dart';
import 'panel_viaje.dart';
import 'vueltas.dart';

/// Las vueltas pendientes por recoger, con su resumen arriba. Lo que abre el QR.
///
/// El orden es el de la planilla -la mas vieja primero-, no por cercania: el
/// orden de despacho es la prioridad, y una vuelta de ayer que sigue ahi es la
/// que mas urge aunque quede lejos.
class VueltasPage extends ConsumerWidget {
  const VueltasPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vueltas = ref.watch(vueltasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vueltas pendientes'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => ref.invalidate(vueltasProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: vueltas.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Error(
          texto: e is ApiError
              ? e.mensaje
              : 'No se pudo traer la lista. Revisa la senal y vuelve a '
                    'intentar.',
          onReintentar: () => ref.invalidate(vueltasProvider),
        ),
        data: (lista) => RefreshIndicator(
          onRefresh: () => ref.refresh(vueltasProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
            children: [
              _Resumen(resumen: ResumenVueltas(lista.vueltas, DateTime.now())),
              _QuienToma(conductor: lista.conductor),
              const SizedBox(height: 4),
              if (lista.vueltas.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No hay vueltas pendientes por recoger.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final v in lista.vueltas)
                _FilaVuelta(vuelta: v, conductor: lista.conductor),
            ],
          ),
        ),
      ),
    );
  }
}

/// A nombre de quien van a quedar las vueltas que se tomen desde este
/// telefono. Va arriba de la lista porque es lo primero que hay que saber: un
/// telefono prestado toma vueltas a nombre de su dueno, no de quien lo tiene.
class _QuienToma extends StatelessWidget {
  const _QuienToma({required this.conductor});

  final Conductor? conductor;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final c = conductor;
    final conCedula = c != null && c.tieneCedula;
    // La cedula quedo atada pero el conductor ya no esta activo en SiriusFleet.
    final huerfana = conCedula && c.nombre == null;

    final String texto;
    if (!conCedula) {
      texto =
          'La primera vuelta que tomes te pide la cedula. Queda guardada en '
          'tu cuenta y no se vuelve a pedir.';
    } else if (!huerfana) {
      texto =
          'Las vueltas quedan a nombre de ${c.nombre} '
          '(CC ${c.cedulaOculta}).';
    } else {
      texto =
          'Tu cedula (CC ${c.cedulaOculta}) ya no aparece entre los '
          'conductores activos de SiriusFleet. Avisale a despacho antes de '
          'tomar una vuelta.';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            huerfana ? Icons.warning_amber : Icons.badge_outlined,
            size: 18,
            color: huerfana ? colores.error : colores.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(fontSize: 13, color: colores.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.resumen});

  final ResumenVueltas resumen;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final r = resumen;
    final vieja = r.masVieja;

    Widget dato(String valor, String etiqueta, {bool alerta = false}) =>
        Expanded(
          child: Column(
            children: [
              Text(
                valor,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: alerta ? colores.error : colores.onSurface,
                ),
              ),
              Text(
                etiqueta,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant),
              ),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Row(
              children: [
                dato('${r.total}', 'por recoger'),
                dato('${r.comercial}', 'comercial'),
                dato('${r.hibrido}', 'hibrido'),
                dato(
                  '${r.deOtroDia}',
                  'de dias\nanteriores',
                  alerta: r.deOtroDia > 0,
                ),
              ],
            ),
            if (vieja != null || r.sinCoordenada > 0) ...[
              const Divider(height: 20),
              if (vieja != null)
                Text(
                  'La mas vieja se reporto ${_cuando(vieja)}.',
                  style: TextStyle(color: colores.onSurfaceVariant),
                ),
              if (r.sinCoordenada > 0)
                Text(
                  r.sinCoordenada == 1
                      ? '1 vuelta no tiene coordenada: se puede tomar, pero '
                            'el mapa no traza la ruta.'
                      : '${r.sinCoordenada} vueltas no tienen coordenada: se '
                            'pueden tomar, pero el mapa no traza la ruta.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colores.error),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilaVuelta extends ConsumerWidget {
  const _FilaVuelta({required this.vuelta, required this.conductor});

  final Vuelta vuelta;
  final Conductor? conductor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colores = Theme.of(context).colorScheme;
    final v = vuelta;
    final otroDia = v.esDeOtroDia(DateTime.now());
    final lejos = _distancia(v);
    final sinPunto = v.origen.punto == null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '#${v.consecutivo}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: colores.outline,
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 11,
                  backgroundColor: colores.surfaceContainerHighest,
                  child: Text(
                    v.letraFruto,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  otroDia
                      ? '${_fecha(v.jornada)} · ${_hora(v.reportadoEn)}'
                      : 'reporte ${_hora(v.reportadoEn)}',
                  style: TextStyle(
                    color: otroDia ? colores.error : colores.onSurfaceVariant,
                    fontWeight: otroDia ? FontWeight.w700 : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Vagones llenos',
              style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant),
            ),
            Text(
              v.origen.corto,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            if (v.origen.codigo != null)
              Text(
                v.origen.codigo!,
                style: TextStyle(fontSize: 12, color: colores.outline),
              ),
            if (v.destino != null) ...[
              const SizedBox(height: 6),
              Text(
                'Ubicar vagon${v.vagon == null ? '' : ' ${v.vagon}'} en '
                '${v.destino!.corto}',
              ),
            ],
            if (v.observaciones != null) ...[
              const SizedBox(height: 6),
              Text(
                v.observaciones!,
                style: TextStyle(color: colores.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    sinPunto
                        ? 'Sin coordenada: pregunta en despacho donde es.'
                        : lejos == null
                        ? 'El mapa te lleva por las vias'
                        : 'A ${formatearDistancia(lejos)} en linea recta',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: sinPunto
                          ? colores.error
                          : colores.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Un boton y no la tarjeta entera: tomar una vuelta la anota
                // en la planilla, y eso no puede pasar por rozar la lista
                // mientras se la recorre con el dedo.
                FilledButton.icon(
                  onPressed: () => _tomar(context, ref, v, conductor),
                  icon: const Icon(Icons.local_shipping, size: 18),
                  label: const Text('Tomar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// En linea recta y no por la via: alcanza para ordenar mentalmente la lista
  /// sin calcular diez rutas. La de verdad la da el mapa al tomarla.
  double? _distancia(Vuelta v) {
    final p = Gps.instancia.ultima;
    final destino = v.origen.punto;
    if (p == null || destino == null) return null;
    return distanciaM(
      PuntoGeo(p.latitude, p.longitude),
      PuntoGeo(destino.latitude, destino.longitude),
    );
  }
}

/// Tomar una vuelta: firmarla, empezar a grabar y abrir el mapa yendo hacia
/// los vagones.
///
/// Una vuelta sin coordenada tambien se deja tomar. Antes no: el acopio que
/// SiriusFleet todavia no ubico dejaba la vuelta sin poder asignarse a nadie
/// desde la app. Lo que falta ahi es la ruta, no el conductor; se toma igual,
/// se graba igual, y el mapa abre sin destino.
Future<void> _tomar(
  BuildContext context,
  WidgetRef ref,
  Vuelta v,
  Conductor? conductor,
) async {
  final sesion = ref.read(sesionProvider).sesion;
  final nombre = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _Confirmar(
      vuelta: v,
      conductor: conductor,
      // Sin el dato del backend se decide con lo que la sesion sabe: las
      // cuentas de Google no tienen clave que pedir.
      pideClave: conductor?.pideClave ?? (sesion?.proveedor != 'Google'),
    ),
  );
  if (nombre == null || !context.mounted) return;

  final destino = v.origen.punto;
  final entrega = v.destino?.punto;
  try {
    await ref
        .read(grabadorProvider.notifier)
        .iniciar(
          nombre: v.nombreViaje,
          destino: destino == null
              ? null
              : PuntoGeo(destino.latitude, destino.longitude),
          destinoNombre: v.origen.corto,
          propiedades: {
            'vuelta_id': v.id,
            'consecutivo': v.consecutivo,
            'jornada': v.jornada.toIso8601String().substring(0, 10),
            'origen': v.origen.codigo,
            'conductor': nombre,
            // Donde dejar el vagon vacio de paso: el segundo tramo del viaje.
            if (entrega != null)
              'entrega': [entrega.longitude, entrega.latitude],
            if (v.destino != null) 'entrega_nombre': v.destino!.corto,
            'vagon': v.vagon,
          },
        );
  } catch (_) {
    // La vuelta ya quedo a su nombre en la planilla. Que no arranque la
    // grabacion no puede dejarlo parado frente a la lista: el mapa abre igual.
  }
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Vuelta #${v.consecutivo} a nombre de $nombre.')),
  );

  // Reemplaza la lista: volver atras desde el mapa no puede mostrar una lista
  // donde la vuelta que se acaba de tomar sigue apareciendo libre.
  await Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(
      builder: (_) => MapaPage.guaicaramo(
        destinoInicial: destino,
        nombreDestinoInicial: destino == null
            ? null
            : 'Vagones en ${v.origen.corto}',
        panelSuperior: const PanelViaje(),
      ),
    ),
  );
}

/// La firma. Pide solo lo que le falta a la cuenta: la cedula la primera vez,
/// la clave si tiene una. Una cuenta de Google que ya dejo su cedula confirma
/// con un toque.
///
/// Devuelve el nombre del conductor como quedo en la planilla, o nulo si se
/// cancelo.
class _Confirmar extends ConsumerStatefulWidget {
  const _Confirmar({
    required this.vuelta,
    required this.conductor,
    required this.pideClave,
  });

  final Vuelta vuelta;
  final Conductor? conductor;
  final bool pideClave;

  @override
  ConsumerState<_Confirmar> createState() => _ConfirmarState();
}

class _ConfirmarState extends ConsumerState<_Confirmar> {
  final _cedula = TextEditingController();
  final _clave = TextEditingController();
  bool _enviando = false;
  bool _verClave = false;
  String? _error;

  bool get _pideCedula => !(widget.conductor?.tieneCedula ?? false);

  @override
  void dispose() {
    _cedula.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_pideCedula && _cedula.text.trim().isEmpty) {
      setState(() => _error = 'Escribe tu cedula.');
      return;
    }
    if (widget.pideClave && _clave.text.isEmpty) {
      setState(() => _error = 'Escribe tu clave de GeoMaps.');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final r = await ref
          .read(apiProvider)
          .confirmarVuelta(
            widget.vuelta.id,
            cedula: _pideCedula ? _cedula.text.trim() : null,
            clave: widget.pideClave ? _clave.text : null,
          );
      if (mounted) {
        Navigator.pop(context, r['conductor'] as String? ?? 'tu nombre');
      }
    } on ApiError catch (e) {
      // La vuelta la tomo otro: la lista ya no sirve.
      if (e.codigo == 409) ref.invalidate(vueltasProvider);
      if (mounted) setState(() => _error = e.mensaje);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Sin conexion con el servidor. Confirmar necesita senal: '
              'busca donde haya y vuelve a intentar.',
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vuelta;
    final nombre = widget.conductor?.nombre;
    final colores = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text('Tomar vuelta #${v.consecutivo}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vas por los vagones en ${v.origen.corto}. Queda anotado en la '
              'planilla ${nombre == null ? 'a tu nombre' : 'a nombre de $nombre'}'
              ', con la hora de salida de ahora.',
            ),
            if (v.origen.punto == null) ...[
              const SizedBox(height: 10),
              Text(
                'Este acopio no tiene coordenada: el mapa no va a trazar la '
                'ruta. Pregunta en despacho donde es.',
                style: TextStyle(color: colores.error),
              ),
            ],
            if (_pideCedula) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _cedula,
                enabled: !_enviando,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: widget.pideClave
                    ? TextInputAction.next
                    : TextInputAction.done,
                onSubmitted: widget.pideClave ? null : (_) => _enviar(),
                decoration: const InputDecoration(
                  labelText: 'Cedula',
                  helperText: 'Solo esta vez: queda guardada en tu cuenta.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (widget.pideClave) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _clave,
                enabled: !_enviando,
                autofocus: !_pideCedula,
                obscureText: !_verClave,
                onSubmitted: (_) => _enviar(),
                decoration: InputDecoration(
                  labelText: 'Clave de GeoMaps',
                  helperText: 'La misma con la que entras a la app.',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _verClave = !_verClave),
                    icon: Icon(
                      _verClave ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: colores.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _enviando ? null : _enviar,
          child: _enviando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Tomar la vuelta'),
        ),
      ],
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.texto, required this.onReintentar});

  final String texto;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(texto, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onReintentar,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

String _dos(int n) => n.toString().padLeft(2, '0');
String _hora(DateTime f) => '${_dos(f.hour)}:${_dos(f.minute)}';
String _fecha(DateTime f) => '${_dos(f.day)}/${_dos(f.month)}';

String _cuando(DateTime f) {
  final hoy = DateTime.now();
  final mismoDia =
      f.year == hoy.year && f.month == hoy.month && f.day == hoy.day;
  return mismoDia
      ? 'hoy a las ${_hora(f)}'
      : 'el ${_fecha(f)} a las ${_hora(f)}';
}
