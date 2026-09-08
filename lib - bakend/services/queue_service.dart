// lib/services/queue_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../src/http_utils.dart';
import 'api_service.dart';

class QueueService {
  QueueService._privateConstructor();
  static final QueueService instance = QueueService._privateConstructor();

  static const _prefsKey = 'send_queue_v1';
  final List<Map<String, dynamic>> _queue = [];
  Timer? _timer;
  bool _running = false;

  Future<void> init() async {
    if (_running) return;
    await _loadFromPrefs();
    _startTimer();
    _running = true;
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    _queue.clear();
    for (final s in raw) {
      try {
        final m = jsonDecode(s);
        if (m is Map) {
          // Aseguramos que los valores internos sean Map<String, dynamic>
          _queue.add(Map<String, dynamic>.from(m));
        } else {
          // Si no es Map, ignoramos la entrada
        }
      } catch (_) {
        // Ignorar entradas corruptas
      }
    }
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _queue.map((m) => jsonEncode(m)).toList();
    await prefs.setStringList(_prefsKey, raw);
  }

  /// Añade un payload a la cola y devuelve el queueId generado.
  Future<String> add(Map<String, dynamic> payload) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final item = {
      'id': id,
      'payload': payload,
      'attempts': 0,
      'status': 'PENDIENTE',
      'nextAttempt': DateTime.now().millisecondsSinceEpoch,
      'createdAt': DateTime.now().toIso8601String(),
    };
    _queue.insert(0, item);
    await _saveToPrefs();
    return id;
  }

  Future<void> removeById(String id) async {
    _queue.removeWhere((m) => m['id'] == id);
    await _saveToPrefs();
  }

  List<Map<String, dynamic>> getQueueSnapshot() {
    // Devolvemos una copia superficial para evitar mutaciones externas
    return _queue.map((m) => Map<String, dynamic>.from(m)).toList();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _processQueue());
  }

  Future<void> _processQueue() async {
    if (_queue.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Iteramos sobre una copia para poder modificar la lista original dentro del bucle
    for (final item in List<Map<String, dynamic>>.from(_queue)) {
      try {
        final nextAttempt = (item['nextAttempt'] is int) ? item['nextAttempt'] as int : int.tryParse(item['nextAttempt']?.toString() ?? '0') ?? 0;
        if (nextAttempt > now) continue;

        final attempts = item['attempts'] is int ? item['attempts'] as int : int.tryParse(item['attempts']?.toString() ?? '0') ?? 0;

        // Normalizamos payload: puede ser Map o String JSON
        final rawPayload = item['payload'];
        Map<String, dynamic> payload;
        if (rawPayload is Map) {
          payload = Map<String, dynamic>.from(rawPayload);
        } else {
          // Si viene como String u otro tipo, intentamos parsearlo con el helper
          payload = parseResponseToMap(rawPayload);
        }

        final res = await ApiService.sendLocationNow(payload);
        print('[QueueService] procesando id=${item['id']} result=$res');

        // Respuesta esperada: Map con clave 'success'
        final resultMap = (res is Map) ? Map<String, dynamic>.from(res) : (res is String ? parseResponseToMap(res) : {'success': false});

        if (resultMap['success'] == true) {
          _queue.removeWhere((m) => m['id'] == item['id']);
          await _saveToPrefs();
        } else {
          final newAttempts = attempts + 1;
          final backoffSeconds = _computeBackoffSeconds(newAttempts);
          item['attempts'] = newAttempts;
          item['status'] = 'REINTENTANDO';
          item['nextAttempt'] = DateTime.now().add(Duration(seconds: backoffSeconds)).millisecondsSinceEpoch;
          await _saveToPrefs();
        }
      } catch (e) {
        // En caso de error (parsing, red, etc.) actualizamos intentos y programamos reintento
        final attempts = item['attempts'] is int ? item['attempts'] as int : int.tryParse(item['attempts']?.toString() ?? '0') ?? 0;
        final newAttempts = attempts + 1;
        final backoffSeconds = _computeBackoffSeconds(newAttempts);
        item['attempts'] = newAttempts;
        item['status'] = 'REINTENTANDO';
        item['nextAttempt'] = DateTime.now().add(Duration(seconds: backoffSeconds)).millisecondsSinceEpoch;
        await _saveToPrefs();
        print('[QueueService] error procesando id=${item['id']}: $e');
      }
    }
  }

  int _computeBackoffSeconds(int attempts) {
    final capped = attempts > 10 ? 10 : attempts;
    // Exponencial con factor base 2 y multiplicador 5
    final seconds = (1 << capped) * 5;
    return seconds > 3600 ? 3600 : seconds;
  }

  Future<void> retryNow(String id) async {
    try {
      final item = _queue.firstWhere((m) => m['id'] == id);
      item['nextAttempt'] = DateTime.now().millisecondsSinceEpoch;
      item['status'] = 'REINTENTANDO';
      await _saveToPrefs();
      await _processQueue();
    } catch (_) {
      // No existe el item; nada que hacer
    }
  }

  Future<void> clearAll() async {
    _queue.clear();
    await _saveToPrefs();
  }

  void dispose() {
    _timer?.cancel();
    _running = false;
  }
}
