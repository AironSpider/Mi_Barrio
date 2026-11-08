import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/emergency_support/presentation/screens/emergency_map_screen.dart';
import '../../features/profile_me/presentation/screens/profile_screen.dart';
import '../../features/proximity_services/presentation/screens/services_directory_screen.dart';
import '../../features/proximity_services/presentation/screens/merchant_business_screen.dart';
import '../../features/solidarity_network/presentation/screens/collaborative_wall_screen.dart';
import 'app_theme.dart';
import 'dev_tools.dart';
import 'global_sync_status_bar.dart';
import 'quick_publish_fab.dart';
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
        label: 'Mi negocio',
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
  final Future<bool> Function()? onPublish;
  final ValueChanged<bool>? onEmergencyPreviewChanged;

  static const emergencyBannerKey = ValueKey('emergency_banner');
  static const emergencyChipKey = ValueKey('emergency_chip');

  /// Índices de pestañas (orden de [ShellTabs.all]).
  static const apoyoTabIndex = 1;
  static const mapaTabIndex = 2;
  static const emergencyPreviewSwitchKey = ValueKey('emergency_preview_switch');

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _index = 0;

  Future<void> _handlePublish() async {
    final onPublish = widget.onPublish;
    if (onPublish != null) {
      final published = await onPublish();
      // Tras publicar se muestra el resultado: el muro (Apoyo) en modo normal,
      // o el Mapa de ayuda tras pedir ayuda en emergencia.
      final destino = widget.isEmergencyMode
          ? MainNavigationShell.mapaTabIndex
          : MainNavigationShell.apoyoTabIndex;
      if (published && mounted && _index != destino) {
        setState(() => _index = destino);
      }
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('La publicación rápida estará lista pronto.'),
        ),
      );
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
          ],
        ),
        actions: [
          if (DevTools.enabled && previewChanged != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: 'Vista previa de emergencia (solo desarrollo)',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bug_report_outlined),
                    Switch(
                      key: MainNavigationShell.emergencyPreviewSwitchKey,
                      value: widget.isEmergencyMode,
                      onChanged: previewChanged,
                    ),
                  ],
                ),
              ),
            ),
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
