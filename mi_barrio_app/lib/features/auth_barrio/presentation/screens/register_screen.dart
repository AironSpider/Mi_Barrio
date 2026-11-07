import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/user_entity.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _joinCode = TextEditingController();
  UserRole _role = UserRole.vecino;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _joinCode.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(authProvider.notifier)
        .register(
          fullName: _name.text,
          email: _email.text,
          password: _password.text,
          role: _role,
          joinCode: _joinCode.text,
        );
    if (mounted &&
        ref.read(authProvider).status != AuthStatus.error &&
        ref.read(authProvider).status != AuthStatus.unauthenticated) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final loading = auth.status == AuthStatus.loading;

    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _name,
                      enabled: !loading,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nombre completo',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (value?.trim().length ?? 0) >= 2
                          ? null
                          : 'Ingresa tu nombre completo',
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _email,
                      enabled: !loading,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (value?.contains('@') ?? false)
                          ? null
                          : 'Correo inválido',
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      enabled: !loading,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Contraseña (mínimo 8 caracteres)',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) => (value?.length ?? 0) >= 8
                          ? null
                          : 'Usa al menos 8 caracteres',
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _joinCode,
                      enabled: !loading,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Código de tu barrio',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (value?.trim().length ?? 0) >= 3
                          ? null
                          : 'Ingresa el código de invitación del barrio',
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<UserRole>(
                      initialValue: _role,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de cuenta',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final role in UserRole.values.where(
                          (role) => role.isSelfSelectable,
                        ))
                          DropdownMenuItem(
                            value: role,
                            child: Text(role.label),
                          ),
                      ],
                      onChanged: loading
                          ? null
                          : (value) {
                              if (value != null) setState(() => _role = value);
                            },
                    ),
                    if (auth.message != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        auth.message!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: loading ? null : _register,
                      child: loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Crear cuenta'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
