// lib/services/api_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

class ApiService {
  ApiService._();

  static String? _envBaseUrl;
  static bool useFake = false;
  static const String _prefsKeyUseFake = 'api_use_fake';

  static void setBaseUrl(String? url) {
    _envBaseUrl = (url == null || url.isEmpty) ? null : url;
    debugPrint('[ApiService] baseUrl set to: ${baseUrl}');
  }

  static String get baseUrl => _envBaseUrl ?? 'http://localhost:3000';

  static Future<void> loadFakeModeFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      useFake = prefs.getBool(_prefsKeyUseFake) ?? false;
      debugPrint('[ApiService] loadFakeModeFromPrefs -> useFake=$useFake');
    } catch (e) {
      debugPrint('[ApiService] loadFakeModeFromPrefs error: $e');
      useFake = false;
    }
  }

  static Future<void> setFakeMode(bool value) async {
    useFake = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKeyUseFake, value);
      debugPrint('[ApiService] setFakeMode -> useFake=$useFake');
    } catch (e) {
      debugPrint('[ApiService] setFakeMode error: $e');
    }
  }

  /// Lista de endpoints a intentar para registrar ubicación/attendance.
  static final List<String> _locationEndpoints = [
    '/api/location',
    '/api/locations',
    '/api/attendance',
    '/api/attendances',
    '/api/checkin',
    '/api/assistances',
    '/location',
    '/locations',
    '/attendance',
    '/checkin'
  ];

  /// Construye headers incluyendo Authorization si hay token disponible.
  /// `scheme` permite alternar entre 'Bearer' y 'Token' si es necesario.
  static Map<String, String> _buildHeaders({String scheme = 'Bearer'}) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = AuthService.instance.token;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = '$scheme $token';
    }
    return headers;
  }

  /// Helper: realiza POST y devuelve un Map con statusCode y body/error.
  static Future<Map<String, dynamic>> _post(Uri uri, Map<String, String> headers, Map<String, dynamic> payload) async {
    try {
      final res = await http
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 12));
      return {'statusCode': res.statusCode, 'body': res.body};
    } catch (e) {
      debugPrint('[ApiService] _post exception for $uri: $e');
      return {'statusCode': -1, 'error': e.toString()};
    }
  }

  /// Envío principal: intenta múltiples endpoints hasta encontrar uno que responda 2xx.
  /// Si recibe 401 intenta refreshToken y reintenta la petición una vez.
  /// Si detecta 400 Invalid user id devuelve permanent=true para evitar reintentos.
  static Future<Map<String, dynamic>> sendLocation(Map<String, dynamic> payload,
      {bool enqueueOnFail = true}) async {
    debugPrint('[ApiService] Modo ${useFake ? "FALSO" : "REAL"} activo. Payload: ${jsonEncode(payload)}');

    if (useFake) {
      await Future.delayed(const Duration(milliseconds: 200));
      return {'success': true, 'statusCode': 200};
    }

    for (final ep in _locationEndpoints) {
      final uri = Uri.parse('$baseUrl$ep');

      // 1) Intento normal con Bearer
      var headers = _buildHeaders(scheme: 'Bearer');
      debugPrint('[ApiService] sendLocation try $uri with Authorization=${headers['Authorization'] != null ? "present" : "none"}');

      final first = await _post(uri, headers, payload);
      final firstStatus = first['statusCode'] is int ? first['statusCode'] as int : -1;
      final firstBody = first['body'] ?? first['error'];

      debugPrint('[ApiService] sendLocation try $uri status=$firstStatus body=$firstBody');

      if (firstStatus >= 200 && firstStatus < 300) {
        return {'success': true, 'statusCode': firstStatus, 'body': firstBody, 'endpoint': ep};
      }

      if (firstStatus == 404) {
        // endpoint no existe, intentar siguiente
        continue;
      }

      // Detectar 400 Invalid user id y marcar como permanente
      if (firstStatus == 400) {
        String parsedError = firstBody?.toString() ?? '';
        try {
          final parsed = jsonDecode(firstBody.toString());
          if (parsed is Map && parsed['error'] != null) parsedError = parsed['error'].toString();
        } catch (_) {}
        if (parsedError.toLowerCase().contains('invalid user id')) {
          debugPrint('[ApiService] sendLocation detected permanent error (Invalid user id) for $uri');
          return {
            'success': false,
            'statusCode': firstStatus,
            'body': firstBody,
            'endpoint': ep,
            'permanent': true,
            'message': 'Invalid user id'
          };
        }
      }

      // Si 401 -> intentar refresh token y reintentar una vez
      if (firstStatus == 401) {
        debugPrint('[ApiService] sendLocation received 401 for $uri. Attempting token refresh...');
        final refreshed = await AuthService.instance.refreshToken();
        debugPrint('[ApiService] token refresh result: $refreshed');

        if (refreshed) {
          // reconstruir headers con token nuevo y reintentar con Bearer
          headers = _buildHeaders(scheme: 'Bearer');
          final retry = await _post(uri, headers, payload);
          final retryStatus = retry['statusCode'] is int ? retry['statusCode'] as int : -1;
          final retryBody = retry['body'] ?? retry['error'];
          debugPrint('[ApiService] sendLocation retry after refresh $uri status=$retryStatus body=$retryBody');

          if (retryStatus >= 200 && retryStatus < 300) {
            return {'success': true, 'statusCode': retryStatus, 'body': retryBody, 'endpoint': ep};
          }

          // Si sigue 401, intentar con esquema 'Token'
          if (retryStatus == 401) {
            debugPrint('[ApiService] retry still 401, attempting with Authorization: Token <token>');
            headers = _buildHeaders(scheme: 'Token');
            final alt = await _post(uri, headers, payload);
            final altStatus = alt['statusCode'] is int ? alt['statusCode'] as int : -1;
            final altBody = alt['body'] ?? alt['error'];
            debugPrint('[ApiService] sendLocation alt-scheme $uri status=$altStatus body=$altBody');

            if (altStatus >= 200 && altStatus < 300) {
              return {'success': true, 'statusCode': altStatus, 'body': altBody, 'endpoint': ep};
            } else if (altStatus == 404) {
              continue;
            } else {
              // Detectar 400 Invalid user id en alt
              if (altStatus == 400) {
                String parsedError = altBody?.toString() ?? '';
                try {
                  final parsed = jsonDecode(altBody.toString());
                  if (parsed is Map && parsed['error'] != null) parsedError = parsed['error'].toString();
                } catch (_) {}
                if (parsedError.toLowerCase().contains('invalid user id')) {
                  return {
                    'success': false,
                    'statusCode': altStatus,
                    'body': altBody,
                    'endpoint': ep,
                    'permanent': true,
                    'message': 'Invalid user id'
                  };
                }
              }
              return {'success': false, 'statusCode': altStatus, 'body': altBody, 'endpoint': ep};
            }
          } else {
            // retryStatus no 2xx y no 401 -> detectar 400 permanent y devolver fallo
            if (retryStatus == 400) {
              String parsedError = retryBody?.toString() ?? '';
              try {
                final parsed = jsonDecode(retryBody.toString());
                if (parsed is Map && parsed['error'] != null) parsedError = parsed['error'].toString();
              } catch (_) {}
              if (parsedError.toLowerCase().contains('invalid user id')) {
                return {
                  'success': false,
                  'statusCode': retryStatus,
                  'body': retryBody,
                  'endpoint': ep,
                  'permanent': true,
                  'message': 'Invalid user id'
                };
              }
            }
            return {'success': false, 'statusCode': retryStatus, 'body': retryBody, 'endpoint': ep};
          }
        } else {
          // refreshToken falló: devolver 401 para que el caller pueda forzar re-login
          debugPrint('[ApiService] refreshToken failed; returning 401 to caller for $uri');
          return {'success': false, 'statusCode': 401, 'body': firstBody, 'endpoint': ep, 'message': 'Token refresh failed'};
        }
      }

      // Otros errores (p. ej. 400, 403, 500) -> detectar 400 Invalid user id y devolver info
      if (firstStatus == 400) {
        String parsedError = firstBody?.toString() ?? '';
        try {
          final parsed = jsonDecode(firstBody.toString());
          if (parsed is Map && parsed['error'] != null) parsedError = parsed['error'].toString();
        } catch (_) {}
        if (parsedError.toLowerCase().contains('invalid user id')) {
          return {
            'success': false,
            'statusCode': firstStatus,
            'body': firstBody,
            'endpoint': ep,
            'permanent': true,
            'message': 'Invalid user id'
          };
        }
      }

      return {'success': false, 'statusCode': firstStatus, 'body': firstBody, 'endpoint': ep};
    }

    // Ningún endpoint respondió 2xx
    debugPrint('[ApiService] sendLocation: no endpoint available for location');
    return {'success': false, 'statusCode': 404, 'message': 'No endpoint available for location'};
  }

  /// Alias que otras partes del código pueden llamar (compatibilidad).
  static Future<Map<String, dynamic>> sendLocationNow(Map<String, dynamic> payload) async {
    return await sendLocation(payload, enqueueOnFail: false);
  }
}
