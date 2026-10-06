// lib/screens/settings.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:asistencia_geo/services/auth_service.dart';
import '../services/api_service.dart';
import '../main.dart'; // necesario para MyApp.of(context)

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _useDark = false;
  bool _isExporting = false;
  bool _isClearing = false;
  String _userName = '';
  String _userRole = 'user';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadAuthInfo();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useDark = prefs.getBool('use_dark_theme') ?? false;
      _userName = prefs.getString('user_name') ?? '';
      _userRole = prefs.getString('user_role') ?? 'user';
    });
  }

  Future<void> _loadAuthInfo() async {
    await AuthService.instance.init();
    setState(() {
      _userRole = AuthService.instance.role;
      _userName = AuthService.instance.userName ?? _userName;
    });
  }

  Future<void> _toggleDark(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_dark_theme', value);
    setState(() => _useDark = value);

    // Llamada segura al método público de MyApp para aplicar el tema en caliente
    try {
      final appState = MyApp.of(context);
      if (appState != null) appState.setDark(value);
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preferencia guardada')));
  }

  String _sanitizeFileName(String input) {
    final sanitized = input.replaceAll(RegExp(r'[^\w\-]'), '_');
    return sanitized.length > 40 ? sanitized.substring(0, 40) : sanitized;
  }

  Future<void> _exportHistoryCsv() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList('history') ?? [];
      final userName = (prefs.getString('user_name') ?? '').trim();

      if (history.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay registros para exportar')));
        setState(() => _isExporting = false);
        return;
      }

      final csvBuffer = StringBuffer();
      csvBuffer.writeln('timestamp;type;details;maps_url');

      for (final entry in history) {
        final lines = entry.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        String timestamp = '';
        String type = '';
        String details = '';
        String mapsUrl = '';

        if (lines.isNotEmpty) {
          final first = lines.first;
          final parts = first.split(' — ');
          timestamp = parts.isNotEmpty ? parts.first.trim() : '';
          if (parts.length > 1) {
            type = parts[1].trim();
          } else {
            type = 'registro';
          }
        }

        if (lines.length > 1) {
          final last = lines.last;
          if (last.startsWith('http')) {
            mapsUrl = last;
            if (lines.length > 2) {
              details = lines.sublist(1, lines.length - 1).join(' | ');
            }
          } else {
            details = lines.sublist(1).join(' | ');
          }
        }

        String esc(String s) => s.replaceAll(';', ',').replaceAll('\n', ' ').trim();

        csvBuffer.writeln('${esc(timestamp)};${esc(type)};${esc(details)};${esc(mapsUrl)}');
      }

      String downloadsPath;
      if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'] ?? '';
        downloadsPath = userProfile.isNotEmpty ? '$userProfile\\Downloads' : Directory.current.path;
      } else if (Platform.isLinux || Platform.isMacOS) {
        final home = Platform.environment['HOME'] ?? Directory.current.path;
        downloadsPath = '$home/Downloads';
      } else {
        downloadsPath = Directory.current.path;
      }

      final timestampFile = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final safeName = userName.isNotEmpty ? _sanitizeFileName(userName) : 'usuario';
      final fileName = 'asistencia_${safeName}_$timestampFile.csv';
      final filePath = '$downloadsPath${Platform.pathSeparator}$fileName';

      final file = File(filePath);
      await file.writeAsString(csvBuffer.toString(), flush: true);

      try {
        if (Platform.isWindows) {
          await Process.run('explorer', ['/select,', filePath]);
        } else if (Platform.isMacOS) {
          await Process.run('open', ['-R', filePath]);
        } else if (Platform.isLinux) {
          await Process.run('xdg-open', [downloadsPath]);
        }
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exportado: $fileName')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error exportando CSV: ${e.toString()}')));
    } finally {
      if (!mounted) return;
      setState(() => _isExporting = false);
    }
  }

  Future<void> _clearHistory() async {
    if (_isClearing) return;
    setState(() => _isClearing = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('history');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Historial borrado')));

    setState(() => _isClearing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Tema oscuro (preferencia local)'),
              value: _useDark,
              onChanged: _toggleDark,
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(_userName.isNotEmpty ? _userName : 'Usuario'),
              subtitle: Text('Rol: $_userRole'),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Versión'),
              subtitle: const Text('1.0.0'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isExporting
                        ? null
                        : () async {
                            await AuthService.instance.init();
                            final role = AuthService.instance.role;
                            if (role != 'supervisor') {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text('Solo supervisores pueden exportar el historial'),
                                backgroundColor: Colors.red,
                              ));
                              return;
                            }
                            await _exportHistoryCsv();
                          },
                    icon: _isExporting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.download),
                    label: Text(_isExporting ? 'Exportando...' : 'Exportar historial a CSV'),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isClearing
                      ? null
                      : () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Confirmar'),
                              content: const Text('¿Borrar todo el historial local?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Borrar')),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await _clearHistory();
                          }
                        },
                  icon: _isClearing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.delete_forever),
                  label: const Text('Borrar historial'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Toggle rápido para modo fake (útil en pruebas)
            ElevatedButton(
              onPressed: () async {
                final current = ApiService.useFake;
                await ApiService.setFakeMode(!current);
                final msg = !current ? 'Modo fake activado' : 'Modo fake desactivado';
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                setState(() {});
              },
              child: Text(ApiService.useFake ? 'Desactivar modo fake (pruebas)' : 'Activar modo fake (pruebas)'),
            ),
          ],
        ),
      ),
    );
  }
}

