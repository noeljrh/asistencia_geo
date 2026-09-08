import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService extends ChangeNotifier {
  AuthService._private();
  static final AuthService instance = AuthService._private();

  final _secure = const FlutterSecureStorage();
  String? _token;
  String? _userName;
  String _role = 'user';
  bool _initialized = false;

  bool get isAuthenticated => _token != null;
  String? get token => _token;
  String get role => _role;
  String? get userName => _userName;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _token = await _secure.read(key: 'auth_token');
    final prefs = await SharedPreferences.getInstance();
    _userName = prefs.getString('user_name');
    _role = prefs.getString('user_role') ?? 'user';
    notifyListeners();
  }

  // Login ficticio: acepta cualquier usuario/clave
  Future<Map<String, dynamic>> login(String username, String password) async {
    _token = 'fake-token';
    _role = username.toLowerCase() == 'admin' ? 'supervisor' : 'user';
    _userName = username;

    await _secure.write(key: 'auth_token', value: _token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _userName ?? '');
    await prefs.setString('user_role', _role);

    notifyListeners();
    return {'success': true};
  }

  Future<void> logout() async {
    _token = null;
    _userName = null;
    _role = 'user';
    await _secure.delete(key: 'auth_token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_name');
    await prefs.remove('user_role');
    notifyListeners();
  }
}

