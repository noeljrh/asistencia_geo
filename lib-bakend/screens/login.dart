// lib/screens/login.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_service.dart';
import '../api/api_client.dart';
import '../auth/auth_state.dart';

class LoginScreen extends StatefulWidget {
  final ApiClient apiClient;
  const LoginScreen({Key? key, required this.apiClient}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final authService = AuthService.instance;
    final authState = Provider.of<AuthState>(context, listen: false);

    try {
      // Llamada al login; AuthService.login maneja token/refresh según tu ApiClient
      final result = await authService.login(
        _emailCtrl.text.trim(),
        _passCtrl.text,
        apiClient: widget.apiClient,
      );

      // Si tu login devuelve token en result, AuthService ya lo guarda.
      // Aseguramos que el token esté persistido y el estado inicializado
      // antes de navegar a la pantalla principal.
      await authService.init(); // asegura que AuthService haya leído storage si aplica
      await authState.init(); // inicializa el AuthState compartido si lo usas

      // Espera explícita a que el token esté disponible
      if (authService.isAuthenticated) {
        // Navega solo cuando el estado está listo
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/');
        return;
      }

      // Si no hay token, mostrar error con la info recibida
      final msg = (result is Map && result['error'] != null) ? result['error'].toString() : 'No se recibió token del servidor';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al iniciar sesión: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (v) => (v == null || v.isEmpty) ? 'Ingresa email' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Contraseña'),
                      validator: (v) => (v == null || v.isEmpty) ? 'Ingresa contraseña' : null,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Iniciar sesión'),
                      ),
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
