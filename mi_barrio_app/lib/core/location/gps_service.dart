import 'package:geolocator/geolocator.dart';

/// Por qué no se pudo obtener la ubicación.
enum GpsError {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  permissionRestricted,
  invalidCoordinates,
}

/// Error del GPS con su motivo ([GpsError]) y un mensaje para mostrar.
class GpsException implements Exception {
  const GpsException(this.reason);

  final GpsError reason;

  @override
  String toString() => switch (reason) {
    GpsError.serviceDisabled => 'Los servicios de ubicación están apagados.',
    GpsError.permissionDenied => 'Se denegó el permiso de ubicación.',
    GpsError.permissionDeniedForever =>
      'El permiso de ubicación está bloqueado en los ajustes del dispositivo.',
    GpsError.permissionRestricted =>
      'El dispositivo no permite acceder a la ubicación.',
    GpsError.invalidCoordinates =>
      'El sensor devolvió coordenadas fuera de rango.',
  };
}

/// Un punto en el mapa (latitud y longitud) obtenido del GPS.
class GpsCoordinates {
  const GpsCoordinates({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
}

/// ¿Está encendido el GPS? (funciones del GPS reemplazables en las pruebas)
typedef LocationServiceCheck = Future<bool> Function();
/// Pide o consulta el permiso de ubicación.
typedef LocationPermissionCheck = Future<LocationPermission> Function();
/// Pide la posición actual al GPS.
typedef CurrentPositionRequest = Future<Position> Function({
  LocationSettings? locationSettings,
});

/// Obtiene la ubicación del sensor nativo; no necesita conexión a internet.
class GpsService {
  GpsService({
    LocationServiceCheck? isLocationServiceEnabled,
    LocationPermissionCheck? checkPermission,
    LocationPermissionCheck? requestPermission,
    CurrentPositionRequest? getCurrentPosition,
  }) : _isLocationServiceEnabled =
           isLocationServiceEnabled ?? Geolocator.isLocationServiceEnabled,
       _checkPermission = checkPermission ?? Geolocator.checkPermission,
       _requestPermission = requestPermission ?? Geolocator.requestPermission,
       _getCurrentPosition =
           getCurrentPosition ?? Geolocator.getCurrentPosition;

  final LocationServiceCheck _isLocationServiceEnabled;
  final LocationPermissionCheck _checkPermission;
  final LocationPermissionCheck _requestPermission;
  final CurrentPositionRequest _getCurrentPosition;

  Future<GpsCoordinates> getCurrentCoordinates({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration timeLimit = const Duration(seconds: 20),
  }) async {
    if (!await _isLocationServiceEnabled()) {
      throw const GpsException(GpsError.serviceDisabled);
    }

    var permission = await _checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _requestPermission();
    }
    switch (permission) {
      case LocationPermission.denied:
        throw const GpsException(GpsError.permissionDenied);
      case LocationPermission.deniedForever:
        throw const GpsException(GpsError.permissionDeniedForever);
      case LocationPermission.unableToDetermine:
        throw const GpsException(GpsError.permissionRestricted);
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        break;
    }

    final position = await _getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        timeLimit: timeLimit,
      ),
    );
    if (!position.latitude.isFinite ||
        position.latitude < -90 ||
        position.latitude > 90 ||
        !position.longitude.isFinite ||
        position.longitude < -180 ||
        position.longitude > 180) {
      throw const GpsException(GpsError.invalidCoordinates);
    }

    return GpsCoordinates(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    );
  }
}
