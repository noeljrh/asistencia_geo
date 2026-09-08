// lib/screens/settings.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/auth_service.dart';
import '../auth/auth_state.dart';
import '../main.dart'; // para MyApp.of(context)?.setDark(...)

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _useDark = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useDark = prefs.getBool('use_dark_theme') ?? false;
      _loading = false;
    });
  }

  Future<void> _onToggleDark(bool value) async {
    setState(() => _useDark = value);
    // Aplica el tema en caliente usando el método expuesto en MyApp
    MyApp.of(context)?.setDark(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_dark_theme', value);
  }

  Future<void> _onLogout() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/');
  }

  @override
  Widget build(BuildContext context) {
    final authState = Provider.of<AuthState>(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Tema oscuro'),
                    value: _useDark,
                    onChanged: _onToggleDark,
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Usuario'),
                    subtitle: Text(authState.user?['email']?.toString() ?? 'No autenticado'),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _onLogout,
                    icon: const Icon(Icons.logout),
                    label: const Text('Cerrar sesión'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  ),
                ],
              ),
            ),
    );
  }
}
