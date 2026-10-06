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

  /// Permite que otro componente marque manualmente un item como enviado (por ejemplo,
  /// cuando el envío por WhatsApp fue exitoso y quieres evitar que la cola marque "fallido").
  Future<void> markAsSent(String id) async {
    _queue.removeWhere((m) => m['id'] == id);
    await _saveToPrefs();
    debugPrint('[QueueService] markAsSent id=$id');
  }

  /// Notificar resultado del envío por WhatsApp para un item de la cola.
  /// Si whatsappRes indica éxito, el item se marca como enviado y se elimina de la cola.
  /// whatsappRes debe contener al menos {'success': bool} o {'statusCode': int}.
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
        // Si WhatsApp falló, dejar la cola como está para que el proceso normal la reintente.
        // Opcional: incrementar attempts o reprogramar según tu política.
        debugPrint('[QueueService] notifyWhatsAppResult id=$id whatsapp reported failure');
      }
    } catch (e) {
      debugPrint('[QueueService] notifyWhatsAppResult exception: $e');
    }
  }

  /// Procesa un item específico ahora. Útil para reintentos manuales o para integrar
  /// el resultado de envíos externos (WhatsApp) con el intento al backend.
  /// Si whatsappRes != null y es exitoso, el item se marcará como enviado sin llamar al backend.
  Future<void> processNowForId(String id, {Map<String, dynamic>? whatsappRes}) async {
    final item = _queue.firstWhere((m) => m['id'] == id, orElse: () => <String, dynamic>{});
    if (item.isEmpty) return;

    // Si WhatsApp ya reportó éxito, eliminar y guardar.
    if (whatsappRes != null) {
      final bool whatsappOk = whatsappRes['success'] == true ||
          (whatsappRes['statusCode'] is int && (whatsappRes['statusCode'] as int) >= 200 && (whatsappRes['statusCode'] as int) < 300);
      if (whatsappOk) {
        await markAsSent(id);
        return;
      }
    }

    // Si no hay whatsappRes o fue fallido, intentar enviar al backend ahora.
    final payload = Map<String, dynamic>.from(item['payload'] as Map);
    try {
      final res = await ApiService.sendLocationNow(payload);
      debugPrint('[QueueService] processNowForId id=$id apiRes=$res');

      final bool apiOk = (res['success'] == true) ||
          (res['statusCode'] is int && (res['statusCode'] as int) >= 200 && (res['statusCode'] as int) < 300);

      if (apiOk) {
        await markAsSent(id);
      } else {
        final statusCode = res['statusCode'] is int ? res['statusCode'] as int : -1;
        if (statusCode == 404) {
          // Endpoint no existe: reprogramar en corto plazo sin penalizar demasiado.
          item['status'] = 'PENDIENTE';
          item['nextAttempt'] = DateTime.now().add(const Duration(seconds: 60)).millisecondsSinceEpoch;
          await _saveToPrefs();
          debugPrint('[QueueService] processNowForId id=$id endpoint 404, reprogramado en 60s');
        } else {
          final attempts = item['attempts'] as int? ?? 0;
          final newAttempts = attempts + 1;
          final backoffSeconds = _computeBackoffSeconds(newAttempts);
          item['attempts'] = newAttempts;
          item['status'] = 'REINTENTANDO';
          item['nextAttempt'] = DateTime.now().add(Duration(seconds: backoffSeconds)).millisecondsSinceEpoch;
          await _saveToPrefs();
          debugPrint('[QueueService] processNowForId id=$id fallo, attempts=$newAttempts, nextAttempt=$backoffSeconds s');
        }
      }
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
    // Iterar sobre una copia para poder modificar la lista original
    for (final rawItem in List<Map<String, dynamic>>.from(_queue)) {
      try {
        final nextAttempt = rawItem['nextAttempt'] as int? ?? 0;
        if (nextAttempt > now) continue;

        final attempts = rawItem['attempts'] as int? ?? 0;
        final payload = Map<String, dynamic>.from(rawItem['payload'] as Map);
        final id = rawItem['id']?.toString() ?? '';

        // Llamada al API (delegada a ApiService)
        final res = await ApiService.sendLocationNow(payload);
        debugPrint('[QueueService] procesando id=$id result=$res');

        // Evaluación tolerante de éxito: aceptar success==true o cualquier 2xx
        final bool apiOk = (res['success'] == true) ||
            (res['statusCode'] is int && (res['statusCode'] as int) >= 200 && (res['statusCode'] as int) < 300) ||
            (res['status'] is int && (res['status'] as int) >= 200 && (res['status'] as int) < 300);

        // Si backend respondió 404 (endpoint no disponible), reprogramar sin penalizar demasiado.
        if (apiOk) {
          _queue.removeWhere((m) => m['id'] == id);
          await _saveToPrefs();
          debugPrint('[QueueService] id=$id enviado y removido (apiOk=true)');
        } else {
          final statusCode = res['statusCode'] is int ? res['statusCode'] as int : -1;

          if (statusCode == 404) {
            // Endpoint no existe: reintentar más tarde sin incrementar attempts.
            rawItem['status'] = 'PENDIENTE';
            rawItem['nextAttempt'] = DateTime.now().add(const Duration(seconds: 60)).millisecondsSinceEpoch;
            // No incrementamos attempts para evitar que se marque como "REINTENTANDO" excesivamente.
            await _saveToPrefs();
            debugPrint('[QueueService] id=$id endpoint 404, reprogramado en 60s sin incrementar attempts');
          } else {
            // Error distinto a 404: incrementar attempts y aplicar backoff
            final newAttempts = attempts + 1;
            final backoffSeconds = _computeBackoffSeconds(newAttempts);
            rawItem['attempts'] = newAttempts;
            rawItem['status'] = 'REINTENTANDO';
            rawItem['nextAttempt'] = DateTime.now().add(Duration(seconds: backoffSeconds)).millisecondsSinceEpoch;
            await _saveToPrefs();
            debugPrint('[QueueService] id=$id fallo, attempts=$newAttempts, nextAttempt en $backoffSeconds s');
          }
        }
      } catch (e) {
        // En caso de excepción de red u otra, incrementar attempts y reprogramar
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
    // Exponencial con factor base 2, multiplicador 5 para suavizar
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

  Future<void> clearAll() async {
    _queue.clear();
    await _saveToPrefs();
  }

  void dispose() {
    _timer?.cancel();
    _running = false;
  }
}
