// lib/services/api_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Envío principal: intenta múltiples endpoints hasta encontrar uno que responda 2xx.
  static Future<Map<String, dynamic>> sendLocation(Map<String, dynamic> payload,
      {bool enqueueOnFail = true}) async {
    debugPrint('[ApiService] Modo ${useFake ? "FALSO" : "REAL"} activo. Payload: ${jsonEncode(payload)}');

    if (useFake) {
      await Future.delayed(const Duration(milliseconds: 200));
      return {'success': true, 'statusCode': 200};
    }

    for (final ep in _locationEndpoints) {
      final uri = Uri.parse('$baseUrl$ep');
      try {
        final res = await http
            .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload))
            .timeout(const Duration(seconds: 12));

        debugPrint('[ApiService] sendLocation try $uri status=${res.statusCode} body=${res.body}');

        if (res.statusCode >= 200 && res.statusCode < 300) {
          return {'success': true, 'statusCode': res.statusCode, 'body': res.body, 'endpoint': ep};
        } else if (res.statusCode == 404) {
          // Intentar siguiente endpoint
          continue;
        } else {
          // Error no-404: devolver info para manejo por caller
          return {'success': false, 'statusCode': res.statusCode, 'body': res.body, 'endpoint': ep};
        }
      } catch (e) {
        debugPrint('[ApiService] sendLocation exception for $uri: $e');
        // Intentar siguiente endpoint
        continue;
      }
    }

    // Ningún endpoint respondió 2xx
    debugPrint('[ApiService] sendLocation: no endpoint disponible para location');
    return {'success': false, 'statusCode': 404, 'message': 'No endpoint available for location'};
  }

  /// Alias que otras partes del código pueden llamar (compatibilidad).
  static Future<Map<String, dynamic>> sendLocationNow(Map<String, dynamic> payload) async {
    return await sendLocation(payload, enqueueOnFail: false);
  }
}
