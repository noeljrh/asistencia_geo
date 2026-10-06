// lib/main.dart
import 'package:flutter/material.dart';
import 'services/auth_service.dart';
import 'services/queue_service.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'screens/settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar una sola vez
  await AuthService.instance.init();
  await QueueService.instance.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control de Asistencia PLANNER 2026',
      initialRoute: AuthService.instance.isAuthenticated ? '/home' : '/',
      routes: {
        '/': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
