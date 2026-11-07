import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/ui_kit/app_theme.dart';
import 'core/ui_kit/main_navigation_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Dev 2: inicialización de SQLite y SyncWorker aquí, antes de runApp.
  runApp(const MiBarrioApp());
}

class MiBarrioApp extends StatefulWidget {
  const MiBarrioApp({super.key, this.initialEmergencyMode = false});

  final bool initialEmergencyMode;

  @override
  State<MiBarrioApp> createState() => _MiBarrioAppState();
}

class _MiBarrioAppState extends State<MiBarrioApp> {
  // Sprint 8: reemplazar por emergency_mode_provider.dart (estado del barrio).
  late bool _isEmergencyMode = widget.initialEmergencyMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mi Barrio',
      debugShowCheckedModeBanner: false,
      // MaterialApp anima el cambio de tema: la app "evoluciona" visualmente.
      theme: AppTheme.of(isEmergency: _isEmergencyMode),
      home: MainNavigationShell(
        isEmergencyMode: _isEmergencyMode,
        onEmergencyPreviewChanged: kDebugMode
            ? (value) => setState(() => _isEmergencyMode = value)
            : null,
      ),
    );
  }
}
