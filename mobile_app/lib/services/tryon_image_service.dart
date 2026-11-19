import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_client.dart';

class TryOnImageService {
  final String apiBaseUrl;
  final String authToken;

  TryOnImageService({
    required this.apiBaseUrl,
    this.authToken = const String.fromEnvironment(
      'BACKEND_AUTH_TOKEN',
      defaultValue: '',
    ),
  });

  ApiClient get _api => ApiClient(
        baseUrl: apiBaseUrl,
        authToken: authToken,
      );

  Map<String, String> _jsonHeaders() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = authToken.trim();
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<Map<String, dynamic>> analyzeFace({
    required File image,
    required List<Map<String, dynamic>> catalog,
  }) async {
    final url = Uri.parse(
      'https://ihufvqrxdswgbagzhydb.supabase.co/functions/v1/tryon-analyze',
    );

    final bytes = await image.readAsBytes();
    if (bytes.isEmpty) {
      throw const ApiException(0, 'Ảnh mặt khách rỗng hoặc không đọc được.');
    }

    late final http.Response response;
    try {
      response = await http
          .post(
            url,
            headers: _jsonHeaders(),
            body: jsonEncode({
              'image_base64': base64Encode(bytes),
              'catalog': catalog,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } on SocketException {
      throw const SocketException('analyze_network_unreachable');
    }

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Chưa thể phân tích khuôn mặt.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['analysis'] is! Map) {
      throw const ApiException(0, 'Dữ liệu phân tích không đúng định dạng.');
    }

    return Map<String, dynamic>.from(decoded['analysis'] as Map);
  }

  Future<Uint8List> generatePreview({
    required File image,
    required String category,
    required String prompt,
  }) async {
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty) {
      throw const ApiException(0, 'Ảnh mặt khách rỗng hoặc không đọc được.');
    }

    final data = await _api.post(
      '/api/tryon/generate',
      {
        'image_base64': base64Encode(bytes),
        'category': category,
        'prompt': prompt,
      },
      timeout: const Duration(seconds: 90),
    );

    final result = data['result_base64'];
    if (result is! String || result.isEmpty) {
      throw const ApiException(0, 'Chưa nhận được ảnh mô phỏng từ máy chủ.');
    }

    try {
      return base64Decode(result);
    } on FormatException {
      throw const ApiException(0, 'Ảnh mô phỏng trả về không hợp lệ.');
    }
  }

  Future<Map<String, dynamic>> sendApprovedPreview({
    required Uint8List imageBytes,
    required String recipientId,
    required String caption,
  }) async {
    if (imageBytes.isEmpty) {
      throw const ApiException(0, 'Chưa có ảnh mô phỏng AI để gửi.');
    }

    final draftRes = await _api.post(
      '/tryon-drafts',
      {
        'recipientId': recipientId.trim(),
        'imageBase64': base64Encode(imageBytes),
        'caption': caption.trim(),
      },
      timeout: const Duration(seconds: 30),
    );

    final media = draftRes['media'];
    final mediaRecordId =
        media is Map<String, dynamic> ? (media['id'] ?? '').toString() : '';
    if (mediaRecordId.isEmpty) {
      throw const ApiException(0, 'Chưa lưu được bản ghi duyệt ảnh.');
    }

    return _api.post(
      '/send-tryon-image',
      {'mediaRecordId': mediaRecordId},
      timeout: const Duration(seconds: 30),
    );
  }
}
