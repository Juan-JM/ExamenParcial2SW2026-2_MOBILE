import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/app_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.initialServer, required this.clientFor, required this.onLoggedIn});

  final String? initialServer;
  final ApiClient Function(String baseUrl) clientFor;
  final void Function(String baseUrl, String token, AppUser user) onLoggedIn;

  /// Servidor por Wi-Fi: IP de la laptop en la red local (`php artisan serve
  /// --host=0.0.0.0`). Se cambia al compilar con
  /// `--dart-define=SERVER_URL=http://<ip>:8000`, o en la app desde Ajustes.
  static const defaultServer = String.fromEnvironment('SERVER_URL', defaultValue: 'http://192.168.100.23:8000');

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _server = widget.initialServer ?? LoginScreen.defaultServer;
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await widget.clientFor(_server).login(_email.text.trim(), _password.text, 'App móvil');
      widget.onLoggedIn(_server, result.token, result.user);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openServerSettings() async {
    final server = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ServerSettingsSheet(initial: _server, clientFor: widget.clientFor),
    );

    if (server != null && mounted) {
      setState(() {
        _server = server;
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: 'Ajustes del servidor',
                onPressed: _openServerSettings,
                icon: const Icon(Icons.tune_rounded, color: AppColors.muted),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 48, 28, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Align(alignment: Alignment.centerLeft, child: AppLogo(size: 60)),
                        const SizedBox(height: 32),
                        Text('Bienvenido de vuelta', style: theme.textTheme.headlineMedium),
                        const SizedBox(height: 8),
                        Text(
                          'Seguí los diagramas de tu equipo en vivo, desde donde estés.',
                          style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.muted, height: 1.4),
                        ),
                        const SizedBox(height: 36),
                        _Label('Correo'),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'nombre@correo.com',
                            prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
                          ),
                          validator: (v) => (v ?? '').contains('@') ? null : 'Escribe tu correo',
                        ),
                        const SizedBox(height: 18),
                        _Label('Contraseña'),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            hintText: '••••••••',
                            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                            suffixIcon: IconButton(
                              tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                              onPressed: () => setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                size: 20,
                                color: AppColors.subtle,
                              ),
                            ),
                          ),
                          validator: (v) => (v ?? '').isEmpty ? 'Escribe tu contraseña' : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          child: _error == null
                              ? const SizedBox(height: 28)
                              : Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  child: _ErrorNote(text: _error!, onSettings: _openServerSettings),
                                ),
                        ),
                        FilledButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                                )
                              : const Text('Entrar'),
                        ),
                        const SizedBox(height: 28),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.visibility_outlined, size: 15, color: AppColors.subtle),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Modo visor · los cambios se hacen en la web',
                                style: theme.textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.text, required this.onSettings});

  final String text;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final connection = text.startsWith('No se pudo conectar');

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13.5))),
          if (connection) TextButton(onPressed: onSettings, child: const Text('Ajustes')),
        ],
      ),
    );
  }
}

/// Hoja de ajustes: dirección del servidor, con prueba de conexión.
class ServerSettingsSheet extends StatefulWidget {
  const ServerSettingsSheet({super.key, required this.initial, required this.clientFor});

  final String initial;
  final ApiClient Function(String baseUrl) clientFor;

  @override
  State<ServerSettingsSheet> createState() => _ServerSettingsSheetState();
}

class _ServerSettingsSheetState extends State<ServerSettingsSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initial);
  bool? _reachable;
  bool _testing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final uri = Uri.tryParse((value ?? '').trim());
    final valid = uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;

    return valid ? null : 'Escribe la dirección completa, por ejemplo http://192.168.1.10:8000';
  }

  Future<void> _test() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _testing = true;
      _reachable = null;
    });
    final ok = await widget.clientFor(_controller.text.trim()).ping();
    if (mounted) {
      setState(() {
        _testing = false;
        _reachable = ok;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Servidor', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Dirección de la laptop en tu red Wi-Fi, con el puerto del servidor.',
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _controller,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'http://192.168.1.10:8000',
                prefixIcon: Icon(Icons.dns_outlined, size: 20),
              ),
              validator: _validate,
              onChanged: (_) => setState(() => _reachable = null),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering_rounded, size: 18),
                  label: const Text('Probar'),
                ),
                const SizedBox(width: 12),
                if (_reachable != null)
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          _reachable! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          size: 18,
                          color: _reachable! ? AppColors.live : AppColors.danger,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _reachable! ? 'Conectado' : 'Sin respuesta',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _reachable! ? const Color(0xFF047857) : AppColors.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  Navigator.of(context).pop(_controller.text.trim().replaceAll(RegExp(r'/+$'), ''));
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
