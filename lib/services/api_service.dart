// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'queue_service.dart';

class ApiService {
  /// Cambia a `true` para pruebas inmediatas sin backend.
  /// Puedes dejarlo `true` temporalmente para que los envíos se marquen como enviados.
  static bool useFake = true;

  /// URL base de tu API real. Ajusta cuando tengas backend.
  static String baseUrl = 'https://tu-api.example.com';

  static Future<void> loadFakeModeFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    useFake = prefs.getBool('api_use_fake') ?? useFake;
  }

  static Future<void> setFakeMode(bool enabled) async {
    useFake = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('api_use_fake', enabled);
  }

  /// Envía inmediatamente al servidor (o simula si useFake==true).
  static Future<Map<String, dynamic>> sendLocationNow(Map<String, dynamic> payload) async {
    if (useFake) {
      // Simula éxito; imprime payload para depuración.
      print('[ApiService] Modo FALSO activo. Payload: ${jsonEncode(payload)}');
      return {'success': true, 'statusCode': 200};
    }

    try {
      final uri = Uri.parse('$baseUrl/locations');
      final token = AuthService.instance.token;
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final res = await http.post(uri, body: jsonEncode(payload), headers: headers).timeout(const Duration(seconds: 15));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return {'success': true, 'statusCode': res.statusCode};
      } else if (res.statusCode == 401) {
        try {
          await AuthService.instance.logout();
        } catch (_) {}
        return {'success': false, 'statusCode': res.statusCode, 'error': 'No autorizado (401)'};
      } else {
        return {'success': false, 'statusCode': res.statusCode, 'error': res.body};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Método público: intenta enviar ahora; si falla, encola y devuelve queueId.
  static Future<Map<String, dynamic>> sendLocation(Map<String, dynamic> payload) async {
    final res = await sendLocationNow(payload);
    if (res['success'] == true) {
      return res;
    }

    try {
      await QueueService.instance.init();
      final queueId = await QueueService.instance.add(payload);
      return {'success': false, 'error': 'Encolado para reintento', 'queued': true, 'queueId': queueId};
    } catch (e) {
      return {'success': false, 'error': 'Fallo al encolar: ${e.toString()}'};
    }
  }

  static Future<void> retryQueueItem(String queueId) async {
    await QueueService.instance.init();
    await QueueService.instance.retryNow(queueId);
  }
}
