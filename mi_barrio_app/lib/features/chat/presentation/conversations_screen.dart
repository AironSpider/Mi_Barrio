import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/barrio_context/tenant_session.dart';
import '../../../core/realtime/chat_socket.dart';
import '../../../core/ui_kit/app_theme.dart';
import '../../solidarity_network/presentation/widgets/post_meta_label.dart';
import '../data/chat_models.dart';
import '../data/chat_remote_ds.dart';
import 'chat_screen.dart';

/// Lista de conversaciones que se refresca sola cuando llega un mensaje.
///
/// - [target] != null: las de UNA publicación (lo que ve su dueño).
/// - [target] == null: "Mis mensajes", todas las del vecino.
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key, this.target, this.remote, this.socket});

  final ChatTarget? target;
  final ChatRemoteDatasource? remote;
  final ChatSocket? socket;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  late final ChatRemoteDatasource _remote =
      widget.remote ?? ChatRemoteDatasource();
  late final ChatSocket _socket = widget.socket ?? ChatSocket.instance;
  StreamSubscription<ChatMessage>? _sub;
  List<ConversationSummary>? _items;
  String? _error;

  bool get _isInbox => widget.target == null;

  @override
  void initState() {
    super.initState();
    _socket.acquire();
    final t = widget.target;
    _sub = _socket.messages
        .where(
          (m) => t == null || (m.kind == t.kind && m.contextId == t.contextId),
        )
        .listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _socket.release();
    super.dispose();
  }

  Future<void> _load() async {
    final tenant = TenantSession.instance.tenantId;
    try {
      final t = widget.target;
      final list = t == null
          ? await _remote.inbox(tenant)
          : await _remote.conversations(tenant, t);
      if (!mounted) return;
      setState(() {
        _items = list;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No pudimos cargar los mensajes. El chat necesita internet.',
        );
      }
    }
  }

  Future<void> _open(ConversationSummary c) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          target: c.target,
          neighborUserId: c.neighborUserId,
          otherName: c.otherName,
          remote: _remote,
          socket: _socket,
        ),
      ),
    );
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(_isInbox ? 'Mis mensajes' : 'Mensajes')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_isInbox) ...[
              Text(widget.target!.title, style: texto.titleMedium),
              const SizedBox(height: 12),
            ],
            if (_error != null)
              _Message(icon: Icons.cloud_off_rounded, text: _error!)
            else if (items == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              _Message(
                icon: Icons.forum_outlined,
                text: _isInbox
                    ? 'Todavía no tienes conversaciones. Escribe a un vecino desde un '
                          'favor del muro o a un comerciante desde su servicio.'
                    : 'Todavía nadie te escribió por esta publicación. Cuando alguien '
                          'lo haga, aparecerá aquí al instante.',
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, c) in items.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: 76),
                      ConversationTile(
                        conversation: c,
                        showContext: _isInbox,
                        onTap: () => _open(c),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fila de una conversación: avatar, nombre, sobre qué es y el último mensaje.
class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
    this.showContext = true,
  });

  final ConversationSummary conversation;
  final VoidCallback onTap;

  /// En "Mis mensajes" se muestra de qué publicación se habla.
  final bool showContext;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final texto = Theme.of(context).textTheme;
    final colores = MiBarrioColors.of(context);
    final mine = c.lastSenderUserId == TenantSession.instance.userId;
    final isService = c.kind == ChatKind.service;
    return ListTile(
      minTileHeight: 76,
      onTap: onTap,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: colores.accentSoft,
            child: Text(
              c.otherName.characters.first.toUpperCase(),
              style: TextStyle(
                color: colores.accentText,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isService
                    ? Icons.storefront_rounded
                    : Icons.volunteer_activism_rounded,
                size: 14,
                color: colores.accentText,
              ),
            ),
          ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              c.otherName,
              style: texto.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            PostMetaLabel.timeAgo(c.lastAt.toUtc().toIso8601String()) ?? '',
            style: texto.labelSmall,
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showContext)
            Text(
              '${isService ? 'Servicio' : 'Favor'}: ${c.contextTitle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: texto.labelMedium?.copyWith(color: colores.accentText),
            ),
          Text(
            '${mine ? 'Tú: ' : ''}${c.lastMessage}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
