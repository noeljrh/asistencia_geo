// lib/auth/auth_service.dart
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../api/api_client.dart';
import '../src/http_utils.dart';

class AuthService extends ChangeNotifier {
  AuthService._private();
  static final AuthService instance = AuthService._private();
  factory AuthService() => instance;

  final _secure = const FlutterSecureStorage();
  String? _token;
  String? _userName;
  String _role = 'user';
  bool _initialized = false;

  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  String? get token => _token;
  String get role => _role;
  String? get userName => _userName;

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

  /// Login: usa ApiClient si se pasa. Devuelve Map con la respuesta normalizada.
  /// Si el servidor no devuelve token pero sí set-cookie, intenta llamar /auth/refresh
  /// para intercambiar cookie por access token.
  Future<Map<String, dynamic>> login(String username, String password, {ApiClient? apiClient}) async {
    final _localSecure = const FlutterSecureStorage();

    if (apiClient != null) {
      try {
        final dynamic rawResp = await apiClient.login(username, password);

        // Logs detallados para diagnosticar headers/body/cookies
        try {
          debugPrint('[DEBUG][login] rawResp.runtimeType=${rawResp.runtimeType}');
          if (rawResp is Response) {
            debugPrint('[DEBUG][login] response.status=${rawResp.statusCode}');
            debugPrint('[DEBUG][login] response.headers=${rawResp.headers.map}');
            final bodyStr = rawResp.data?.toString() ?? '';
            debugPrint('[DEBUG][login] response.data (truncated): ${bodyStr.substring(0, bodyStr.length.clamp(0, 500))}');
          } else {
            final s = rawResp.toString();
            debugPrint('[DEBUG][login] rawResp (truncated): ${s.substring(0, s.length.clamp(0, 500))}');
          }
        } catch (_) {}

        // Normalizar payload
        dynamic respData;
        if (rawResp is Response) {
          respData = rawResp.data;
        } else {
          respData = rawResp;
        }

        // Intentar parsear JSON si viene en body
        Map<String, dynamic>? map;
        try {
          map = parseResponseToMap(respData);
        } catch (_) {
          map = null;
        }

        // Buscar token en claves comunes
        String? token = map != null ? (map['accessToken'] ?? map['token'] ?? map['access_token'])?.toString() : null;

        // Si no hay token en body, intentar intercambio cookie -> token usando /auth/refresh
        if (token == null) {
          debugPrint('[DEBUG][login] No token in body, checking for set-cookie and attempting refresh endpoint');
          // Si ApiClient capturó set-cookie en apiClient.lastSetCookie, usarlo
          final cookieHeader = apiClient.lastSetCookie;
          if (cookieHeader != null && cookieHeader.isNotEmpty) {
            try {
              final refreshResp = await apiClient.refreshWithCookie(cookieHeader: cookieHeader);
              debugPrint('[DEBUG][login] refresh response.status=${refreshResp.statusCode}');
              final refreshData = parseResponseToMap(refreshResp.data);
              token = (refreshData['accessToken'] ?? refreshData['token'] ?? refreshData['access_token'])?.toString();
              if (token != null) {
                debugPrint('[DEBUG][login] token obtained from refresh endpoint');
                map = refreshData;
              }
            } catch (e) {
              debugPrint('[DEBUG][login] refresh endpoint failed: $e');
            }
          } else {
            debugPrint('[DEBUG][login] no set-cookie captured to use for refresh');
          }
        }

        if (token == null) {
          debugPrint('[DEBUG][login] NO se encontró token en la respuesta ni en refresh. keys=${map?.keys}');
          throw Exception('No token returned from login; server may be using cookies only');
        }

        final user = map != null && map['user'] is Map ? Map<String, dynamic>.from(map['user']) : null;

        try {
          await setToken(token);
          debugPrint('[DEBUG][login] token guardado en AuthService');
        } catch (e) {
          debugPrint('[DEBUG][login] fallo guardando token en AuthService: $e');
        }

        try {
          await _localSecure.write(key: 'auth_token', value: token);
          debugPrint('[DEBUG][login] token guardado en FlutterSecureStorage');
        } catch (e) {
          debugPrint('[DEBUG][login] fallo guardando token en secure storage: $e');
        }

        if (user != null) {
          try {
            await setUser(name: user['name']?.toString(), role: user['role']?.toString());
            debugPrint('[DEBUG][login] user guardado en AuthService: ${user['name']}');
          } catch (e) {
            debugPrint('[DEBUG][login] fallo guardando user en AuthService: $e');
          }
        }

        return map ?? {'success': true};
      } catch (e) {
        debugPrint('[DEBUG][login] Error en login con ApiClient: $e');
        rethrow;
      }
    }

    // Fallback local (modo offline/testing)
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

  Future<void> logout({ApiClient? apiClient}) async {
    if (apiClient != null) {
      try {
        await apiClient.dio.post('/api/auth/logout');
      } catch (_) {}
    }
    await clear();
  }

  Future<Map<String, dynamic>> me({ApiClient? apiClient}) async {
    if (apiClient != null) {
      try {
        final resp = await apiClient.dio.get(
          '/api/users/me',
          options: Options(
            headers: _token != null ? {'Authorization': 'Bearer $_token'} : null,
            responseType: ResponseType.json,
          ),
        );
        return parseResponseToMap(resp.data);
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        final body = e.response?.data;
        debugPrint('[AuthService.me] DioException status=$status body=$body');
        throw Exception('Failed to fetch profile from server: status=$status body=$body');
      } catch (e) {
        debugPrint('[AuthService.me] Error fetching profile: $e');
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
