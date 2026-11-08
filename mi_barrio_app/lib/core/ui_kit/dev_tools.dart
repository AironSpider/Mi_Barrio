import 'package:flutter/foundation.dart';

/// Herramientas de desarrollo (interruptor 🐞 de emergencia, avisos internos).
///
/// Nunca aparecen en el build de demo: en release/profile están apagadas, y
/// en debug también se apagan si el build apunta a un servidor real
/// (`--dart-define=API_BASE_URL=...`) o si se marca `--dart-define=DEMO_BUILD=true`.
class DevTools {
  DevTools._();

  static const _demoBuild = bool.fromEnvironment('DEMO_BUILD');
  static const _apiFromBuild = String.fromEnvironment('API_BASE_URL');

  static bool get enabled =>
      kDebugMode && !_demoBuild && _apiFromBuild.isEmpty;
}
