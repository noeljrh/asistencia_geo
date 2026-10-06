// lib/widgets/name_entry_dialog.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/auth_service.dart';

class NameEntryDialog extends StatefulWidget {
  const NameEntryDialog({Key? key}) : super(key: key);

  @override
  State<NameEntryDialog> createState() => _NameEntryDialogState();
}

class _NameEntryDialogState extends State<NameEntryDialog> {
  final _nameCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name') ?? '';
    _nameCtrl.text = name;
  }

  Future<void> _onSave() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Ingresa un nombre vÃ¡lido');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // Guardar en SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', name);

      // Actualizar AuthService (si usas login ficticio)
      try {
        await AuthService.instance.init();
        // Si AuthService tiene mÃ©todo para guardar role/username, Ãºsalo:
        // AquÃ­ usamos login ficticio con nombre y contraseÃ±a vacÃ­a para asignar role
        await AuthService.instance.login(name, '');
      } catch (_) {}

      if (!mounted) return;
      Navigator.of(context).pop(name);
    } catch (e) {
      setState(() => _error = 'No se pudo guardar: ${e.toString()}');
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ingrese su nombre'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Nombre completo'),
            textCapitalization: TextCapitalization.words,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _onSave,
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Guardar'),
        ),
      ],
    );
  }
}

