// lib/screens/home.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_service.dart';
import '../api/api_client.dart';
import '../src/http_utils.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final authService = AuthService.instance;
    final apiClient = Provider.of<ApiClient?>(context, listen: false);

    try {
      if (apiClient == null) {
        debugPrint('[HomeScreen] No ApiClient available, redirecting to login');
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }

      final map = await authService.me(apiClient: apiClient);
      if (!mounted) return;
      setState(() {
        _profile = map;
      });
    } catch (e, st) {
      debugPrint('[HomeScreen] Error fetching profile: $e\n$st');

      final msg = e.toString();

      if (msg.contains('No local user data') ||
          msg.contains('401') ||
          msg.contains('No access token') ||
          msg.contains('Unauthorized')) {
        try {
          await authService.clear();
        } catch (_) {}
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }

      if (!mounted) return;
      setState(() {
        _error = 'Error al obtener perfil: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onLogout() async {
    final authService = AuthService.instance;
    final apiClient = Provider.of<ApiClient?>(context, listen: false);

    try {
      if (apiClient != null) {
        // Si tu AuthService define logout que requiere ApiClient, úsalo.
        // Si no, el fallback es clear().
        try {
          await authService.logout(apiClient: apiClient);
        } catch (_) {
          await authService.clear();
        }
      } else {
        await authService.clear();
      }
    } catch (e) {
      debugPrint('[HomeScreen] Error during logout: $e');
      try {
        await authService.clear();
      } catch (_) {}
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inicio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _onLogout,
          ),
        ],
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _error != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Error: $_error', style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _loadProfile, child: const Text('Reintentar')),
                    ],
                  )
                : _profile != null
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Bienvenido, ${_profile!['name'] ?? _profile!['email'] ?? 'Usuario'}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(_profile!.toString()),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(onPressed: _loadProfile, child: const Text('Actualizar perfil')),
                          ],
                        ),
                      )
                    : const Text('No hay datos de perfil'),
      ),
    );
  }
}
