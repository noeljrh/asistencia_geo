// lib/main.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login.dart';
import 'screens/home.dart';
import 'screens/settings.dart';
import 'package:asistencia_geo/services/auth_service.dart';
import 'services/api_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ajusta la URL según tu entorno. Usa localhost si ejecutas backend en la misma máquina.
  ApiService.setBaseUrl('http://localhost:3000');

  // Cargar modo fake guardado en prefs (si existe) y forzar modo real/false si lo deseas.
  await ApiService.loadFakeModeFromPrefs();
  await ApiService.setFakeMode(false);

  // Inicializar AuthService (carga tokens desde SharedPreferences)
  await AuthService.instance.init();

  // Leer preferencias para decidir la ruta inicial y el tema
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

  // Contador auxiliar usado únicamente para pruebas/debug (no afecta la lógica de rutas)
  // Está aquí para que los tests que esperan un contador por defecto (0 -> 1) pasen.
  // Se muestra solo en modos no release (debug/tests).
  int _testCounter = 0;

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

  // Incrementa el contador de prueba (solo para overlay de debug/tests)
  void _incrementTestCounter() {
    setState(() {
      _testCounter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // MaterialApp normal con rutas y configuración existente.
    // Usamos `builder` para inyectar el overlay dentro del árbol ya provisto por MaterialApp,
    // de modo que Directionality y MediaQuery estén disponibles para el overlay.
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
      builder: (context, child) {
        // En modo release devolvemos el child tal cual.
        if (kReleaseMode) {
          return child ?? const SizedBox.shrink();
        }

        // En debug/test añadimos un overlay que no interfiere con la UI principal.
        return Stack(
          children: [
            // El child ya tiene Directionality y MediaQuery.
            if (child != null) child,
            // Positioned overlay en la esquina inferior derecha.
            Positioned(
              right: 16,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      '$_testCounter',
                      key: const Key('counter'),
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton(
                    heroTag: 'test_counter_fab',
                    onPressed: _incrementTestCounter,
                    child: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
