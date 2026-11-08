import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/entities/user_entity.dart';
import '../providers/auth_provider.dart';
import '../widgets/neighborhood_emergency_card.dart';
import '../../../proximity_services/presentation/widgets/admin_merchant_approval_panel.dart';

class NeighborhoodAdminScreen extends ConsumerWidget {
  const NeighborhoodAdminScreen({super.key, required this.user});

  final UserEntity user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final joinCode = user.joinCode ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración del barrio'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () => ref.read(authProvider.notifier).logout(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Hola, ${user.fullName}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text('Barrio: ${user.tenantName ?? 'Sin barrio'}'),
          const SizedBox(height: 24),
          if (user.tenantId != null) ...[
            NeighborhoodEmergencyCard(tenantId: user.tenantId!),
            const SizedBox(height: 16),
          ],
          const AdminMerchantApprovalPanel(),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Código para invitar vecinos y comerciantes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  // El código destacado: es lo que la junta dicta o comparte.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SelectableText(
                      joinCode.isEmpty ? 'Código no disponible' : joinCode,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Comparte este código solo con personas que pertenezcan '
                    'a tu barrio.',
                  ),
                  if (joinCode.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: joinCode),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Código copiado')),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('Copiar código'),
                        ),
                        FilledButton.icon(
                          onPressed: () async {
                            final invitation =
                                'Únete a ${user.tenantName ?? 'mi barrio'} '
                                'en Mi Barrio con el código $joinCode.';
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              // Menú del teléfono: WhatsApp, SMS, correo…
                              await SharePlus.instance.share(
                                ShareParams(
                                  text: invitation,
                                  subject: 'Invitación a Mi Barrio',
                                ),
                              );
                            } catch (_) {
                              // Sin menú de compartir (ej. escritorio): se copia.
                              await Clipboard.setData(
                                ClipboardData(text: invitation),
                              );
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Invitación copiada. Ya puedes pegarla y enviarla.',
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.share_rounded),
                          label: const Text('Compartir invitación'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
