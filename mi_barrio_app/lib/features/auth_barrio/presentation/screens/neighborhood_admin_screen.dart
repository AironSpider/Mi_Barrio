import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                  SelectableText(
                    joinCode.isEmpty ? 'Código no disponible' : joinCode,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Comparte este código solo con personas que pertenezcan '
                    'a tu barrio.',
                  ),
                  if (joinCode.isNotEmpty)
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      children: [
                        TextButton.icon(
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
                        TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text:
                                    'Únete a ${user.tenantName ?? 'mi barrio'} '
                                    'en Mi Barrio con el código $joinCode.',
                              ),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Invitación copiada. Ya puedes compartirla.',
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}
