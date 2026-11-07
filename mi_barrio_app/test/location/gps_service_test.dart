import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mi_barrio_app/core/location/gps_service.dart';

Position testPosition({
  double latitude = -5.1945,
  double longitude = -80.6328,
}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime.utc(2026, 11, 7),
  accuracy: 8,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  group('GpsService', () {
    test(
      'obtiene coordenadas con el sensor nativo sin requerir internet',
      () async {
        LocationSettings? requestedSettings;
        final service = GpsService(
          isLocationServiceEnabled: () async => true,
          checkPermission: () async => LocationPermission.whileInUse,
          getCurrentPosition: ({locationSettings}) async {
            requestedSettings = locationSettings;
            return testPosition();
          },
        );

        final coordinates = await service.getCurrentCoordinates(
          timeLimit: const Duration(seconds: 5),
        );

        expect(coordinates.latitude, -5.1945);
        expect(coordinates.longitude, -80.6328);
        expect(coordinates.accuracy, 8);
        expect(requestedSettings?.accuracy, LocationAccuracy.high);
        expect(requestedSettings?.timeLimit, const Duration(seconds: 5));
      },
    );

    test('solicita permiso si aún no fue concedido', () async {
      var requested = false;
      final service = GpsService(
        isLocationServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.denied,
        requestPermission: () async {
          requested = true;
          return LocationPermission.whileInUse;
        },
        getCurrentPosition: ({locationSettings}) async => testPosition(),
      );

      await service.getCurrentCoordinates();

      expect(requested, isTrue);
    });

    test('explica cuando la ubicación del dispositivo está apagada', () async {
      final service = GpsService(
        isLocationServiceEnabled: () async => false,
        checkPermission: () async => LocationPermission.whileInUse,
      );

      await expectLater(
        service.getCurrentCoordinates(),
        throwsA(
          isA<GpsException>().having(
            (error) => error.reason,
            'reason',
            GpsError.serviceDisabled,
          ),
        ),
      );
    });

    test('explica cuando el permiso fue denegado permanentemente', () async {
      final service = GpsService(
        isLocationServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.deniedForever,
      );

      await expectLater(
        service.getCurrentCoordinates(),
        throwsA(
          isA<GpsException>().having(
            (error) => error.reason,
            'reason',
            GpsError.permissionDeniedForever,
          ),
        ),
      );
    });

    test('rechaza coordenadas fuera de rango', () async {
      final service = GpsService(
        isLocationServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.always,
        getCurrentPosition: ({locationSettings}) async =>
            testPosition(longitude: 181),
      );

      await expectLater(
        service.getCurrentCoordinates(),
        throwsA(
          isA<GpsException>().having(
            (error) => error.reason,
            'reason',
            GpsError.invalidCoordinates,
          ),
        ),
      );
    });
  });
}
