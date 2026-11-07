import 'local_id.dart';

/// Validaciones comunes antes de escribir en SQLite.
///
/// Rechazan datos que el backend no aceptaría: así un registro inválido no se
/// queda atascado en la cola de sincronización para siempre.
class RecordValidation {
  RecordValidation._();

  static void uuid(String value, String field) => LocalId.requireUuid(value, field);

  static void oneOf(String value, Set<String> allowed, String field) {
    if (!allowed.contains(value)) {
      throw ArgumentError.value(
          value, field, 'Valor no permitido. Opciones: ${allowed.join(', ')}');
    }
  }

  /// Devuelve el texto sin espacios sobrantes; falla si queda vacío o largo.
  static String requiredText(String value, String field, {required int maxLength}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(value, field, 'No puede estar vacío');
    }
    if (trimmed.length > maxLength) {
      throw ArgumentError.value(
          value, field, 'Máximo $maxLength caracteres (tiene ${trimmed.length})');
    }
    return trimmed;
  }

  static void coordinates(double lat, double lng) {
    if (lat.isNaN || lat < -90 || lat > 90) {
      throw ArgumentError.value(lat, 'lat', 'Latitud fuera de rango (-90 a 90)');
    }
    if (lng.isNaN || lng < -180 || lng > 180) {
      throw ArgumentError.value(lng, 'lng', 'Longitud fuera de rango (-180 a 180)');
    }
  }
}
