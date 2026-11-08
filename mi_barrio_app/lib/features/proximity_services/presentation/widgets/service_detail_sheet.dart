import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../moderation/data/content_reports.dart';
import '../../../moderation/presentation/report_flow.dart';
import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/database_sqlite/sqlite_database.dart';
import '../../../../core/database_sqlite/sync_outbox_dao.dart';
import '../../../../core/sync_manager/sync_coordinator.dart';
import '../../../../core/ui_kit/app_theme.dart';
import '../../../../core/ui_kit/star_rating_display.dart';
import '../../../../core/ui_kit/star_rating_input.dart';
import '../../../../core/ui_kit/sync_status_chip.dart';
import '../../data/datasources/endorsements_sqlite_ds.dart';
import '../../data/datasources/services_remote_ds.dart';
import '../../data/datasources/services_sqlite_ds.dart';
import 'offer_service_sheet.dart';
import '../../data/models/endorsement_model.dart';
import '../../data/models/service_model.dart';
import '../../../../shared/contact_launcher.dart';
import '../../../../shared/local_distance.dart';
import '../../../solidarity_network/presentation/widgets/post_meta_label.dart';
import '../../../../core/ui_kit/location_map.dart';
import '../../../chat/data/chat_models.dart';
import '../../../chat/data/chat_remote_ds.dart';
import '../../../chat/presentation/chat_screen.dart';
import '../../../chat/presentation/conversations_screen.dart';
import '../../../emergency_support/presentation/providers/emergency_provider.dart';
import 'service_category_ui.dart';
import '../../../../core/ui_kit/safe_image.dart';
import '../../../../core/moderation/content_filter.dart';

/// Abre el detalle de un servicio en una hoja inferior.
Future<void> showServiceDetailSheet(
  BuildContext context, {
  required LocalServiceModel service,
  String? tenantId,
  String? userId,
  EndorsementsSqliteDatasource? endorsementsDatasource,
  ServicesRemoteDatasource? remoteDatasource,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => ServiceDetailSheet(
      service: service,
      tenantId: tenantId,
      userId: userId,
      endorsementsDatasource: endorsementsDatasource,
      remoteDatasource: remoteDatasource,
    ),
  );
}

/// Detalle del servicio: mini mapa sin internet, contacto, calificaciones de
/// vecinos y formulario "Califica este servicio" (estrellas + comentario).
class ServiceDetailSheet extends StatefulWidget {
  const ServiceDetailSheet({
    super.key,
    required this.service,
    this.tenantId,
    this.userId,
    this.endorsementsDatasource,
    this.remoteDatasource,
    this.centerLat,
    this.centerLng,
    this.syncPhase,
    this.chatRemote,
  });

  /// Chat con el comerciante (los tests pasan uno falso).
  final ChatRemoteDatasource? chatRemote;

  final LocalServiceModel service;
  final String? tenantId;
  final String? userId;
  final EndorsementsSqliteDatasource? endorsementsDatasource;

  /// Calificaciones del servidor. Si es null se usa el real (salvo en tests).
  final ServicesRemoteDatasource? remoteDatasource;

  /// Centro del barrio para el mini mapa (por defecto, el de la sesión).
  final double? centerLat;
  final double? centerLng;

  /// Solo para pruebas: reemplaza al estado global de sincronización.
  final ValueListenable<SyncPhase>? syncPhase;

  static const saveKey = ValueKey('service_rating_save');
  static const commentKey = ValueKey('service_rating_comment');
  static const mapKey = ValueKey('service_mini_map');
  static const directionsKey = ValueKey('service_directions');
  static const editKey = ValueKey('service_edit');
  static const chatKey = ValueKey('service_chat');
  static const messagesKey = ValueKey('service_messages');
  static const callButtonKey = ValueKey('service_call');
  static const whatsappButtonKey = ValueKey('service_whatsapp');
  static const maxComment = 140;

  @override
  State<ServiceDetailSheet> createState() => _ServiceDetailSheetState();
}

class _Contact {
  const _Contact({this.name, this.phone, this.whatsapp});

  final String? name;
  final String? phone;
  final String? whatsapp;

  bool get isEmpty =>
      (phone == null || phone!.isEmpty) &&
      (whatsapp == null || whatsapp!.isEmpty);
}

class _ServiceDetailSheetState extends State<ServiceDetailSheet> {
  static const _maxShownRatings = 30;

  late final String _tenantId;
  late final String _userId;
  late final EndorsementsSqliteDatasource _ds;
  late final ValueListenable<SyncPhase> _phase;
  late final StreamSubscription<String> _queueSubscription;
  final TextEditingController _comment = TextEditingController();

  List<EndorsementModel> _endorsements = const [];
  EndorsementModel? _mine;
  _Contact? _contact;
  int _stars = 0;
  bool _touched = false;
  bool _saving = false;
  bool _loadingList = true;
  String? _notice;
  String? _error;
  int _loadVersion = 0;
  HelpLocation? _myLocation;
  List<String> _photos = const [];

  bool get _isOwn => widget.service.providerUserId == _userId;

  bool get _hasChanges {
    final savedStars = _mine?.rating ?? 0;
    final savedComment = _mine?.shortComment ?? '';
    return _stars != savedStars || _comment.text.trim() != savedComment;
  }

  @override
  void initState() {
    super.initState();
    _tenantId = widget.tenantId ?? TenantSession.instance.tenantId;
    _userId = widget.userId ?? TenantSession.instance.userId;
    _ds = widget.endorsementsDatasource ?? EndorsementsSqliteDatasource();
    _phase = widget.syncPhase ?? SyncCoordinator.instance.phase;
    _phase.addListener(_onSyncChanged);
    _queueSubscription = SyncOutboxDao.onQueued.listen((tenantId) {
      if (tenantId == _tenantId) unawaited(_load());
    });
    _comment.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_load(loadContact: true));
      unawaited(_refreshFromServer());
      unawaited(
        ServicesSqliteDatasource()
            .localPhotos(widget.service.id)
            .then((p) {
              if (mounted && p.isNotEmpty) setState(() => _photos = p);
            })
            .catchError((_) {}),
      );
      // Tu ubicación (GPS o centro del barrio) para "A 350 m de ti".
      unawaited(
        HelpLocator.resolveQuietly().then((loc) {
          if (mounted) setState(() => _myLocation = loc);
        }),
      );
    });
  }

  @override
  void dispose() {
    _phase.removeListener(_onSyncChanged);
    unawaited(_queueSubscription.cancel());
    _comment.dispose();
    super.dispose();
  }

  void _onSyncChanged() {
    if (_phase.value == SyncPhase.idle || _phase.value == SyncPhase.error) {
      unawaited(_load());
    }
  }

  /// Pide las calificaciones al servidor (se guardan en SQLite) y recarga la
  /// lista. Sin red o con error, se queda con lo guardado en el teléfono.
  Future<void> _refreshFromServer() async {
    try {
      final remote =
          widget.remoteDatasource ??
          (Platform.environment.containsKey('FLUTTER_TEST')
              ? null
              : ServicesRemoteDatasource());
      if (remote == null) return;
      await remote.fetchEndorsements(
        tenantId: _tenantId,
        serviceId: widget.service.id,
      );
      if (mounted) await _load();
      // Fotos: las guardadas en el teléfono primero; si no coinciden con las
      // del servicio (faltan o cambiaron), del servidor.
      if (widget.service.photoCount > 0 &&
          _photos.length != widget.service.photoCount) {
        final photos = await remote.fetchServicePhotos(
          tenantId: _tenantId,
          serviceId: widget.service.id,
        );
        if (photos.isNotEmpty) {
          await ServicesSqliteDatasource().cachePhotos(
            _tenantId,
            widget.service.id,
            photos,
          );
          if (mounted) setState(() => _photos = photos);
        }
      }
    } catch (_) {
      // Sin red: la lista local ya está en pantalla.
    }
  }

  /// Contacto del comerciante. Lo trae el servidor junto con el servicio
  /// (`contact_phone` / `contact_whatsapp`). La tabla local `users` solo tiene
  /// el perfil del dueño de ESTE teléfono: sirve para ver el propio servicio.
  Future<_Contact?> _loadContact() async {
    final service = widget.service;
    String? clean(String? v) =>
        (v == null || v.trim().isEmpty) ? null : v.trim();
    final fromService = _Contact(
      name: clean(service.publisherName),
      phone: clean(service.contactPhone),
      whatsapp: clean(service.contactWhatsapp),
    );
    if (!fromService.isEmpty) return fromService;
    try {
      final db = await LocalDatabase.instance.database;
      final rows = await db.query(
        'users',
        columns: ['full_name', 'phone', 'whatsapp'],
        where: 'id = ? AND tenant_id = ? AND is_deleted = 0',
        whereArgs: [service.providerUserId, _tenantId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.first;
      return _Contact(
        name: row['full_name'] as String?,
        phone: clean(row['phone'] as String?),
        whatsapp: clean(row['whatsapp'] as String?),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _load({bool loadContact = false}) async {
    final version = ++_loadVersion;
    try {
      final list = await _ds.listForService(_tenantId, widget.service.id);
      final mine = await _ds.myRating(widget.service.id, _userId);
      final contact = loadContact ? await _loadContact() : _contact;
      if (!mounted || version != _loadVersion) return;
      if (!_touched) {
        final text = mine?.shortComment ?? '';
        if (_comment.text != text) _comment.text = text;
      }
      setState(() {
        _endorsements = list;
        _mine = mine;
        _contact = contact;
        _loadingList = false;
        if (!_touched) _stars = mine?.rating ?? 0;
      });
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _loadingList = false;
        _error = 'No se pudieron cargar las calificaciones.';
      });
    }
  }

  Future<void> _onStarTap(int value) async {
    if (_saving) return;
    // Tocar la misma estrella otra vez quita la calificación.
    if (value == _stars) {
      await _clearRating();
      return;
    }
    setState(() {
      _stars = value;
      _touched = true;
      _notice = null;
      _error = null;
    });
  }

  Future<void> _clearRating() async {
    final hadSaved = _mine != null;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      if (hadSaved) {
        await _ds.removeEndorsement(
          tenantId: _tenantId,
          serviceId: widget.service.id,
          endorserUserId: _userId,
        );
      }
      _touched = false;
      _stars = 0;
      _comment.clear();
      await _load();
      if (!mounted) return;
      setState(() {
        _notice = hadSaved
            ? 'Quitaste tu calificación. Se enviará solo cuando haya señal.'
            : null;
      });
    } on ArgumentError catch (error) {
      if (!mounted) return;
      setState(() => _error = '${error.message}');
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'No se pudo quitar la calificación. Intenta de nuevo.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _stars == 0 || !_hasChanges) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await _ds.rateService(
        tenantId: _tenantId,
        serviceId: widget.service.id,
        endorserUserId: _userId,
        rating: _stars,
        shortComment: _comment.text,
      );
      _touched = false;
      await _load();
      if (!mounted) return;
      setState(() {
        _notice = 'Calificación guardada en tu teléfono. Se enviará solo cuando haya señal.';
      });
    } on ArgumentError catch (error) {
      if (!mounted) return;
      setState(() => _error = '${error.message}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo guardar. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    final service = widget.service;
    final publisher = service.publisherName?.trim();
    final title = (publisher != null && publisher.isNotEmpty)
        ? '$publisher, ${service.title}'
        : service.title;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, title),
            if (_photos.isNotEmpty) ...[
              const SizedBox(height: 14),
              _PhotoStrip(photos: _photos, title: service.title),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Un pedido ("Pedir") no se califica: no tiene estrellas.
                      if (service.isNeed)
                        const Chip(
                          avatar: Icon(Icons.campaign_rounded, size: 18),
                          label: Text('Pide este servicio'),
                        )
                      else if (service.ratingAvg != null)
                        StarRatingDisplay(
                          rating: service.ratingAvg!,
                          count: service.endorsementsCount,
                        )
                      // Solo vistos buenos (sin estrellas): antes salía
                      // "0.0 (1)", como si fuera una mala calificación.
                      else
                        Text(
                          service.endorsementsCount == 0
                              ? 'Aún sin calificaciones'
                              : service.endorsementsCount == 1
                              ? '1 vecino lo recomienda · aún sin estrellas'
                              : '${service.endorsementsCount} vecinos lo recomiendan · aún sin estrellas',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      if (service.priceText != null)
                        Chip(
                          avatar: const Icon(Icons.sell_rounded, size: 18),
                          label: Text(service.priceText!),
                        ),
                    ],
                  ),
                ),
                // Al otro extremo de las estrellas: reportar (no en lo propio).
                if (!_isOwn)
                  ReportButton(
                    targetType: ReportTarget.service,
                    targetId: service.id,
                    onReported: () => Navigator.of(context).maybePop(),
                  ),
              ],
            ),
            if (_isOwn) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: ServiceDetailSheet.editKey,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  final saved = await showOfferServiceSheet(
                    context,
                    tenantId: _tenantId,
                    userId: _userId,
                    existing: service,
                  );
                  if (saved) navigator.maybePop();
                },
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Editar servicio'),
              ),
            ],
            if (service.description.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(service.description, style: texto.bodyLarge),
            ],
            const SizedBox(height: 20),
            Text('Dónde está', style: texto.titleMedium),
            const SizedBox(height: 8),
            _buildMap(context),
            const SizedBox(height: 20),
            Text(
              _isOwn ? 'Tus clientes' : 'Contacto',
              style: texto.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_isOwn)
              _buildOwnMessages(context)
            else ...[
              _buildChatButton(context),
              const SizedBox(height: 12),
              _buildContact(context),
            ],
            const SizedBox(height: 20),
            if (_isOwn)
              Text(
                'Este es tu servicio. Tus vecinos pueden calificarlo.',
                style: texto.bodyLarge,
              )
            else
              _buildRatingForm(context),
            const SizedBox(height: 20),
            _buildRatingsList(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String title) {
    final esquema = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    final colores = MiBarrioColors.of(context);
    final service = widget.service;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: esquema.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            ServiceCategoryUi.icon(service.category),
            size: 28,
            color: esquema.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ServiceCategory.labels[service.category] ?? service.category,
                style: texto.labelLarge?.copyWith(
                  color: esquema.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(title, style: texto.titleLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // "Sincronizado" no le dice nada al vecino: solo se avisa lo pendiente.
                  if (service.isPending) SyncStatusChip.fromPending(true),
                  if (service.isAvailableInEmergency)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colores.urgencyHigh.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.health_and_safety,
                            size: 20,
                            color: colores.urgencyHigh,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'En emergencias',
                            style: texto.labelLarge?.copyWith(
                              color: colores.urgencyHigh,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Cerrar',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }

  /// Dónde atiende: mapa real, distancia desde ti y "Cómo llegar".
  Widget _buildMap(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final esquema = Theme.of(context).colorScheme;
    final service = widget.service;
    final me = _myLocation;
    final fromLat =
        me?.lat ?? widget.centerLat ?? TenantSession.instance.centerLat;
    final fromLng =
        me?.lng ?? widget.centerLng ?? TenantSession.instance.centerLng;
    final distance = LocalDistance.label(
      LocalDistance.km(fromLat, fromLng, service.lat, service.lng),
    );
    final fromText = me != null && me.fromGps
        ? 'de ti'
        : 'del centro del barrio';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LocationMap(
          key: ServiceDetailSheet.mapKey,
          lat: service.lat,
          lng: service.lng,
          myLat: me != null && me.fromGps ? me.lat : null,
          myLng: me != null && me.fromGps ? me.lng : null,
          label: 'Mapa: ${service.title} está a $distance $fromText.',
          icon: ServiceCategoryUi.icon(service.category),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              Icons.near_me_rounded,
              size: 20,
              color: esquema.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text('A $distance $fromText.', style: texto.bodyLarge),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          key: ServiceDetailSheet.directionsKey,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            if (!await ContactLauncher.directions(service.lat, service.lng)) {
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text('No se pudo abrir el mapa del teléfono.'),
                  ),
                );
            }
          },
          icon: const Icon(Icons.directions_walk_rounded),
          label: const Text('Cómo llegar'),
        ),
      ],
    );
  }

  ChatTarget get _chatTarget {
    final s = widget.service;
    final name = s.publisherName?.trim();
    return ChatTarget(
      kind: ChatKind.service,
      contextId: s.id,
      title: name != null && name.isNotEmpty ? '$name, ${s.title}' : s.title,
      ownerUserId: s.providerUserId,
    );
  }

  /// Chat en la app con el comerciante (sin compartir números).
  Widget _buildChatButton(BuildContext context) {
    final name =
        _contact?.name ?? widget.service.publisherName ?? 'el comerciante';
    return FilledButton.icon(
      key: ServiceDetailSheet.chatKey,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            target: _chatTarget,
            neighborUserId: _userId,
            otherName: name,
            remote: widget.chatRemote,
          ),
        ),
      ),
      icon: const Icon(Icons.forum_rounded),
      label: const Text('Escribir por Mi Barrio'),
    );
  }

  /// El comerciante ve aquí las conversaciones de sus clientes.
  Widget _buildOwnMessages(BuildContext context) {
    return OutlinedButton.icon(
      key: ServiceDetailSheet.messagesKey,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ConversationsScreen(
            target: _chatTarget,
            remote: widget.chatRemote,
          ),
        ),
      ),
      icon: const Icon(Icons.forum_rounded),
      label: const Text('Mensajes de clientes'),
    );
  }

  Widget _buildContact(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final contact = _contact;
    if (contact == null || contact.isEmpty) {
      return Text(
        'Todavía no hay un número de contacto en tu teléfono para este vecino.',
        style: texto.bodyLarge,
      );
    }
    final lines = <(String, String)>[
      if (contact.phone != null && contact.phone!.isNotEmpty)
        ('Teléfono', contact.phone!),
      if (contact.whatsapp != null && contact.whatsapp!.isNotEmpty)
        ('WhatsApp', contact.whatsapp!),
    ];
    final callNumber = contact.phone ?? contact.whatsapp;
    final waNumber = contact.whatsapp ?? contact.phone;
    final who = (contact.name?.isNotEmpty ?? false)
        ? contact.name!
        : widget.service.title;

    Future<void> open(
      Future<bool> Function(String) action,
      String number,
      String label,
    ) async {
      final messenger = ScaffoldMessenger.of(context);
      if (await action(number)) return;
      // Sin app de teléfono / WhatsApp (ej. tablet): al menos queda copiado.
      await Clipboard.setData(ClipboardData(text: number));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir $label. Copiamos el número.'),
          ),
        );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (contact.name != null && contact.name!.isNotEmpty)
          Text(contact.name!, style: texto.bodyLarge),
        const SizedBox(height: 8),
        // Acciones directas, grandes y con verbo (adultos mayores, una mano).
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (callNumber != null && ContactLauncher.isDialable(callNumber))
              Semantics(
                button: true,
                label: 'Llamar a $who',
                // TalkBack: el doble toque necesita la acción aquí.
                onTap: () => open(ContactLauncher.call, callNumber, 'el teléfono'),
                excludeSemantics: true,
                child: FilledButton.icon(
                  key: ServiceDetailSheet.callButtonKey,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(140, 56),
                  ),
                  onPressed: () =>
                      open(ContactLauncher.call, callNumber, 'el teléfono'),
                  icon: const Icon(Icons.call_rounded),
                  label: const Text('Llamar'),
                ),
              ),
            if (waNumber != null && ContactLauncher.isDialable(waNumber))
              Semantics(
                button: true,
                label: 'Escribir por WhatsApp a $who',
                // TalkBack: el doble toque necesita la acción aquí.
                onTap: () => open(ContactLauncher.whatsapp, waNumber, 'WhatsApp'),
                excludeSemantics: true,
                child: OutlinedButton.icon(
                  key: ServiceDetailSheet.whatsappButtonKey,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(140, 56),
                  ),
                  onPressed: () =>
                      open(ContactLauncher.whatsapp, waNumber, 'WhatsApp'),
                  icon: const Icon(Icons.chat_rounded),
                  label: const Text('WhatsApp'),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final (label, value) in lines)
          Row(
            children: [
              Expanded(child: Text('$label: $value', style: texto.bodyLarge)),
              TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: value));
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text('$label copiado.')));
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copiar'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildRatingForm(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    final canSave = !_saving && _stars > 0 && _hasChanges;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Califica este servicio', style: texto.titleMedium),
        const SizedBox(height: 8),
        Center(
          child: StarRatingInput(
            value: _stars,
            onChanged: _saving ? null : (value) => unawaited(_onStarTap(value)),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Toca la misma estrella otra vez para quitar tu calificación.',
          style: texto.bodyMedium?.copyWith(color: esquema.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        TextField(
          inputFormatters: const [OffensiveWordsFormatter()],
          key: ServiceDetailSheet.commentKey,
          controller: _comment,
          maxLength: ServiceDetailSheet.maxComment,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => _touched = true,
          style: texto.bodyLarge,
          decoration: InputDecoration(
            labelText: 'Comentario (opcional)',
            hintText: 'Ej: Llegó a la hora y dejó todo limpio',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: ServiceDetailSheet.saveKey,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: canSave ? () => unawaited(_save()) : null,
                icon: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.star_rounded),
                label: const Text('Guardar calificación'),
              ),
            ),
            if (_mine != null) ...[
              const SizedBox(width: 12),
              SyncStatusChip.fromPending(_mine!.isPending),
            ],
          ],
        ),
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
    );
  }

  Widget _buildRatingsList(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final shown = _endorsements.take(_maxShownRatings).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Calificaciones de vecinos', style: texto.titleMedium),
        const SizedBox(height: 8),
        if (_loadingList)
          Text('Cargando calificaciones…', style: texto.bodyLarge)
        else if (shown.isEmpty)
          Text('Todavía nadie calificó este servicio.', style: texto.bodyLarge)
        else
          for (final item in shown)
            _ReviewTile(
              name: item.endorserUserId == _userId
                  ? 'Tú'
                  : (item.endorserName ?? 'Un vecino'),
              rating: item.rating,
              comment: item.shortComment,
              when: PostMetaLabel.timeAgo(item.updatedAt),
              pending: item.endorserUserId == _userId && item.isPending,
            ),
        if (_endorsements.length > _maxShownRatings)
          Text(
            'Y ${_endorsements.length - _maxShownRatings} calificaciones más.',
            style: texto.bodyMedium,
          ),
      ],
    );
  }
}

/// Una reseña: quién la publicó, sus estrellas, cuándo y su comentario.
class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.name,
    required this.rating,
    required this.comment,
    required this.when,
    required this.pending,
  });

  final String name;
  final int? rating;
  final String? comment;
  final String? when;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final colores = MiBarrioColors.of(context);
    final hasComment = comment != null && comment!.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: colores.accentSoft,
            child: Text(
              name.characters.first.toUpperCase(),
              style: TextStyle(
                color: colores.accentText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(name, style: texto.titleSmall)),
                    if (when != null) Text(when!, style: texto.labelSmall),
                  ],
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (rating != null)
                      StarRatingDisplay(
                        rating: rating!.toDouble(),
                        size: 18,
                        showValue: false,
                      )
                    else
                      Text('Visto bueno', style: texto.bodyMedium),
                    if (pending) SyncStatusChip.fromPending(true),
                  ],
                ),
                if (hasComment) ...[
                  const SizedBox(height: 4),
                  Text(comment!, style: texto.bodyLarge),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fotos del servicio en tira horizontal; al tocar una se abre con zoom.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.photos, required this.title});

  final List<String> photos;
  final String title;

  @override
  Widget build(BuildContext context) {
    final images = [for (final p in photos) base64Decode(p)];
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) => Semantics(
          image: true,
          button: true,
          label:
              'Foto ${i + 1} de ${images.length} de $title. Toca para ampliar.',
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  backgroundColor: Colors.black,
                  appBar: AppBar(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                  ),
                  body: PageView(
                    controller: PageController(initialPage: i),
                    children: [
                      for (final img in images)
                        Center(
                          child: InteractiveViewer(
                            maxScale: 5,
                            child: SafeMemoryImage(img),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SafeMemoryImage(
                images[i],
                width: images.length == 1 ? 260 : 200,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
