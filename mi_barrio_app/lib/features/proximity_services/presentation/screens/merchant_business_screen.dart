import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../data/datasources/merchant_business_remote_ds.dart';

class MerchantBusinessScreen extends StatefulWidget {
  const MerchantBusinessScreen({super.key, this.datasource});

  final MerchantBusinessRemoteDatasource? datasource;

  @override
  State<MerchantBusinessScreen> createState() => _MerchantBusinessScreenState();
}

class _MerchantBusinessScreenState extends State<MerchantBusinessScreen> {
  late final MerchantBusinessRemoteDatasource _datasource;
  List<Map<String, dynamic>> _services = const [];
  final Map<String, List<Map<String, dynamic>>> _recommendations = {};
  final Set<String> _sendingReplies = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _datasource = widget.datasource ?? MerchantBusinessRemoteDatasource();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final services = await _datasource.myServices(
        TenantSession.instance.tenantId,
      );
      final fetched = await Future.wait(
        services.map((service) {
          final id = service['id']?.toString() ?? '';
          return _datasource.recommendations(
            tenantId: TenantSession.instance.tenantId,
            serviceId: id,
          );
        }),
      );
      if (!mounted) return;
      setState(() {
        _services = services;
        _recommendations
          ..clear()
          ..addEntries([
            for (var index = 0; index < services.length; index++)
              MapEntry(services[index]['id'].toString(), fetched[index]),
          ]);
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('No se pudo cargar Mi negocio: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar tus servicios y recomendaciones.';
        _loading = false;
      });
    }
  }

  Future<void> _reply({
    required String serviceId,
    required String recommendationId,
    required String text,
  }) async {
    if (text.trim().isEmpty || !_sendingReplies.add(recommendationId)) return;
    setState(() {});
    try {
      await _datasource.reply(
        tenantId: TenantSession.instance.tenantId,
        serviceId: serviceId,
        recommendationId: recommendationId,
        text: text.trim(),
      );
      await _load();
      if (!mounted) return;
      _message('Respuesta enviada.');
    } catch (error, stackTrace) {
      debugPrint('No se pudo responder la recomendación: $error\n$stackTrace');
      if (mounted) {
        _message('No pudimos enviar tu respuesta. Intenta de nuevo.');
      }
    } finally {
      _sendingReplies.remove(recommendationId);
      if (mounted) setState(() {});
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    if (_services.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!TenantSession.instance.isApproved) ...[
                const Icon(Icons.hourglass_top_rounded, size: 40),
                const SizedBox(height: 12),
                const Text(
                  'Tu cuenta de comerciante está pendiente de aprobación del administrador. '
                  'Mientras esperas, puedes usar las funciones de vecino.',
                  textAlign: TextAlign.center,
                ),
              ] else
                const Text(
                  'Todavía no tienes servicios publicados. Usa el botón + para ofrecer uno.',
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Text('Mi negocio', style: Theme.of(context).textTheme.headlineSmall),
          if (!TenantSession.instance.isApproved) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Tu cuenta de comerciante está pendiente de aprobación. '
                  'Mientras tanto puedes usar el muro, las recomendaciones '
                  'y las funciones de ayuda como cualquier vecino; podrás '
                  'publicar servicios cuando el administrador te apruebe.',
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text('Gestiona tus servicios y responde a tus vecinos.'),
          const SizedBox(height: 12),
          for (final service in _services) ...[
            _serviceCard(context, service),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _serviceCard(BuildContext context, Map<String, dynamic> service) {
    final serviceId = service['id']?.toString() ?? '';
    final reviews = _recommendations[serviceId] ?? const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              service['title']?.toString() ?? 'Servicio',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (service['description'] case final String description
                when description.isNotEmpty)
              Text(description),
            const SizedBox(height: 8),
            Text(
              reviews.isEmpty
                  ? 'Aún no tienes recomendaciones.'
                  : 'Recomendaciones (${reviews.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final review in reviews)
              _recommendation(context, serviceId, review),
          ],
        ),
      ),
    );
  }

  Widget _recommendation(
    BuildContext context,
    String serviceId,
    Map<String, dynamic> review,
  ) {
    final recommendationId = review['id']?.toString() ?? '';
    final reply = review['provider_reply']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (review['rating'] is int)
                Text(List.filled(review['rating'] as int, '★').join()),
              Text(
                review['short_comment']?.toString() ?? 'Visto bueno vecinal',
              ),
              if (reply.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Tu respuesta: $reply'),
              ] else ...[
                const SizedBox(height: 8),
                _ReplyInput(
                  sending: _sendingReplies.contains(recommendationId),
                  onSend: (text) => _reply(
                    serviceId: serviceId,
                    recommendationId: recommendationId,
                    text: text,
                  ),
                ),
              ],
            ],
          ),
        ),
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
          controller: _controller,
          maxLength: 1000,
          decoration: const InputDecoration(
            labelText: 'Responder recomendación',
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
