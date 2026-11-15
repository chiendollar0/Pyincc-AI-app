import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

class TryOnImageService {
  final String geminiApiKey;
  final String? imageGenApiUrl;
  final String? imageGenApiKey;

  TryOnImageService({
    required this.geminiApiKey,
    this.imageGenApiUrl,
    this.imageGenApiKey,
  });

  /// Bước 1: Gemini phân tích khuôn mặt và gợi ý mẫu trong catalog.
  Future<Map<String, dynamic>> analyzeFaceAndSuggestCatalog({
    required File customerFaceImage,
    required List<Map<String, dynamic>> shopCatalog,
  }) async {
    if (geminiApiKey.trim().isEmpty) {
      throw Exception('Chưa cấu hình Gemini API key.');
    }
    if (shopCatalog.isEmpty) {
      throw Exception('Catalog rỗng — không thể gợi ý mẫu.');
    }

    final model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: geminiApiKey,
      generationConfig: GenerationConfig(responseMimeType: 'application/json'),
    );

    final imageBytes = await customerFaceImage.readAsBytes();
    if (imageBytes.isEmpty) {
      throw Exception('Ảnh mặt khách rỗng hoặc không đọc được.');
    }

    final catalogJson = jsonEncode(shopCatalog);

    final prompt = '''
Bạn là chuyên gia thẩm mỹ phun xăm. Quan sát ảnh mặt mộc của khách và đối chiếu với catalog: $catalogJson.
Trả về JSON đúng cấu trúc:
{
  "face_shape": "dáng mặt",
  "skin_tone": "tông da",
  "current_condition": "tình trạng mày/môi hiện tại",
  "recommended_item_id": "id mẫu phù hợp nhất trong catalog",
  "consultation_script": "lời tư vấn ngắn, tự nhiên, giọng chủ tiệm"
}
''';

    final response = await model.generateContent([
      Content.multi([
        TextPart(prompt),
        DataPart('image/jpeg', imageBytes),
      ]),
    ]);

    String? text = response.text;
    if (text == null || text.trim().isEmpty) {
      throw Exception('Gemini không trả về kết quả.');
    }

    // Bóc markdown fence nếu có
    text = text.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\n?'), '');
      text = text.replaceFirst(RegExp(r'\n?```$'), '');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (e) {
      throw Exception('Gemini trả về không phải JSON hợp lệ: $e');
    }

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Gemini trả về JSON không đúng cấu trúc object.');
    }

    return decoded;
  }

  /// Bước 2: Gọi endpoint ghép mày/môi. Ném lỗi kèm mã HTTP nếu thất bại.
  Future<Uint8List> generateTryOnPreview({
    required File customerFaceImage,
    required String category, // 'eyebrow' hoặc 'lip'
    required String stylePromptHint,
  }) async {
    final url = imageGenApiUrl;
    if (url == null || url.trim().isEmpty) {
      throw Exception('Chưa cấu hình endpoint ghép ảnh (TRYON_API_URL).');
    }
    if (category != 'eyebrow' && category != 'lip') {
      throw Exception('Category không hợp lệ: $category (chỉ nhận eyebrow/lip).');
    }

    final imageBytes = await customerFaceImage.readAsBytes();
    if (imageBytes.isEmpty) {
      throw Exception('Ảnh mặt khách rỗng hoặc không đọc được.');
    }

    final base64Image = base64Encode(imageBytes);
    final target = category == 'eyebrow' ? 'eyebrows' : 'lips';
    final fullPrompt =
        'Keep the face, skin texture, eyes, nose and lighting identical. '
        'Only modify the $target to apply: $stylePromptHint. '
        'Realistic cosmetic permanent makeup photography.';

    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              if (imageGenApiKey != null && imageGenApiKey!.isNotEmpty)
                'Authorization': 'Bearer $imageGenApiKey',
            },
            body: jsonEncode({
              'image_base64': base64Image,
              'target_area': target,
              'prompt': fullPrompt,
              'strength': 0.55,
            }),
          )
          .timeout(const Duration(seconds: 90));
    } on SocketException catch (e) {
      throw Exception('Không kết nối được endpoint ghép ảnh: $e');
    } catch (e) {
      throw Exception('Lỗi gọi endpoint ghép ảnh: $e');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String detail = response.body;
      if (detail.length > 300) detail = '${detail.substring(0, 300)}...';
      throw Exception(
        'Endpoint ghép ảnh lỗi HTTP ${response.statusCode}: $detail',
      );
    }

    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (e) {
      throw Exception('Endpoint trả về body không phải JSON hợp lệ: $e');
    }
    if (data is! Map<String, dynamic>) {
      throw Exception('Endpoint trả về JSON không đúng cấu trúc object.');
    }

    final result = data['result_base64'];
    if (result is! String || result.isEmpty) {
      throw Exception('Endpoint không trả về result_base64.');
    }

    try {
      return base64Decode(result);
    } catch (e) {
      throw Exception('result_base64 không decode được: $e');
    }
  }
}
