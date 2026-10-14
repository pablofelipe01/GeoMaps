import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'vueltas.dart';
import 'vueltas_page.dart';

/// La camara apuntando al QR de vueltas pendientes que imprime SiriusFleet.
///
/// En cuanto lee el QR correcto pasa a la lista, sin boton de por medio: quien
/// escanea esta de pie en el patio con el telefono en una mano.
class EscanearPage extends StatefulWidget {
  const EscanearPage({super.key});

  @override
  State<EscanearPage> createState() => _EscanearPageState();
}

class _EscanearPageState extends State<EscanearPage> {
  final _camara = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    // Un solo aviso por QR: la camara lee el mismo codigo varias veces por
    // segundo, y sin esto saldria un mensaje encima de otro.
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _listo = false;

  @override
  void dispose() {
    _camara.dispose();
    super.dispose();
  }

  void _alLeer(BarcodeCapture captura) {
    if (_listo) return;
    for (final codigo in captura.barcodes) {
      final texto = codigo.rawValue;
      if (texto == null) continue;
      if (esQrDeVueltas(texto)) {
        _listo = true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const VueltasPage()),
        );
        return;
      }
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Ese QR no es el de vueltas pendientes. Busca el que dice '
            '"QR · vueltas pendientes" en despacho.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear QR')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _camara,
            onDetect: _alLeer,
            errorBuilder: (context, error) => _SinCamara(error: error),
          ),
          // El recuadro dice donde poner el QR. Sin el, la gente acerca el
          // telefono hasta que el codigo no entra entero en la imagen.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              'Apunta al QR de vueltas pendientes',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                shadows: [Shadow(blurRadius: 6, color: Colors.black)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SinCamara extends StatelessWidget {
  const _SinCamara({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final sinPermiso =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            sinPermiso
                ? 'GeoMaps no tiene permiso para usar la camara. Activalo en '
                      'los ajustes del telefono para escanear el QR.'
                : 'No se pudo abrir la camara.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        ),
      ),
    );
  }
}
