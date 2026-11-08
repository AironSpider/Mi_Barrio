import 'package:flutter/widgets.dart';

/// Abre el formulario de "Publicar" de la pestaña actual desde cualquier
/// parte de ella (por ejemplo, el botón de una lista vacía).
///
/// Lo pone la barra de navegación principal; fuera de ella (tests, pantallas
/// sueltas) no existe y las listas vacías simplemente no muestran el botón.
class PublishAction extends InheritedWidget {
  const PublishAction({
    super.key,
    required this.onPublish,
    required super.child,
  });

  final VoidCallback onPublish;

  static VoidCallback? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PublishAction>()?.onPublish;

  @override
  bool updateShouldNotify(PublishAction oldWidget) =>
      oldWidget.onPublish != onPublish;
}
