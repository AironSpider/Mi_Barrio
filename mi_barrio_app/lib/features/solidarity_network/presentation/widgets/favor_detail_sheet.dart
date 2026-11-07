import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/ui_kit/sync_status_chip.dart';
import '../../data/models/solidarity_post_model.dart';

/// Marca un favor ajeno como "en coordinación". Lo entrega la capa de datos
/// (Dev 2): guarda en el teléfono como PENDING y encola el cambio.
typedef CoordinateFavorCallback = Future<void> Function(
  SolidarityPostModel post,
);

/// Abre el detalle de un favor en una hoja inferior.
Future<void> showFavorDetailSheet(
  BuildContext context, {
  required SolidarityPostModel post,
  String? userId,
  CoordinateFavorCallback? onCoordinate,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => FavorDetailSheet(
      post: post,
      userId: userId,
      onCoordinate: onCoordinate,
    ),
  );
}

/// Detalle del favor. El vecino que NO es el autor puede tocar "Coordinar".
class FavorDetailSheet extends StatefulWidget {
  const FavorDetailSheet({
    super.key,
    required this.post,
    this.userId,
    this.onCoordinate,
  });

  final SolidarityPostModel post;
  final String? userId;

  /// Si es null, el botón "Coordinar" aparece desactivado.
  final CoordinateFavorCallback? onCoordinate;

  static const coordinateKey = ValueKey('favor_coordinate_button');

  @override
  State<FavorDetailSheet> createState() => _FavorDetailSheetState();
}

class _FavorDetailSheetState extends State<FavorDetailSheet> {
  late String _status;
  late bool _pending;
  bool _busy = false;
  String? _notice;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = widget.post.status;
    _pending = widget.post.isPending;
  }

  String get _userId => widget.userId ?? TenantSession.instance.userId;

  bool get _isOwn => widget.post.authorUserId == _userId;

  Future<void> _coordinate() async {
    final callback = widget.onCoordinate;
    if (callback == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await callback(widget.post);
      if (!mounted) return;
      setState(() {
        _status = SolidarityStatus.enCoordinacion;
        _pending = true;
        _notice =
            'Listo: quedó en coordinación. Se sincronizará en segundo plano.';
      });
    } on ArgumentError catch (error) {
      if (!mounted) return;
      setState(() => _error = '${error.message}');
    } on StateError catch (error) {
      // Ya está tomado o completado: se muestra el mensaje de la capa de datos.
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'No se pudo coordinar. Intenta de nuevo.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _statusLabel => switch (_status) {
    SolidarityStatus.enCoordinacion => 'En coordinación',
    SolidarityStatus.completado => 'Completado',
    _ => 'Disponible',
  };

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    final post = widget.post;
    final isOffer = post.flowType == SolidarityFlowType.ofrezcoAyuda;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      avatar: Icon(
                        isOffer
                            ? Icons.favorite_rounded
                            : Icons.back_hand_rounded,
                        size: 18,
                        color: esquema.primary,
                      ),
                      label: Text(isOffer ? 'Ofrezco ayuda' : 'Necesito ayuda'),
                    ),
                    if (post.isEmergencyContext)
                      const Chip(
                        avatar: Icon(Icons.emergency_rounded, size: 18),
                        label: Text('Emergencia'),
                      ),
                    Chip(
                      avatar: const Icon(Icons.handshake_rounded, size: 18),
                      label: Text(_statusLabel),
                    ),
                    SyncStatusChip.fromPending(_pending),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(post.title, style: texto.titleLarge),
          const SizedBox(height: 4),
          Text(
            SolidarityModality.labels[post.modality] ?? post.modality,
            style: texto.bodyLarge?.copyWith(color: esquema.onSurfaceVariant),
          ),
          if (post.description != null &&
              post.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(post.description!, style: texto.bodyLarge),
          ],
          const SizedBox(height: 20),
          _buildAction(context),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(_notice!, style: texto.bodyMedium),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: texto.bodyMedium?.copyWith(color: esquema.error),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAction(BuildContext context) {
    final texto = Theme.of(context).textTheme;

    if (_isOwn) {
      return Text('Este es tu favor.', style: texto.bodyLarge);
    }
    if (_status == SolidarityStatus.completado) {
      return Text('Este favor ya fue completado.', style: texto.bodyLarge);
    }
    if (_status == SolidarityStatus.enCoordinacion) {
      return Text(
        'Este favor ya está en coordinación con un vecino.',
        style: texto.bodyLarge,
      );
    }

    final canCoordinate = widget.onCoordinate != null && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: FavorDetailSheet.coordinateKey,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: canCoordinate ? () => unawaited(_coordinate()) : null,
            icon: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.handshake_rounded),
            label: const Text('Coordinar'),
          ),
        ),
        if (widget.onCoordinate == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Coordinar todavía no está disponible en esta versión.',
              style: texto.bodyMedium,
            ),
          ),
      ],
    );
  }
}
