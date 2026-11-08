import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/barrio_context/tenant_session.dart';
import 'package:mi_barrio_app/core/network/api_client.dart';
import 'package:mi_barrio_app/core/realtime/favor_chat_socket.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/datasources/solidarity_remote_ds.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/models/favor_interactions.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/models/solidarity_post_model.dart';
import 'package:mi_barrio_app/features/solidarity_network/presentation/screens/favor_chat_screen.dart';
import 'package:mi_barrio_app/features/solidarity_network/presentation/screens/favor_detail_screen.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _author = 'aaaaaaaa-1111-4111-8111-111111111111';

/// Servidor falso: guarda comentarios, reseñas y mensajes en memoria.
class _FakeRemote extends SolidarityRemoteDatasource {
  _FakeRemote() : super(api: ApiClient(baseUrl: 'http://fake'));

  final commentList = <PostComment>[];
  final reviewsList = <FavorReview>[];
  final sent = <ChatMessage>[];

  @override
  Future<String?> fetchPhoto(String tenantId, String postId) async => null;

  @override
  Future<List<PostComment>> comments(String tenantId, String postId) async => [...commentList];

  @override
  Future<PostComment> addComment(String tenantId, String postId, String text) async {
    final c = PostComment(
      id: 'c${commentList.length}',
      authorUserId: TenantSession.instance.userId,
      authorName: 'Yo',
      body: text,
      createdAt: DateTime.now(),
    );
    commentList.add(c);
    return c;
  }

  @override
  Future<List<FavorReview>> reviews(String tenantId, String postId) async => [...reviewsList];

  @override
  Future<FavorReview> addReview(String tenantId, String postId, {required int rating, String? comment}) async {
    final r = FavorReview(
      id: 'r1',
      reviewerUserId: TenantSession.instance.userId,
      reviewerName: 'Yo',
      reviewedUserId: 'helper',
      reviewedName: 'Luis R.',
      rating: rating,
      comment: comment,
      createdAt: DateTime.now(),
    );
    reviewsList.add(r);
    return r;
  }

  @override
  Future<List<ChatMessage>> messages(String tenantId, String postId, String neighborId) async => [...sent];

  @override
  Future<ChatMessage> sendMessage(String tenantId, String postId, String neighborId, String text) async {
    final m = ChatMessage(
      id: 'm${sent.length}',
      postId: postId,
      neighborUserId: neighborId,
      senderUserId: TenantSession.instance.userId,
      senderName: 'Yo',
      body: text,
      createdAt: DateTime.now(),
    );
    sent.add(m);
    return m;
  }
}

SolidarityPostModel _post({
  String author = _author,
  String status = SolidarityStatus.disponible,
  String? phone,
  String? coordinator,
}) =>
    SolidarityPostModel(
      id: 'post-1',
      tenantId: TenantSession.instance.tenantId,
      authorUserId: author,
      flowType: SolidarityFlowType.solicitoAyuda,
      modality: SolidarityModality.prestamoHerramienta,
      title: 'Necesito un taladro',
      lat: -5.19,
      lng: -80.63,
      status: status,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      syncStatus: 'SYNCED',
      authorName: 'Rosa C.',
      contactPhone: phone,
      coordinatorUserId: coordinator,
      coordinatorName: coordinator == null ? null : 'Luis R.',
    );

void main() {
  late _FakeRemote remote;

  setUpAll(() {
    // Sin servidor de WebSocket en los tests: la conexión falla y reintenta.
    FavorChatSocket.connector = (_) => throw WebSocketChannelException('sin red');
  });
  setUp(() => remote = _FakeRemote());

  Future<void> open(
    WidgetTester tester,
    SolidarityPostModel post, {
    CoordinateFavorCallback? onCoordinate,
    ChangeFavorStatusCallback? onChangeStatus,
  }) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.day(),
      home: FavorDetailScreen(
        post: post,
        remote: remote,
        local: _NoPhotos(),
        onCoordinate: onCoordinate,
        onChangeStatus: onChangeStatus,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('"Quiero ayudar" ofrece WhatsApp, Llamar y Chat; sin teléfono se explican', (tester) async {
    await open(tester, _post(), onCoordinate: (_) async {});
    await tester.tap(find.byKey(FavorDetailScreen.coordinateKey));
    await tester.pumpAndSettle();

    expect(find.text('¿Cómo quieres coordinar con Rosa C.?'), findsOneWidget);
    expect(find.text('Chat en Mi Barrio'), findsOneWidget);
    expect(find.text('Rosa C. no agregó WhatsApp a su perfil.'), findsOneWidget);
    expect(find.text('Rosa C. no agregó teléfono a su perfil.'), findsOneWidget);
    expect(tester.widget<ListTile>(find.byKey(FavorDetailScreen.callOptionKey)).enabled, isFalse);
  });

  testWidgets('con teléfono, WhatsApp y Llamar están disponibles', (tester) async {
    await open(tester, _post(phone: '987654321'), onCoordinate: (_) async {});
    await tester.tap(find.byKey(FavorDetailScreen.coordinateKey));
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(find.byKey(FavorDetailScreen.whatsappOptionKey)).enabled, isTrue);
    expect(tester.widget<ListTile>(find.byKey(FavorDetailScreen.callOptionKey)).enabled, isTrue);
  });

  testWidgets('elegir Chat coordina el favor y abre el chat en tiempo real', (tester) async {
    var coordinated = 0;
    await open(tester, _post(), onCoordinate: (_) async => coordinated++);
    await tester.tap(find.byKey(FavorDetailScreen.coordinateKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FavorDetailScreen.chatOptionKey));
    await tester.pumpAndSettle();

    expect(coordinated, 1);
    expect(find.byType(FavorChatScreen), findsOneWidget);

    await tester.enterText(find.byKey(FavorChatScreen.inputKey), 'Te lo presto hoy');
    await tester.pump();
    await tester.tap(find.byKey(FavorChatScreen.sendKey));
    await tester.pumpAndSettle();
    expect(find.text('Te lo presto hoy'), findsOneWidget);

    // Llega la respuesta de la autora por el canal en tiempo real.
    FavorChatSocket.instance.injectForTesting(ChatMessage(
      id: 'srv-1',
      postId: 'post-1',
      neighborUserId: TenantSession.instance.userId,
      senderUserId: _author,
      senderName: 'Rosa C.',
      body: '¡Gracias! Paso a las 5',
      createdAt: DateTime.now(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('¡Gracias! Paso a las 5'), findsOneWidget);

    // Mensajes de OTRA conversación no se mezclan.
    FavorChatSocket.instance.injectForTesting(ChatMessage(
      id: 'srv-2',
      postId: 'otro-favor',
      neighborUserId: TenantSession.instance.userId,
      senderUserId: _author,
      senderName: 'Rosa C.',
      body: 'Esto es de otro favor',
      createdAt: DateTime.now(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Esto es de otro favor'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
  });

  testWidgets('se puede comentar públicamente', (tester) async {
    await open(tester, _post());
    expect(find.text('Sé el primero en comentar.'), findsOneWidget);
    await tester.enterText(find.byKey(FavorDetailScreen.commentInputKey), 'Yo tengo uno');
    await tester.pump();
    await tester.tap(find.byKey(FavorDetailScreen.commentSendKey));
    await tester.pumpAndSettle();
    expect(find.text('Yo tengo uno'), findsOneWidget);
    expect(find.text('Comentarios (1)'), findsOneWidget);
  });

  testWidgets('el autor marca completado y deja su reseña con estrellas', (tester) async {
    final me = TenantSession.instance.userId;
    await open(
      tester,
      _post(author: me, status: SolidarityStatus.enCoordinacion, coordinator: 'helper'),
      onChangeStatus: (p, status) async => p.copyWith(status: status),
    );
    expect(find.text('Luis R. está coordinando contigo.'), findsOneWidget);
    expect(find.byKey(FavorDetailScreen.messagesKey), findsOneWidget);
    expect(find.byKey(FavorDetailScreen.coordinateKey), findsNothing);

    await tester.tap(find.byKey(FavorDetailScreen.completeKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, completado'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Favor completado con ayuda de Luis R.'), findsOneWidget);
    expect(find.text('¿Cómo te ayudó Luis R.?'), findsOneWidget);
    await tester.ensureVisible(find.byKey(FavorDetailScreen.reviewSendKey));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('5 estrellas'));
    await tester.pump();
    await tester.tap(find.byKey(FavorDetailScreen.reviewSendKey));
    await tester.pumpAndSettle();
    expect(remote.reviewsList.single.rating, 5);
    expect(find.text('¿Cómo te ayudó Luis R.?'), findsNothing, reason: 'ya dejó su reseña');
  });

  testWidgets('un vecino que no participó ve las reseñas pero no puede dejar una', (tester) async {
    remote.reviewsList.add(FavorReview(
      id: 'r0',
      reviewerUserId: _author,
      reviewerName: 'Rosa C.',
      reviewedUserId: 'helper',
      reviewedName: 'Luis R.',
      rating: 4,
      comment: 'Muy puntual',
      createdAt: DateTime.now(),
    ));
    await open(tester, _post(status: SolidarityStatus.completado, coordinator: 'helper'));
    expect(find.text('Muy puntual'), findsOneWidget);
    expect(find.byKey(FavorDetailScreen.reviewSendKey), findsNothing);
    expect(find.byKey(FavorDetailScreen.coordinateKey), findsNothing);
  });
}

/// Sin base local en estos tests: nunca hay foto guardada.
class _NoPhotos extends SolidaritySqliteDatasource {
  @override
  Future<String?> localPhoto(String postId) async => null;

  @override
  Future<void> cachePhoto(String tenantId, String postId, String photoB64) async {}
}
