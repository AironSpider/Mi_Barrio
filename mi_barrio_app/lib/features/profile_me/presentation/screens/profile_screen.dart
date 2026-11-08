import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/database_sqlite/history_dao.dart';
import '../../../../core/sync_manager/pending_changes.dart';
import '../../../../core/ui_kit/app_theme.dart';
import '../../../../core/ui_kit/photo_picker.dart';
import '../../../../core/ui_kit/sync_status_chip.dart';
import '../../../auth_barrio/presentation/providers/auth_provider.dart';
import '../../../chat/presentation/conversations_screen.dart';
import '../../../legal/legal_screens.dart';
import '../../../proximity_services/data/models/service_model.dart';
import '../../data/profile_local_storage.dart';
import '../../data/user_profile_model.dart';
import 'edit_profile_screen.dart';
import 'history_screen.dart';

/// Pestaña "Tú": quién soy, mi actividad y accesos rápidos.
///
/// Los datos se ven aquí en modo lectura; se editan en un solo lugar
/// ("Editar perfil"). La foto se cambia tocando la cámara del avatar.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.storage, this.history});

  final ProfileLocalStorage? storage;
  final HistoryDao? history;

  static const editKey = ValueKey('open_edit_profile');
  static const photoKey = ValueKey('profile_change_photo');
  static const legalKey = ValueKey('open_legal');
  static const deleteAccountKey = ValueKey('delete_account_button');
  static const deleteConfirmFieldKey = ValueKey('delete_account_confirm_field');
  static const deleteConfirmKey = ValueKey('delete_account_confirm');

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final ProfileLocalStorage _storage =
      widget.storage ?? ProfileLocalStorage();
  late final HistoryDao _history = widget.history ?? HistoryDao();

  UserProfileModel? _profile;
  HistoryCounts? _counts;
  bool _isLoading = true;
  bool _savingPhoto = false;
  String? _error;

  TenantSession get _session => TenantSession.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadProfile());
    });
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _storage.getProfile(_session.userId);
      final counts = await _history.counts(_session.tenantId, _session.userId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _counts = counts;
        _isLoading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar tu perfil.';
        _isLoading = false;
      });
    }
  }

  Future<void> _changePhoto() async {
    try {
      final b64 = await pickPhotoB64(context, maxB64Length: 100 * 1024);
      if (b64 == null || !mounted) return;
      setState(() => _savingPhoto = true);
      final updated = await _storage.updatePhoto(
        userId: _session.userId,
        tenantId: _session.tenantId,
        photoB64: b64,
      );
      if (mounted) setState(() => _profile = updated);
      _snack('Foto actualizada. Se enviará solo cuando haya señal.');
    } on StateError catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo cambiar la foto.');
    } finally {
      if (mounted) setState(() => _savingPhoto = false);
    }
  }

  Future<void> _openEdit() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditProfileScreen(storage: _storage),
      ),
    );
    if (mounted) unawaited(_loadProfile());
  }

  void _openHistory() =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const HistoryScreen()));

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Si hay cambios sin sincronizar, pide confirmación antes de cerrar sesión.
  Future<void> _logout() async {
    final n = await PendingChanges.count(_session.tenantId);
    final aviso = PendingChanges.logoutWarning(n);
    if (aviso != null) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cambios sin sincronizar'),
          content: Text(aviso),
          actions: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Seguir aquí'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Cerrar sesión'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    await ref.read(authProvider.notifier).logout();
  }

  /// "Eliminar mi cuenta": confirma escribiendo ELIMINAR y borra en el servidor.
  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text('Eliminando tu cuenta…')),
            ],
          ),
        ),
      ),
    );
    final error = await ref.read(authProvider.notifier).deleteAccount();
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            error ?? 'Tu cuenta y tus datos fueron eliminados. ¡Gracias por ser parte de Mi Barrio!',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = ref.watch(authProvider).user;
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final profile = _profile;
    final name = profile?.fullName ?? user?.fullName ?? '';
    final counts = _counts;

    return RefreshIndicator(
      onRefresh: _loadProfile,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          _Header(
            name: name,
            roleLabel: user?.role.label ?? profile?.roleLabel ?? '',
            neighborhood: user?.tenantName ?? _session.tenantName,
            initials: profile?.initials ?? '',
            photoB64: profile?.photoB64,
            pending: profile?.isPending,
            savingPhoto: _savingPhoto,
            onChangePhoto: profile == null ? null : _changePhoto,
            onEdit: _openEdit,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
            ),
          ],
          if (counts != null) ...[
            const _SectionTitle('Tu actividad'),
            Row(
              children: [
                _Stat(
                  icon: Icons.handyman_rounded,
                  value: counts.services,
                  label: 'Servicios',
                  onTap: _openHistory,
                ),
                const SizedBox(width: 10),
                _Stat(
                  icon: Icons.volunteer_activism_rounded,
                  value: counts.posts,
                  label: 'Favores',
                  onTap: _openHistory,
                ),
                const SizedBox(width: 10),
                _Stat(
                  icon: Icons.warning_amber_rounded,
                  value: counts.sos,
                  label: 'Pedidos',
                  onTap: _openHistory,
                ),
              ],
            ),
          ],
          const _SectionTitle('Tu información'),
          _InfoCard(
            profile: profile,
            onEdit: _openEdit,
            // "Negocio" solo tiene sentido para quien ofrece servicios.
            showBusiness:
                (profile?.role ?? _session.role) == UserRole.comerciante,
          ),
          const _SectionTitle('Accesos rápidos'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _LinkTile(
                  key: const ValueKey('open_inbox'),
                  icon: Icons.forum_rounded,
                  title: 'Mis mensajes',
                  subtitle: 'Conversaciones por favores y servicios',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ConversationsScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _LinkTile(
                  key: const ValueKey('open_history'),
                  icon: Icons.history_rounded,
                  title: 'Mi historial',
                  subtitle: 'Tus servicios, favores y pedidos de ayuda',
                  onTap: _openHistory,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _LinkTile(
                  key: ProfileScreen.legalKey,
                  icon: Icons.policy_outlined,
                  title: 'Términos y privacidad',
                  subtitle: 'Reglas, tus datos y el manual de usuario',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LegalDocumentsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            key: const ValueKey('logout_button'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
            ),
            onPressed: () => unawaited(_logout()),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Cerrar sesión'),
          ),
          // El admin del barrio no puede borrarse desde la app (el servidor lo explica).
          if (user?.role.apiValue != 'ADMIN_BARRIO') ...[
            const SizedBox(height: 12),
            TextButton.icon(
              key: ProfileScreen.deleteAccountKey,
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: scheme.error,
              ),
              onPressed: () => unawaited(_deleteAccount()),
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Eliminar mi cuenta'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Portada del perfil: foto (o iniciales) con botón de cámara, nombre, rol y barrio.
class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.roleLabel,
    required this.neighborhood,
    required this.initials,
    required this.photoB64,
    required this.pending,
    required this.savingPhoto,
    required this.onChangePhoto,
    required this.onEdit,
  });

  final String name;
  final String roleLabel;
  final String neighborhood;
  final String initials;
  final String? photoB64;
  final bool? pending;
  final bool savingPhoto;
  final VoidCallback? onChangePhoto;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = MiBarrioColors.of(context);
    final photo = photoB64;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(height: 56, color: colores.accentSoft),
          Transform.translate(
            offset: const Offset(0, -40),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: CircleAvatar(
                        radius: 44,
                        backgroundColor: colores.accentSoft,
                        backgroundImage: photo == null
                            ? null
                            : MemoryImage(base64Decode(photo)),
                        // Una foto dañada no rompe la pantalla: quedan las iniciales.
                        onBackgroundImageError: photo == null
                            ? null
                            : (_, _) {},
                        child: photo == null
                            ? Text(
                                initials.isEmpty ? '?' : initials,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: colores.accentText,
                                ),
                              )
                            : null,
                      ),
                    ),
                    if (onChangePhoto != null)
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: IconButton.filled(
                          key: ProfileScreen.photoKey,
                          tooltip: 'Cambiar foto de perfil',
                          onPressed: savingPhoto ? null : onChangePhoto,
                          icon: savingPhoto
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.photo_camera_rounded),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Semantics(
                  header: true,
                  child: Text(
                    name.isEmpty ? 'Mi perfil' : name,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    roleLabel,
                    neighborhood,
                  ].where((t) => t.isNotEmpty).join(' · '),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (pending != null) ...[
                  const SizedBox(height: 8),
                  SyncStatusChip.fromPending(pending!),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: ProfileScreen.editKey,
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Editar perfil'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final int value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = MiBarrioColors.of(context);
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Semantics(
            button: true,
            label: '$value $label. Ver historial.',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              child: Column(
                children: [
                  Icon(icon, color: colores.accentText),
                  const SizedBox(height: 4),
                  Text('$value', style: theme.textTheme.headlineSmall),
                  Text(
                    label,
                    style: theme.textTheme.labelMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Datos del perfil en modo lectura. Lo que falta se ofrece completar.
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.profile,
    required this.onEdit,
    required this.showBusiness,
  });

  final UserProfileModel? profile;
  final VoidCallback onEdit;
  final bool showBusiness;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final rows = <(IconData, String, String?)>[
      (Icons.call_outlined, 'Teléfono', p?.phone),
      (Icons.chat_outlined, 'WhatsApp', p?.whatsapp),
      (Icons.mail_outline_rounded, 'Correo de contacto', p?.emailContacto),
      (Icons.home_outlined, 'Referencia de domicilio', p?.addressReference),
      if (showBusiness) (Icons.storefront_outlined, 'Negocio', _business(p)),
      (
        Icons.public_rounded,
        'Redes',
        [
          p?.facebookUrl,
          p?.instagramUrl,
        ].whereType<String>().where((s) => s.isNotEmpty).join('\n'),
      ),
    ];
    final missing = rows
        .where((r) => r.$3 == null || r.$3!.trim().isEmpty)
        .length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (icon, label, value) in rows)
              ListTile(
                minTileHeight: 56,
                leading: Icon(icon),
                title: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                subtitle: Text(
                  value == null || value.trim().isEmpty
                      ? 'Sin completar'
                      : value,
                  style: value == null || value.trim().isEmpty
                      ? TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        )
                      : Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            if (missing > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: Text(
                    missing == 1
                        ? 'Completa 1 dato para que tus vecinos te ubiquen mejor'
                        : 'Completa $missing datos para que tus vecinos te ubiquen mejor',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String? _business(UserProfileModel? p) {
    if (p == null) return null;
    final parts = [
      p.publisherName,
      if (p.publisherType != null) PublisherType.labels[p.publisherType],
      if (p.publisherCategory != null)
        ServiceCategory.labels[p.publisherCategory] ?? p.publisherCategory,
    ].whereType<String>().where((s) => s.isNotEmpty);
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 64,
    leading: Icon(icon, color: MiBarrioColors.of(context).accentText),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

/// Pide escribir ELIMINAR para que nadie borre su cuenta por un toque sin querer.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();

  bool get _ready => _controller.text.trim().toUpperCase() == 'ELIMINAR';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
      title: const Text('¿Eliminar tu cuenta?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Esto no se puede deshacer:\n'
              '• Se borran tu nombre, correo, teléfono y fotos.\n'
              '• Tus servicios, favores, comentarios y mensajes dejan de verse.\n'
              '• Se cierra tu sesión en este celular.\n\n'
              'Necesitas internet. Para confirmar, escribe ELIMINAR:',
            ),
            const SizedBox(height: 12),
            TextField(
              key: ProfileScreen.deleteConfirmFieldKey,
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'ELIMINAR',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: ProfileScreen.deleteConfirmKey,
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _ready ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Eliminar cuenta'),
        ),
      ],
    );
  }
}
