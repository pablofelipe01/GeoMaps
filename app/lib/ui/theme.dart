import 'package:flutter/material.dart';

/// El tema Sirius. Portado de sirius_agro.
///
/// Un ajuste propio de GeoMaps: la app se usa a pleno sol en un potrero, asi
/// que los controles sobre el mapa van con fondo solido y contraste alto, no
/// con la superficie translucida de Material 3. Un boton semitransparente
/// sobre una imagen satelital no se ve al mediodia.
final ThemeData temaSirius = ThemeData(
  useMaterial3: true,
  fontFamily: 'MuseoSlab',
  // TODO: portar la paleta Sirius de sirius_agro/app/lib/ui/theme.dart
);
