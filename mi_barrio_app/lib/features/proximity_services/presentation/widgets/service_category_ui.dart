import 'package:flutter/material.dart';

import '../../data/models/service_model.dart';

/// Ícono y etiqueta corta de cada categoría de oficio (un solo lugar para
/// el directorio, el detalle y "Ofrecer servicio").
class ServiceCategoryUi {
  ServiceCategoryUi._();

  static const _icons = <String, IconData>{
    ServiceCategory.gasfiteria: Icons.plumbing_rounded,
    ServiceCategory.carpinteria: Icons.carpenter_rounded,
    ServiceCategory.electricidad: Icons.electrical_services_rounded,
    ServiceCategory.paseadorMascotas: Icons.pets_rounded,
    ServiceCategory.clases: Icons.school_rounded,
    ServiceCategory.cerrajeria: Icons.key_rounded,
    ServiceCategory.soporteEmergencia: Icons.health_and_safety_rounded,
  };

  static IconData icon(String category) =>
      _icons[category] ?? Icons.handyman_rounded;

  /// Etiqueta para chips y tarjetas pequeñas ("Mascotas" en vez de
  /// "Paseador de mascotas").
  static String shortLabel(String category) =>
      category == ServiceCategory.paseadorMascotas
      ? 'Mascotas'
      : ServiceCategory.labels[category] ?? category;
}
