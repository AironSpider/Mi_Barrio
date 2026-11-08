import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/barrio_context/tenant_session.dart';
import '../../../core/realtime/chat_socket.dart';
import '../../../core/ui_kit/app_theme.dart';
import '../data/chat_models.dart';
import '../data/chat_remote_ds.dart';

/// Chat en tiempo real sobre un favor o un servicio, entre su dueño (autor o
/// comerciante) y un vecino.
///
/// Conversación = (publicación, vecino que no es el dueño): [neighborUserId].
/// Enviar = REST (queda guardado aunque el otro no esté); recibir = WebSocket.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.target,
    required this.neighborUserId,
    required this.otherName,
    this.remote,
    this.socket,
  });

  final ChatTarget target;
  final String neighborUserId;

  /// Con quién se habla (dueño o vecino), para el título.
  final String otherName;
  final ChatRemoteDatasource? remote;
  final ChatSocket? socket;

  static const inputKey = ValueKey('chat_input');
  static const sendKey = ValueKey('chat_send');

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatRemoteDatasource _remote =
      widget.remote ?? ChatRemoteDatasource();
  late final ChatSocket _socket = widget.socket ?? ChatSocket.instance;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<ChatMessage>? _sub;

  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  String get _me => TenantSession.instance.userId;
  String get _tenant => TenantSession.instance.tenantId;

  @override
  void initState() {
    super.initState();
    _socket.acquire();
    _socket.status.addListener(_onStatus);
    _sub = _socket.messages.listen((m) {
      final t = widget.target;
      if (m.kind != t.kind ||
          m.contextId != t.contextId ||
          m.neighborUserId != widget.neighborUserId) {
        return;
      }
      _add(m);
    });
    _input.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _socket.status.removeListener(_onStatus);
    _socket.release();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Al reconectar se recarga: pudo llegar algo mientras no había señal.
  void _onStatus() {
    if (!mounted) return;
    setState(() {});
    if (_socket.status.value == RealtimeStatus.connected && !_loading) _load();
  }

  Future<void> _load() async {
    try {
      final list = await _remote.messages(
        _tenant,
        widget.target,
        widget.neighborUserId,
      );
      if (!mounted) return;
      setState(() {
        _messages = list;
        _loading = false;
        _error = null;
      });
      _scrollToEnd();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'No pudimos cargar la conversación. El chat necesita internet.';
      });
    }
  }

  void _add(ChatMessage m) {
    if (!mounted || _messages.any((x) => x.id == m.id)) return;
    setState(() => _messages = [..._messages, m]);
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final sent = await _remote.sendMessage(
        _tenant,
        widget.target,
        widget.neighborUserId,
        text,
      );
      _input.clear();
      _add(sent);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(
        () => _error = msg.contains('todavía no te escribió')
            ? msg
            : 'No se pudo enviar. Revisa tu conexión e intenta de nuevo.',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final esquema = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.otherName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.target.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: texto.bodySmall?.copyWith(color: esquema.onPrimary),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _ConnectionBanner(status: _socket.status.value),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? _EmptyChat(
                    isOwner: widget.target.ownerUserId == _me,
                    kind: widget.target.kind,
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      final showDay =
                          i == 0 ||
                          !_sameDay(_messages[i - 1].createdAt, m.createdAt);
                      return Column(
                        children: [
                          if (showDay) _DayDivider(date: m.createdAt),
                          _Bubble(message: m, mine: m.senderUserId == _me),
                        ],
                      );
                    },
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: texto.bodyMedium?.copyWith(color: esquema.error),
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: ChatScreen.inputKey,
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje',
                        counterText: '',
                        filled: true,
                        fillColor: esquema.surface,
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
                    key: ChatScreen.sendKey,
                    tooltip: 'Enviar',
                    iconSize: 26,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(52, 52),
                    ),
                    onPressed: _input.text.trim().isEmpty || _sending
                        ? null
                        : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// "Conectado en tiempo real" no se muestra (es lo normal): solo se avisa
/// mientras se conecta o reconecta.
class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.status});

  final RealtimeStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == RealtimeStatus.connected) return const SizedBox.shrink();
    final texto = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      color: AppPalette.pendingBackground,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(
            Icons.sync_rounded,
            size: 18,
            color: AppPalette.syncPending,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Conectando… los mensajes nuevos llegarán al volver la conexión.',
              style: texto.bodyMedium?.copyWith(color: AppPalette.syncPending),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.isOwner, required this.kind});

  final bool isOwner;
  final ChatKind kind;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              isOwner
                  ? 'Aún no hay mensajes en esta conversación.'
                  : kind == ChatKind.service
                  ? 'Pregunta lo que necesites: precio, horario o cuándo puede atenderte.'
                  : 'Escribe para coordinar: cuándo, dónde y cómo ayudar.',
              textAlign: TextAlign.center,
              style: texto.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final label = day == today
        ? 'Hoy'
        : day == today.subtract(const Duration(days: 1))
        ? 'Ayer'
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    final time =
        '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}';
    final fg = mine ? esquema.onPrimary : esquema.onSurface;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Semantics(
          label: '${mine ? 'Tú' : message.senderName}, $time: ${message.body}',
          excludeSemantics: true,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            decoration: BoxDecoration(
              color: mine ? esquema.primary : esquema.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(mine ? 18 : 4),
                bottomRight: Radius.circular(mine ? 4 : 18),
              ),
              border: mine
                  ? null
                  : Border.all(color: esquema.outline.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    message.body,
                    style: texto.bodyLarge?.copyWith(color: fg),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  time,
                  style: texto.labelSmall?.copyWith(
                    color: fg.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
