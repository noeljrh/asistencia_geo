// lib/screens/login.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../widgets/name_entry_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _loading = false;
  String _info = '';

  @override
  void initState() {
    super.initState();
    _checkExistingUser();
  }

  Future<void> _checkExistingUser() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name');
    if (name != null && name.isNotEmpty) {
      // Ya hay usuario: navegar a home sin mostrar diálogo
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  Future<void> _onLoginPressed() async {
    // Si quieres mantener el login ficticio: usamos AuthService.login
    setState(() {
      _loading = true;
      _info = '';
    });

    final username = _userController.text.trim();
    final password = _passController.text;

    // Si no ingresó nombre, abrimos el diálogo para pedirlo
    if (username.isEmpty) {
      await _openNameDialog();
      setState(() => _loading = false);
      return;
    }

    try {
      final res = await AuthService.instance.login(username, password);
      if (res['success'] == true) {
        // Guardado hecho por AuthService; navegar a home
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        setState(() => _info = 'Error al iniciar sesión');
      }
    } catch (e) {
      setState(() => _info = 'Error: ${e.toString()}');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openNameDialog() async {
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NameEntryDialog(),
    );

    if (result != null && result.isNotEmpty) {
      // Si el diálogo devolvió nombre, ya fue guardado; vamos a home
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ingreso'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          children: [
            const SizedBox(height: 8),
            TextField(
              controller: _userController,
              decoration: const InputDecoration(labelText: 'Usuario (opcional)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passController,
              decoration: const InputDecoration(labelText: 'Contraseña (opcional)'),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loading ? null : _onLoginPressed,
              icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.login),
              label: Text(_loading ? 'Ingresando...' : 'Ingresar / Registrar nombre'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loading ? null : _openNameDialog,
              child: const Text('Ingresar solo nombre (sin credenciales)'),
            ),
            const SizedBox(height: 12),
            if (_info.isNotEmpty) Text(_info, style: const TextStyle(color: Colors.red)),
            const Spacer(),
            const Text('Si no tienes credenciales, usa "Ingresar solo nombre".'),
          ],
        ),
      ),
    );
  }
}

