// lib/auth/auth_service.dart
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../src/http_utils.dart';

/// Servicio de autenticación local y remoto.
/// - Mantiene compatibilidad con el singleton `AuthService.instance`.
/// - Permite usar el backend si se pasa un `ApiClient` a los métodos `login`/`logout`/`me`.
class AuthService extends ChangeNotifier {
  AuthService._private();
  static final AuthService instance = AuthService._private();

  final _secure = const FlutterSecureStorage();
  String? _token;
  String? _userName;
  String _role = 'user';
  bool _initialized = false;

  bool get isAuthenticated => _token != null;
  String? get token => _token;
  String get role => _role;
  String? get userName => _userName;

  /// Inicializa leyendo token y prefs. Idempotente.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _token = await _secure.read(key: 'auth_token');
    } catch (_) {
      _token = null;
    }
    final prefs = await SharedPreferences.getInstance();
    _userName = prefs.getString('user_name');
    _role = prefs.getString('user_role') ?? 'user';
    notifyListeners();
  }

  /// Establece token manualmente (útil tras login desde ApiClient)
  Future<void> setToken(String? token) async {
    _token = token;
    if (token == null) {
      try {
        await _secure.delete(key: 'auth_token');
      } catch (_) {}
    } else {
      try {
        await _secure.write(key: 'auth_token', value: token);
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Establece datos de usuario simples (nombre y rol) y los persiste en prefs
  Future<void> setUser({String? name, String? role}) async {
    _userName = name ?? _userName;
    _role = role ?? _role;
    final prefs = await SharedPreferences.getInstance();
    if (_userName != null && _userName!.isNotEmpty) {
      await prefs.setString('user_name', _userName!);
    } else {
      await prefs.remove('user_name');
    }
    await prefs.setString('user_role', _role);
    notifyListeners();
  }

  /// Limpia estado local y almacenamiento seguro/prefs
  Future<void> clear() async {
    _token = null;
    _userName = null;
    _role = 'user';
    try {
      await _secure.delete(key: 'auth_token');
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_name');
    await prefs.remove('user_role');
    notifyListeners();
  }

  /// Login: si se pasa un ApiClient, hace la llamada real al backend.
  /// Si no se pasa, mantiene el comportamiento ficticio anterior.
  ///
  /// Devuelve el Map con la respuesta (por ejemplo {'accessToken':..., 'user': {...}}).
  Future<Map<String, dynamic>> login(String username, String password, {ApiClient? apiClient}) async {
    // Helper de almacenamiento seguro local para logs/guardado adicional
    final _localSecure = const FlutterSecureStorage();

    if (apiClient != null) {
      try {
        // Llamada al cliente HTTP (ApiClient.login debe devolver Map<String,dynamic>)
        final resp = await apiClient.login(username, password);

        // Aseguramos que tenemos un Map<String,dynamic>
        final map = parseResponseToMap(resp);

        // Logs de depuración (temporales)
        try {
          print('[DEBUG][login] resp.runtimeType=${resp.runtimeType}');
          final bodyStr = resp.toString();
          print('[DEBUG][login] resp.body (truncated): ${bodyStr.substring(0, bodyStr.length.clamp(0, 500))}');
        } catch (_) {}

        // Buscar token en las claves más comunes
        final token = map['accessToken'] ?? map['token'] ?? map['access_token'];
        if (token == null) {
          print('[DEBUG][login] NO se encontró token en la respuesta. keys=${map.keys}');
          throw Exception('No token returned from login');
        }

        // Extraer user si viene
        final user = map['user'] is Map ? Map<String, dynamic>.from(map['user']) : null;

        // Guardar token en memoria/estado y en almacenamiento seguro
        try {
          await setToken(token.toString());
          print('[DEBUG][login] token guardado en AuthService');
        } catch (e) {
          print('[DEBUG][login] fallo guardando token en AuthService: $e');
        }

        try {
          await _localSecure.write(key: 'auth_token', value: token.toString());
          print('[DEBUG][login] token guardado en FlutterSecureStorage');
        } catch (e) {
          print('[DEBUG][login] fallo guardando token en secure storage: $e');
        }

        // Guardar datos de usuario simples en prefs si vienen
        if (user != null) {
          try {
            await setUser(name: user['name']?.toString(), role: user['role']?.toString());
            print('[DEBUG][login] user guardado en AuthService: ${user['name']}');
          } catch (e) {
            print('[DEBUG][login] fallo guardando user en AuthService: $e');
          }
        }

        return map;
      } catch (e) {
        print('[DEBUG][login] Error en login con ApiClient: $e');
        rethrow;
      }
    }

    // Si no hay ApiClient, comportamiento ficticio (compatibilidad con tu código previo)
    _token = 'fake-token';
    _role = username.toLowerCase() == 'admin' ? 'supervisor' : 'user';
    _userName = username;

    try {
      await _localSecure.write(key: 'auth_token', value: _token);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _userName ?? '');
    await prefs.setString('user_role', _role);

    notifyListeners();
    return {'success': true, 'token': _token, 'user': {'name': _userName, 'role': _role}};
  }

  /// Logout: si se pasa ApiClient, intenta notificar al backend; siempre limpia el estado local.
  Future<void> logout({ApiClient? apiClient}) async {
    if (apiClient != null) {
      try {
        await apiClient.dio.post('/api/auth/logout');
      } catch (_) {
        // ignoramos errores de red al hacer logout remoto
      }
    }
    await clear();
  }

  /// Obtiene el perfil del usuario actual desde el backend si se pasa ApiClient.
  /// Si no se pasa ApiClient, devuelve la info local (si existe) o lanza excepción.
  Future<Map<String, dynamic>> me({ApiClient? apiClient}) async {
    if (apiClient != null) {
      try {
        // Preferir usar el método dedicado de ApiClient si existe
        try {
          final map = await apiClient.getUserMe();
          return map;
        } catch (_) {
          // Fallback a llamada directa para más control/logs
          final resp = await apiClient.dio.get('/api/users/me',
              options: Options(headers: _token != null ? {'Authorization': 'Bearer $_token'} : null));
          return parseResponseToMap(resp.data);
        }
      } on Exception catch (e) {
        print('[AuthService.me] Error fetching profile: $e');
        throw Exception('Failed to fetch profile from server: $e');
      }
    } else {
      if (_userName != null) {
        return {'name': _userName, 'role': _role};
      }
      throw Exception('No local user data available and no ApiClient provided');
    }
  }
}

