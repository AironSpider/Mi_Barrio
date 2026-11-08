import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/database_sqlite/history_dao.dart';
import '../../../../core/database_sqlite/sync_outbox_dao.dart';
import '../../../../core/ui_kit/app_theme.dart';
import '../../../../core/ui_kit/star_rating_display.dart';
import '../../../../core/ui_kit/sync_status_chip.dart';
import '../../../chat/data/chat_models.dart';
import '../../../chat/presentation/conversations_screen.dart';
import '../../data/datasources/merchant_business_remote_ds.dart';
import '../../data/models/service_model.dart';
import '../widgets/offer_service_sheet.dart';
import '../widgets/service_category_ui.dart';
import '../widgets/service_detail_sheet.dart';
import '../../../../core/moderation/content_filter.dart';

/// "Mi negocio": mis servicios (desde el teléfono, sin internet) con accesos a
/// editar, ver mensajes de clientes y responder sus reseñas (con internet).
class MerchantBusinessScreen extends StatefulWidget {
  const MerchantBusinessScreen({super.key, this.datasource, this.history});

  final MerchantBusinessRemoteDatasource? datasource;
  final HistoryDao? history;

  @override
  State<MerchantBusinessScreen> createState() => _MerchantBusinessScreenState();
}

class _MerchantBusinessScreenState extends State<MerchantBusinessScreen> {
  late final MerchantBusinessRemoteDatasource _remote =
      widget.datasource ?? MerchantBusinessRemoteDatasource();
  late final HistoryDao _history = widget.history ?? HistoryDao();
  late final StreamSubscription<String> _queueSub;

  List<LocalServiceModel>? _services;
  final Map<String, List<Map<String, dynamic>>> _reviews = {};
  bool _reviewsOffline = false;
  final Set<String> _sendingReplies = {};

  String get _tenant => TenantSession.instance.tenantId;
  String get _me => TenantSession.instance.userId;

  @override
  void initState() {
    super.initState();
    _queueSub = SyncOutboxDao.onQueued.listen((t) {
      if (t == _tenant) unawaited(_load());
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_queueSub.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    final services = await _history.myServices(_tenant, _me);
    if (!mounted) return;
    setState(() => _services = services);
    var offline = false;
    for (final s in services) {
      try {
        final list = await _remote.recommendations(
          tenantId: _tenant,
          serviceId: s.id,
        );
        _reviews[s.id] = list;
      } catch (_) {
        offline = true;
      }
    }
    if (mounted) setState(() => _reviewsOffline = offline);
  }

  Future<void> _reply(String serviceId, String reviewId, String text) async {
    if (text.trim().isEmpty || !_sendingReplies.add(reviewId)) return;
    setState(() {});
    try {
      await _remote.reply(
        tenantId: _tenant,
        serviceId: serviceId,
        recommendationId: reviewId,
        text: text.trim(),
      );
      await _load();
      _snack('Respuesta enviada.');
    } catch (_) {
      _snack('No pudimos enviar tu respuesta. Revisa tu conexión.');
    } finally {
      _sendingReplies.remove(reviewId);
      if (mounted) setState(() {});
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _offer({LocalServiceModel? existing}) async {
    final profile = await loadMerchantProfile(_me, tenantId: _tenant);
    if (!mounted) return;
    final saved = await showOfferServiceSheet(
      context,
      profile: profile,
      existing: existing,
    );
    if (saved) {
      _snack(existing == null ? 'Servicio publicado.' : 'Cambios guardados.');
      unawaited(_load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final services = _services;
    if (services == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text('Mi negocio', style: texto.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Tus servicios, los mensajes de tus clientes y sus reseñas.',
            style: texto.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('merchant_offer_button'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: () => _offer(),
            icon: const Icon(Icons.add_business_rounded),
            label: const Text('Brindar un servicio'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ConversationsScreen(),
              ),
            ),
            icon: const Icon(Icons.forum_rounded),
            label: const Text('Mis mensajes'),
          ),
          const SizedBox(height: 20),
          if (services.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      Icons.storefront_outlined,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Todavía no publicaste servicios. Toca "Brindar un servicio": '
                      'agrega fotos, precio y dónde atiendes.',
                      textAlign: TextAlign.center,
                      style: texto.bodyLarge,
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text('Mis servicios (${services.length})', style: texto.titleLarge),
            if (_reviewsOffline)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Sin conexión: las reseñas se verán cuando vuelva internet.',
                  style: texto.bodyMedium,
                ),
              ),
            const SizedBox(height: 10),
            for (final s in services) _serviceCard(context, s),
          ],
        ],
      ),
    );
  }

  Widget _serviceCard(BuildContext context, LocalServiceModel s) {
    final texto = Theme.of(context).textTheme;
    final colores = MiBarrioColors.of(context);
    final reviews = _reviews[s.id] ?? const [];
    final target = ChatTarget(
      kind: ChatKind.service,
      contextId: s.id,
      title: s.publisherName?.isNotEmpty == true
          ? '${s.publisherName}, ${s.title}'
          : s.title,
      ownerUserId: s.providerUserId,
    );
    return Card(
      key: ValueKey('merchant_service_${s.id}'),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colores.accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    ServiceCategoryUi.icon(s.category),
                    color: colores.accentText,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ServiceCategory.labels[s.category] ?? s.category,
                        style: texto.labelMedium,
                      ),
                      Text(s.title, style: texto.titleMedium),
                    ],
                  ),
                ),
                if (s.isPending) SyncStatusChip.fromPending(true),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StarRatingDisplay(
                  rating: s.ratingAvg ?? 0,
                  count: s.endorsementsCount,
                  size: 18,
                ),
                if (s.priceText != null)
                  Chip(
                    label: Text(s.priceText!),
                    avatar: const Icon(Icons.sell_rounded, size: 16),
                  ),
                if (s.photoCount > 0)
                  Chip(
                    label: Text('${s.photoCount} fotos'),
                    avatar: const Icon(Icons.photo_library_rounded, size: 16),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _offer(existing: s),
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Editar'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ConversationsScreen(target: target),
                    ),
                  ),
                  icon: const Icon(Icons.forum_rounded),
                  label: const Text('Mensajes'),
                ),
                TextButton.icon(
                  onPressed: () => showServiceDetailSheet(context, service: s),
                  icon: const Icon(Icons.visibility_rounded),
                  label: const Text('Ver como vecino'),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              reviews.isEmpty
                  ? 'Aún no tienes reseñas.'
                  : 'Reseñas (${reviews.length})',
              style: texto.titleSmall,
            ),
            for (final r in reviews) _review(context, s.id, r),
          ],
        ),
      ),
    );
  }

  Widget _review(
    BuildContext context,
    String serviceId,
    Map<String, dynamic> r,
  ) {
    final texto = Theme.of(context).textTheme;
    final id = r['id']?.toString() ?? '';
    final reply = r['provider_reply']?.toString() ?? '';
    final name = r['endorser_name']?.toString() ?? 'Un vecino';
    final rating = r['rating'] is int ? r['rating'] as int : null;
    final comment = r['short_comment']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: texto.titleSmall)),
              if (rating != null)
                StarRatingDisplay(
                  rating: rating.toDouble(),
                  size: 16,
                  showValue: false,
                ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(comment, style: texto.bodyLarge),
          ],
          const SizedBox(height: 8),
          if (reply.isNotEmpty)
            Text(
              'Tu respuesta: $reply',
              style: texto.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
            )
          else
            _ReplyInput(
              sending: _sendingReplies.contains(id),
              onSend: (text) => _reply(serviceId, id, text),
            ),
        ],
      ),
    );
  }
}

class _ReplyInput extends StatefulWidget {
  const _ReplyInput({required this.sending, required this.onSend});

  final bool sending;
  final ValueChanged<String> onSend;

  @override
  State<_ReplyInput> createState() => _ReplyInputState();
}

class _ReplyInputState extends State<_ReplyInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: TextField(
          inputFormatters: const [OffensiveWordsFormatter()],
          controller: _controller,
          maxLength: 1000,
          decoration: const InputDecoration(
            labelText: 'Responder a esta reseña',
            counterText: '',
          ),
        ),
      ),
      IconButton(
        tooltip: 'Enviar respuesta',
        onPressed: widget.sending
            ? null
            : () {
                final text = _controller.text.trim();
                if (text.isEmpty) return;
                widget.onSend(text);
                _controller.clear();
              },
        icon: widget.sending
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.send_rounded),
      ),
    ],
  );
}
