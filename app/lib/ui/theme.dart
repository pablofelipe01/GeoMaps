import 'package:flutter/material.dart';

/// El tema Sirius.
///
/// Un ajuste propio de GeoMaps: la app se usa a pleno sol en un potrero, asi
/// que los controles sobre el mapa van con fondo solido y contraste alto, no
/// con la superficie translucida de Material 3. Un boton semitransparente sobre
/// una imagen satelital no se ve al mediodia.
///
/// TODO(marca): traer de sirius_agro la paleta Sirius y la Museo Slab. Mientras
/// tanto, el verde de semilla mantiene la app legible sin mentir sobre la marca.
final ThemeData temaSirius = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B5E20)),
);
