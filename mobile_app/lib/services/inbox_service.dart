import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class InboxService {
  final String webhookBaseUrl;
  final String webhookApiKey;
  final String supabaseUrl;
  final String supabaseAnonKey;

  InboxService({
    required this.webhookBaseUrl,
    required this.webhookApiKey,
    this.supabaseUrl = '',
    this.supabaseAnonKey = '',
  });

  bool get hasWebhookConfig =>
      webhookBaseUrl.trim().isNotEmpty && webhookApiKey.trim().isNotEmpty;

  bool get hasSupabaseRestConfig =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  Uri _webhookEndpoint(String path) {
    final base = webhookBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  Future<List<Map<String, dynamic>>> fetchMessages({int limit = 30}) async {
    if (hasWebhookConfig) {
      return _fetchFromWebhookBackend(limit: limit);
    }
    if (hasSupabaseRestConfig) {
      return _fetchFromSupabaseRest(limit: limit);
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> _fetchFromWebhookBackend({
    required int limit,
  }) async {
    late final http.Response response;
    try {
      response = await http
          .get(
            _webhookEndpoint('/messages?limit=$limit'),
            headers: {
              'x-api-key': webhookApiKey.trim(),
            },
          )
          .timeout(const Duration(seconds: 15));
    } on SocketException catch (e) {
      throw Exception('Không kết nối được Meta Webhook backend: $e');
    }

    if (response.statusCode != 200) {
      throw Exception(
        'Lỗi tải tin nhắn (HTTP ${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['messages'] is! List) {
      throw Exception('Dữ liệu /messages trả về không đúng định dạng.');
    }

    final rawList = decoded['messages'] as List;
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(_mapRowToTriageItem)
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchFromSupabaseRest({
    required int limit,
  }) async {
    final base = supabaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      '$base/rest/v1/conversation_messages?select=*&order=created_at.desc&limit=$limit',
    );

    late final http.Response response;
    try {
      response = await http
          .get(
            uri,
            headers: {
              'apikey': supabaseAnonKey.trim(),
              'Authorization': 'Bearer ${supabaseAnonKey.trim()}',
            },
          )
          .timeout(const Duration(seconds: 15));
    } on SocketException catch (e) {
      throw Exception('Không kết nối được Supabase REST: $e');
    }

    if (response.statusCode != 200) {
      throw Exception(
        'Supabase REST lỗi HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Dữ liệu Supabase trả về không phải danh sách.');
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(_mapRowToTriageItem)
        .toList();
  }

  Future<void> sendMessage({
    required String recipientId,
    required String text,
  }) async {
    if (!hasWebhookConfig) {
      throw Exception(
        'Chưa cấu hình WEBHOOK_API_URL và WEBHOOK_API_KEY trong mục Chủ tiệm.',
      );
    }

    late final http.Response response;
    try {
      response = await http
          .post(
            _webhookEndpoint('/send-message'),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': webhookApiKey.trim(),
            },
            body: jsonEncode({
              'recipientId': recipientId.trim(),
              'text': text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 20));
    } on SocketException catch (e) {
      throw Exception('Không kết nối được backend gửi tin: $e');
    }

    if (response.statusCode != 200) {
      throw Exception(
        'Gửi tin thất bại (HTTP ${response.statusCode}): ${response.body}',
      );
    }
  }

  Map<String, dynamic> _mapRowToTriageItem(Map<String, dynamic> row) {
    final psid = (row['customer_psid'] ?? 'unknown').toString();
    final channel = (row['channel'] ?? 'facebook').toString().toUpperCase();
    final text = (row['message_text'] ?? '').toString().trim();
    final imageUrl =
        (row['attachment_url'] ?? row['image_url'] ?? '').toString().trim();
    final isFromCustomer = row['is_from_customer'] != false;

    String tag = 'TIN NHẮN MỚI';
    String tagType = 'normal';
    String aiSuggestion =
        'Dạ bên em đã nhận được tin nhắn của chị! Chị gửi em xin ảnh cận vùng mày/môi hiện tại để chuyên viên tư vấn mẫu hợp dáng mặt nhất cho mình nhé ạ!';

    final lower = text.toLowerCase();
    if (lower.contains('trổ xanh') ||
        lower.contains('trổ đỏ') ||
        lower.contains('sửa mày') ||
        lower.contains('hút màu') ||
        lower.contains('hỏng')) {
      tag = 'CA KHÓ / SỬA MÀY';
      tagType = 'urgent';
      aiSuggestion =
          'Dạ bên em chuyên xử lý nền mày trổ xanh/đỏ bằng Laser kết hợp đi sợi Hairstroke tự nhiên. Chị gửi em xin ảnh cận chân mày hiện tại để Master lên phác đồ cho mình nhé!';
    } else if (imageUrl.isNotEmpty) {
      tag = 'KHÁCH GỬI ẢNH';
      tagType = 'image';
      aiSuggestion =
          'Dạ em đã nhận được ảnh của chị rồi ạ! Với nền hiện tại mình làm Mày sợi Hairstroke hoặc Môi Collagen sẽ rất tự nhiên, em gửi chị xem thử mẫu ghép AI nhé?';
    } else if (lower.contains('giá') ||
        lower.contains('lịch') ||
        lower.contains('môi') ||
        lower.contains('mày')) {
      tag = 'HỎI GIÁ / ĐẶT LỊCH';
      tagType = 'lead';
      aiSuggestion =
          'Dạ hiện bên em đang có ưu đãi cho Mày sợi Hairstroke và Môi Collagen. Chị muốn đặt lịch khung giờ nào hôm nay để em giữ chỗ chuyên viên trưởng cho mình ạ?';
    }

    final shortPsid =
        psid.length > 6 ? '...${psid.substring(psid.length - 6)}' : psid;

    return {
      'id': (row['id'] ?? row['message_id'] ?? psid).toString(),
      'psid': psid,
      'name': 'Khách $channel ($shortPsid)',
      'tag': isFromCustomer ? tag : 'ĐÃ PHẢN HỒI',
      'tagType': isFromCustomer ? tagType : 'replied',
      'summary': text.isNotEmpty
          ? text
          : (imageUrl.isNotEmpty ? '[Khách gửi hình ảnh]' : '[Tin nhắn mới]'),
      'imageUrl': imageUrl,
      'aiSuggestion': aiSuggestion,
      'createdAt': (row['created_at'] ?? '').toString(),
    };
  }
}
