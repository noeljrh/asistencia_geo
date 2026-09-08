// lib/api/api_client.dart
import 'dart:io';
import 'package:dio/dio.dart';
import '../auth/auth_state.dart';
import '../src/http_utils.dart';

class ApiClient {
  final Dio dio;
  final AuthState authState;

  ApiClient(String baseUrl, this.authState)
      : dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(milliseconds: 30000),
          receiveTimeout: const Duration(milliseconds: 30000),
          responseType: ResponseType.json,
          headers: {'Content-Type': 'application/json'},
        )) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        print('[API] REQUEST ${options.method} ${options.uri}');
        handler.next(options);
      },
      onResponse: (response, handler) {
        print('[API] RESPONSE ${response.statusCode} ${response.requestOptions.uri}');
        handler.next(response);
      },
      onError: (err, handler) {
        print('[API] ERROR ${err.type} ${err.message}');
        handler.next(err);
      },
    ));
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final resp = await dio.post('/api/auth/login', data: {'email': email, 'password': password});
      print('[API][login] resp.data runtimeType: ${resp.data.runtimeType}');
      return parseResponseToMap(resp.data);
    } on DioException catch (e) {
      final msg = e.response?.data ?? e.message;
      throw Exception('Login failed: $msg');
    }
  }

  Future<Map<String, dynamic>> refresh() async {
    try {
      final resp = await dio.post('/api/auth/refresh');
      print('[API][refresh] resp.data runtimeType: ${resp.data.runtimeType}');
      return parseResponseToMap(resp.data);
    } on DioException catch (e) {
      final msg = e.response?.data ?? e.message;
      throw Exception('Refresh failed: $msg');
    }
  }

  Future<Map<String, dynamic>> getProtected({String? accessToken}) async {
    try {
      final resp = await dio.get('/api/protected',
          options: Options(headers: accessToken != null ? {'Authorization': 'Bearer $accessToken'} : null));
      print('[API][protected] resp.data runtimeType: ${resp.data.runtimeType}');
      return parseResponseToMap(resp.data);
    } on DioException catch (e) {
      final msg = e.response?.data ?? e.message;
      throw Exception('Protected failed: $msg');
    }
  }

  void setBaseUrl(String baseUrl) {
    dio.options.baseUrl = baseUrl;
    print('[API] baseUrl changed to $baseUrl');
  }
}
