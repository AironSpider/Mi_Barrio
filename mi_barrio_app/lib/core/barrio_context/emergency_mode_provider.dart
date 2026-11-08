import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../auth/auth_session_store.dart';
import '../database_sqlite/sqlite_database.dart';

/// Estado global del Modo Emergencia.
///
/// Estado efectivo = toggle local del vecino **O** bandera del barrio
/// (`tenants.is_emergency_active`, llega por el pull en el Sprint 8).
/// Si la bandera del barrio está activa, el toggle del vecino queda bloqueado.
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

  static const _settingKey = 'emergency_local_toggle';

  /// Última bandera del barrio recibida (`tenantId|1` o `tenantId|0`).
  /// Se guarda para que, si la app se reinicia SIN señal en plena emergencia,
  /// siga en modo emergencia (antes volvía a verde hasta el próximo pull).
  static const _tenantFlagKey = 'emergency_tenant_flag';

  final ValueNotifier<bool> _local = ValueNotifier(false);
  final ValueNotifier<bool> _tenant = ValueNotifier(false);
  final ValueNotifier<bool> _active = ValueNotifier(false);

  /// true si la app debe mostrarse en Modo Emergencia.
  ValueListenable<bool> get isActive => _active;

  /// true si la emergencia la activó la junta vecinal (toggle bloqueado:
  /// "Activada por tu junta vecinal").
  ValueListenable<bool> get isLockedByTenant => _tenant;

  bool get localToggle => _local.value;

  /// Carga el toggle guardado. Llamar una vez al iniciar la app.
  Future<void> load() async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [_settingKey],
      limit: 1,
    );
    _local.value = rows.isNotEmpty && rows.first['value'] == '1';
    _tenant.value = await _storedTenantFlag(db);
    _recompute();
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

  /// El vecino activa/desactiva su vista de emergencia. Se guarda en el teléfono.
  /// Si la junta vecinal la activó, no se puede desactivar desde aquí.
  Future<void> setLocal(bool value) async {
    if (_tenant.value && !value) return;
    final db = await LocalDatabase.instance.database;
    await db.insert('app_settings', {
      'key': _settingKey,
      'value': value ? '1' : '0',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _local.value = value;
    _recompute();
  }

  /// Bandera del barrio recibida del servidor (Sprint 8).
  /// Con [tenantId] además se guarda en el teléfono (ver [_tenantFlagKey]).
  Future<void> setTenantFlag(bool value, {String? tenantId}) async {
    _tenant.value = value;
    _recompute();
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

  void _recompute() => _active.value = _local.value || _tenant.value;

  @visibleForTesting
  void resetForTesting() {
    _local.value = false;
    _tenant.value = false;
    _recompute();
  }
}
