// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth/auth_state.dart';
import 'auth/auth_service.dart';
import 'api/api_client.dart';
import 'screens/login.dart';
import 'screens/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Usa la instancia singleton de AuthState y asegúrate de inicializarla.
  final authState = AuthState.instance;
  await authState.init();

  // Crea ApiClient con la URL de tu backend y la referencia a authState.
  final apiClient = ApiClient('http://localhost:3000', authState);

  runApp(MyApp(authState: authState, apiClient: apiClient));
}

class MyApp extends StatelessWidget {
  final AuthState authState;
  final ApiClient apiClient;
  const MyApp({Key? key, required this.authState, required this.apiClient}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthState>.value(value: authState),
        Provider<ApiClient>.value(value: apiClient),
      ],
      child: MaterialApp(
        title: 'Mi App',
        debugShowCheckedModeBanner: false,
        routes: {
          '/login': (ctx) => LoginScreen(apiClient: apiClient),
          '/': (ctx) => _RootDecider(),
        },
        initialRoute: '/',
      ),
    );
  }
}

/// Decide la pantalla inicial según el estado de autenticación
class _RootDecider extends StatelessWidget {
  const _RootDecider({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authState = Provider.of<AuthState>(context);
    final apiClient = Provider.of<ApiClient>(context, listen: false);

    if (authState.isAuthenticated) {
      return const HomeScreen();
    } else {
      return LoginScreen(apiClient: apiClient);
    }
  }
}
