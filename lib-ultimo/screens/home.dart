// lib/screens/home.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/queue_service.dart';
import '../services/location_service.dart'; // si no existe, elimina esta línea

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _name = '';
  String _status = '';
  List<String> _history = [];
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadName();
    _loadHistory();
  }

  Future<void> _loadName() async {
    final svcName = AuthService.instance.userName;
    if (svcName.isNotEmpty) {
      setState(() => _name = svcName);
      return;
    }
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
      final res = await ApiService.sendLocation(payload, enqueueOnFail: false);

      if (res['success'] == true) {
        final entry = '$timestamp — Enviado: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}\n$mapsUrl';
        await _addHistory(entry);
        if (!mounted) return;
        setState(() => _status = 'Enviado correctamente');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enviado correctamente')));
        return;
      }

      // Si falla o 401, encolar como fallback
      await QueueService.instance.init();
      final qid = await QueueService.instance.add(payload);
      final entry = '$timestamp — PENDIENTE — queueId:$qid\n$mapsUrl';
      await _addHistory(entry);
      if (!mounted) return;
      setState(() => _status = 'Encolado para reintento');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Encolado para reintento')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Error: ${e.toString()}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    } finally {
      if (!mounted) return;
      setState(() => _isSending = false);
    }
  }

  Future<void> _logout() async {
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    final userNameDisplay = _name.isNotEmpty ? _name : 'Usuario';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Control de Asistencia PLANNER 2026'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(userNameDisplay.isNotEmpty ? userNameDisplay[0].toUpperCase() : 'U')),
                title: Text(userNameDisplay),
                subtitle: Text('Estado: $_status'),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _history.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.history, size: 48, color: Colors.black26),
                          SizedBox(height: 8),
                          Text('No hay registros aún. Pulsa Enviar para crear uno.'),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final item = _history[index];
                        final title = item.split('\n').first;
                        final subtitle = item.split('\n').skip(1).join(' ');
                        return ListTile(title: Text(title), subtitle: Text(subtitle));
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

