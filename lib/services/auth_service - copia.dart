// lib/services/auth_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class AuthService {
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

  String? _token;
  String? _refreshToken;
  String _role = '';
  String _userName = '';
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await loadFromPrefs();
    debugPrint('AuthService.init: isAuthenticated=${isAuthenticated}');
  }

  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('auth_token');
      _refreshToken = prefs.getString('refresh_token');
      _userName = prefs.getString('user_name') ?? '';
      _role = prefs.getString('user_role') ?? '';
    } catch (e) {
      debugPrint('AuthService.loadFromPrefs error: $e');
      _token = null;
      _refreshToken = null;
      _userName = '';
      _role = '';
    }
  }

  Future<void> saveTokens(String accessToken, String refreshToken, {String? userName, String? role}) async {
    _token = accessToken;
    _refreshToken = refreshToken;
    if (userName != null) _userName = userName;
    if (role != null) _role = role;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', accessToken);
    await prefs.setString('refresh_token', refreshToken);
    if (userName != null) await prefs.setString('user_name', userName);
    if (role != null) await prefs.setString('user_role', role);
    debugPrint('AuthService.saveTokens saved token=${accessToken.isNotEmpty}');
  }

  String? get token => _token;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  String get role => _role;
  String get userName => _userName;

  Future<void> logout() async {
    _token = null;
    _refreshToken = null;
    _userName = '';
    _role = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_name');
    await prefs.remove('user_role');
    debugPrint('AuthService.logout: cleared credentials');
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    // Enviar como "email" porque el backend exige email+password
    final payload = {'email': username, 'password': password};

    // Intentamos primero la ruta con /api (según tu backend) y hacemos fallback a /auth/login
    final uri1 = Uri.parse('${ApiService.baseUrl}/api/auth/login');
    debugPrint('AuthService.login -> POST $uri1 payload keys=${payload.keys.toList()}');

    http.Response res;
    try {
      res = await http
          .post(uri1,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('AuthService.login exception (uri1): $e');

      // Intentar ruta alternativa sin /api
      final uri2 = Uri.parse('${ApiService.baseUrl}/auth/login');
      debugPrint('AuthService.login attempting fallback -> POST $uri2');
      try {
        res = await http
            .post(uri2,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(payload))
            .timeout(const Duration(seconds: 12));
      } catch (e2) {
        debugPrint('AuthService.login exception (uri2): $e2');
        return {'success': false, 'message': e2.toString()};
      }
    }

    debugPrint('AuthService.login status=${res.statusCode} body=${res.body}');

    try {
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = res.body.isNotEmpty ? jsonDecode(res.body) : <String, dynamic>{};

        // Soporte flexible para distintos nombres de token/usuario, incluyendo camelCase y token anidado
        String? access;
        if (body is Map) {
          access = (body['access_token'] ??
                  body['token'] ??
                  body['auth_token'] ??
                  body['access'] ??
                  body['accessToken'])
              ?.toString();

          // Si token viene dentro de un objeto user (ej: { accessToken: "...", user: {...} })
          if ((access == null || access.isEmpty) && body['user'] is Map) {
            final userObj = body['user'] as Map;
            access = (userObj['accessToken'] ?? userObj['token'] ?? userObj['auth_token'])?.toString();
          }
        }

        final refresh = (body is Map && (body['refresh_token'] ?? body['refresh']) != null)
            ? (body['refresh_token'] ?? body['refresh']).toString()
            : '';

        // Nombre de usuario: buscar en varios campos, también dentro de user{}
        String name = username;
        if (body is Map) {
          if (body['user'] is Map) {
            final userObj = body['user'] as Map;
            name = (userObj['name'] ?? userObj['username'] ?? userObj['email'])?.toString() ?? name;
          } else {
            name = (body['user_name'] ?? body['username'] ?? body['user'] ?? body['email'])?.toString() ?? name;
          }
        }

        if (access != null && access.isNotEmpty) {
          await saveTokens(access, refresh, userName: name);
          _token = access;
          _refreshToken = refresh;
          _userName = name;
          debugPrint('AuthService.login: token saved, userName=$_userName');
          return {'success': true, 'message': 'Login exitoso', 'access_token': access};
        } else {
          debugPrint('AuthService.login: no access token in response body keys=${body is Map ? body.keys.toList() : []}');
          return {'success': false, 'message': 'Respuesta inválida', 'body': body};
        }
      } else {
        String msg = 'Error ${res.statusCode}';
        try {
          final parsed = jsonDecode(res.body);
          if (parsed is Map && parsed['error'] != null) msg = parsed['error'].toString();
        } catch (_) {}
        return {'success': false, 'message': msg, 'statusCode': res.statusCode};
      }
    } catch (e) {
      debugPrint('AuthService.login parse exception: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<bool> refreshToken() async {
    if (_refreshToken == null || _refreshToken!.isEmpty) {
      debugPrint('AuthService.refreshToken: no refresh token disponible');
      return false;
    }
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/auth/refresh');
      final res = await http.post(uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': _refreshToken}))
        .timeout(const Duration(seconds: 12));

      debugPrint('AuthService.refreshToken status=${res.statusCode} body=${res.body}');

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = jsonDecode(res.body);
        final newAccess = body['access_token'] as String? ?? body['token'] as String?;
        final newRefresh = body['refresh_token'] as String? ?? _refreshToken;
        final name = body['user_name'] as String? ?? _userName;
        final role = body['role'] as String? ?? _role;

        if (newAccess != null && newAccess.isNotEmpty) {
          await saveTokens(newAccess, newRefresh ?? '', userName: name, role: role);
          _token = newAccess;
          _refreshToken = newRefresh;
          _userName = name ?? _userName;
          _role = role ?? _role;
          debugPrint('AuthService.refreshToken: refreshed successfully');
          return true;
        }
      } else {
        debugPrint('AuthService.refreshToken failed status=${res.statusCode}');
        await logout();
      }
    } catch (e) {
      debugPrint('AuthService.refreshToken exception: $e');
    }
    return false;
  }

  Future<void> refreshUserInfo() async {
    await loadFromPrefs();
  }
}

