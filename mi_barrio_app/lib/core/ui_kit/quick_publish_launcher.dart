import 'package:flutter/material.dart';

import '../barrio_context/tenant_session.dart';
import '../../features/emergency_support/presentation/providers/emergency_provider.dart';
import '../../features/solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import 'done_confirmation.dart';
import 'quick_publish_modal.dart';

class QuickPublishLauncher {
  QuickPublishLauncher._();

  static final SolidaritySqliteDatasource _datasource =
      SolidaritySqliteDatasource();

  static Future<bool> open(
    BuildContext context, {
    required bool isEmergencyMode,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    return showQuickPublishModal(
      context,
      isEmergencyMode: isEmergencyMode,
      onPublish: (datos) async {
        // Ubicación real para el mapa del barrio (GPS); sin GPS, el centro.
        final ubicacion = await HelpLocator.resolve();
        await _datasource.publishInThreeClicks(
          tenantId: TenantSession.instance.tenantId,
          authorUserId: TenantSession.instance.userId,
          modality: datos.modality,
          title: datos.title,
          lat: ubicacion.lat,
          lng: ubicacion.lng,
          flowType: datos.flowType,
          isEmergencyContext: datos.isEmergencyContext,
          photoB64: datos.photoB64,
        );
        DoneConfirmation.show(
          messenger,
          'Tu publicación ya está en el muro. Se enviará sola cuando haya señal.',
        );
      },
    );
  }
}
