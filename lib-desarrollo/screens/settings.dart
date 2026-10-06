// lib/screens/settings.dart
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String role = '';
  String userName = '';

  @override
  void initState() {
    super.initState();
    role = AuthService.instance.role;
    userName = AuthService.instance.userName;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Usuario: $userName', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text('Rol: $role', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                await AuthService.instance.logout();
                if (!mounted) return;
                Navigator.pushReplacementNamed(context, '/login');
              },
              child: const Text('Cerrar sesión'),
            ),
          ],
        ),
      ),
    );
  }
}
