// lib/services/queue_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    debugPrint('[QueueService] init: queue length=${_queue.length}');
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    _queue.clear();
    for (final s in raw) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        _queue.add(m);
      } catch (_) {}
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
    debugPrint('[QueueService] add id=$id payloadKeys=${payload.keys.toList()}');
    return id;
  }

  Future<void> removeById(String id) async {
    _queue.removeWhere((m) => m['id'] == id);
    await _saveToPrefs();
    debugPrint('[QueueService] removeById id=$id');
  }

  /// Marca manualmente un item como enviado.
  Future<void> markAsSent(String id) async {
    _queue.removeWhere((m) => m['id'] == id);
    await _saveToPrefs();
    debugPrint('[QueueService] markAsSent id=$id');
  }

  /// Notificar resultado del envío por WhatsApp para un item de la cola.
  Future<void> notifyWhatsAppResult(String id, Map<String, dynamic> whatsappRes) async {
    try {
      final item = _queue.firstWhere((m) => m['id'] == id, orElse: () => <String, dynamic>{});
      if (item.isEmpty) {
        debugPrint('[QueueService] notifyWhatsAppResult: item not found id=$id');
        return;
      }

      final bool whatsappOk = whatsappRes['success'] == true ||
          (whatsappRes['statusCode'] is int && (whatsappRes['statusCode'] as int) >= 200 && (whatsappRes['statusCode'] as int) < 300);

      debugPrint('[QueueService] notifyWhatsAppResult id=$id whatsappOk=$whatsappOk res=$whatsappRes');

      if (whatsappOk) {
        await markAsSent(id);
      } else {
        debugPrint('[QueueService] notifyWhatsAppResult id=$id whatsapp reported failure');
      }
    } catch (e) {
      debugPrint('[QueueService] notifyWhatsAppResult exception: $e');
    }
  }

  /// Reintenta ahora un item específico (útil para reintentos manuales).
  Future<void> processNowForId(String id, {Map<String, dynamic>? whatsappRes}) async {
    final item = _queue.firstWhere((m) => m['id'] == id, orElse: () => <String, dynamic>{});
    if (item.isEmpty) return;

    if (whatsappRes != null) {
      final bool whatsappOk = whatsappRes['success'] == true ||
          (whatsappRes['statusCode'] is int && (whatsappRes['statusCode'] as int) >= 200 && (whatsappRes['statusCode'] as int) < 300);
      if (whatsappOk) {
        await markAsSent(id);
        return;
      }
    }

    final payload = Map<String, dynamic>.from(item['payload'] as Map);
    try {
      final res = await ApiService.sendLocationNow(payload);
      debugPrint('[QueueService] processNowForId id=$id apiRes=$res');

      final bool apiOk = (res['success'] == true) ||
          (res['statusCode'] is int && (res['statusCode'] as int) >= 200 && (res['statusCode'] as int) < 300);

      if (apiOk) {
        await markAsSent(id);
        return;
      }

      final statusCode = res['statusCode'] is int ? res['statusCode'] as int : -1;
      final message = (res['message'] ?? res['body'] ?? '').toString();

      // Permanent error (e.g., invalid user id) -> mark as permanent failure
      if (res['permanent'] == true || (statusCode == 400 && message.toLowerCase().contains('invalid user id'))) {
        item['status'] = 'FALLIDO_PERMANENTE';
        await _saveToPrefs();
        debugPrint('[QueueService] processNowForId id=$id marked FALLIDO_PERMANENTE');
        return;
      }

      if (statusCode == 401 && message.toLowerCase().contains('token')) {
        item['status'] = 'PENDIENTE_TOKEN';
        item['nextAttempt'] = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
        await _saveToPrefs();
        debugPrint('[QueueService] processNowForId id=$id token issue: paused for 1h');
        return;
      }

      if (statusCode == 404) {
        item['status'] = 'PENDIENTE';
        item['nextAttempt'] = DateTime.now().add(const Duration(seconds: 60)).millisecondsSinceEpoch;
        await _saveToPrefs();
        debugPrint('[QueueService] processNowForId id=$id endpoint 404, reprogramado en 60s');
        return;
      }

      final attempts = item['attempts'] as int? ?? 0;
      final newAttempts = attempts + 1;
      final backoffSeconds = _computeBackoffSeconds(newAttempts);
      item['attempts'] = newAttempts;
      item['status'] = 'REINTENTANDO';
      item['nextAttempt'] = DateTime.now().add(Duration(seconds: backoffSeconds)).millisecondsSinceEpoch;
      await _saveToPrefs();
      debugPrint('[QueueService] processNowForId id=$id fallo, attempts=$newAttempts, nextAttempt=$backoffSeconds s');
    } catch (e) {
      final attempts = item['attempts'] as int? ?? 0;
      final newAttempts = attempts + 1;
      final backoffSeconds = _computeBackoffSeconds(newAttempts);
      item['attempts'] = newAttempts;
      item['status'] = 'REINTENTANDO';
      item['nextAttempt'] = DateTime.now().add(Duration(seconds: backoffSeconds)).millisecondsSinceEpoch;
      await _saveToPrefs();
      debugPrint('[QueueService] processNowForId id=$id exception: $e; attempts=$newAttempts; reprogramado $backoffSeconds s');
    }
  }

  List<Map<String, dynamic>> getQueueSnapshot() {
    return List<Map<String, dynamic>>.from(_queue);
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _processQueue());
  }

  Future<void> _processQueue() async {
    if (_queue.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final rawItem in List<Map<String, dynamic>>.from(_queue)) {
      try {
        final nextAttempt = rawItem['nextAttempt'] as int? ?? 0;
        if (nextAttempt > now) continue;

        final attempts = rawItem['attempts'] as int? ?? 0;
        final payload = Map<String, dynamic>.from(rawItem['payload'] as Map);
        final id = rawItem['id']?.toString() ?? '';

        final res = await ApiService.sendLocationNow(payload);
        debugPrint('[QueueService] procesando id=$id result=$res');

        final bool apiOk = (res['success'] == true) ||
            (res['statusCode'] is int && (res['statusCode'] as int) >= 200 && (res['statusCode'] as int) < 300);

        if (apiOk) {
          _queue.removeWhere((m) => m['id'] == id);
          await _saveToPrefs();
          debugPrint('[QueueService] id=$id enviado y removido (apiOk=true)');
          continue;
        }

        final statusCode = res['statusCode'] is int ? res['statusCode'] as int : -1;
        final message = (res['message'] ?? res['body'] ?? '').toString();

        // Permanent error -> mark and skip further retries
        if (res['permanent'] == true || (statusCode == 400 && message.toLowerCase().contains('invalid user id'))) {
          rawItem['status'] = 'FALLIDO_PERMANENTE';
          await _saveToPrefs();
          debugPrint('[QueueService] id=$id marcado FALLIDO_PERMANENTE por respuesta del servidor');
          continue;
        }

        // Token issue -> pause for longer
        if (statusCode == 401 && message.toLowerCase().contains('token')) {
          rawItem['status'] = 'PENDIENTE_TOKEN';
          rawItem['nextAttempt'] = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
          await _saveToPrefs();
          debugPrint('[QueueService] id=$id token issue detected, paused for 1h');
          continue;
        }

        // 404 -> short reattempt without penalizing
        if (statusCode == 404) {
          rawItem['status'] = 'PENDIENTE';
          rawItem['nextAttempt'] = DateTime.now().add(const Duration(seconds: 60)).millisecondsSinceEpoch;
          await _saveToPrefs();
          debugPrint('[QueueService] id=$id endpoint 404, reprogramado en 60s');
          continue;
        }

        // Otros errores -> incrementar attempts y aplicar backoff
        final newAttempts = attempts + 1;
        final backoffSeconds = _computeBackoffSeconds(newAttempts);
        rawItem['attempts'] = newAttempts;
        rawItem['status'] = 'REINTENTANDO';
        rawItem['nextAttempt'] = DateTime.now().add(Duration(seconds: backoffSeconds)).millisecondsSinceEpoch;
        await _saveToPrefs();
        debugPrint('[QueueService] id=$id fallo, attempts=$newAttempts, nextAttempt en $backoffSeconds s');
      } catch (e) {
        final attempts = rawItem['attempts'] as int? ?? 0;
        final newAttempts = attempts + 1;
        final backoffSeconds = _computeBackoffSeconds(newAttempts);
        rawItem['attempts'] = newAttempts;
        rawItem['status'] = 'REINTENTANDO';
        rawItem['nextAttempt'] = DateTime.now().add(Duration(seconds: backoffSeconds)).millisecondsSinceEpoch;
        await _saveToPrefs();
        debugPrint('[QueueService] id=${rawItem['id']} exception: $e; attempts=$newAttempts; reprogramado $backoffSeconds s');
      }
    }
  }

  int _computeBackoffSeconds(int attempts) {
    final capped = attempts > 10 ? 10 : attempts;
    final seconds = (1 << capped) * 5;
    return seconds > 3600 ? 3600 : seconds;
  }

  Future<void> retryNow(String id) async {
    final item = _queue.firstWhere((m) => m['id'] == id, orElse: () => <String, dynamic>{});
    if (item.isEmpty) return;
    item['nextAttempt'] = DateTime.now().millisecondsSinceEpoch;
    item['status'] = 'REINTENTANDO';
    await _saveToPrefs();
    await _processQueue();
  }

  /// Reprograma inmediatamente todos los items marcados como PENDIENTE_TOKEN
  /// para que se intenten ahora. Útil tras un login exitoso.
  Future<void> resumePendingTokenItems() async {
    var changed = false;
    for (final item in _queue) {
      final status = (item['status'] ?? '').toString();
      if (status == 'PENDIENTE_TOKEN') {
        item['status'] = 'REINTENTANDO';
        item['nextAttempt'] = DateTime.now().millisecondsSinceEpoch;
        changed = true;
        debugPrint('[QueueService] resumePendingTokenItems: reprogramado id=${item['id']}');
      }
    }
    if (changed) {
      await _saveToPrefs();
      // Ejecutar procesamiento inmediato en background
      unawaited(_processQueue());
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
