import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'image_preprocessor.dart';

class FaceAnalysis {
  const FaceAnalysis({
    required this.faceDetected,
    this.faceShape = '',
    this.skinTone = '',
    this.observations = '',
    this.recommendedItemId,
    this.consultationNote = '',
  });

  final bool faceDetected;
  final String faceShape;
  final String skinTone;
  final String observations;
  final String? recommendedItemId;
  final String consultationNote;

  factory FaceAnalysis.fromJson(Map<String, dynamic> j) => FaceAnalysis(
        faceDetected: j['face_detected'] == true,
        faceShape: (j['face_shape'] ?? '').toString(),
        skinTone: (j['skin_tone'] ?? '').toString(),
        observations: (j['observations'] ?? '').toString(),
        recommendedItemId: j['recommended_item_id']?.toString(),
        consultationNote: (j['consultation_note'] ??
                j['consultation_script'] ??
                '')
            .toString(),
      );
}

class TryOnImageService {
  static const String _supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ihufvqrxdswgbagzhydb.supabase.co',
  );

  const TryOnImageService({this.authToken = ''});

  final String authToken;

  /// Chuẩn hóa ảnh trên máy, rồi gọi Edge Function tryon-analyze bằng JWT người dùng.
  Future<FaceAnalysis> analyzeFace(File image) async {
    final baseSupabaseUrl = _supabaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final url = Uri.parse('$baseSupabaseUrl/functions/v1/tryon-analyze');

    final bytes = await ImagePreprocessor.prepare(image);
    if (bytes.isEmpty) {
      throw const ApiException(0, 'Ảnh mặt khách rỗng hoặc không đọc được.');
    }

    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = authToken.trim();
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    late final http.Response response;
    try {
      response = await http
          .post(
            url,
            headers: headers,
            body: jsonEncode({'image_base64': base64Encode(bytes)}),
          )
          .timeout(const Duration(seconds: 30));
    } on SocketException {
      throw const SocketException('analyze_network_unreachable');
    }

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Phân tích ảnh thất bại.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Phản hồi phân tích không hợp lệ.');
    }

    final map = Map<String, dynamic>.from(decoded);
    if (map['analysis'] is Map) {
      return FaceAnalysis.fromJson(
        Map<String, dynamic>.from(map['analysis'] as Map),
      );
    }
    return FaceAnalysis.fromJson(map);
  }
}
