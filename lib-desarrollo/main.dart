// lib/main.dart
import 'package:flutter/material.dart';
import 'services/auth_service.dart';
import 'services/queue_service.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'screens/settings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyAppStarter());
}

class MyAppStarter extends StatelessWidget {
  const MyAppStarter({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control de Asistencia PLANNER 2026',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const InitLoader(),
      routes: {
        '/home': (context) => const HomeScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/login': (context) => const LoginScreen(),
      },
    );
  }
}

class InitLoader extends StatefulWidget {
  const InitLoader({super.key});
  @override
  State<InitLoader> createState() => _InitLoaderState();
}

class _InitLoaderState extends State<InitLoader> {
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initializeServices();
  }

  Future<void> _initializeServices() async {
    await AuthService.instance.init();
    await QueueService.instance.init();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) return const LoginScreen();
        final authed = AuthService.instance.isAuthenticated;
        return authed ? const HomeScreen() : const LoginScreen();
      },
    );
  }
}
