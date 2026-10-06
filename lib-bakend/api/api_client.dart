// lib/api/api_client.dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../auth/auth_state.dart';

class ApiClient {
  final Dio dio;
  final AuthState authState;
  final _secure = const FlutterSecureStorage();

  /// Último set-cookie recibido del servidor (cadena completa)
  String? lastSetCookie;

  ApiClient(String baseUrl, this.authState)
      : dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        )) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        debugPrint('[API][onRequest] ${options.method} ${options.path} beforeHeaders=${options.headers}');
        try {
          // Preferir token en memoria
          String? token = authState.token;

          // Fallback a secure storage
          if (token == null || token.isEmpty) {
            try {
              token = await _secure.read(key: 'auth_token');
              debugPrint('[API][onRequest] token read from secure storage: ${token != null}');
            } catch (e) {
              debugPrint('[API][onRequest] secure storage read error: $e');
            }
          } else {
            debugPrint('[API][onRequest] token read from authState');
          }

          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          } else if (lastSetCookie != null && lastSetCookie!.isNotEmpty) {
            // Si no hay token, pero tenemos cookie recibida previamente, enviarla
            options.headers['cookie'] = lastSetCookie;
            debugPrint('[API][onRequest] sending cookie header from lastSetCookie');
          }
        } catch (e) {
          debugPrint('[API][onRequest] token/cookie read error: $e');
        }
        debugPrint('[API][onRequest] ${options.method} ${options.path} afterHeaders=${options.headers}');
        handler.next(options);
      },
      onResponse: (response, handler) {
        final ct = response.headers.value('content-type') ?? '';
        debugPrint('[API][onResponse] ${response.requestOptions.method} ${response.requestOptions.path} status=${response.statusCode} content-type=$ct');
        // Capturar set-cookie si viene en la respuesta
        try {
          final sc = response.headers.map['set-cookie'];
          if (sc != null && sc.isNotEmpty) {
            // Unir múltiples cookies en una sola cadena separada por '; '
            lastSetCookie = sc.join('; ');
            debugPrint('[API][onResponse] captured set-cookie: ${lastSetCookie!.substring(0, lastSetCookie!.length.clamp(0,120))}');
          }
        } catch (e) {
          debugPrint('[API][onResponse] error reading set-cookie: $e');
        }

        if (ct.toLowerCase().contains('html')) {
          handler.reject(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              error: 'Server returned HTML instead of JSON',
            ),
          );
          return;
        }
        handler.next(response);
      },
      onError: (err, handler) {
        debugPrint('[API][onError] ${err.requestOptions.method} ${err.requestOptions.path} error=${err.error} status=${err.response?.statusCode}');
        handler.next(err);
      },
    ));
  }

  /// Conveniencia: login. Ajusta la ruta/data si tu backend usa otros nombres.
  Future<Response> login(String email, String password) {
    return dio.post('/api/auth/login', data: {'email': email, 'password': password});
  }

  /// Conveniencia: endpoint refresh que intercambia cookie por access token
  Future<Response> refreshWithCookie({String? cookieHeader}) {
    final headers = <String, String>{'Accept': 'application/json'};
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      headers['cookie'] = cookieHeader;
    } else if (lastSetCookie != null && lastSetCookie!.isNotEmpty) {
      headers['cookie'] = lastSetCookie!;
    }
    return dio.get('/api/auth/refresh', options: Options(headers: headers));
  }
}
