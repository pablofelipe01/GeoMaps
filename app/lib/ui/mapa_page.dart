import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../core/ubicacion.dart';
import '../state/sesion.dart';
import '../state/zona_guaicaramo.dart';
import 'capa_parcelas.dart';
import 'capa_vias.dart';

/// La pantalla principal: el mapa.
///
/// Lo unico que no puede faltar nunca en ella es **donde estoy y que tan
/// confiable es ese punto**. El circulo de precision se dibuja siempre, no como
/// opcion: un punto azul sin su radio hace creer que el GPS sabe mas de lo que
/// sabe.
///
/// Esta es la primera version real. Todavia no lee MBTiles del usuario ni
/// guarda trazados; sirve para responder en el telefono las dos preguntas que
/// deciden todo el proyecto: si `flutter_map` rinde con imagen satelital, y si
/// el GPS entrega precision util bajo condiciones de campo.
class MapaPage extends ConsumerStatefulWidget {
  const MapaPage({this.archivoVias, this.archivoParcelas, super.key});

  /// El asset de vias del predio que se esta abriendo, si es que abre uno.
  /// Nulo es el mapa a secas: satelite o calles y la posicion propia.
  final String? archivoVias;

  /// El asset de lotes del predio (bloques y parcelas), si los tiene.
  final String? archivoParcelas;

  @override
  ConsumerState<MapaPage> createState() => _MapaPageState();
}

class _MapaPageState extends ConsumerState<MapaPage> {
  final _mapa = MapController();

  StreamSubscription<Position>? _suscripcion;
  Position? _posicion;
  String? _error;

  /// Si el mapa sigue a la posicion. Se apaga en cuanto el usuario arrastra:
  /// pelear contra un recentrado automatico mientras se mira un lindero es la
  /// forma mas rapida de que alguien cierre la app.
  bool _siguiendo = true;

  CapaBase _capa = CapaBase.satelite;

  /// Las vias del predio se pueden apagar. Sobre un lote recien sembrado, las
  /// lineas tapan justo lo que se fue a mirar.
  bool _verVias = true;

  /// Los linderos de los lotes, igual: se apagan para mirar el cultivo limpio.
  bool _verParcelas = true;

  /// El zoom y el area visible mandan sobre que rotulos se dibujan. Se guardan
  /// aca porque el mapa los reporta por callback, no se pueden leer en el build
  /// antes del primer cuadro.
  double _zoom = 15;
  LatLngBounds? _visible;

  @override
  void initState() {
    super.initState();
    _arrancarGps();
  }

  @override
  void dispose() {
    _suscripcion?.cancel();
    super.dispose();
  }

  Future<void> _arrancarGps() async {
    final permiso = await Ubicacion.pedirPermisos();
    if (!mounted) return;
    if (!permiso.concedido) {
      setState(() => _error = permiso.motivo);
      return;
    }
    setState(() => _error = null);
    _suscripcion = Ubicacion.flujo().listen((p) {
      if (!mounted) return;
      setState(() => _posicion = p);
      if (_siguiendo) {
        _mapa.move(LatLng(p.latitude, p.longitude), _mapa.camera.zoom);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final aqui = _posicion == null
        ? null
        : LatLng(_posicion!.latitude, _posicion!.longitude);

    // Las vias del predio, si esta pantalla abrio uno. Se leen del asset una
    // sola vez por arranque y quedan en memoria.
    final vias = widget.archivoVias == null
        ? null
        : ref.watch(viasPredioProvider(widget.archivoVias!)).valueOrNull;

    final parcelas = widget.archivoParcelas == null
        ? null
        : ref
              .watch(parcelasPredioProvider(widget.archivoParcelas!))
              .valueOrNull;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapa,
            options: MapOptions(
              // Guaicaramo, mientras no haya un fix. Abrir en el Atlantico
              // (0,0) haria creer que el GPS fallo.
              initialCenter: aqui ?? const LatLng(4.28, -72.89),
              initialZoom: 15,
              onPositionChanged: (camara, porGesto) {
                setState(() {
                  _zoom = camara.zoom;
                  _visible = camara.visibleBounds;
                  if (porGesto && _siguiendo) _siguiendo = false;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _capa.url,
                userAgentPackageName: _capa.paquete,
                maxNativeZoom: _capa.zoomMax,
              ),

              // Orden de abajo hacia arriba: imagen, lotes, vias, posicion.
              // Los linderos van primero porque son areas; una via encima de
              // un lindero se ve, un lindero encima de una via lo borra.
              if (parcelas != null && _verParcelas)
                CapaParcelas(
                  parcelas: parcelas,
                  zoom: _zoom,
                  visible: _visible,
                ),

              // Las vias van sobre la imagen y debajo del punto propio: saber
              // donde estoy no lo puede tapar una linea.
              if (vias != null && _verVias) CapaVias(vias: vias),

              if (parcelas != null && _verParcelas)
                RotulosBloque(parcelas: parcelas, zoom: _zoom),

              if (aqui != null) ...[
                // El circulo de precision va SIEMPRE, debajo del punto.
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: aqui,
                      radius: _posicion!.accuracy,
                      useRadiusInMeter: true,
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderColor: Colors.blue.withValues(alpha: 0.4),
                      borderStrokeWidth: 1,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: aqui,
                      width: 22,
                      height: 22,
                      child: const _PuntoPropio(),
                    ),
                  ],
                ),
              ],
            ],
          ),
          _BarraEstado(posicion: _posicion, error: _error),
          if (vias != null && _verVias)
            const Positioned(left: 16, bottom: 32, child: LeyendaVias()),
          Positioned(
            right: 16,
            bottom: 32,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'cuenta',
                  onPressed: () => _mostrarCuenta(context),
                  tooltip: 'Mi cuenta',
                  child: const Icon(Icons.account_circle_outlined),
                ),
                if (parcelas != null) ...[
                  const SizedBox(height: 12),
                  FloatingActionButton.small(
                    heroTag: 'parcelas',
                    onPressed: () =>
                        setState(() => _verParcelas = !_verParcelas),
                    tooltip: _verParcelas
                        ? 'Ocultar los lotes'
                        : 'Ver los lotes (${parcelas.parcelas.length})',
                    child: Icon(_verParcelas ? Icons.grid_on : Icons.grid_off),
                  ),
                ],
                if (vias != null) ...[
                  const SizedBox(height: 12),
                  FloatingActionButton.small(
                    heroTag: 'vias',
                    onPressed: () => setState(() => _verVias = !_verVias),
                    tooltip: _verVias
                        ? 'Ocultar las vias del predio'
                        : 'Ver las vias del predio (${vias.cuantas})',
                    child: Icon(_verVias ? Icons.route : Icons.route_outlined),
                  ),
                ],
                const SizedBox(height: 12),
                FloatingActionButton.small(
                  heroTag: 'capa',
                  onPressed: () => setState(() => _capa = _capa.otra),
                  tooltip: _capa.otra.titulo,
                  child: Icon(_capa.otra.icono),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'centrar',
                  onPressed: aqui == null
                      ? null
                      : () {
                          setState(() => _siguiendo = true);
                          _mapa.move(aqui, 17);
                        },
                  tooltip: 'Centrar en mi posicion',
                  child: Icon(
                    _siguiendo ? Icons.my_location : Icons.location_searching,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Quien esta conectado y cuanto le queda de sesion.
  ///
  /// Los dias restantes se muestran porque son el dato que decide si alguien
  /// puede salir tranquilo a una semana de campo. Enterarse de que la sesion
  /// vencio estando en el lote es justo lo que hay que evitar.
  void _mostrarCuenta(BuildContext context) {
    final sesion = ref.read(sesionProvider).sesion;
    if (sesion == null) return;

    showModalBottomSheet<void>(
      context: context,
      builder: (hoja) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: sesion.foto != null
                  ? CircleAvatar(backgroundImage: NetworkImage(sesion.foto!))
                  : const CircleAvatar(child: Icon(Icons.person)),
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
          ],
        ),
      ),
    );
  }
}

/// Las dos formas de mirar el terreno.
///
/// No sobra ninguna: el satelite muestra el cultivo, la ronda del cano y donde
/// termina el potrero, lo que un mapa de calles nunca va a mostrar, pero se
/// pierde para ubicarse porque no tiene nombres. Las calles tienen la via y el
/// caserio y no tienen ni un arbol. En campo se alterna entre las dos.
///
/// Ninguna pide llave ni cuenta.
enum CapaBase {
  satelite(
    'Satelite',
    Icons.satellite_alt,
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    // Esri no sirve teselas nativas mas alla de z19 en zona rural. Sin este
    // tope, acercarse mas deja la pantalla en gris en vez de escalar la ultima.
    19,
  ),
  calles(
    'Calles',
    Icons.map_outlined,
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    19,
  );

  const CapaBase(this.titulo, this.icono, this.url, this.zoomMax);

  final String titulo;
  final IconData icono;
  final String url;
  final int zoomMax;

  CapaBase get otra => this == satelite ? calles : satelite;

  /// La regla de uso del servidor publico de OSM pide identificar la app en el
  /// user agent.
  String get paquete => 'com.siriusregenerative.geomaps';
}

class _PuntoPropio extends StatelessWidget {
  const _PuntoPropio();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
      ),
    );
  }
}

/// La barra de arriba. Dice la precision en metros, que es el dato que decide
/// si lo que se esta levantando sirve para un lindero o solo para ubicarse.
class _BarraEstado extends StatelessWidget {
  const _BarraEstado({required this.posicion, required this.error});

  final Position? posicion;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final String texto;
    final Color color;

    if (error != null) {
      texto = error!;
      color = Colors.red.shade700;
    } else if (posicion == null) {
      texto = 'Buscando senal GPS...';
      color = Colors.orange.shade800;
    } else {
      final p = posicion!;
      texto =
          '${p.latitude.toStringAsFixed(6)}, '
          '${p.longitude.toStringAsFixed(6)}   '
          '+/- ${p.accuracy.toStringAsFixed(0)} m';
      // El umbral no es cosmetico: por encima de 10 m el punto no sirve para
      // marcar un vertice de lindero, y quien lo marca tiene que verlo en el
      // momento, no descubrirlo despues en la oficina.
      color = p.accuracy <= 10 ? Colors.green.shade800 : Colors.orange.shade800;
    }

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          // Fondo solido y no translucido: la app se usa a pleno sol y un
          // control semitransparente sobre imagen satelital no se ve.
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.gps_fixed, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                texto,
                style: const TextStyle(
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
