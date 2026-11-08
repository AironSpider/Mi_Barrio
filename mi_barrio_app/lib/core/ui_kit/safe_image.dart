import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Foto guardada en el teléfono. Si los datos están dañados muestra un ícono
/// en vez de romper la pantalla.
class SafeMemoryImage extends StatelessWidget {
  const SafeMemoryImage(
    this.bytes, {
    super.key,
    this.width,
    this.height,
    this.fit,
  });

  final Uint8List bytes;
  final double? width;
  final double? height;
  final BoxFit? fit;

  @override
  Widget build(BuildContext context) => Image.memory(
    bytes,
    width: width,
    height: height,
    fit: fit,
    errorBuilder: (context, _, _) => Container(
      width: width,
      height: height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.broken_image_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
