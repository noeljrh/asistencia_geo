// lib/src/http_utils.dart
import 'dart:convert';

Map<String, dynamic> parseResponseToMap(dynamic data) {
  if (data == null) {
    throw Exception('Response is null');
  }
  if (data is Map) {
    return Map<String, dynamic>.from(data);
  }
  if (data is String) {
    try {
      final parsed = jsonDecode(data);
      if (parsed is Map) return Map<String, dynamic>.from(parsed);
      throw Exception('Parsed JSON is not an object');
    } catch (e) {
      throw Exception('Failed to parse response string as JSON: $e');
    }
  }
  throw Exception('Unexpected response type: ${data.runtimeType}');
}


