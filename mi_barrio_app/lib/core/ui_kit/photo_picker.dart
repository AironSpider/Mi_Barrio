import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Elige una foto ya comprimida (máx. 800 px, calidad 60). Los tests la reemplazan.
typedef PhotoPicker = Future<List<int>?> Function(ImageSource source);

Future<List<int>?> _defaultPicker(ImageSource source) async {
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 800,
    maxHeight: 800,
    imageQuality: 60,
  );
  return file?.readAsBytes();
}

/// Selector de fotos de toda la app (reemplazable en pruebas).
PhotoPicker appPhotoPicker = _defaultPicker;

/// Pregunta "Cámara o Galería" y devuelve la foto en base64 (null si se canceló).
/// Lanza [StateError] si la foto supera [maxB64Length].
Future<String?> pickPhotoB64(
  BuildContext context, {
  required int maxB64Length,
}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            minTileHeight: 64,
            leading: const Icon(Icons.photo_camera_rounded),
            title: const Text('Tomar foto'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            minTileHeight: 64,
            leading: const Icon(Icons.photo_library_rounded),
            title: const Text('Elegir de la galería'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  final bytes = await appPhotoPicker(source);
  if (bytes == null) return null;
  final b64 = base64Encode(bytes);
  if (b64.length > maxB64Length) {
    throw StateError(
      'La foto es muy pesada. Prueba con otra o tómala de más lejos.',
    );
  }
  return b64;
}
