import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class TryOnImageService {
  final String apiBaseUrl;

  TryOnImageService({required this.apiBaseUrl});

  Uri _endpoint(String path) {
    final base = apiBaseUrl.trim();
    if (base.isEmpty) {
      throw Exception('Chưa cấu hình endpoint thử ảnh (TRYON_API_URL).');
    }

    return Uri.parse('${base.replaceFirst(RegExp(r'/+$'), '')}$path');
  }

  Future<Map<String, dynamic>> _postJson({
    required String path,
    required Map<String, dynamic> body,
    required Duration timeout,
  }) async {
    late final http.Response response;
    try {
      response = await http
          .post(
            _endpoint(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on SocketException catch (e) {
      throw Exception('Không kết nối được backend thử ảnh: $e');
    }

    if (response.statusCode != 200) {
      var detail = response.body;
      if (detail.length > 300) detail = '${detail.substring(0, 300)}...';
      throw Exception('Backend lỗi HTTP ${response.statusCode}: $detail');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Backend trả về JSON không đúng cấu trúc object.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> analyzeFace({
    required File image,
    required List<Map<String, dynamic>> catalog,
  }) async {
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Ảnh mặt khách rỗng hoặc không đọc được.');
    }

    return _postJson(
      path: '/api/tryon/analyze',
      body: {
        'image_base64': base64Encode(bytes),
        'catalog': catalog,
      },
      timeout: const Duration(seconds: 60),
    );
  }

  Future<Uint8List> generatePreview({
    required File image,
    required String category,
    required String prompt,
  }) async {
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Ảnh mặt khách rỗng hoặc không đọc được.');
    }

    final data = await _postJson(
      path: '/api/tryon/generate',
      body: {
        'image_base64': base64Encode(bytes),
        'category': category,
        'prompt': prompt,
      },
      timeout: const Duration(seconds: 90),
    );

    final result = data['result_base64'];
    if (result is! String || result.isEmpty) {
      throw Exception('Backend không trả về ảnh.');
    }

    try {
      return base64Decode(result);
    } on FormatException catch (e) {
      throw Exception('Ảnh backend trả về không hợp lệ: $e');
    }
  }
}
