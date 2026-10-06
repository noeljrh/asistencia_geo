// lib/screens/login.dart
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;

  Future<void> _submit() async {
    if (_loading) return;
    setState(() => _loading = true);
    final res = await AuthService.instance.login(_user.text.trim(), _pass.text);
    if (res is Map && res['success'] == true) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      final msg = (res is Map && res['message'] != null) ? res['message'].toString() : 'Login fallido';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: _user, decoration: const InputDecoration(labelText: 'Usuario')),
            const SizedBox(height: 8),
            TextField(controller: _pass, decoration: const InputDecoration(labelText: 'Contraseña'), obscureText: true),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loading ? null : _submit, child: _loading ? const CircularProgressIndicator() : const Text('Entrar')),
          ],
        ),
      ),
    );
  }
}
