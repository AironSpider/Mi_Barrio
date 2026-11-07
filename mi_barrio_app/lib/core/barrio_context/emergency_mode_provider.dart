import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

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
    try {
      final db = await LocalDatabase.instance.database;
      final rows = await db.query('app_settings',
          where: 'key = ?', whereArgs: [_settingKey], limit: 1);
      _local.value = rows.isNotEmpty && rows.first['value'] == '1';
    } catch (_) {
      _local.value = false; // si falla la lectura, la app arranca en modo normal
    }
    _recompute();
  }

  /// El vecino activa/desactiva su vista de emergencia. Se guarda en el teléfono.
  /// Si la junta vecinal la activó, no se puede desactivar desde aquí.
  Future<void> setLocal(bool value) async {
    if (_tenant.value && !value) return;
    _local.value = value;
    _recompute();
    final db = await LocalDatabase.instance.database;
    await db.insert('app_settings', {'key': _settingKey, 'value': value ? '1' : '0'},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Bandera del barrio recibida del servidor (Sprint 8).
  void setTenantFlag(bool value) {
    _tenant.value = value;
    _recompute();
  }

  void _recompute() => _active.value = _local.value || _tenant.value;

  @visibleForTesting
  void resetForTesting() {
    _local.value = false;
    _tenant.value = false;
    _recompute();
  }
}
