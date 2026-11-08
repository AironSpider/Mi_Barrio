import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/realtime/favor_chat_socket.dart';
import '../../../../core/ui_kit/app_theme.dart';
import '../../data/datasources/solidarity_remote_ds.dart';
import '../../data/models/favor_interactions.dart';
import '../../data/models/solidarity_post_model.dart';
import '../widgets/post_meta_label.dart';
import 'favor_chat_screen.dart';

/// El autor de un favor ve aquí a cada vecino que le escribió.
class FavorConversationsScreen extends StatefulWidget {
  const FavorConversationsScreen({super.key, required this.post, this.remote, this.socket});

  final SolidarityPostModel post;
  final SolidarityRemoteDatasource? remote;
  final FavorChatSocket? socket;

  @override
  State<FavorConversationsScreen> createState() => _FavorConversationsScreenState();
}

class _FavorConversationsScreenState extends State<FavorConversationsScreen> {
  late final SolidarityRemoteDatasource _remote = widget.remote ?? SolidarityRemoteDatasource();
  late final FavorChatSocket _socket = widget.socket ?? FavorChatSocket.instance;
  StreamSubscription<ChatMessage>? _sub;
  List<ConversationSummary>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _socket.acquire();
    // Un mensaje nuevo en este favor reordena la lista al instante.
    _sub = _socket.messages.where((m) => m.postId == widget.post.id).listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _socket.release();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _remote.conversations(TenantSession.instance.tenantId, widget.post.id);
      if (mounted) {
        setState(() {
          _items = list;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No pudimos cargar los mensajes. Revisa tu conexión.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Mensajes del favor')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(widget.post.title, style: texto.titleMedium),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, style: texto.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.error))
            else if (items == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Todavía nadie te escribió por este favor. Cuando un vecino te '
                    'escriba, la conversación aparecerá aquí al instante.',
                    style: texto.bodyLarge,
                  ),
                ),
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, c) in items.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: 72),
                      ListTile(
                        minTileHeight: 72,
                        leading: CircleAvatar(
                          backgroundColor: MiBarrioColors.of(context).accentSoft,
                          child: Text(
                            c.neighborName.isEmpty ? '?' : c.neighborName[0].toUpperCase(),
                            style: TextStyle(color: MiBarrioColors.of(context).accentText),
                          ),
                        ),
                        title: Text(c.neighborName),
                        subtitle: Text(
                          '${c.lastSenderUserId == TenantSession.instance.userId ? 'Tú: ' : ''}${c.lastMessage}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          PostMetaLabel.timeAgo(c.lastAt.toUtc().toIso8601String()) ?? '',
                          style: texto.labelMedium,
                        ),
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => FavorChatScreen(
                              post: widget.post,
                              neighborUserId: c.neighborUserId,
                              otherName: c.neighborName,
                              remote: _remote,
                              socket: _socket,
                            ),
                          ));
                          unawaited(_load());
                        },
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
