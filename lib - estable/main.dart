// lib/main.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login.dart';
import 'screens/home.dart';
import 'screens/settings.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.instance.init();
  await ApiService.loadFakeModeFromPrefs();
  final prefs = await SharedPreferences.getInstance();
  final name = prefs.getString('user_name');
  final savedDark = prefs.getBool('use_dark_theme') ?? false;
  runApp(MyApp(initialRoute: name == null ? '/' : '/home', initialDark: savedDark));
}

class MyApp extends StatefulWidget {
  final String initialRoute;
  final bool initialDark;
  const MyApp({this.initialRoute = '/', this.initialDark = false, Key? key}) : super(key: key);

  // Exponer el estado para que SettingsScreen pueda llamar setDark
  static _MyAppState? of(BuildContext context) => context.findAncestorStateOfType<_MyAppState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialDark ? ThemeMode.dark : ThemeMode.light;
  }

  // Método público que SettingsScreen llamará para aplicar el tema en caliente
  void setDark(bool dark) async {
    setState(() => _themeMode = dark ? ThemeMode.dark : ThemeMode.light);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_dark_theme', dark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control de Asistencia PLANNER 2026',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: _themeMode,
      initialRoute: widget.initialRoute,
      routes: {
        '/': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
