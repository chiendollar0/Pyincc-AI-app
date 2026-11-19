import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int status;
  final String message;

  const ApiException(this.status, this.message);

  @override
  String toString() => message;
}

class ApiClient {
  final String baseUrl;
  final String authToken;

  const ApiClient({
    required this.baseUrl,
    this.authToken = '',
  });

  Uri _uri(String path) {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      throw const ApiException(0, 'Chưa cấu hình địa chỉ máy chủ.');
    }
    return Uri.parse('$base$path');
  }

  Map<String, String> _headers({bool json = false}) {
    final headers = <String, String>{};
    if (json) {
      headers['Content-Type'] = 'application/json';
    }
    final token = authToken.trim();
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    late final http.Response response;
    try {
      response = await http
          .get(_uri(path), headers: _headers())
          .timeout(timeout);
    } on SocketException {
      throw const SocketException('network_unreachable');
    }
    return _decodeObjectResponse(response);
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    late final http.Response response;
    try {
      response = await http
          .post(
            _uri(path),
            headers: _headers(json: true),
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on SocketException {
      throw const SocketException('network_unreachable');
    }
    return _decodeObjectResponse(response);
  }

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    late final http.Response response;
    try {
      response = await http
          .put(
            _uri(path),
            headers: _headers(json: true),
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on SocketException {
      throw const SocketException('network_unreachable');
    }
    return _decodeObjectResponse(response);
  }

  Map<String, dynamic> _decodeObjectResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Yêu cầu chưa thành công.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException(0, 'Dữ liệu phản hồi không đúng định dạng.');
    }
    return decoded;
  }
}
