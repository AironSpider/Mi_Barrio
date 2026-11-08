import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../features/emergency_support/presentation/screens/emergency_map_screen.dart';
import '../../features/onboarding_tutorial/presentation/screens/tutorial_screen.dart';
import '../../features/proximity_services/presentation/widgets/offer_service_sheet.dart';
import '../../features/solidarity_network/presentation/screens/apoyo_screen.dart';
import '../../features/profile_me/presentation/screens/profile_screen.dart';
import '../../features/proximity_services/presentation/screens/services_directory_screen.dart';
import '../../features/proximity_services/presentation/screens/merchant_business_screen.dart';
import '../../features/solidarity_network/presentation/screens/collaborative_wall_screen.dart';
import 'app_theme.dart';
import 'done_confirmation.dart';
import 'publish_action.dart';
import 'global_sync_status_bar.dart';
import 'quick_publish_fab.dart';
import '../barrio_context/emergency_mode_provider.dart';
import '../barrio_context/tenant_session.dart';
import '../sync_manager/sync_coordinator.dart';

class ShellTab {
  const ShellTab({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
    this.showsPublish = true,
  });

  /// false = la pestaña no muestra el botón flotante "Publicar"/"Pedir ayuda".
  final bool showsPublish;
  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final WidgetBuilder builder;
}

class ShellTabs {
  ShellTabs._();

  static final List<ShellTab> all = [
    ShellTab(
      id: 'servicios',
      label: 'Servicios',
      icon: Icons.handyman_outlined,
      selectedIcon: Icons.handyman_rounded,
      builder: (_) => const ServicesDirectoryScreen(),
    ),
    ShellTab(
      id: 'apoyo',
      label: 'Apoyo',
      icon: Icons.volunteer_activism_outlined,
      selectedIcon: Icons.volunteer_activism_rounded,
      builder: (_) => const CollaborativeWallScreen(),
    ),
    ShellTab(
      id: 'mapa',
      label: 'Mapa',
      // En el mapa no se publica (en emergencia sí aparece "Ayuda").
      showsPublish: false,
      icon: Icons.map_outlined,
      selectedIcon: Icons.map_rounded,
      builder: (_) => const EmergencyMapScreen(),
    ),
    ShellTab(
      id: 'tu',
      label: 'Tú',
      showsPublish: false,
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      builder: (_) => const ProfileScreen(),
    ),
  ];

  static List<ShellTab> forCurrentRole() {
    if (!TenantSession.instance.isComerciante) return all;
    return [
      ...all.take(3),
      const ShellTab(
        id: 'negocio',
        // "Mi negocio" no cabía con 5 pestañas y empujaba el ícono.
        label: 'Negocio',
        icon: Icons.storefront_outlined,
        selectedIcon: Icons.storefront_rounded,
        builder: _merchantBusiness,
        showsPublish: false,
      ),
      all.last,
    ];
  }

  static Widget _merchantBusiness(BuildContext context) =>
      const MerchantBusinessScreen();
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({
    super.key,
    required this.isEmergencyMode,
    this.onPublish,
    this.onEmergencyPreviewChanged,
    this.syncPhase,
  });

  final bool isEmergencyMode;

  /// Estado de sync para la barra global (por defecto, el del SyncCoordinator).
  final ValueListenable<SyncPhase>? syncPhase;

  /// Botón "Ayuda" en modo emergencia (pedido de ayuda). En el día a día,
  /// "Publicar" abre el formulario de la pestaña (Servicios o Apoyo).
  final Future<bool> Function()? onPublish;
  final ValueChanged<bool>? onEmergencyPreviewChanged;

  static const emergencyBannerKey = ValueKey('emergency_banner');
  static const emergencyChipKey = ValueKey('emergency_chip');

  /// Índices de pestañas (orden de [ShellTabs.all]).
  static const apoyoTabIndex = 1;
  static const mapaTabIndex = 2;

  /// Interruptor ⚠ de la barra (modo emergencia del vecino).
  static const emergencyPreviewSwitchKey = ValueKey('emergency_preview_switch');
  static const helpButtonKey = ValueKey('help_button');

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _index = 0;

  Future<void> _openTutorial(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) =>
            TutorialScreen(onFinished: () => Navigator.of(ctx).pop()),
      ),
    );
  }

  Future<void> _handlePublish() async {
    final messenger = ScaffoldMessenger.of(context);
    // Emergencia: "Ayuda" abre el pedido de ayuda en cualquier pestaña y
    // después se muestra el Mapa de ayuda.
    if (widget.isEmergencyMode) {
      final onPublish = widget.onPublish;
      if (onPublish == null) return;
      final published = await onPublish();
      if (published && mounted && _index != MainNavigationShell.mapaTabIndex) {
        setState(() => _index = MainNavigationShell.mapaTabIndex);
      }
      return;
    }
    // Día a día: cada pestaña abre SU formulario (Servicios o Apoyo).
    final tabs = ShellTabs.forCurrentRole();
    final tabId = _index < tabs.length ? tabs[_index].id : '';
    final session = TenantSession.instance;
    if (tabId == 'servicios') {
      final profile = await loadMerchantProfile(
        session.userId,
        tenantId: session.tenantId,
      );
      if (!mounted) return;
      final saved = await showOfferServiceSheet(
        context,
        tenantId: session.tenantId,
        userId: session.userId,
        profile: profile,
      );
      if (saved) {
        DoneConfirmation.show(
          messenger,
          'Tu servicio ya está publicado. Se enviará solo cuando haya señal.',
        );
      }
    } else if (tabId == 'apoyo') {
      final saved = await showApoyoScreen(context);
      if (saved) {
        DoneConfirmation.show(
          messenger,
          'Tu publicación ya está en el muro. Se enviará sola cuando haya señal.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ShellTabs.forCurrentRole();
    final previewChanged = widget.onEmergencyPreviewChanged;

    return Scaffold(
      appBar: AppBar(
        // Título y chip comparten el espacio: con texto grande se acortan
        // (puntos suspensivos) en vez de desbordar.
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppPalette.card,
                shape: BoxShape.circle,
              ),
              child: Image.asset(
                'assets/images/logo_mi_barrio.png',
                height: 28,
                excludeFromSemantics: true,
              ),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'Mi Barrio',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            // Ayuda: vuelve a mostrar el tutorial de inicio.
            IconButton(
              key: MainNavigationShell.helpButtonKey,
              tooltip: 'Cómo usar Mi Barrio',
              onPressed: () => _openTutorial(context),
              icon: const FaIcon(
                FontAwesomeIcons.circleInfo,
                size: 20,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          _EmergencyToggle(
            isEmergencyMode: widget.isEmergencyMode,
            onChanged: (value) {
              unawaited(EmergencyModeProvider.instance.setLocal(value));
              previewChanged?.call(value);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (widget.isEmergencyMode)
            Semantics(
              key: MainNavigationShell.emergencyBannerKey,
              liveRegion: true,
              child: const _EmergencyBanner(),
            ),
          GlobalSyncStatusBar(phase: widget.syncPhase),
          Expanded(
            child: PublishAction(
              onPublish: () => unawaited(_handlePublish()),
              child: IndexedStack(
                index: _index,
                children: [
                  for (final tab in tabs)
                    KeyedSubtree(
                      key: ValueKey('tab_${tab.id}'),
                      child: Builder(builder: tab.builder),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      // En emergencia "Pedir ayuda" está en todas las pestañas.
      floatingActionButton:
          widget.isEmergencyMode ||
              (_index < tabs.length && tabs[_index].showsPublish)
          ? QuickPublishFab(
              isEmergencyMode: widget.isEmergencyMode,
              onPressed: _handlePublish,
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final tab in tabs)
            NavigationDestination(
              key: ValueKey('nav_${tab.id}'),
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}

/// Franja "Modo emergencia" de ancho completo bajo la barra superior.
/// El estado no se comunica solo con color: ícono + texto.
class _EmergencyBanner extends StatelessWidget {
  const _EmergencyBanner();

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Container(
      key: MainNavigationShell.emergencyChipKey,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppPalette.emergencyBackground,
        border: Border(
          bottom: BorderSide(color: AppPalette.emergencyStripe, width: 3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 24,
            color: AppPalette.emergencyOnPrimaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Modo emergencia. ',
                    style: texto.labelLarge?.copyWith(
                      color: AppPalette.emergencyOnPrimaryContainer,
                    ),
                  ),
                  TextSpan(
                    text: 'Primero lo urgente y lo más cercano.',
                    style: texto.bodyMedium?.copyWith(
                      color: AppPalette.emergencyOnPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Interruptor ⚠ de la barra: el vecino pasa SU vista a modo emergencia
/// (naranja, solo lo de emergencia y botón "Ayuda"). Si la junta vecinal ya
/// activó la emergencia, queda encendido y bloqueado.
class _EmergencyToggle extends StatelessWidget {
  const _EmergencyToggle({
    required this.isEmergencyMode,
    required this.onChanged,
  });

  final bool isEmergencyMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EmergencyModeProvider.instance.isLockedByTenant,
      builder: (context, locked, _) {
        final on = isEmergencyMode || locked;
        return Tooltip(
          message: locked
              ? 'Emergencia activada por tu junta vecinal'
              : on
              ? 'Salir del modo emergencia'
              : 'Ver el barrio en modo emergencia',
          // Una sola etiqueta para el ícono y el interruptor.
          child: MergeSemantics(
            child: Semantics(
              label: 'Modo emergencia',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ExcludeSemantics(
                    child: FaIcon(
                      FontAwesomeIcons.triangleExclamation,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Switch(
                    key: MainNavigationShell.emergencyPreviewSwitchKey,
                    value: on,
                    onChanged: locked ? null : onChanged,
                    // Apagado: blanco. Encendido: blanco con el punto naranja.
                    thumbColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? AppPalette.emergencyPrimary
                          : Colors.white,
                    ),
                    trackColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.35),
                    ),
                    trackOutlineColor: const WidgetStatePropertyAll(
                      Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
