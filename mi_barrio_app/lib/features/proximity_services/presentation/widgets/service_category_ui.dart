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
    ServiceCategory.albanileria: Icons.foundation_rounded,
    ServiceCategory.pintura: Icons.format_paint_rounded,
    ServiceCategory.mecanica: Icons.car_repair_rounded,
    ServiceCategory.tecnologia: Icons.phone_android_rounded,
    ServiceCategory.costura: Icons.checkroom_rounded,
    ServiceCategory.belleza: Icons.content_cut_rounded,
    ServiceCategory.limpieza: Icons.cleaning_services_rounded,
    ServiceCategory.lavanderia: Icons.local_laundry_service_rounded,
    ServiceCategory.jardineria: Icons.yard_rounded,
    ServiceCategory.mudanza: Icons.local_shipping_rounded,
    ServiceCategory.comida: Icons.restaurant_rounded,
    ServiceCategory.bodega: Icons.storefront_rounded,
    ServiceCategory.cuidado: Icons.family_restroom_rounded,
    ServiceCategory.salud: Icons.medical_services_rounded,
    ServiceCategory.otros: Icons.handyman_rounded,
  };

  static IconData icon(String category) =>
      _icons[category] ?? Icons.handyman_rounded;

  /// Etiqueta para chips y tarjetas pequeñas ("Mascotas" en vez de
  /// "Paseador de mascotas").
  static const _short = <String, String>{
    ServiceCategory.paseadorMascotas: 'Mascotas',
    ServiceCategory.tecnologia: 'Celulares y PC',
    ServiceCategory.belleza: 'Belleza',
    ServiceCategory.mudanza: 'Mudanzas',
    ServiceCategory.cuidado: 'Cuidado',
    ServiceCategory.soporteEmergencia: 'Emergencia',
  };

  static String shortLabel(String category) =>
      _short[category] ?? ServiceCategory.labels[category] ?? category;
}
