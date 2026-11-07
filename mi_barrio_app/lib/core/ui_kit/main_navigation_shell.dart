import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/emergency_support/presentation/screens/emergency_map_screen.dart';
import '../../features/profile_me/presentation/screens/profile_screen.dart';
import '../../features/proximity_services/presentation/screens/services_directory_screen.dart';
import '../../features/solidarity_network/presentation/screens/collaborative_wall_screen.dart';
import 'app_theme.dart';
import 'quick_publish_fab.dart';

class ShellTab {
  const ShellTab({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
  });

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
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      builder: (_) => const ProfileScreen(),
    ),
  ];
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({
    super.key,
    required this.isEmergencyMode,
    this.onPublish,
    this.onEmergencyPreviewChanged,
  });

  final bool isEmergencyMode;
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
    final tabs = ShellTabs.all;
    final previewChanged = widget.onEmergencyPreviewChanged;

    return Scaffold(
      appBar: AppBar(
        // Título y chip comparten el espacio: con texto grande se acortan
        // (puntos suspensivos) en vez de desbordar.
        title: Row(
          children: [
            const Flexible(
              child: Text('Mi Barrio', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (widget.isEmergencyMode) ...[
              const SizedBox(width: 8),
              const Flexible(child: _EmergencyChip()),
            ],
          ],
        ),
        actions: [
          if (kDebugMode && previewChanged != null)
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
              label: 'Modo emergencia activo',
              liveRegion: true,
              child: Container(height: 4, color: AppPalette.emergencyStripe),
            ),
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
      floatingActionButton: QuickPublishFab(
        isEmergencyMode: widget.isEmergencyMode,
        onPressed: _handlePublish,
      ),
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


/// Chip "Emergencia" en la barra superior: el estado no se comunica solo con color.
class _EmergencyChip extends StatelessWidget {
  const _EmergencyChip();

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        label: 'Modo emergencia activo',
        excludeSemantics: true,
        child: Container(
          key: MainNavigationShell.emergencyChipKey,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppPalette.card,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: AppPalette.emergencyOnPrimaryContainer,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Emergencia',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: texto.labelMedium?.copyWith(
                    color: AppPalette.emergencyOnPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
