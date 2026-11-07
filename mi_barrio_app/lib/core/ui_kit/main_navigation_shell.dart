import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/emergency_support/presentation/screens/emergency_map_screen.dart';
import '../../features/emergency_support/presentation/screens/humanitarian_board_screen.dart';
import '../../features/proximity_services/presentation/screens/services_directory_screen.dart';
import '../../features/solidarity_network/presentation/screens/collaborative_wall_screen.dart';
import 'quick_publish_fab.dart';

/// Una pestaña de la navegación principal.
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

/// Pestañas por modo. Para agregar una pantalla nueva basta con sumar un
/// [ShellTab] aquí (escalabilidad por features).
class ShellTabs {
  ShellTabs._();

  /// Modo Día a Día: economía local primero.
  static final List<ShellTab> day = [
    ShellTab(
      id: 'oficios',
      label: 'Oficios',
      icon: Icons.handyman_outlined,
      selectedIcon: Icons.handyman_rounded,
      builder: (_) => const ServicesDirectoryScreen(),
    ),
    ShellTab(
      id: 'muro',
      label: 'Muro',
      icon: Icons.volunteer_activism_outlined,
      selectedIcon: Icons.volunteer_activism_rounded,
      builder: (_) => const CollaborativeWallScreen(),
    ),
    ShellTab(
      id: 'emergencia',
      label: 'Emergencia',
      icon: Icons.health_and_safety_outlined,
      selectedIcon: Icons.health_and_safety_rounded,
      builder: (_) => const HumanitarianBoardScreen(isEmergencyMode: false),
    ),
  ];

  /// Modo Emergencia: la app "evoluciona" y prioriza la ayuda humanitaria.
  static final List<ShellTab> emergency = [
    ShellTab(
      id: 'ayuda',
      label: 'Ayuda',
      icon: Icons.sos_outlined,
      selectedIcon: Icons.sos_rounded,
      builder: (_) => const HumanitarianBoardScreen(isEmergencyMode: true),
    ),
    ShellTab(
      id: 'mapa',
      label: 'Mapa',
      icon: Icons.map_outlined,
      selectedIcon: Icons.map_rounded,
      builder: (_) => const EmergencyMapScreen(),
    ),
    ShellTab(
      id: 'apoyo',
      label: 'Apoyo',
      icon: Icons.handyman_outlined,
      selectedIcon: Icons.handyman_rounded,
      builder: (_) => const ServicesDirectoryScreen(emergencyOnly: true),
    ),
    ShellTab(
      id: 'recursos',
      label: 'Recursos',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2_rounded,
      builder: (_) => const CollaborativeWallScreen(criticalResourcesOnly: true),
    ),
  ];

  static List<ShellTab> forMode({required bool isEmergency}) =>
      isEmergency ? emergency : day;
}

/// Estructura principal: AppBar + pestañas inferiores + botón (+).
///
/// El estado de emergencia llega desde afuera. En el Sprint 8 se conecta a
/// `emergency_mode_provider.dart` (Dev 2); mientras tanto, en modo debug hay
/// un interruptor de vista previa en la AppBar.
class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({
    super.key,
    required this.isEmergencyMode,
    this.onPublish,
    this.onEmergencyPreviewChanged,
  });

  final bool isEmergencyMode;

  /// Clic 1 del flujo de publicación. Se conecta al modal en el Sprint 2.
  final VoidCallback? onPublish;

  /// Solo para pruebas en desarrollo. Si es null, no se muestra el interruptor.
  final ValueChanged<bool>? onEmergencyPreviewChanged;

  static const emergencyBannerKey = ValueKey('emergency_banner');
  static const emergencyPreviewSwitchKey = ValueKey('emergency_preview_switch');

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _index = 0;

  @override
  void didUpdateWidget(covariant MainNavigationShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Al cambiar de modo, la app abre en la pestaña prioritaria del nuevo modo
    // (en emergencia: el tablero de ayuda).
    if (oldWidget.isEmergencyMode != widget.isEmergencyMode) {
      _index = 0;
    }
  }

  void _handlePublish() {
    final onPublish = widget.onPublish;
    if (onPublish != null) {
      onPublish();
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('La publicación rápida estará lista pronto.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ShellTabs.forMode(isEmergency: widget.isEmergencyMode);
    final index = _index.clamp(0, tabs.length - 1);
    final previewChanged = widget.onEmergencyPreviewChanged;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Barrio'),
        actions: [
          if (kDebugMode && previewChanged != null)
            _EmergencyPreviewSwitch(
              value: widget.isEmergencyMode,
              onChanged: previewChanged,
            ),
        ],
      ),
      body: Column(
        children: [
          if (widget.isEmergencyMode) const _EmergencyBanner(),
          Expanded(
            child: IndexedStack(
              // Una pila por modo para no mezclar el estado de pestañas.
              key: ValueKey(widget.isEmergencyMode),
              index: index,
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
        selectedIndex: index,
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

class _EmergencyBanner extends StatelessWidget {
  const _EmergencyBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      key: MainNavigationShell.emergencyBannerKey,
      liveRegion: true,
      container: true,
      child: Material(
        color: scheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: scheme.onPrimaryContainer, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Modo emergencia activo. Prioriza los pedidos de ayuda.',
                  style: textTheme.titleMedium
                      ?.copyWith(color: scheme.onPrimaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmergencyPreviewSwitch extends StatelessWidget {
  const _EmergencyPreviewSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: 'Vista previa del modo emergencia (solo desarrollo)',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bug_report_outlined),
            Switch(
              key: MainNavigationShell.emergencyPreviewSwitchKey,
              value: value,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
