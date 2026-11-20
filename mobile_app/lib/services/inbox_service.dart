import 'api_client.dart';

class InboxService {
  static const String defaultBackendUrl = 'https://pyincccrm.bothelper.vn';

  final String webhookBaseUrl;
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String authToken;

  InboxService({
    this.webhookBaseUrl = defaultBackendUrl,
    this.supabaseUrl = '',
    this.supabaseAnonKey = '',
    this.authToken = const String.fromEnvironment(
      'BACKEND_AUTH_TOKEN',
      defaultValue: '',
    ),
  });

  ApiClient get apiClient => ApiClient(
        baseUrl: webhookBaseUrl,
        authToken: authToken,
      );

  bool get hasWebhookConfig => webhookBaseUrl.trim().isNotEmpty;

  Future<List<Map<String, dynamic>>> fetchConnectedPages() async {
    if (!hasWebhookConfig) return const [];
    final decoded = await apiClient.get(
      '/connected-pages',
      timeout: const Duration(seconds: 12),
    );
    if (decoded['pages'] is List) {
      return (decoded['pages'] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> fetchMessages({int limit = 30}) async {
    if (!hasWebhookConfig) return const [];
    final decoded = await apiClient.get(
      '/messages?limit=$limit',
      timeout: const Duration(seconds: 15),
    );
    final raw = decoded['messages'];
    if (raw == null) return const [];
    if (raw is! List) {
      throw const ApiException(0, 'Dữ liệu hộp thư không đúng định dạng.');
    }
    return raw
        .whereType<Map<String, dynamic>>()
        .map(_mapRowToTriageItem)
        .toList();
  }

  Future<void> sendMessage({
    required String messageRecordId,
    required String recipientId,
    required String text,
  }) async {
    await apiClient.post(
      '/messages/${Uri.encodeComponent(messageRecordId.trim())}/approve',
      {'text': text.trim()},
      timeout: const Duration(seconds: 15),
    );

    await apiClient.post(
      '/send-message',
      {'messageRecordId': messageRecordId.trim()},
      timeout: const Duration(seconds: 20),
    );
  }

  Future<Map<String, dynamic>> fetchSettings() async {
    if (!hasWebhookConfig) {
      return const {
        'onDuty': true,
        'consultationScript': '',
      };
    }
    return apiClient.get(
      '/settings',
      timeout: const Duration(seconds: 12),
    );
  }

  Future<void> saveSettings({
    bool? onDuty,
    String? consultationScript,
  }) async {
    final payload = <String, dynamic>{};
    if (onDuty != null) payload['onDuty'] = onDuty;
    if (consultationScript != null) {
      payload['consultationScript'] = consultationScript.trim();
    }
    await apiClient.put(
      '/settings',
      payload,
      timeout: const Duration(seconds: 15),
    );
  }

  Future<List<Map<String, String>>> fetchBookings() async {
    if (!hasWebhookConfig) return const [];
    final decoded = await apiClient.get(
      '/bookings',
      timeout: const Duration(seconds: 12),
    );
    if (decoded['bookings'] is! List) return const [];
    final rawList = decoded['bookings'] as List;
    return rawList.whereType<Map<String, dynamic>>().map((row) {
      final rawTime = (row['scheduled_at'] ?? '').toString();
      String formattedTime = rawTime;
      final parsed = DateTime.tryParse(rawTime);
      if (parsed != null) {
        final local = parsed.toLocal();
        final hh = local.hour.toString().padLeft(2, '0');
        final mm = local.minute.toString().padLeft(2, '0');
        formattedTime = '$hh:$mm';
      }
      final phone = (row['customer_phone'] ?? '').toString().trim();
      final name = (row['customer_name'] ?? 'Khách hàng').toString().trim();
      final statusRaw = (row['status'] ?? 'confirmed').toString();
      final statusLabel = statusRaw == 'pending'
          ? 'Chờ xác nhận'
          : statusRaw == 'done'
              ? 'Hoàn thành'
              : 'Đã chốt';
      return <String, String>{
        'time': formattedTime,
        'customer': phone.isNotEmpty ? '$name ($phone)' : name,
        'service': (row['service_name'] ?? '').toString(),
        'status': statusLabel,
      };
    }).toList();
  }

  Future<Map<String, String>> createBooking({
    required String time,
    required String customerName,
    required String serviceName,
  }) async {
    await apiClient.post(
      '/bookings',
      {
        'time': time.trim(),
        'customerName': customerName.trim(),
        'serviceName': serviceName.trim(),
      },
      timeout: const Duration(seconds: 15),
    );
    return <String, String>{
      'time': time.trim(),
      'customer': customerName.trim(),
      'service': serviceName.trim(),
      'status': 'Đã chốt',
    };
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
          'Dạ bên em chuyên xử lý nền mày trổ xanh/đỏ bằng Laser kết hợp đi sợi Hairstroke tự nhiên. Chị gửi em xin ảnh cận chân mày hiện tại để chuyên gia lên phác đồ cho mình nhé!';
    } else if (imageUrl.isNotEmpty) {
      tag = 'KHÁCH GỬI ẢNH';
      tagType = 'image';
      aiSuggestion =
          'Dạ em đã nhận được ảnh của chị rồi ạ! Với nền hiện tại mình làm Mày sợi Hairstroke hoặc Môi Collagen sẽ rất tự nhiên, em gửi chị xem thử mẫu mô phỏng AI nhé?';
    } else if (lower.contains('giá') ||
        lower.contains('lịch') ||
        lower.contains('môi') ||
        lower.contains('mày')) {
      tag = 'HỎI GIÁ / ĐẶT LỊCH';
      tagType = 'lead';
      aiSuggestion =
          'Dạ hiện bên em đang có ưu đãi cho Mày sợi Hairstroke và Môi Collagen. Chị muốn đặt lịch khung giờ nào hôm nay để em giữ chỗ chuyên viên trưởng cho mình ạ?';
    }

    final customerName = (row['customer_name'] ?? '').toString().trim();
    final channelLabel =
        channel == 'ZALO' ? 'Khách Zalo' : 'Khách Messenger';

    return {
      'id': (row['id'] ?? row['message_id'] ?? psid).toString(),
      'psid': psid,
      'pageId': (row['page_id'] ?? '').toString().trim(),
      'name': customerName.isNotEmpty ? customerName : channelLabel,
      'tag': isFromCustomer ? tag : 'ĐÃ PHẢN HỒI',
      'tagType': isFromCustomer ? tagType : 'replied',
      'summary': text.isNotEmpty
          ? text
          : (imageUrl.isNotEmpty ? '[Khách gửi hình ảnh]' : '[Tin nhắn mới]'),
      'imageUrl': imageUrl,
      'aiSuggestion': (row['draft_reply'] ?? '').toString().trim().isNotEmpty
          ? (row['draft_reply'] ?? '').toString().trim()
          : aiSuggestion,
      'createdAt': (row['created_at'] ?? '').toString(),
    };
  }
}
