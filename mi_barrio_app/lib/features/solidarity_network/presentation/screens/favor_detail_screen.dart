import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../moderation/data/content_reports.dart';
import '../../../moderation/presentation/report_flow.dart';
import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/ui_kit/app_theme.dart';
import '../../../../core/ui_kit/star_rating_display.dart';
import '../../../../core/ui_kit/star_rating_input.dart';
import '../../../../core/ui_kit/sync_status_chip.dart';
import '../../../../shared/contact_launcher.dart';
import '../../../chat/data/chat_models.dart';
import '../../../chat/data/chat_remote_ds.dart';
import '../../../chat/presentation/chat_screen.dart';
import '../../../chat/presentation/conversations_screen.dart';
import '../../data/datasources/solidarity_remote_ds.dart';
import '../../data/datasources/solidarity_sqlite_ds.dart';
import '../../data/models/favor_interactions.dart';
import '../../data/models/solidarity_post_model.dart';
import '../widgets/post_meta_label.dart';
import '../../../../core/ui_kit/safe_image.dart';

/// Marca un favor ajeno como "en coordinación" (capa de datos: queda en el
/// teléfono como PENDING y se encola).
typedef CoordinateFavorCallback = Future<void> Function(
  SolidarityPostModel post,
);

/// El autor cambia el estado de su favor (completado / disponible otra vez).
typedef ChangeFavorStatusCallback = Future<SolidarityPostModel> Function(
  SolidarityPostModel post,
  String newStatus,
);

/// Detalle de un favor del muro, en pantalla completa:
/// foto, datos, quién publicó y quién ayuda, cómo contactar (WhatsApp,
/// llamada o chat en la app), comentarios y, al completarse, las reseñas.
class FavorDetailScreen extends StatefulWidget {
  const FavorDetailScreen({
    super.key,
    required this.post,
    this.onCoordinate,
    this.onChangeStatus,
    this.remote,
    this.local,
    this.chatRemote,
  });

  final SolidarityPostModel post;

  /// Si es null, ayudar solo abre el contacto (sin marcar "en coordinación").
  final CoordinateFavorCallback? onCoordinate;
  final ChangeFavorStatusCallback? onChangeStatus;
  final SolidarityRemoteDatasource? remote;
  final SolidaritySqliteDatasource? local;
  final ChatRemoteDatasource? chatRemote;

  static const coordinateKey = ValueKey('favor_coordinate_button');
  static const messagesKey = ValueKey('favor_messages_button');
  static const completeKey = ValueKey('favor_complete_button');
  static const commentInputKey = ValueKey('favor_comment_input');
  static const commentSendKey = ValueKey('favor_comment_send');
  static const reviewSendKey = ValueKey('favor_review_send');
  static const chatOptionKey = ValueKey('favor_contact_chat');
  static const whatsappOptionKey = ValueKey('favor_contact_whatsapp');
  static const callOptionKey = ValueKey('favor_contact_call');

  @override
  State<FavorDetailScreen> createState() => _FavorDetailScreenState();
}

class _FavorDetailScreenState extends State<FavorDetailScreen> {
  late final SolidarityRemoteDatasource _remote =
      widget.remote ?? SolidarityRemoteDatasource();
  late final SolidaritySqliteDatasource _local =
      widget.local ?? SolidaritySqliteDatasource();
  late SolidarityPostModel _post = widget.post;

  Uint8List? _photo;
  bool _photoLoading = false;

  List<PostComment>? _comments;
  String? _commentsError;
  final _commentInput = TextEditingController();
  bool _sendingComment = false;

  List<FavorReview>? _reviews;
  int _myStars = 0;
  final _reviewComment = TextEditingController();
  bool _sendingReview = false;
  String? _reviewError;

  bool _busy = false;
  String? _notice;
  String? _error;

  String get _me => TenantSession.instance.userId;
  String get _tenant => TenantSession.instance.tenantId;
  bool get _isOwn => _post.authorUserId == _me;
  bool get _iHelp => _post.coordinatorUserId == _me;
  String get _authorName => _isOwn ? 'Tú' : (_post.authorName ?? 'Un vecino');

  ChatTarget get _chatTarget => ChatTarget(
    kind: ChatKind.favor,
    contextId: _post.id,
    title: _post.title,
    ownerUserId: _post.authorUserId,
  );

  @override
  void initState() {
    super.initState();
    _commentInput.addListener(() => setState(() {}));
    unawaited(_loadPhoto());
    unawaited(_loadComments());
    if (_post.status == SolidarityStatus.completado) unawaited(_loadReviews());
  }

  @override
  void dispose() {
    _commentInput.dispose();
    _reviewComment.dispose();
    super.dispose();
  }

  // ── Datos ──

  Future<void> _loadPhoto() async {
    if (!_post.hasPhoto) return;
    setState(() => _photoLoading = true);
    try {
      var b64 = await _local.localPhoto(_post.id);
      if (b64 == null) {
        b64 = await _remote.fetchPhoto(_tenant, _post.id);
        if (b64 != null) await _local.cachePhoto(_tenant, _post.id, b64);
      }
      if (mounted && b64 != null) setState(() => _photo = base64Decode(b64!));
    } catch (_) {
      // Sin foto guardada ni conexión: se muestra el aviso.
    } finally {
      if (mounted) setState(() => _photoLoading = false);
    }
  }

  Future<void> _loadComments() async {
    try {
      final list = await _remote.comments(_tenant, _post.id);
      if (mounted) {
        setState(() {
          _comments = list;
          _commentsError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _commentsError =
              'Los comentarios necesitan internet. Desliza para reintentar.',
        );
      }
    }
  }

  Future<void> _loadReviews() async {
    try {
      final list = await _remote.reviews(_tenant, _post.id);
      if (mounted) setState(() => _reviews = list);
    } catch (_) {
      if (mounted) setState(() => _reviews = const []);
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      _loadComments(),
      if (_post.status == SolidarityStatus.completado) _loadReviews(),
    ]);
  }

  // ── Acciones ──

  Future<void> _sendComment() async {
    final text = _commentInput.text.trim();
    if (text.isEmpty || _sendingComment) return;
    setState(() => _sendingComment = true);
    try {
      final c = await _remote.addComment(_tenant, _post.id, text);
      _commentInput.clear();
      if (mounted) setState(() => _comments = [...?_comments, c]);
    } catch (_) {
      _snack('No se pudo publicar tu comentario. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  Future<void> _deleteComment(PostComment c) async {
    try {
      await _remote.deleteComment(_tenant, _post.id, c.id);
      if (mounted) {
        setState(
          () => _comments = [...?_comments]..removeWhere((x) => x.id == c.id),
        );
      }
    } catch (_) {
      _snack('No se pudo borrar el comentario.');
    }
  }

  Future<void> _sendReview() async {
    if (_myStars == 0 || _sendingReview) return;
    setState(() {
      _sendingReview = true;
      _reviewError = null;
    });
    try {
      final r = await _remote.addReview(
        _tenant,
        _post.id,
        rating: _myStars,
        comment: _reviewComment.text,
      );
      if (mounted) setState(() => _reviews = [...?_reviews, r]);
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (mounted) {
        setState(
          () => _reviewError =
              msg.contains('ya dejaste') || msg.contains('Ya dejaste')
              ? msg
              : 'No se pudo enviar la reseña. Si el favor se completó hace poco, '
                    'espera a que se sincronice e intenta de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _sendingReview = false);
    }
  }

  Future<void> _changeStatus(String status) async {
    final change = widget.onChangeStatus;
    if (change == null || _busy) return;
    if (status == SolidarityStatus.completado) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('¿Marcar como completado?'),
          content: const Text(
            'El favor sale del muro y podrán calificarse entre ustedes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Todavía no'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sí, completado'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      final updated = await change(_post, status);
      if (!mounted) return;
      setState(() {
        _post = updated;
        _notice = status == SolidarityStatus.completado
            ? '¡Gracias por ayudar a tu barrio! Ya puedes dejar tu reseña.'
            : 'Tu favor está disponible otra vez.';
      });
      if (status == SolidarityStatus.completado) unawaited(_loadReviews());
    } catch (_) {
      _snack('No se pudo cambiar el estado. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Ayudar": elige cómo contactar (WhatsApp, llamada o chat en la app).
  /// Si el favor estaba disponible, queda "en coordinación" contigo.
  Future<void> _help() async {
    final option = await showModalBottomSheet<_ContactOption>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) =>
          _ContactOptionsSheet(post: _post, authorName: _authorName),
    );
    if (option == null || !mounted) return;

    if (_post.status == SolidarityStatus.disponible &&
        widget.onCoordinate != null) {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        await widget.onCoordinate!(_post);
        if (!mounted) return;
        setState(() {
          _post = _post.copyWith(
            status: SolidarityStatus.enCoordinacion,
            coordinatorUserId: _me,
            syncStatus: 'PENDING',
          );
          _notice = 'Listo: estás coordinando este favor. Se sincronizará en segundo plano.';
        });
      } on StateError catch (e) {
        if (mounted) setState(() => _error = e.message);
      } on ArgumentError catch (e) {
        if (mounted) setState(() => _error = '${e.message}');
      } catch (_) {
        if (mounted) {
          setState(() => _error = 'No se pudo coordinar. Intenta de nuevo.');
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (!mounted) return;

    final greeting =
        'Hola ${_post.authorName ?? ''}, te escribo por tu publicación '
                '"${_post.title}" en Mi Barrio.'
            .replaceAll('Hola ,', 'Hola,');
    switch (option) {
      case _ContactOption.chat:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChatScreen(
              target: _chatTarget,
              neighborUserId: _me,
              otherName: _authorName,
              remote: widget.chatRemote,
            ),
          ),
        );
      case _ContactOption.whatsapp:
        final number = _post.contactWhatsapp ?? _post.contactPhone!;
        if (!await ContactLauncher.whatsapp(number, text: greeting)) {
          _snack('No se pudo abrir WhatsApp.');
        }
      case _ContactOption.call:
        if (!await ContactLauncher.call(_post.contactPhone!)) {
          _snack('No se pudo abrir el teléfono.');
        }
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ── Pantalla ──

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final esquema = Theme.of(context).colorScheme;
    final isOffer = _post.flowType == SolidarityFlowType.ofrezcoAyuda;
    final meta = PostMetaLabel.timeAgo(_post.updatedAt);

    return Scaffold(
      appBar: AppBar(title: Text(isOffer ? 'Ofrece ayuda' : 'Pide ayuda')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (_post.hasPhoto) ...[
              _PhotoView(
                photo: _photo,
                loading: _photoLoading,
                title: _post.title,
              ),
              const SizedBox(height: 16),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(
                    isOffer ? Icons.favorite_rounded : Icons.back_hand_rounded,
                    size: 18,
                    color: esquema.primary,
                  ),
                  label: Text(isOffer ? 'Ofrezco ayuda' : 'Necesito ayuda'),
                ),
                Chip(
                  label: Text(
                    SolidarityModality.labels[_post.modality] ?? _post.modality,
                  ),
                ),
                if (_post.isEmergencyContext)
                  const Chip(
                    avatar: Icon(Icons.emergency_rounded, size: 18),
                    label: Text('Emergencia'),
                  ),
                if (_post.isPending) SyncStatusChip.fromPending(true),
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              header: true,
              child: Text(_post.title, style: texto.headlineSmall),
            ),
            if (_post.description?.trim().isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text(_post.description!, style: texto.bodyLarge),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _PersonRow(
                    name: _authorName,
                    caption: [
                      if (_isOwn) 'Publicaste este favor' else 'Publicó este favor',
                      ?meta,
                    ].join(' · '),
                  ),
                ),
                // Al otro extremo: reportar (no en lo propio).
                if (!_isOwn)
                  ReportButton(
                    targetType: ReportTarget.post,
                    targetId: _post.id,
                    onReported: () => Navigator.of(context).maybePop(true),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _StatusBanner(post: _post, me: _me),
            const SizedBox(height: 16),
            ..._actions(context),
            if (_notice != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(_notice!, style: texto.bodyMedium),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: texto.bodyMedium?.copyWith(color: esquema.error),
                ),
              ),
            ],
            if (_post.status == SolidarityStatus.completado) ...[
              const SizedBox(height: 24),
              _reviewsSection(context),
            ],
            const SizedBox(height: 24),
            _commentsSection(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    final completed = _post.status == SolidarityStatus.completado;
    if (_isOwn) {
      return [
        OutlinedButton.icon(
          key: FavorDetailScreen.messagesKey,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ConversationsScreen(
                target: _chatTarget,
                remote: widget.chatRemote,
              ),
            ),
          ),
          icon: const Icon(Icons.forum_rounded),
          label: const Text('Mensajes de vecinos'),
        ),
        if (!completed && widget.onChangeStatus != null) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            key: FavorDetailScreen.completeKey,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _busy
                ? null
                : () => _changeStatus(SolidarityStatus.completado),
            icon: const Icon(Icons.task_alt_rounded),
            label: const Text('Marcar como completado'),
          ),
          if (_post.status == SolidarityStatus.enCoordinacion)
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => _changeStatus(SolidarityStatus.disponible),
              icon: const Icon(Icons.undo_rounded),
              label: const Text('No se concretó: volver a disponible'),
            ),
        ],
      ];
    }
    if (completed) return const [];
    return [
      FilledButton.icon(
        key: FavorDetailScreen.coordinateKey,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        onPressed: _busy ? null : _help,
        icon: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : const Icon(Icons.handshake_rounded),
        label: Text(
          _iHelp
              ? 'Contactar a ${_post.authorName ?? 'quien publicó'}'
              : _post.flowType == SolidarityFlowType.ofrezcoAyuda
              ? 'Me interesa'
              : 'Quiero ayudar',
        ),
      ),
    ];
  }

  Widget _reviewsSection(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final reviews = _reviews;
    final participant = _isOwn || _iHelp;
    final reviewed = reviews?.any((r) => r.reviewerUserId == _me) ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(icon: Icons.star_rounded, text: 'Reseñas'),
        if (reviews == null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          if (reviews.isEmpty)
            Text(
              'Todavía no hay reseñas de este favor.',
              style: texto.bodyLarge,
            ),
          for (final r in reviews)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r.reviewerUserId == _me ? 'Tú' : r.reviewerName} → '
                      '${r.reviewedUserId == _me ? 'ti' : r.reviewedName}',
                      style: texto.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    StarRatingDisplay(
                      rating: r.rating.toDouble(),
                      size: 20,
                      showValue: false,
                    ),
                    if (r.comment != null) ...[
                      const SizedBox(height: 4),
                      Text(r.comment!, style: texto.bodyLarge),
                    ],
                  ],
                ),
              ),
            ),
          if (participant && !reviewed) ...[
            if (_post.coordinatorUserId == null)
              Text(
                'No quedó registrado quién ayudó, así que no se pueden dejar reseñas.',
                style: texto.bodyMedium,
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _isOwn
                            ? '¿Cómo te ayudó ${_post.coordinatorName ?? 'tu vecino'}?'
                            : '¿Cómo fue coordinar con ${_post.authorName ?? 'tu vecino'}?',
                        style: texto.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: StarRatingInput(
                          value: _myStars,
                          onChanged: _sendingReview
                              ? null
                              : (v) => setState(() => _myStars = v),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _reviewComment,
                        maxLength: 300,
                        maxLines: 3,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Comentario (opcional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_reviewError != null)
                        Text(
                          _reviewError!,
                          style: texto.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        key: FavorDetailScreen.reviewSendKey,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: _myStars == 0 || _sendingReview
                            ? null
                            : _sendReview,
                        icon: const Icon(Icons.star_rounded),
                        label: const Text('Enviar reseña'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ],
    );
  }

  Widget _commentsSection(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final esquema = Theme.of(context).colorScheme;
    final comments = _comments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          icon: Icons.chat_bubble_outline_rounded,
          text: comments == null
              ? 'Comentarios'
              : 'Comentarios (${comments.length})',
        ),
        if (_commentsError != null)
          Text(
            _commentsError!,
            style: texto.bodyMedium?.copyWith(color: esquema.onSurfaceVariant),
          )
        else if (comments == null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (comments.isEmpty)
          Text('Sé el primero en comentar.', style: texto.bodyLarge),
        if (comments != null)
          for (final c in comments)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Avatar(
                    name: c.authorUserId == _me ? 'Tú' : c.authorName,
                    radius: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      decoration: BoxDecoration(
                        color: esquema.surface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.authorUserId == _me ? 'Tú' : c.authorName,
                                  style: texto.labelLarge,
                                ),
                              ),
                              Text(
                                PostMetaLabel.timeAgo(
                                      c.createdAt.toUtc().toIso8601String(),
                                    ) ??
                                    '',
                                style: texto.labelSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(c.body, style: texto.bodyLarge),
                        ],
                      ),
                    ),
                  ),
                  if (c.authorUserId == _me)
                    IconButton(
                      tooltip: 'Borrar mi comentario',
                      onPressed: () => _deleteComment(c),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                ],
              ),
            ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: FavorDetailScreen.commentInputKey,
                controller: _commentInput,
                minLines: 1,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Escribe un comentario público',
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              key: FavorDetailScreen.commentSendKey,
              tooltip: 'Publicar comentario',
              style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
              onPressed: _commentInput.text.trim().isEmpty || _sendingComment
                  ? null
                  : _sendComment,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

enum _ContactOption { whatsapp, call, chat }

/// Las 3 formas de coordinar. Las que no tienen dato (el autor no cargó
/// teléfono) aparecen desactivadas con la explicación.
class _ContactOptionsSheet extends StatelessWidget {
  const _ContactOptionsSheet({required this.post, required this.authorName});

  final SolidarityPostModel post;
  final String authorName;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final hasWa = post.hasWhatsapp || post.hasPhone;
    final willCoordinate = post.status == SolidarityStatus.disponible;
    Widget option({
      required Key key,
      required IconData icon,
      required Color color,
      required String title,
      required String subtitle,
      required _ContactOption? value,
    }) => Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        key: key,
        enabled: value != null,
        minTileHeight: 72,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: value == null ? 0.08 : 0.15),
          child: Icon(
            icon,
            color: value == null ? Theme.of(context).disabledColor : color,
          ),
        ),
        title: Text(title, style: texto.titleMedium),
        subtitle: Text(subtitle),
        trailing: value == null
            ? null
            : const Icon(Icons.chevron_right_rounded),
        onTap: value == null ? null : () => Navigator.of(context).pop(value),
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '¿Cómo quieres coordinar con $authorName?',
            style: texto.titleLarge,
          ),
          if (willCoordinate) ...[
            const SizedBox(height: 4),
            Text(
              'Al elegir una opción, el favor queda "En coordinación" contigo.',
              style: texto.bodyMedium,
            ),
          ],
          const SizedBox(height: 16),
          option(
            key: FavorDetailScreen.chatOptionKey,
            icon: Icons.forum_rounded,
            color: AppPalette.dayPrimary,
            title: 'Chat en Mi Barrio',
            subtitle: 'Mensajes al instante, sin compartir tu número.',
            value: _ContactOption.chat,
          ),
          option(
            key: FavorDetailScreen.whatsappOptionKey,
            icon: Icons.chat_rounded,
            color: const Color(0xFF1B7F3B),
            title: 'WhatsApp',
            subtitle: hasWa
                ? 'Se abre con un saludo ya escrito.'
                : '$authorName no agregó WhatsApp a su perfil.',
            value: hasWa ? _ContactOption.whatsapp : null,
          ),
          option(
            key: FavorDetailScreen.callOptionKey,
            icon: Icons.call_rounded,
            color: AppPalette.daySecondary,
            title: 'Llamar',
            subtitle: post.hasPhone
                ? 'Llamada directa a su teléfono.'
                : '$authorName no agregó teléfono a su perfil.',
            value: post.hasPhone ? _ContactOption.call : null,
          ),
        ],
      ),
    );
  }
}

/// Cierra la frase con punto, sin duplicarlo ("Luis R." → "Luis R.").
String _sentence(String text) => text.endsWith('.') ? text : '$text.';

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.post, required this.me});

  final SolidarityPostModel post;
  final String me;

  @override
  Widget build(BuildContext context) {
    final colores = MiBarrioColors.of(context);
    final (
      IconData icon,
      String text,
      Color bg,
      Color fg,
    ) = switch (post.status) {
      SolidarityStatus.enCoordinacion => (
        Icons.handshake_rounded,
        post.coordinatorUserId == me
            ? 'Tú estás coordinando este favor.'
            : post.authorUserId == me
            ? '${post.coordinatorName ?? 'Un vecino'} está coordinando contigo.'
            : '${post.coordinatorName ?? 'Un vecino'} ya está ayudando. Igual puedes escribir.',
        colores.accentSoft,
        colores.accentText,
      ),
      SolidarityStatus.completado => (
        Icons.task_alt_rounded,
        _sentence(
          'Favor completado${post.coordinatorName != null ? ' con ayuda de ${post.coordinatorUserId == me ? 'ti' : post.coordinatorName}' : ''}',
        ),
        colores.syncedBackground,
        colores.syncSynced,
      ),
      _ => (
        Icons.radio_button_checked_rounded,
        'Disponible: nadie lo está coordinando todavía.',
        colores.pill,
        colores.onPill,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: fg, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.name, required this.caption});

  final String name;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Row(
      children: [
        _Avatar(name: name, radius: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: texto.titleMedium),
              Text(
                caption,
                style: texto.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.radius});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colores = MiBarrioColors.of(context);
    return CircleAvatar(
      radius: radius,
      backgroundColor: colores.accentSoft,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: colores.accentText,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text, style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
        ],
      ),
    );
  }
}

/// Foto del favor (16:10). Al tocarla se abre a pantalla completa con zoom.
class _PhotoView extends StatelessWidget {
  const _PhotoView({
    required this.photo,
    required this.loading,
    required this.title,
  });

  final Uint8List? photo;
  final bool loading;
  final String title;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final bytes = photo;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: bytes != null
            ? Semantics(
                image: true,
                label: 'Foto de: $title. Toca para ampliar.',
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        backgroundColor: Colors.black,
                        appBar: AppBar(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                        ),
                        body: Center(
                          child: InteractiveViewer(
                            maxScale: 5,
                            child: SafeMemoryImage(bytes),
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: SafeMemoryImage(bytes, fit: BoxFit.cover),
                ),
              )
            : Container(
                color: esquema.surface,
                alignment: Alignment.center,
                child: loading
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.image_not_supported_outlined,
                            color: esquema.onSurfaceVariant,
                          ),
                          const SizedBox(height: 6),
                          const Text('La foto se verá cuando haya internet.'),
                        ],
                      ),
              ),
      ),
    );
  }
}
