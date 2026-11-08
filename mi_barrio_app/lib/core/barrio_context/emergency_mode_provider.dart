import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../auth/auth_session_store.dart';
import '../database_sqlite/sqlite_database.dart';

/// Estado global del Modo Emergencia: lo activa la junta vecinal
/// (`tenants.is_emergency_active`, llega por el pull) y vale para todo el barrio.
///
/// Uso en la UI:
/// ```dart
/// ValueListenableBuilder<bool>(
///   valueListenable: EmergencyModeProvider.instance.isActive,
///   builder: (_, active, __) => ...,
/// )
/// ```
class EmergencyModeProvider {
  EmergencyModeProvider._();
  static final EmergencyModeProvider instance = EmergencyModeProvider._();

  /// Última bandera del barrio recibida (`tenantId|1` o `tenantId|0`).
  /// Se guarda para que, si la app se reinicia SIN señal en plena emergencia,
  /// siga en modo emergencia (antes volvía a verde hasta el próximo pull).
  static const _tenantFlagKey = 'emergency_tenant_flag';

  final ValueNotifier<bool> _active = ValueNotifier(false);

  /// true si la app debe mostrarse en Modo Emergencia.
  ValueListenable<bool> get isActive => _active;

  /// Carga la última bandera guardada. Llamar una vez al iniciar la app.
  Future<void> load() async {
    final db = await LocalDatabase.instance.database;
    _active.value = await _storedTenantFlag(db);
  }

  /// La bandera guardada vale solo si es del barrio de la sesión guardada
  /// (otro vecino de otro barrio en el mismo teléfono no la hereda).
  Future<bool> _storedTenantFlag(Database db) async {
    try {
      final rows = await db.query('app_settings',
          where: 'key = ?', whereArgs: [_tenantFlagKey], limit: 1);
      final parts = (rows.isEmpty ? null : rows.first['value'] as String?)?.split('|');
      if (parts == null || parts.length != 2 || parts[1] != '1') return false;
      final session = await AuthSessionStore.instance.read();
      return session != null && session['tenant_id'] == parts[0];
    } catch (_) {
      return false;
    }
  }

  /// Bandera del barrio recibida del servidor.
  /// Con [tenantId] además se guarda en el teléfono (ver [_tenantFlagKey]).
  Future<void> setTenantFlag(bool value, {String? tenantId}) async {
    _active.value = value;
    if (tenantId == null) return;
    try {
      final db = await LocalDatabase.instance.database;
      await db.insert('app_settings', {
        'key': _tenantFlagKey,
        'value': '$tenantId|${value ? 1 : 0}',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {
      // Si no se pudo guardar, el estado en memoria ya cambió igual.
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _active.value = false;
  }
}
