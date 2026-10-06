// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'auth_service.dart';
import 'queue_service.dart';

class ApiService {
  static bool useFake = false;
  static String? _envBaseUrl;
  static String? _envEndpointPath;

  static dynamic jsonDecodeSafe(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return s;
    }
  }

  static Future<void> initFromEnv() async {
    try {
      final api = dotenv.env['API_BASE_URL'];
      final path = dotenv.env['LOCATIONS_PATH'];
      if (api != null && api.isNotEmpty) _envBaseUrl = api;
      if (path != null && path.isNotEmpty) _envEndpointPath = path;
      debugPrint('ApiService.initFromEnv: baseUrl=$_envBaseUrl endpoint=$_envEndpointPath');
    } catch (e) {
      debugPrint('ApiService.initFromEnv error: $e');
    }
  }

  static String get baseUrl => _envBaseUrl ?? 'http://localhost:3000';
  static String get endpointPath => _envEndpointPath ?? '/api/locations';

  static Future<void> loadFakeModeFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    useFake = prefs.getBool('api_use_fake') ?? useFake;
    debugPrint('ApiService.loadFakeModeFromPrefs: useFake=$useFake');
  }

  static Future<void> setFakeMode(bool enabled) async {
    useFake = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('api_use_fake', enabled);
    debugPrint('ApiService.setFakeMode: useFake=$useFake');
  }

  static Uri _buildUri() {
    final normalizedBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final normalizedPath = endpointPath.startsWith('/') ? endpointPath : '/$endpointPath';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  static Future<Map<String, dynamic>> sendLocationNow(Map<String, dynamic> payload) async {
    if (useFake) {
      debugPrint('[ApiService] Modo FALSO activo. Payload: ${jsonEncode(payload)}');
      return {'success': true, 'statusCode': 200};
    }

    final uri = _buildUri();
    String? token = AuthService.instance.token;
    Map<String, String> headers() {
      final h = <String, String>{'Content-Type': 'application/json', 'Accept': 'application/json'};
      if (token != null && token.isNotEmpty) h['Authorization'] = 'Bearer $token';
      return h;
    }

    debugPrint('DEBUG: ApiService.sendLocationNow -> POST ${uri.toString()} payload=$payload authTokenPresent=${token != null && token.isNotEmpty}');

    try {
      final res = await http.post(uri, body: jsonEncode(payload), headers: headers()).timeout(const Duration(seconds: 15));

      debugPrint('DEBUG: ApiService.sendLocationNow response status=${res.statusCode} body=${res.body}');

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return {'success': true, 'statusCode': res.statusCode, 'data': res.body.isNotEmpty ? jsonDecodeSafe(res.body) : null};
      } else if (res.statusCode == 401) {
        debugPrint('DEBUG: ApiService.sendLocationNow 401 body=${res.body}');
        try {
          final refreshed = await AuthService.instance.refreshToken();
          if (refreshed) {
            token = AuthService.instance.token;
            final retryRes = await http.post(uri, body: jsonEncode(payload), headers: headers()).timeout(const Duration(seconds: 15));
            debugPrint('DEBUG: ApiService.sendLocationNow retry status=${retryRes.statusCode} body=${retryRes.body}');
            if (retryRes.statusCode >= 200 && retryRes.statusCode < 300) {
              return {'success': true, 'statusCode': retryRes.statusCode, 'data': retryRes.body.isNotEmpty ? jsonDecodeSafe(retryRes.body) : null};
            } else if (retryRes.statusCode == 401) {
              try {
                await AuthService.instance.logout();
              } catch (e) {
                debugPrint('DEBUG: ApiService.sendLocationNow logout error after retry: $e');
              }
              return {'success': false, 'statusCode': retryRes.statusCode, 'error': 'No autorizado (401)', 'body': retryRes.body};
            } else {
              return {'success': false, 'statusCode': retryRes.statusCode, 'error': retryRes.body};
            }
          } else {
            try {
              await AuthService.instance.logout();
            } catch (e) {
              debugPrint('DEBUG: ApiService.sendLocationNow logout error after failed refresh: $e');
            }
            return {'success': false, 'statusCode': res.statusCode, 'error': 'No autorizado (401)', 'body': res.body};
          }
        } catch (e) {
          debugPrint('DEBUG: ApiService.sendLocationNow refresh error: $e');
          try {
            await AuthService.instance.logout();
          } catch (_) {}
          return {'success': false, 'statusCode': res.statusCode, 'error': 'No autorizado (401)', 'body': res.body};
        }
      } else {
        return {'success': false, 'statusCode': res.statusCode, 'error': res.body};
      }
    } catch (e) {
      debugPrint('DEBUG: ApiService.sendLocationNow exception: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> sendLocation(Map<String, dynamic> payload, {bool enqueueOnFail = true}) async {
    debugPrint('DEBUG: ApiService.sendLocation called payload=$payload endpoint=${endpointPath} baseUrl=${baseUrl} useFake=${useFake} enqueueOnFail=$enqueueOnFail');

    final res = await sendLocationNow(payload);
    if (res['success'] == true) {
      return res;
    }

    if (!enqueueOnFail) {
      return res;
    }

    try {
      await QueueService.instance.init();
      debugPrint('DEBUG: ApiService.sendLocation -> encolando payload=$payload');
      final queueId = await QueueService.instance.add(payload);
      debugPrint('DEBUG: ApiService.sendLocation -> encolado queueId=$queueId');
      return {'success': false, 'error': 'Encolado para reintento', 'queued': true, 'queueId': queueId};
    } catch (e) {
      debugPrint('DEBUG: ApiService.sendLocation enqueue error: $e');
      return {'success': false, 'error': 'Fallo al encolar: ${e.toString()}'};
    }
  }

  static Future<void> retryQueueItem(String queueId) async {
    await QueueService.instance.init();
    await QueueService.instance.retryNow(queueId);
  }
}
