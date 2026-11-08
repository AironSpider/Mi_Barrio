import 'package:flutter/material.dart';

import '../barrio_context/tenant_session.dart';
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
        await _datasource.publishInThreeClicks(
          tenantId: TenantSession.instance.tenantId,
          authorUserId: TenantSession.instance.userId,
          modality: datos.modality,
          title: datos.title,
          lat: TenantSession.instance.centerLat,
          lng: TenantSession.instance.centerLng,
          flowType: datos.flowType,
          isEmergencyContext: datos.isEmergencyContext,
        );
        DoneConfirmation.show(
          messenger,
          'Tu publicación ya está en el muro. Se enviará sola cuando haya señal.',
        );
      },
    );
  }
}
