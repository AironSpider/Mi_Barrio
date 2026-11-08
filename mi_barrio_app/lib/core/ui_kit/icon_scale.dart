import 'package:flutter/widgets.dart';

/// Cuánto crecen los íconos con la letra del teléfono (1 a 1,6 veces).
///
/// Con "tamaño de fuente" grande el texto crece pero los íconos no: un adulto
/// mayor veía palabras enormes junto a íconos diminutos.
double escalaIcono(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6).toDouble();
