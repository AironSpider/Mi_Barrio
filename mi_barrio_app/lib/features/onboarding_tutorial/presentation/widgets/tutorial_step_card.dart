import 'package:flutter/material.dart';

/// Un paso del tutorial: ícono grande, título y explicación corta.
class TutorialStepCard extends StatelessWidget {
  const TutorialStepCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 64, color: scheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 32),
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 16),
          Text(description, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
