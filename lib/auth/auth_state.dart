// lib/auth/auth_state.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:asistencia_geo/services/auth_service.dart';

/// Adaptador ligero que expone la interfaz mínima que ApiClient y UI esperan.
/// Delegará en AuthService.instance para obtener token, estado y notificar cambios.
class AuthState extends ChangeNotifier {
  AuthState._private();
  static final AuthState instance = AuthState._private();

  final AuthService _service = AuthService.instance;
  final _secure = const FlutterSecureStorage();

  /// Inicializa delegando en AuthService
  Future<void> init() async {
    await _service.init();
    // Reemite notificaciones de AuthService
    _service.addListener(() => notifyListeners());
  }

  /// Token en memoria (puede ser null)
  String? get token => _service.token;

  /// Indica si hay sesión activa
  bool get isAuthenticated => _service.isAuthenticated;

  /// Exponer nombre/rol si lo necesitas
  String? get userName => _service.userName;
  String get role => _service.role;

  /// Métodos de conveniencia que delegan
  Future<void> setToken(String? token) => _service.setToken(token);
  Future<void> setUser({String? name, String? role}) => _service.setUser(name: name, role: role);
  Future<void> clear() => _service.clear();
}

