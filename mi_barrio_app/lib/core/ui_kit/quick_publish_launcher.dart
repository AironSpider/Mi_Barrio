import 'package:flutter/material.dart';

import '../../features/solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import 'quick_publish_modal.dart';

class QuickPublishLauncher {
  QuickPublishLauncher._();

  static const String _tenantIdTemporal =
      'a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d';
  static const String _usuarioIdTemporal =
      '5f3a2c1b-1234-4abc-9def-0123456789ab';
  static const double _latTemporal = -5.1945;
  static const double _lngTemporal = -80.6328;

  static final SolidaritySqliteDatasource _datasource =
      SolidaritySqliteDatasource();

  static Future<void> open(
    BuildContext context, {
    required bool isEmergencyMode,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    return showQuickPublishModal(
      context,
      isEmergencyMode: isEmergencyMode,
      onPublish: (datos) async {
        await _datasource.publishInThreeClicks(
          tenantId: _tenantIdTemporal,
          authorUserId: _usuarioIdTemporal,
          modality: datos.modality,
          title: datos.title,
          lat: _latTemporal,
          lng: _lngTemporal,
          flowType: datos.flowType,
          isEmergencyContext: datos.isEmergencyContext,
        );
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Guardado en el teléfono')),
          );
      },
    );
  }
}
