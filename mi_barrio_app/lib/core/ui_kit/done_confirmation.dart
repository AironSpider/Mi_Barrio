import 'package:flutter/material.dart';

/// Confirmación grande y simple después de publicar: "¡Listo!" + qué pasó.
///
/// Se ve sin leer mucho (ícono de check) y aclara que funciona sin señal.
class DoneConfirmation {
  DoneConfirmation._();

  static const snackBarKey = ValueKey('done_confirmation');

  static void show(ScaffoldMessengerState messenger, String detail) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: snackBarKey,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '¡Listo!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(detail),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }
}
