import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/barrio_context/emergency_mode_provider.dart';
import 'core/network/connectivity_monitor.dart';
import 'core/sync_manager/sync_coordinator.dart';
import 'core/ui_kit/app_theme.dart';
import 'core/ui_kit/main_navigation_shell.dart';
import 'core/ui_kit/quick_publish_launcher.dart';

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
  await SyncCoordinator.instance.start();
  runApp(const MiBarrioApp());
}

class MiBarrioApp extends StatefulWidget {
  const MiBarrioApp({super.key, this.initialEmergencyMode = false});

  final bool initialEmergencyMode;

  @override
  State<MiBarrioApp> createState() => _MiBarrioAppState();
}

class _MiBarrioAppState extends State<MiBarrioApp> {
  late bool _isEmergencyMode = widget.initialEmergencyMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mi Barrio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.of(isEmergency: _isEmergencyMode),
      home: Builder(
        builder: (context) => MainNavigationShell(
          isEmergencyMode: _isEmergencyMode,
          onPublish: () => QuickPublishLauncher.open(
            context,
            isEmergencyMode: _isEmergencyMode,
          ),
          onEmergencyPreviewChanged: kDebugMode
              ? (value) => setState(() => _isEmergencyMode = value)
              : null,
        ),
      ),
    );
  }
}
