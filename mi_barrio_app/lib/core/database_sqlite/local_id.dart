import 'package:uuid/uuid.dart';

/// Identificadores generados en el teléfono, sin red.
///
/// UUID v4 con generador criptográfico (`Random.secure`, el valor por defecto
/// del paquete `uuid`): 122 bits aleatorios, por lo que dos vecinos offline
/// no generan el mismo id al sincronizar con PostgreSQL.
class LocalId {
  LocalId._();

  static const _uuid = Uuid();

  static final _v4Pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  static final _anyUuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  /// Nuevo UUID v4 en minúsculas (formato que acepta PostgreSQL).
  static String generate() => _uuid.v4();

  /// true si [value] es un UUID v4 válido.
  static bool isValidV4(String value) => _v4Pattern.hasMatch(value);

  /// true si [value] tiene formato UUID (cualquier versión). Útil para
  /// `tenant_id` / `user_id` que puede crear el servidor.
  static bool isUuid(String value) => _anyUuidPattern.hasMatch(value);

  /// Lanza [ArgumentError] si [value] no es un UUID.
  static void requireUuid(String value, String fieldName) {
    if (!isUuid(value)) {
      throw ArgumentError.value(value, fieldName, 'Debe ser un UUID válido');
    }
  }
}
