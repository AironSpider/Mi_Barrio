import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/barrio_context/emergency_mode_provider.dart';
import 'core/barrio_context/tenant_session.dart';
import 'core/network/connectivity_monitor.dart';
import 'core/sync_manager/sync_coordinator.dart';
import 'core/ui_kit/app_theme.dart';
import 'core/ui_kit/main_navigation_shell.dart';
import 'core/ui_kit/quick_publish_launcher.dart';
import 'features/auth_barrio/presentation/providers/auth_provider.dart';
import 'features/auth_barrio/domain/entities/user_entity.dart';
import 'features/auth_barrio/presentation/screens/login_screen.dart';
import 'features/auth_barrio/presentation/screens/neighborhood_admin_screen.dart';
import 'features/auth_barrio/presentation/screens/platform_admin_screen.dart';
import 'features/emergency_support/data/repositories/emergency_repository_impl.dart';
import 'features/emergency_support/presentation/providers/emergency_provider.dart';
import 'features/emergency_support/presentation/widgets/sos_sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await ConnectivityMonitor.instance.start();
  // Dev 2: estado de emergencia guardado + sincronización automática
  // (al abrir, al volver internet, tras cada publicación y cada 60 s).
  await EmergencyModeProvider.instance.load();
  // SOS guardados en SQLite + sync (antes: solo en memoria).
  EmergencyReports.use(EmergencyRepositoryImpl());
  // En emergencia se sincroniza cada 15 s; en modo normal, cada 60 s.
  EmergencyModeProvider.instance.isActive.addListener(() {
    SyncCoordinator.instance.setInterval(_syncInterval());
  });
  runApp(const ProviderScope(child: MiBarrioApp()));
}

Duration _syncInterval() => EmergencyModeProvider.instance.isActive.value
    ? const Duration(seconds: 15)
    : const Duration(seconds: 60);

class MiBarrioApp extends StatefulWidget {
  const MiBarrioApp({super.key, this.initialEmergencyMode = false});

  final bool initialEmergencyMode;

  @override
  State<MiBarrioApp> createState() => _MiBarrioAppState();
}

class _MiBarrioAppState extends State<MiBarrioApp> {
  late bool _isEmergencyMode;

  @override
  void initState() {
    super.initState();
    _isEmergencyMode =
        widget.initialEmergencyMode ||
        EmergencyModeProvider.instance.isActive.value;
    EmergencyModeProvider.instance.isActive.addListener(
      _onEmergencyModeChanged,
    );
  }

  void _onEmergencyModeChanged() {
    final active = EmergencyModeProvider.instance.isActive.value;
    if (_isEmergencyMode != active) {
      setState(() => _isEmergencyMode = active);
    }
  }

  @override
  void dispose() {
    EmergencyModeProvider.instance.isActive.removeListener(
      _onEmergencyModeChanged,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mi Barrio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.of(isEmergency: _isEmergencyMode),
      home: _AuthGate(
        isEmergencyMode: _isEmergencyMode,
        onEmergencyPreviewChanged: kDebugMode
            ? (value) => setState(() => _isEmergencyMode = value)
            : null,
      ),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate({
    required this.isEmergencyMode,
    required this.onEmergencyPreviewChanged,
  });

  final bool isEmergencyMode;
  final ValueChanged<bool>? onEmergencyPreviewChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authProvider, (previous, next) {
      final user = next.user;
      if (user != null) {
        if (user.role == UserRole.superAdmin) {
          TenantSession.instance.applyPlatformAdmin(user.id);
        } else if (user.tenantId != null) {
          TenantSession.instance.applyAuthenticatedUser(
            authenticatedTenantId: user.tenantId!,
            authenticatedUserId: user.id,
            authenticatedTenantName: user.tenantName ?? '',
            authenticatedRole: user.role.apiValue,
            authenticatedInviteCode: user.joinCode,
            authenticatedIsApproved: user.isApproved,
            authenticatedCenterLat: user.centerLat ?? 0,
            authenticatedCenterLng: user.centerLng ?? 0,
          );
        }
        if (user.role == UserRole.vecino || user.role == UserRole.comerciante) {
          unawaited(
            SyncCoordinator.instance.start(
              syncImmediately: true,
              interval: _syncInterval(),
            ),
          );
        } else {
          unawaited(SyncCoordinator.instance.stop());
        }
      } else if (next.status == AuthStatus.unauthenticated ||
          next.status == AuthStatus.error) {
        TenantSession.instance.clearAuthenticatedUser();
        unawaited(SyncCoordinator.instance.stop());
      }
    });

    final auth = ref.watch(authProvider);
    if (auth.status == AuthStatus.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final user = auth.user;
    if (user == null) return const LoginScreen();

    return switch (user.role) {
      UserRole.superAdmin => PlatformAdminScreen(user: user),
      UserRole.adminBarrio => NeighborhoodAdminScreen(user: user),
      UserRole.comerciante || UserRole.vecino => MainNavigationShell(
        isEmergencyMode: isEmergencyMode,
        // En emergencia el botón principal es "Pedir ayuda" (SOS en 3 clics).
        onPublish: () => isEmergencyMode
            ? showSosSheet(context)
            : QuickPublishLauncher.open(
                context,
                isEmergencyMode: isEmergencyMode,
              ),
        onEmergencyPreviewChanged: onEmergencyPreviewChanged,
      ),
    };
  }
}
