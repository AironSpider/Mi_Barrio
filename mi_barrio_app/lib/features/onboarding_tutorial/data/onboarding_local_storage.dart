import 'package:shared_preferences/shared_preferences.dart';

/// Recuerda, por cuenta, si el vecino ya vio el tutorial (no se repite al reabrir).
///
/// Mínimo para el Sprint 11 (Dev 3); Dev 2 puede sincronizarlo además con
/// `users.tutorial_completed` del perfil.
class OnboardingLocalStorage {
  static String _key(String userId) => 'tutorial_completed_$userId';

  Future<bool> isCompleted(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(userId)) ?? false;
  }

  Future<void> markCompleted(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(userId), true);
  }
}
