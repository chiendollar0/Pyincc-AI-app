import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/errors/api_exception.dart';

export '../core/errors/api_exception.dart';

class ApiClient {
  final String baseUrl;
  final String authToken;
  final String Function()? tokenProvider;
  final Future<String?> Function()? onUnauthorized;

  const ApiClient({
    required this.baseUrl,
    this.authToken = '',
    this.tokenProvider,
    this.onUnauthorized,
  });

  Uri _uri(String path) {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      throw const ApiException(0, 'Chưa cấu hình địa chỉ máy chủ.');
    }
    return Uri.parse('$base$path');
  }

  String _currentToken() => (tokenProvider?.call() ?? authToken).trim();

  Map<String, String> _headers({bool json = false, String? tokenOverride}) {
    final headers = <String, String>{};
    if (json) {
      headers['Content-Type'] = 'application/json';
    }
    final token = (tokenOverride ?? _currentToken()).trim();
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<Map<String, dynamic>> _sendWithAutoRefresh(
    Future<http.Response> Function(String? tokenOverride) send,
  ) async {
    http.Response response;
    try {
      response = await send(null);
    } on SocketException {
      throw const SocketException('network_unreachable');
    }

    if (response.statusCode == 401 && onUnauthorized != null) {
      final refreshed = await onUnauthorized!();
      if (refreshed != null && refreshed.trim().isNotEmpty) {
        try {
          response = await send(refreshed.trim());
        } on SocketException {
          throw const SocketException('network_unreachable');
        }
      }
    }
    return _decodeObjectResponse(response);
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Duration timeout = const Duration(seconds: 15),
  }) =>
      _sendWithAutoRefresh(
        (token) => http
            .get(_uri(path), headers: _headers(tokenOverride: token))
            .timeout(timeout),
      );

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 20),
  }) =>
      _sendWithAutoRefresh(
        (token) => http
            .post(
              _uri(path),
              headers: _headers(json: true, tokenOverride: token),
              body: jsonEncode(body),
            )
            .timeout(timeout),
      );

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 15),
  }) =>
      _sendWithAutoRefresh(
        (token) => http
            .put(
              _uri(path),
              headers: _headers(json: true, tokenOverride: token),
              body: jsonEncode(body),
            )
            .timeout(timeout),
      );

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 15),
  }) =>
      _sendWithAutoRefresh(
        (token) => http
            .patch(
              _uri(path),
              headers: _headers(json: true, tokenOverride: token),
              body: jsonEncode(body),
            )
            .timeout(timeout),
      );

  Future<Map<String, dynamic>> delete(
    String path, {
    Duration timeout = const Duration(seconds: 15),
  }) =>
      _sendWithAutoRefresh(
        (token) => http
            .delete(_uri(path), headers: _headers(tokenOverride: token))
            .timeout(timeout),
      );

  Map<String, dynamic> _decodeObjectResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String serverCode = 'Yêu cầu chưa thành công.';
      String? serverCaseId;
      try {
        final parsed = jsonDecode(response.body);
        if (parsed is Map<String, dynamic>) {
          if (parsed['error'] is String) {
            serverCode = (parsed['error'] as String).trim();
          }
          if (parsed['case_id'] is String &&
              (parsed['case_id'] as String).trim().isNotEmpty) {
            serverCaseId = (parsed['case_id'] as String).trim();
          }
        }
      } catch (_) {
        // Giữ thông báo mặc định nếu phản hồi không phải JSON
      }
      throw ApiException(response.statusCode, serverCode, caseId: serverCaseId);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException(0, 'Dữ liệu phản hồi không đúng định dạng.');
    }
    return decoded;
  }
}
