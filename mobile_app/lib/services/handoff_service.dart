import 'dart:convert';
import 'dart:io';

import 'api_client.dart';
import 'image_preprocessor.dart';

class HandoffCase {
  const HandoffCase({
    required this.id,
    required this.source,
    required this.status,
    this.customerText = '',
    this.imageUrl = '',
    this.summary = '',
    this.risk = 'low',
    this.faceDetected = true,
    this.recommendedItemId,
    this.draftReply = '',
    this.psid = '',
    this.pageId = '',
    this.createdAt = '',
  });

  final String id;
  final String source;
  final String status;
  final String customerText;
  final String imageUrl;
  final String summary;
  final String risk;
  final bool faceDetected;
  final String? recommendedItemId;
  final String draftReply;
  final String psid;
  final String pageId;
  final String createdAt;

  bool get canSend =>
      status == 'approved' && psid.isNotEmpty && pageId.isNotEmpty;

  bool get canRelease =>
      source == 'business_ai_handover' && psid.isNotEmpty && pageId.isNotEmpty;

  factory HandoffCase.fromJson(Map<String, dynamic> j) {
    final analysis = j['analysis'] is Map
        ? Map<String, dynamic>.from(j['analysis'] as Map)
        : const <String, dynamic>{};
    return HandoffCase(
      id: (j['id'] ?? '').toString(),
      source: (j['source'] ?? 'owner_capture').toString(),
      status: (j['status'] ?? 'pending_review').toString(),
      customerText: (j['customer_text'] ?? '').toString(),
      imageUrl: (j['image_url'] ?? '').toString(),
      summary: (analysis['summary'] ?? '').toString(),
      risk: (analysis['risk'] ?? 'low').toString(),
      faceDetected: analysis.containsKey('face_detected')
          ? analysis['face_detected'] == true
          : true,
      recommendedItemId: analysis['recommended_item_id']?.toString(),
      draftReply: (j['draft_reply'] ?? analysis['draft_reply'] ?? '').toString(),
      psid: (j['psid'] ?? '').toString(),
      pageId: (j['page_id'] ?? '').toString(),
      createdAt: (j['created_at'] ?? '').toString(),
    );
  }
}

class HandoffService {
  const HandoffService(this.api);

  final ApiClient api;

  Future<List<HandoffCase>> fetchCases({
    String status = 'pending_review,approved',
    int limit = 30,
  }) async {
    final query = status.trim().isEmpty
        ? '/handoff-cases?limit=$limit'
        : '/handoff-cases?status=${Uri.encodeQueryComponent(status.trim())}&limit=$limit';
    final body = await api.get(query, timeout: const Duration(seconds: 15));
    final raw = body['cases'];
    if (raw == null) return const [];
    if (raw is! List) {
      throw const ApiException(0, 'Dữ liệu ca tư vấn không đúng định dạng.');
    }
    return raw
        .whereType<Map<String, dynamic>>()
        .map(HandoffCase.fromJson)
        .toList();
  }

  Future<HandoffCase> captureCase(File image, {String? customerText}) async {
    final bytes = await ImagePreprocessor.prepare(image);
    if (bytes.isEmpty) {
      throw const ApiException(0, 'Ảnh khách rỗng hoặc không đọc được.');
    }
    final payload = <String, dynamic>{
      'image_base64': base64Encode(bytes),
    };
    if (customerText != null && customerText.trim().isNotEmpty) {
      payload['customer_text'] = customerText.trim();
    }
    final body = await api.post(
      '/handoff-cases/capture',
      payload,
      timeout: const Duration(seconds: 40),
    );
    return HandoffCase.fromJson({
      'id': body['id'],
      'source': 'owner_capture',
      'status': body['status'] ?? 'pending_review',
      'analysis': body['analysis'],
    });
  }

  Future<void> approveCase({
    required String id,
    required String draftReply,
  }) async {
    final cleanId = Uri.encodeComponent(id.trim());
    await api.post(
      '/handoff-cases/$cleanId/approve',
      {'draft_reply': draftReply.trim()},
      timeout: const Duration(seconds: 15),
    );
  }

  Future<void> rejectCase(String id) async {
    final cleanId = Uri.encodeComponent(id.trim());
    await api.post(
      '/handoff-cases/$cleanId/reject',
      const {},
      timeout: const Duration(seconds: 15),
    );
  }

  Future<void> sendCase(String id) async {
    final cleanId = Uri.encodeComponent(id.trim());
    await api.post(
      '/handoff-cases/$cleanId/send',
      const {},
      timeout: const Duration(seconds: 20),
    );
  }

  Future<void> releaseCase(String id) async {
    final cleanId = Uri.encodeComponent(id.trim());
    await api.post(
      '/handoff-cases/$cleanId/release',
      const {},
      timeout: const Duration(seconds: 15),
    );
  }

  Future<void> analyzeCase(String id) async {
    final cleanId = Uri.encodeComponent(id.trim());
    await api.post(
      '/handoff-cases/$cleanId/analyze',
      const {},
      timeout: const Duration(seconds: 40),
    );
  }
}
