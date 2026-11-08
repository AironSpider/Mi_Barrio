import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_barrio_app/core/network/api_client.dart';
import 'package:mi_barrio_app/features/auth_barrio/data/datasources/auth_remote_datasource.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/datasources/solidarity_remote_ds.dart';

/// Pruebas profundas de la capa de red: qué se envía al servidor y cómo se
/// explican los errores (sin red, servidor caído, respuestas raras).
void main() {
  group('ApiClient.decodeOrThrow', () {
    test('2xx devuelve el JSON', () {
      expect(ApiClient.decodeOrThrow(http.Response('{"a": 1}', 200)), {'a': 1});
    });

    test('error con "detail" muestra ese mensaje', () {
      expect(
        () => ApiClient.decodeOrThrow(
          http.Response('{"detail": "No encontrado"}', 404),
        ),
        throwsA(predicate((e) => e.toString().contains('No encontrado'))),
      );
    });

    test('error con "error" (formato del backend) también se muestra', () {
      expect(
        () => ApiClient.decodeOrThrow(
          http.Response('{"success": false, "error": "Datos inválidos"}', 422),
        ),
        throwsA(predicate((e) => e.toString().contains('Datos inválidos'))),
      );
    });

    test('un 500 con HTML no rompe: mensaje genérico', () {
      expect(
        () => ApiClient.decodeOrThrow(http.Response('<html>502</html>', 502)),
        throwsA(
          predicate(
            (e) => e.toString().contains('No se pudo completar la acción'),
          ),
        ),
      );
    });
  });

  group('AuthRemoteDatasource', () {
    AuthRemoteDatasource remote(
      Future<http.Response> Function(http.Request) handler,
    ) => AuthRemoteDatasource(baseUrl: 'http://api', client: MockClient(handler));

    test('login normaliza el correo antes de enviarlo', () async {
      late Map<String, dynamic> body;
      await remote((r) async {
        body = jsonDecode(r.body) as Map<String, dynamic>;
        return http.Response('{"access_token": "t"}', 200);
      }).login(email: '  Rosa@Correo.COM ', password: 'Clave123');
      expect(body['email'], 'rosa@correo.com');
      expect(body['password'], 'Clave123', reason: 'la contraseña no se toca');
    });

    test('registro: código del barrio en mayúsculas y nombre sin espacios', () async {
      late Map<String, dynamic> body;
      await remote((r) async {
        body = jsonDecode(r.body) as Map<String, dynamic>;
        return http.Response('{}', 201);
      }).register(
        fullName: '  Rosa Calle ',
        email: 'rosa@correo.com',
        password: 'Clave123',
        role: 'VECINO',
        joinCode: ' barrio-01 ',
        acceptedTerms: true,
      );
      expect(body['full_name'], 'Rosa Calle');
      expect(body['join_code'], 'BARRIO-01');
      expect(body['accept_terms'], isTrue, reason: 'sin esto el servidor no crea la cuenta');
    });

    test('credenciales malas: el mensaje del servidor y su código', () async {
      expect(
        () => remote(
          (_) async => http.Response(
            '{"detail": "El correo o la contraseña no coinciden"}',
            401,
          ),
        ).login(email: 'a@b.com', password: 'x'),
        throwsA(
          isA<AuthException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', contains('no coinciden')),
        ),
      );
    });

    test('sin internet: explica que revise datos o Wi-Fi', () async {
      expect(
        () => remote(
          (_) async => throw const SocketException('sin red'),
        ).login(email: 'a@b.com', password: 'x'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('Wi-Fi'),
          ),
        ),
      );
    });

    test('servidor dormido (timeout): pide esperar y reintentar', () async {
      expect(
        () => remote(
          (_) async => throw TimeoutException('lento'),
        ).login(email: 'a@b.com', password: 'x'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('despertando'),
          ),
        ),
      );
    });

    test('respuesta que no es JSON: dice el código del servidor', () async {
      expect(
        () => remote(
          (_) async => http.Response('Bad Gateway', 502),
        ).login(email: 'a@b.com', password: 'x'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('502'),
          ),
        ),
      );
    });

    test('código de barrio inexistente devuelve null (no es un error)', () async {
      final name = await remote(
        (_) async => http.Response('{"detail": "no"}', 404),
      ).lookupNeighborhoodName('nada');
      expect(name, isNull);
    });

    test('código de barrio válido devuelve el nombre limpio', () async {
      late Uri asked;
      final name = await remote((r) async {
        asked = r.url;
        return http.Response('{"name": "  Barrio Norte "}', 200);
      }).lookupNeighborhoodName(' barrio-01 ');
      expect(name, 'Barrio Norte');
      expect(asked.path, '/api/v1/tenants/by-code/BARRIO-01');
    });
  });

  group('SolidarityRemoteDatasource', () {
    SolidarityRemoteDatasource remote(
      Future<http.Response> Function(http.Request) handler,
    ) => SolidarityRemoteDatasource(
      api: ApiClient(baseUrl: 'http://api', client: MockClient(handler)),
    );

    test('fotos: usa la ruta nueva de varias fotos', () async {
      final photos = await remote((r) async {
        expect(r.headers['X-Tenant-ID'], 't1');
        return http.Response('{"photos": ["a", "", "b"]}', 200);
      }).fetchPhotos('t1', 'p1');
      expect(photos, ['a', 'b'], reason: 'las vacías se descartan');
    });

    test('fotos: si el servidor es anterior, usa la de una sola foto', () async {
      final photos = await remote((r) async {
        if (r.url.path.endsWith('/photos')) return http.Response('', 404);
        return http.Response('{"photo_b64": "unica"}', 200);
      }).fetchPhotos('t1', 'p1');
      expect(photos, ['unica']);
    });

    test('fotos: sin red devuelve vacío, no rompe la pantalla', () async {
      final photos = await remote(
        (_) async => throw const SocketException('sin red'),
      ).fetchPhotos('t1', 'p1');
      expect(photos, isEmpty);
    });

    test('comentarios: lee la lista y pone "Vecino" si falta el nombre', () async {
      final list = await remote(
        (_) async => http.Response(
          jsonEncode([
            {'id': 'c1', 'author_user_id': 'u1', 'author_name': 'Rosa C.', 'body': 'Hola'},
            {'id': 'c2', 'author_user_id': 'u2', 'body': 'Sin nombre'},
            'basura',
          ]),
          200,
        ),
      ).comments('t1', 'p1');
      expect(list.map((c) => c.authorName), ['Rosa C.', 'Vecino']);
    });

    test('reseña: el comentario vacío no se envía y el texto va sin espacios', () async {
      final bodies = <Map<String, dynamic>>[];
      final ds = remote((r) async {
        bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
        return http.Response(
          '{"id": "r1", "rating": 5, "created_at": "2026-11-08T10:00:00Z"}',
          201,
        );
      });
      await ds.addReview('t1', 'p1', rating: 5, comment: '   ');
      await ds.addReview('t1', 'p1', rating: 4, comment: '  Muy amable  ');
      expect(bodies[0], {'rating': 5});
      expect(bodies[1], {'rating': 4, 'comment': 'Muy amable'});
    });

    test('borrar un comentario ajeno: muestra el motivo del servidor', () async {
      expect(
        () => remote(
          (_) async => http.Response('{"detail": "Solo puedes borrar tus comentarios"}', 403),
        ).deleteComment('t1', 'p1', 'c1'),
        throwsA(predicate((e) => e.toString().contains('tus comentarios'))),
      );
    });
  });
}
