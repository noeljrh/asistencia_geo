// lib/services/queue_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'auth_service.dart';

class QueueService {
  static final QueueService instance = QueueService._internal();

  QueueService._internal();

  final Map<String, Map<String, dynamic>> _queue = {};
  Timer? _timer;
  bool _started = false;
  final String _prefsKey = 'asistencia_queue_v1';

  /// Intervalo entre intentos de procesamiento (ajustable)
  Duration _interval = const Duration(seconds: 10);

  /// Inicializa la cola: carga desde SharedPreferences y arranca el timer.
  /// Idempotente: llamar varias veces no reiniciará el timer.
  Future<void> init() async {
    if (_started) {
      debugPrint('QueueService.init: ya inicializado');
      return;
    }

    debugPrint('QueueService.init: cargando desde prefs...');
    await _loadFromPrefs();
    _startTimer();
    _started = true;
    debugPrint('QueueService.init: iniciado. queueLength=${_queue.length}');
  }

  /// Detener la cola (útil para pruebas)
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    _started = false;
    debugPrint('QueueService.dispose: detenido');
  }

  /// Agrega un payload a la cola y lo persiste.
  /// Devuelve el id generado para el item encolado.
  Future<String> add(Map<String, dynamic> payload) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final item = {
      'id': id,
      'payload': payload,
      'attempts': 0,
      'status': 'PENDIENTE',
      'nextAttemptAt': DateTime.now().toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
    };
    _queue[id] = item;
    await _saveToPrefs();
    debugPrint('QueueService.add id=$id payload=$payload');
    return id;
  }

  /// Marca un item como enviado por el usuario (por ejemplo, tras confirmar envío por WhatsApp).
  /// Si removeFromQueue es true, el item se elimina de la cola; si es false, se mantiene como historial con status ENVIADO.
  Future<void> markSent(String id, {bool removeFromQueue = true}) async {
    final item = _queue[id];
    if (item == null) {
      debugPrint('QueueService.markSent: item no encontrado id=$id');
      return;
    }

    item['status'] = 'ENVIADO';
    item['sentAt'] = DateTime.now().toIso8601String();

    if (removeFromQueue) {
      _queue.remove(id);
      debugPrint('QueueService.markSent: item eliminado de la cola id=$id');
    } else {
      _queue[id] = item;
      debugPrint('QueueService.markSent: item marcado ENVIADO id=$id (conservado en historial)');
    }

    await _saveToPrefs();
  }

  /// Reintentar ahora un item específico (si existe)
  Future<void> retryNow(String queueId) async {
    final item = _queue[queueId];
    if (item == null) {
      debugPrint('QueueService.retryNow: item no encontrado id=$queueId');
      return;
    }
    item['nextAttemptAt'] = DateTime.now().toIso8601String();
    item['status'] = 'REINTENTANDO';
    await _saveToPrefs();
    debugPrint('QueueService.retryNow: marcado para reintento inmediato id=$queueId');
    // Procesar inmediatamente en background (no bloquear quien llamó)
    unawaited(_processQueue());
  }

  /// Carga la cola desde SharedPreferences
  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) {
        debugPrint('QueueService._loadFromPrefs: no hay datos previos');
        return;
      }
      final Map<String, dynamic> decoded = jsonDecode(raw);
      _queue.clear();
      decoded.forEach((k, v) {
        _queue[k] = Map<String, dynamic>.from(v as Map);
      });
      debugPrint('QueueService._loadFromPrefs loaded=${_queue.length}');
    } catch (e) {
      debugPrint('QueueService._loadFromPrefs error: $e');
    }
  }

  /// Persiste la cola en SharedPreferences
  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_queue);
      await prefs.setString(_prefsKey, encoded);
      debugPrint('QueueService._saveToPrefs saved=${_queue.length}');
    } catch (e) {
      debugPrint('QueueService._saveToPrefs error: $e');
    }
  }

  /// Inicia el timer periódico que procesa la cola
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) async {
      await _processQueue();
    });
    debugPrint('QueueService._startTimer: timer iniciado con intervalo ${_interval.inSeconds}s');
  }

  /// Procesa la cola: intenta enviar items cuyo nextAttemptAt <= ahora
  Future<void> _processQueue() async {
    if (_queue.isEmpty) {
      // nada que procesar
      return;
    }

    // Evitar que múltiples ejecuciones concurrentes procesen la misma cola
    if (!_started) return;

    final now = DateTime.now();
    final ids = _queue.keys.toList();

    for (final id in ids) {
      final item = _queue[id];
      if (item == null) continue;

      try {
        final nextAttemptAt = DateTime.parse(item['nextAttemptAt'] as String);
        if (nextAttemptAt.isAfter(now)) continue;

        // Si no estamos en modo fake y no hay token, reprogramar y saltar
        if (!ApiService.useFake && !AuthService.instance.isAuthenticated) {
          // reintentar más tarde cuando el usuario inicie sesión
          item['attempts'] = (item['attempts'] as int? ?? 0);
          item['nextAttemptAt'] = DateTime.now().add(const Duration(seconds: 60)).toIso8601String();
          await _saveToPrefs();
          debugPrint('QueueService._processQueue: sin auth, reprogramado id=$id para +60s');
          continue;
        }

        // Intentar enviar
        final payload = Map<String, dynamic>.from(item['payload'] as Map);
        debugPrint('QueueService._processQueue processing id=$id attempts=${item['attempts']} payload=$payload');

        final res = await ApiService.sendLocationNow(payload);

        // Manejo de respuesta
        final statusCode = res['statusCode'] as int?;
        if (res['success'] == true) {
          // Eliminamos del queue
          _queue.remove(id);
          await _saveToPrefs();
          debugPrint('QueueService._processQueue success id=$id removed');
        } else if (statusCode == 401) {
          // 401: token faltante o inválido
          final body = res['body']?.toString() ?? res['error']?.toString() ?? '';
          debugPrint('QueueService._processQueue 401 body=$body');

          // Si el backend indica token inválido/expirado, forzar logout y reintentar más tarde
          if (body.contains('Invalid') || body.contains('expired') || body.contains('invalid')) {
            try {
              await AuthService.instance.logout();
            } catch (e) {
              debugPrint('QueueService._processQueue logout error: $e');
            }
            // Programar reintento largo para esperar que el usuario vuelva a loguearse
            item['attempts'] = (item['attempts'] as int? ?? 0) + 1;
            item['nextAttemptAt'] = DateTime.now().add(const Duration(minutes: 30)).toIso8601String();
            await _saveToPrefs();
            debugPrint('QueueService._processQueue token inválido: forzado logout y reprogramado id=$id para +30min');
          } else {
            // Missing token u otro 401: reintentar con backoff normal
            final attempts = (item['attempts'] as int? ?? 0) + 1;
            item['attempts'] = attempts;
            final backoffSeconds = _computeBackoffSeconds(attempts);
            item['nextAttemptAt'] = DateTime.now().add(Duration(seconds: backoffSeconds)).toIso8601String();
            await _saveToPrefs();
            debugPrint('QueueService._processQueue 401 reprogramado id=$id in ${backoffSeconds}s attempts=$attempts');
          }
        } else {
          // Otros fallos: incrementar attempts y programar reintento exponencial
          final attempts = (item['attempts'] as int? ?? 0) + 1;
          item['attempts'] = attempts;
          final backoffSeconds = _computeBackoffSeconds(attempts);
          item['nextAttemptAt'] = DateTime.now().add(Duration(seconds: backoffSeconds)).toIso8601String();
          await _saveToPrefs();
          debugPrint('QueueService._processQueue failed id=$id status=${statusCode ?? 'n/a'} error=${res['error'] ?? 'unknown'} scheduled retry in ${backoffSeconds}s attempts=$attempts');
        }
      } catch (e, st) {
        debugPrint('QueueService._processQueue caught exception: $e');
        debugPrint(st.toString());
        // Si hay excepción al procesar, programar reintento con backoff
        try {
          final attempts = (item['attempts'] as int? ?? 0) + 1;
          item['attempts'] = attempts;
          final backoffSeconds = _computeBackoffSeconds(attempts);
          item['nextAttemptAt'] = DateTime.now().add(Duration(seconds: backoffSeconds)).toIso8601String();
          await _saveToPrefs();
          debugPrint('QueueService._processQueue exception scheduled retry attempts=$attempts in ${backoffSeconds}s');
        } catch (e2) {
          debugPrint('QueueService._processQueue error scheduling retry: $e2');
        }
      }
    }
  }

  /// Cálculo simple de backoff exponencial con tope
  int _computeBackoffSeconds(int attempts) {
    final base = 10; // segundos
    final maxBackoff = 3600; // 1 hora
    final capped = attempts > 6 ? 6 : attempts;
    final backoff = base * (1 << capped); // exponencial hasta 2^6
    return backoff > maxBackoff ? maxBackoff : backoff;
  }

  /// Para pruebas: obtener la longitud actual de la cola
  int get queueLength => _queue.length;

  /// Para pruebas: listar ids en cola
  List<String> get queuedIds => _queue.keys.toList();

  /// Obtener snapshot de la cola (útil para UI)
  List<Map<String, dynamic>> getQueueSnapshot() {
    return _queue.values.map((m) => Map<String, dynamic>.from(m)).toList();
  }
}

