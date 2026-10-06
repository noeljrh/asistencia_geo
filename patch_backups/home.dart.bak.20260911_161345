// lib/screens/home.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/location_service.dart';
import '../services/api_service.dart';
import '../services/queue_service.dart';
import '../widgets/history_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _name = '';
  String _status = '';
  List<String> _history = [];
  bool _isSending = false;
  bool _isPreparingWhatsApp = false;

  @override
  void initState() {
    super.initState();
    _loadName();
    _loadHistory();
    QueueService.instance.init();
  }

  Future<void> _loadName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _name = prefs.getString('user_name') ?? '');
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _history = prefs.getStringList('history') ?? []);
  }

  Future<void> _saveHistoryList() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('history', _history);
  }

  Future<void> _addHistory(String entry) async {
    _history.insert(0, entry);
    await _saveHistoryList();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _sendLocationToServer() async {
    if (_isSending) return;
    setState(() {
      _isSending = true;
      _status = 'Obteniendo ubicación...';
    });

    try {
      final pos = await LocationService.getCurrentPosition();
      final timestamp = DateFormat("yyyy-MM-dd HH:mm:ss").format(DateTime.now());
      final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}';

      final payload = {
        'name': _name,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'timestamp': timestamp,
        'accuracy': pos.accuracy,
        'maps_url': mapsUrl,
      };

      setState(() => _status = 'Intentando enviar al servidor...');
      // Intento inmediato SIN encolar automáticamente si falla
      final res = await ApiService.sendLocation(payload, enqueueOnFail: false);

      print('[DEBUG] ApiService.sendLocation (direct) response: $res');

      if (res['success'] == true) {
        // Enviado correctamente
        final entry = '$timestamp — Enviado: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}\n$mapsUrl';
        await _addHistory(entry);
        if (!mounted) return;
        setState(() => _status = 'Enviado correctamente');
        _showSnack('Enviado correctamente', success: true);
      } else {
        // Falló el envío inmediato: mostrar diálogo con opciones
        if (!mounted) return;
        setState(() => _status = 'Error al enviar. Esperando acción del usuario');

        final choice = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('No se pudo enviar'),
            content: const Text('No fue posible enviar al servidor. ¿Qué deseas hacer?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('retry'),
                child: const Text('Reintentar ahora'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('enqueue'),
                child: const Text('Encolar para reintento'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop('mark_sent'),
                child: const Text('Marcar como enviado'),
              ),
            ],
          ),
        );

        // Manejar la elección del usuario
        if (choice == 'retry') {
          // Reintentar inmediatamente (usar enqueueOnFail true para que encole si falla)
          setState(() => _status = 'Reintentando ahora...');
          final retryRes = await ApiService.sendLocation(payload, enqueueOnFail: true);
          print('[DEBUG] ApiService.sendLocation (retry) response: $retryRes');

          if (retryRes['success'] == true) {
            final entry = '$timestamp — Reenviado correctamente: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}\n$mapsUrl';
            await _addHistory(entry);
            if (!mounted) return;
            setState(() => _status = 'Reenviado correctamente');
            _showSnack('Reenviado correctamente', success: true);
          } else if (retryRes['queued'] == true && retryRes['queueId'] != null) {
            final qid = retryRes['queueId'] as String;
            final entry = '$timestamp — PENDIENTE — queueId:$qid\n$mapsUrl';
            await _addHistory(entry);
            if (!mounted) return;
            setState(() => _status = 'Encolado para reintento');
            _showSnack('Encolado para reintento', success: false);
          } else {
            final err = retryRes['error'] ?? 'Error desconocido';
            final entry = '$timestamp — Error al reenviar: $err\n$mapsUrl';
            await _addHistory(entry);
            if (!mounted) return;
            setState(() => _status = 'Error al reenviar: $err');
            _showSnack('Error al reenviar: $err', success: false);
          }
        } else if (choice == 'enqueue') {
          // Encolar explícitamente
          try {
            await QueueService.instance.init();
            final qid = await QueueService.instance.add(payload);
            final entry = '$timestamp — PENDIENTE — queueId:$qid\n$mapsUrl';
            await _addHistory(entry);
            if (!mounted) return;
            setState(() => _status = 'Encolado para reintento');
            _showSnack('Encolado para reintento', success: false);
          } catch (e) {
            final entry = '$timestamp — Error al encolar: ${e.toString()}\n$mapsUrl';
            await _addHistory(entry);
            if (!mounted) return;
            setState(() => _status = 'Error al encolar');
            _showSnack('Error al encolar: ${e.toString()}', success: false);
          }
        } else if (choice == 'mark_sent') {
          // Marcar manualmente como enviado (no encolamos)
          final entry = '$timestamp — Enviado manualmente: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}\n$mapsUrl';
          await _addHistory(entry);
          if (!mounted) return;
          setState(() => _status = 'Marcado como enviado (manual)');
          _showSnack('Marcado como enviado', success: true);
        } else {
          // Si cerró el diálogo de forma inesperada, guardar PENDIENTE por seguridad
          final entry = '$timestamp — PENDIENTE (sin acción)\n$mapsUrl';
          await _addHistory(entry);
          if (!mounted) return;
          setState(() => _status = 'Pendiente');
          _showSnack('Guardado como pendiente', success: false);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Error: ${e.toString()}');
      _showSnack('Error: ${e.toString()}', success: false);

      // Intentar encolar por seguridad
      try {
        final timestamp = DateFormat("yyyy-MM-dd HH:mm:ss").format(DateTime.now());
        final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=0,0';
        final payload = {
          'name': _name,
          'latitude': 0,
          'longitude': 0,
          'timestamp': timestamp,
          'accuracy': 0,
          'maps_url': mapsUrl,
        };
        await QueueService.instance.init();
        final queueId = await QueueService.instance.add(payload);
        final entry = '$timestamp — PENDIENTE — queueId:$queueId\n$mapsUrl';
        await _addHistory(entry);
      } catch (_) {}
    } finally {
      if (!mounted) return;
      setState(() => _isSending = false);
    }
  }

  /// Versión adaptada de _sendViaWhatsApp que:
  /// - intenta notificar al backend sin encolar (enqueueOnFail: false)
  /// - abre WhatsApp
  /// - pide confirmación al usuario
  /// - marca como ENVIADO (o guarda historial) según la confirmación
  Future<void> _sendViaWhatsApp() async {
    if (_isPreparingWhatsApp) return;
    setState(() {
      _isPreparingWhatsApp = true;
      _status = 'Obteniendo ubicación...';
    });

    String? maybeQueueId;
    String mapsUrl = '';
    String timestamp = '';

    try {
      final pos = await LocationService.getCurrentPosition();
      timestamp = DateFormat("yyyy-MM-dd HH:mm:ss").format(DateTime.now());
      mapsUrl = 'https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}';

      final messageText = 'Registro de asistencia\n'
          'Nombre: $_name\n'
          'FechaHora: $timestamp\n'
          'Lat: ${pos.latitude}\n'
          'Lon: ${pos.longitude}\n'
          'Accuracy: ${pos.accuracy}\n'
          'Ver en mapa: $mapsUrl';

      final encoded = Uri.encodeComponent(messageText);
      final url = 'https://wa.me/?text=$encoded';
      final uri = Uri.parse(url);

      // Intentar notificar al backend, pero NO encolar si falla (enqueueOnFail: false)
      final payload = {
        'name': _name,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'timestamp': timestamp,
        'accuracy': pos.accuracy,
        'maps_url': mapsUrl,
      };

      final apiRes = await ApiService.sendLocation(payload, enqueueOnFail: false);
      print('[DEBUG] ApiService.sendLocation (WhatsApp) response: $apiRes');

      if (apiRes['queued'] == true && apiRes['queueId'] != null) {
        maybeQueueId = apiRes['queueId'] as String;
      }

      // Abrir WhatsApp
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Intentar esquema whatsapp:// en fallback (móvil)
        final waScheme = Uri.parse('whatsapp://send?text=$encoded');
        if (await canLaunchUrl(waScheme)) {
          await launchUrl(waScheme, mode: LaunchMode.externalApplication);
        } else {
          if (!mounted) return;
          setState(() => _status = 'No se puede abrir WhatsApp');
          _showSnack('No se puede abrir WhatsApp', success: false);
          return;
        }
      }

      // Pedir confirmación al usuario después de abrir WhatsApp
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmar envío'),
          content: const Text('¿Confirmas que enviaste el mensaje por WhatsApp?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Sí, enviado')),
          ],
        ),
      );

      if (confirmed == true) {
        // Si había un queueId (backend encoló algo), marcarlo como enviado
        if (maybeQueueId != null && maybeQueueId.isNotEmpty) {
          try {
            await QueueService.instance.markSent(maybeQueueId, removeFromQueue: true);
            // Actualizar historial: reemplazar la entrada PENDIENTE por ENVIADO si existe
            final pendingIndex = _history.indexWhere((h) => h.contains('queueId:$maybeQueueId'));
            final entry = '$timestamp — WhatsApp confirmado — Enviado: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}\n$mapsUrl';
            if (pendingIndex != -1) {
              _history[pendingIndex] = entry;
              await _saveHistoryList();
            } else {
              await _addHistory(entry);
            }
          } catch (e) {
            final entry = '$timestamp — WhatsApp confirmado — Enviado: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}\n$mapsUrl';
            await _addHistory(entry);
          }
        } else {
          // No hubo queueId: guardar historial ENVIADO
          final entry = '$timestamp — WhatsApp confirmado — Enviado: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}\n$mapsUrl';
          await _addHistory(entry);
        }

        if (!mounted) return;
        setState(() => _status = 'WhatsApp: confirmado enviado');
        _showSnack('Marcado como enviado', success: true);
      } else {
        // Usuario no confirmó: si la llamada al backend devolvió success==true, ya se guardó en backend.
        // Si no hubo queueId and not confirmed, guardamos PENDIENTE
        if (maybeQueueId != null && maybeQueueId.isNotEmpty) {
          final pendingIndex = _history.indexWhere((h) => h.contains('queueId:$maybeQueueId'));
          if (pendingIndex == -1) {
            final entry = '$timestamp — WhatsApp preparado — PENDIENTE — queueId:$maybeQueueId\n$mapsUrl';
            await _addHistory(entry);
          }
        } else {
          final entry = '$timestamp — WhatsApp preparado — PENDIENTE\n$mapsUrl';
          await _addHistory(entry);
        }

        if (!mounted) return;
        setState(() => _status = 'No confirmado');
        _showSnack('No marcado como enviado', success: false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Error: ${e.toString()}');
      _showSnack('Error: ${e.toString()}', success: false);
    } finally {
      if (!mounted) return;
      setState(() => _isPreparingWhatsApp = false);
    }
  }

  Future<void> _openMaps(String mapsUrl) async {
    final uri = Uri.tryParse(mapsUrl);
    if (uri == null) {
      _showSnack('URL de mapa inválida', success: false);
      return;
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showSnack('No se puede abrir el mapa', success: false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_name');
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/');
  }

  void _showSnack(String message, {required bool success}) {
    final color = success ? Colors.green : Colors.red;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, duration: const Duration(seconds: 2)),
    );
  }

  String? _lastSentTimestamp() {
    if (_history.isEmpty) return null;
    final first = _history.first;
    final lines = first.split('\n');
    if (lines.isEmpty) return null;
    final title = lines.first;
    final parts = title.split(' — ');
    return parts.isNotEmpty ? parts.first : null;
  }

  String? _extractMapsUrlFromEntry(String entry) {
    final lines = entry.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    for (final line in lines.reversed) {
      if (line.startsWith('http://') || line.startsWith('https://')) {
        return line;
      }
      final idx = line.indexOf('http');
      if (idx != -1) {
        final possible = line.substring(idx).trim();
        if (possible.startsWith('http://') || possible.startsWith('https://')) {
          return possible;
        }
      }
    }
    return null;
  }

  String? _extractQueueIdFromEntry(String entry) {
    final match = RegExp(r'queueId:([A-Za-z0-9_\-]+)').firstMatch(entry);
    return match != null ? match.group(1) : null;
  }

  @override
  Widget build(BuildContext context) {
    final userNameStyle = Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 22) ??
        const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87);

    final subtitleStyle = Theme.of(context).textTheme.bodySmall ??
        const TextStyle(fontSize: 13, color: Colors.black54);

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              color: Colors.blue.shade700,
              child: const Center(
                child: Icon(Icons.calendar_today, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
        title: const Text('Control de Asistencia PLANNER 2026'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Ajustes',
            onPressed: () async {
              await Navigator.pushNamed(context, '/settings');
              await _loadHistory();
              if (!mounted) return;
              setState(() {});
            },
          ),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSending ? null : _sendLocationToServer,
        icon: _isSending
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.send),
        label: Text(_isSending ? 'Enviando...' : 'Enviar'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.blue.shade700,
                      child: Text(
                        _name.isNotEmpty ? _name[0].toUpperCase() : 'U',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_name.isNotEmpty ? _name : 'Usuario no identificado', style: userNameStyle),
                          const SizedBox(height: 4),
                          Text('Último envío: ${_lastSentTimestamp() ?? '—'}', style: subtitleStyle),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_outlined),
                      tooltip: 'Copiar nombre',
                      onPressed: () {
                        if (_name.isNotEmpty) {
                          _showSnack('Nombre copiado al portapapeles', success: true);
                        } else {
                          _showSnack('No hay nombre para copiar', success: false);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: _isSending ? 0.9 : 1.0,
                            child: ElevatedButton.icon(
                              onPressed: _isSending ? null : _sendLocationToServer,
                              icon: _isSending
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.send),
                              label: Text(_isSending ? 'Enviando...' : 'Enviar al servidor'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: _isPreparingWhatsApp ? 0.9 : 1.0,
                            child: ElevatedButton.icon(
                              onPressed: _isPreparingWhatsApp ? null : _sendViaWhatsApp,
                              icon: _isPreparingWhatsApp
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.chat),
                              label: Text(_isPreparingWhatsApp ? 'Preparando...' : 'WhatsApp'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: Text('Estado: $_status', style: const TextStyle(fontStyle: FontStyle.italic))),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: const [
                Text('Historial local', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),

            Expanded(
              child: _history.isEmpty
                  ? const Center(child: Text('Sin registros'))
                  : ListView.builder(
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final item = _history[index];
                        final lines = item.split('\n');
                        final title = lines.isNotEmpty ? lines.first : item;
                        final subtitle = lines.length > 1 ? lines.sublist(1).join(' ') : '';
                        final mapsUrl = _extractMapsUrlFromEntry(item);

                        String? status;
                        if (item.contains('PENDIENTE')) status = 'PENDIENTE';
                        else if (item.contains('REINTENTANDO')) status = 'REINTENTANDO';
                        else if (item.contains('Error') || item.contains('Error al enviar') || item.contains('FALLIDO')) status = 'FALLIDO';
                        else status = 'ENVIADO';

                        return Dismissible(
                          key: Key(item + index.toString()),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          onDismissed: (direction) async {
                            _history.removeAt(index);
                            await _saveHistoryList();
                            if (!mounted) return;
                            setState(() {});
                            _showSnack('Entrada eliminada', success: true);
                          },
                          child: HistoryCard(
                            title: title,
                            subtitle: subtitle,
                            mapsUrl: mapsUrl,
                            status: status,
                            onDetails: () {
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Detalle'),
                                  content: Text(item),
                                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
                                ),
                              );
                            },
                            onDelete: () async {
                              _history.removeAt(index);
                              await _saveHistoryList();
                              if (!mounted) return;
                              setState(() {});
                              _showSnack('Entrada eliminada', success: true);
                            },
                            onRetry: () async {
                              final queueId = _extractQueueIdFromEntry(item);
                              if (queueId != null && queueId.isNotEmpty) {
                                await QueueService.instance.init();
                                await QueueService.instance.retryNow(queueId);
                                _showSnack('Reintento solicitado', success: true);
                                return;
                              }

                              try {
                                final latLonMatch = RegExp(r'(-?\d+\.\d+),\s*(-?\d+\.\d+)').firstMatch(item);
                                double? lat;
                                double? lon;
                                if (latLonMatch != null) {
                                  lat = double.tryParse(latLonMatch.group(1) ?? '');
                                  lon = double.tryParse(latLonMatch.group(2) ?? '');
                                }
                                final timestamp = DateFormat("yyyy-MM-dd HH:mm:ss").format(DateTime.now());
                                final maps = mapsUrl ?? 'https://www.google.com/maps';
                                final payload = {
                                  'name': _name,
                                  'latitude': lat ?? 0,
                                  'longitude': lon ?? 0,
                                  'timestamp': timestamp,
                                  'accuracy': 0,
                                  'maps_url': maps,
                                };

                                final res = await ApiService.sendLocation(payload);
                                if (res['success'] == true) {
                                  final newEntry = '$timestamp — Reenviado correctamente\n$maps';
                                  _history[index] = newEntry;
                                  await _saveHistoryList();
                                  if (!mounted) return;
                                  setState(() {});
                                  _showSnack('Reenviado correctamente', success: true);
                                } else if (res['queued'] == true && res['queueId'] != null) {
                                  final qid = res['queueId'] as String;
                                  final newEntry = '$timestamp — PENDIENTE — queueId:$qid\n$maps';
                                  _history[index] = newEntry;
                                  await _saveHistoryList();
                                  if (!mounted) return;
                                  setState(() {});
                                  _showSnack('Encolado para reintento', success: false);
                                } else {
                                  _showSnack('No se pudo reintentar', success: false);
                                }
                              } catch (e) {
                                _showSnack('No se pudo reintentar: ${e.toString()}', success: false);
                              }
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
