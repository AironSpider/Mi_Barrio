import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_barrio_app/features/auth_barrio/data/datasources/auth_remote_datasource.dart';

void main() {
  test(
    'login normalizes email and current-user sends the Bearer token',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/login')) {
          expect(jsonDecode(request.body), {
            'email': 'vecina@example.com',
            'password': 'password123',
          });
          return http.Response('{}', 200);
        }
        return http.Response(
          jsonEncode({'id': 'user-1', 'role': 'VECINO'}),
          200,
        );
      });
      final datasource = AuthRemoteDatasource(
        baseUrl: 'http://localhost:8000',
        client: client,
      );

      await datasource.login(
        email: ' Vecina@Example.com ',
        password: 'password123',
      );
      await datasource.getCurrentUser('signed-token');

      expect(requests[1].url.path, '/api/v1/auth/me');
      expect(requests[1].headers['Authorization'], 'Bearer signed-token');
    },
  );

  test('remote errors expose the server message and status code', () async {
    final datasource = AuthRemoteDatasource(
      baseUrl: 'http://localhost:8000',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'detail': 'Correo o contraseña incorrectos'}),
          401,
        ),
      ),
    );

    await expectLater(
      datasource.login(email: 'a@b.com', password: 'password123'),
      throwsA(
        isA<AuthException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having(
              (error) => error.message,
              'message',
              'Correo o contraseña incorrectos',
            ),
      ),
    );
  });

  test('timeout explains the server may be waking up (Render free)', () async {
    final datasource = AuthRemoteDatasource(
      baseUrl: 'https://example.onrender.com',
      client: MockClient((_) async {
        throw TimeoutException('request timed out');
      }),
    );

    await expectLater(
      datasource.register(
        fullName: 'Vecina',
        email: 'vecina@example.com',
        password: 'password123',
        role: 'VECINO',
        joinCode: 'BARRIO-01',
        acceptedTerms: true,
      ),
      throwsA(
        isA<AuthException>().having(
          (error) => error.message,
          'message',
          contains('despertando'),
        ),
      ),
    );
  });

  test('no connection asks to check mobile data or Wi-Fi', () async {
    final datasource = AuthRemoteDatasource(
      baseUrl: 'https://example.onrender.com',
      client: MockClient((_) async {
        throw http.ClientException('Failed host lookup');
      }),
    );

    await expectLater(
      datasource.login(email: 'a@b.com', password: 'password123'),
      throwsA(
        isA<AuthException>()
            .having((error) => error.message, 'message', contains('datos móviles o el Wi-Fi'))
            .having((error) => error.statusCode, 'statusCode', isNull),
      ),
    );
  });
}
