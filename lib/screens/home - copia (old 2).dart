// lib/screens/home.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/location_service.dart';
import '../services/api_service.dart';
import '../services/queue_service.dart';
import '../services/auth_service.dart';
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
    setState(() => _name = prefs.getString('user_name') ?? AuthService.instance.userName);
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

  Future<Map<String, dynamic>> _buildPayloadWithUserId({
    required String name,
    required double latitude,
    required double longitude,
    required String timestamp,
    required double accuracy,
    required String mapsUrl,
  }) async {
    // Preferir AuthService.instance.userId si está disponible
    int? uid = AuthService.instance.userId;
    if (uid == null) {
      final prefs = await SharedPreferences.getInstance();
      uid = prefs.getInt('user_id');
    }

    final payload = {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp,
      'accuracy': accuracy,
      'maps_url': mapsUrl,
    };

    // Añadir user_id en formatos comunes que el backend podría esperar
    if (uid != null) {
      payload['user_id'] = uid;
      payload['userId'] = uid;
    }

    return payload;
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

      final payload = await _buildPayloadWithUserId(
        name: _name,
        latitude: pos.latitude,
        longitude: pos.longitude,
        timestamp: timestamp,
        accuracy: pos.accuracy,
        mapsUrl: mapsUrl,
      );

      setState(() => _status = 'Enviando al servidor...');
      final res = await ApiService.sendLocation(payload);

      // DEBUG log para verificar la respuesta exacta
      debugPrint('[DEBUG] ApiService.sendLocation response: $res');

      // Si backend aceptó (2xx)
      if (res['success'] == true) {
        final entry = '$timestamp — Enviado: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}\n$mapsUrl';
        await _addHistory(entry);
        if (!mounted) return;
        setState(() => _status = 'Enviado correctamente');
        _showSnack('Enviado correctamente', success: true);
        return;
      }

      // Manejo específico: si 401 por token inválido/expirado -> encolar para reintento
      final int statusCode = res['statusCode'] is int ? res['statusCode'] as int : -1;
      final String message = (res['message'] ?? res['body'] ?? '').toString();

      if (statusCode == 401 && message.toLowerCase().contains('token')) {
        await QueueService.instance.init();
        final queueId = await QueueService.instance.add(payload);
        final entry = '$timestamp — PENDIENTE — queueId:$queueId\n$mapsUrl';
        await _addHistory(entry);
        if (!mounted) return;
        setState(() => _status = 'Encolado por token inválido');
        _showSnack('Encolado para reintento (token inválido)', success: false);
        return;
      }

      // Si ApiService devolvió queued info directamente
      if (res['queued'] == true && res['queueId'] != null) {
        final queueId = res['queueId'] as String;
        final entry = '$timestamp — PENDIENTE — queueId:$queueId\n$mapsUrl';
        await _addHistory(entry);
        if (!mounted) return;
        setState(() => _status = 'Encolado para reintento');
        _showSnack('Encolado para reintento', success: false);
        return;
      }

      // Caso general de error: mostrar y guardar en historial
      final err = res['error'] ?? res['message'] ?? 'Código ${res['statusCode'] ?? 'N/A'}';
      final entry = '$timestamp — Error al enviar: $err\n$mapsUrl';
      await _addHistory(entry);
      if (!mounted) return;
      setState(() => _status = 'Error al enviar: $err');
      _showSnack('Error al enviar: $err', success: false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Error: ${e.toString()}');
      _showSnack('Error: ${e.toString()}', success: false);

      try {
        final timestamp = DateFormat("yyyy-MM-dd HH:mm:ss").format(DateTime.now());
        final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=0,0';
        final payload = await _buildPayloadWithUserId(
          name: _name,
          latitude: 0,
          longitude: 0,
          timestamp: timestamp,
          accuracy: 0,
          mapsUrl: mapsUrl,
        );
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

  Future<void> _sendViaWhatsApp() async {
    if (_isPreparingWhatsApp) return;
    setState(() {
      _isPreparingWhatsApp = true;
      _status = 'Obteniendo ubicación...';
    });

    try {
      final pos = await LocationService.getCurrentPosition();
      final timestamp = DateFormat("yyyy-MM-dd HH:mm:ss").format(DateTime.now());
      final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}';

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

      // Prepare payload and add to queue first so we have a queueId to correlate
      final payload = await _buildPayloadWithUserId(
        name: _name,
        latitude: pos.latitude,
        longitude: pos.longitude,
        timestamp: timestamp,
        accuracy: pos.accuracy,
        mapsUrl: mapsUrl,
      );

      await QueueService.instance.init();
      final queueId = await QueueService.instance.add(payload);
      debugPrint('[Home] WhatsApp flow created queueId=$queueId payloadKeys=${payload.keys.toList()}');

      if (await canLaunchUrl(uri)) {
        // Open WhatsApp (external)
        await launchUrl(uri);

        // Consider WhatsApp "opened" as success for the user flow: notify the queue
        final whatsappRes = {'success': true, 'statusCode': 200};
        try {
          await QueueService.instance.notifyWhatsAppResult(queueId, whatsappRes);
          debugPrint('[Home] notifyWhatsAppResult called for queueId=$queueId whatsappOk=true');
        } catch (e) {
          debugPrint('[Home] notifyWhatsAppResult exception: $e');
        }

        // Fire-and-forget: still attempt to register on backend, but do not block UX
        ApiService.sendLocation(payload).then((res) async {
          debugPrint('[Home] background ApiService.sendLocation (after WhatsApp) response: $res');

          final int statusCode = res['statusCode'] is int ? res['statusCode'] as int : -1;
          final String message = (res['message'] ?? res['body'] ?? '').toString();

          // Si backend aceptó, nada más que hacer
          if (res['success'] == true) {
            debugPrint('[Home] background send: backend accepted');
            return;
          }

          // Si 401 por token inválido/expirado -> encolar
          if (statusCode == 401 && message.toLowerCase().contains('token')) {
            try {
              await QueueService.instance.init();
              final qid = await QueueService.instance.add(payload);
              debugPrint('[Home] background send: enqueued due to token issue queueId=$qid');
            } catch (e) {
              debugPrint('[Home] background send: failed to enqueue after 401: $e');
            }
            return;
          }

          // Si ApiService devolvió queued info directamente
          if (res['queued'] == true && res['queueId'] != null) {
            debugPrint('[Home] background send: backend returned queued info queueId=${res['queueId']}');
            return;
          }

          // Otros errores: loguear
          debugPrint('[Home] background send: other error status=$statusCode body=${res['body']}');
        }).catchError((e) {
          debugPrint('[Home] background ApiService.sendLocation exception: $e');
        });

        // Update local history as WhatsApp prepared and considered sent
        final entry = '$timestamp — WhatsApp preparado — Enviado: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}\n$mapsUrl';
        await _addHistory(entry);

        if (!mounted) return;
        setState(() => _status = 'WhatsApp abierto');
        _showSnack('WhatsApp abierto', success: true);
      } else {
        // Could not open WhatsApp: remove the queue item (or keep it, depending on policy).
        await QueueService.instance.removeById(queueId);
        if (!mounted) return;
        setState(() => _status = 'No se puede abrir WhatsApp');
        _showSnack('No se puede abrir WhatsApp', success: false);
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
                                final payload = await _buildPayloadWithUserId(
                                  name: _name,
                                  latitude: lat ?? 0,
                                  longitude: lon ?? 0,
                                  timestamp: timestamp,
                                  accuracy: 0,
                                  mapsUrl: maps,
                                );

                                final res = await ApiService.sendLocation(payload);

                                if (res['success'] == true) {
                                  final newEntry = '$timestamp — Reenviado correctamente\n$maps';
                                  _history[index] = newEntry;
                                  await _saveHistoryList();
                                  if (!mounted) return;
                                  setState(() {});
                                  _showSnack('Reenviado correctamente', success: true);
                                  return;
                                }

                                final int statusCode = res['statusCode'] is int ? res['statusCode'] as int : -1;
                                final String message = (res['message'] ?? res['body'] ?? '').toString();

                                if (statusCode == 401 && message.toLowerCase().contains('token')) {
                                  // Encolar para reintento automático
                                  await QueueService.instance.init();
                                  final qid = await QueueService.instance.add(payload);
                                  final newEntry = '$timestamp — PENDIENTE — queueId:$qid\n$maps';
                                  _history[index] = newEntry;
                                  await _saveHistoryList();
                                  if (!mounted) return;
                                  setState(() {});
                                  _showSnack('Encolado para reintento (token inválido)', success: false);
                                  return;
                                }

                                if (res['queued'] == true && res['queueId'] != null) {
                                  final qid = res['queueId'] as String;
                                  final newEntry = '$timestamp — PENDIENTE — queueId:$qid\n$maps';
                                  _history[index] = newEntry;
                                  await _saveHistoryList();
                                  if (!mounted) return;
                                  setState(() {});
                                  _showSnack('Encolado para reintento', success: false);
                                  return;
                                }

                                _showSnack('No se pudo reintentar', success: false);
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
