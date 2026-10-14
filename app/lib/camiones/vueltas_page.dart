import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

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
              _Resumen(resumen: ResumenVueltas(lista, DateTime.now())),
              const SizedBox(height: 8),
              if (lista.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No hay vueltas pendientes por recoger.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final v in lista) _FilaVuelta(vuelta: v),
            ],
          ),
        ),
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
                      ? '1 vuelta no tiene coordenada: no se puede trazar la ruta.'
                      : '${r.sinCoordenada} vueltas no tienen coordenada: no se '
                            'puede trazar la ruta.',
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
  const _FilaVuelta({required this.vuelta});

  final Vuelta vuelta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colores = Theme.of(context).colorScheme;
    final v = vuelta;
    final otroDia = v.esDeOtroDia(DateTime.now());
    final lejos = _distancia(v);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _tomar(context, ref, v),
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
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
              const SizedBox(height: 8),
              Text(
                v.origen.punto == null
                    ? 'Sin coordenada: pregunta en despacho donde es.'
                    : lejos == null
                    ? 'Toca para tomar esta vuelta'
                    : 'A ${formatearDistancia(lejos)} en linea recta · toca '
                          'para tomarla',
                style: TextStyle(
                  fontSize: 12.5,
                  color: v.origen.punto == null
                      ? colores.error
                      : colores.primary,
                ),
              ),
            ],
          ),
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

/// Tomar una vuelta: confirmar con cedula y clave, empezar a grabar y abrir el
/// mapa yendo hacia los vagones.
Future<void> _tomar(BuildContext context, WidgetRef ref, Vuelta v) async {
  final destino = v.origen.punto;
  if (destino == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Esta vuelta no tiene coordenada en SiriusFleet. Pregunta en '
          'despacho donde es antes de tomarla.',
        ),
      ),
    );
    return;
  }

  final confirmada = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _Confirmar(vuelta: v),
  );
  if (confirmada != true || !context.mounted) return;

  await ref
      .read(grabadorProvider.notifier)
      .iniciar(
        nombre: v.nombreViaje,
        destino: PuntoGeo(destino.latitude, destino.longitude),
        destinoNombre: v.origen.corto,
        propiedades: {
          'vuelta_id': v.id,
          'consecutivo': v.consecutivo,
          'jornada': v.jornada.toIso8601String().substring(0, 10),
          'origen': v.origen.codigo,
        },
      );
  if (!context.mounted) return;

  // Reemplaza la lista: volver atras desde el mapa no puede mostrar una lista
  // donde la vuelta que se acaba de tomar sigue apareciendo libre.
  await Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(
      builder: (_) => MapaPage.guaicaramo(
        destinoInicial: LatLng(destino.latitude, destino.longitude),
        nombreDestinoInicial: 'Vagones en ${v.origen.corto}',
        panelSuperior: const PanelViaje(),
      ),
    ),
  );
}

/// La firma: cedula y clave. Si sale bien la vuelta ya quedo anotada en la
/// planilla a nombre del conductor.
class _Confirmar extends ConsumerStatefulWidget {
  const _Confirmar({required this.vuelta});

  final Vuelta vuelta;

  @override
  ConsumerState<_Confirmar> createState() => _ConfirmarState();
}

class _ConfirmarState extends ConsumerState<_Confirmar> {
  final _cedula = TextEditingController();
  final _clave = TextEditingController();
  bool _enviando = false;
  bool _verClave = false;
  String? _error;

  @override
  void dispose() {
    _cedula.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_cedula.text.trim().isEmpty || _clave.text.isEmpty) {
      setState(() => _error = 'Escribe tu cedula y tu clave.');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ref
          .read(apiProvider)
          .confirmarVuelta(
            widget.vuelta.id,
            cedula: _cedula.text.trim(),
            clave: _clave.text,
          );
      if (mounted) Navigator.pop(context, true);
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
    return AlertDialog(
      title: Text('Tomar vuelta #${v.consecutivo}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vas por los vagones en ${v.origen.corto}. Queda anotado en la '
              'planilla a tu nombre, con la hora de salida de ahora.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _cedula,
              enabled: !_enviando,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Cedula',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _clave,
              enabled: !_enviando,
              obscureText: !_verClave,
              onSubmitted: (_) => _enviar(),
              decoration: InputDecoration(
                labelText: 'Clave de GeoMaps',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _verClave = !_verClave),
                  icon: Icon(
                    _verClave ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.pop(context, false),
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
              : const Text('Confirmar'),
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
