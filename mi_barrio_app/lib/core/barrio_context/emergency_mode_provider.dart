import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../auth/auth_session_store.dart';
import '../database_sqlite/sqlite_database.dart';

/// Estado global del Modo Emergencia.
///
/// Estado efectivo = bandera del barrio (la activa la junta vecinal:
/// `tenants.is_emergency_active`, llega por el pull) **o** el interruptor ⚠
/// del vecino (solo cambia SU vista: tema naranja, filtros de emergencia y el
/// botón "Ayuda"; no avisa a nadie). Si la junta la activó, el interruptor
/// queda bloqueado en encendido.
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

  /// Interruptor ⚠ del vecino (se recuerda en el teléfono).
  static const _localFlagKey = 'emergency_local_toggle';

  final ValueNotifier<bool> _active = ValueNotifier(false);
  final ValueNotifier<bool> _tenant = ValueNotifier(false);
  bool _local = false;

  /// true si la app debe mostrarse en Modo Emergencia.
  ValueListenable<bool> get isActive => _active;

  /// true si la emergencia la activó la junta vecinal (interruptor bloqueado).
  ValueListenable<bool> get isLockedByTenant => _tenant;

  /// Lo que eligió el vecino en el interruptor ⚠.
  bool get localToggle => _local;

  void _recompute() => _active.value = _tenant.value || _local;

  /// Carga la última bandera guardada. Llamar una vez al iniciar la app.
  Future<void> load() async {
    final db = await LocalDatabase.instance.database;
    _tenant.value = await _storedTenantFlag(db);
    try {
      final rows = await db.query('app_settings',
          where: 'key = ?', whereArgs: [_localFlagKey], limit: 1);
      _local = rows.isNotEmpty && rows.first['value'] == '1';
    } catch (_) {
      _local = false;
    }
    _recompute();
  }

  /// Interruptor ⚠ de la barra superior. No hace nada si la junta ya activó
  /// la emergencia (queda encendido).
  Future<void> setLocal(bool value) async {
    _local = value;
    _recompute();
    try {
      final db = await LocalDatabase.instance.database;
      await db.insert('app_settings', {
        'key': _localFlagKey,
        'value': value ? '1' : '0',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {
      // Si no se pudo guardar, el estado en memoria ya cambió igual.
    }
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

  @visibleForTesting
  void resetForTesting() {
    _local = false;
    _tenant.value = false;
    _active.value = false;
  }
}
