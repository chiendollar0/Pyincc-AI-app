import 'api_client.dart';

class StaffMember {
  const StaffMember({
    required this.id,
    required this.role,
    required this.status,
    this.userId = '',
    this.invitedEmail = '',
    this.invitedFbUserId = '',
    this.createdAt = '',
  });

  final String id;
  final String role;
  final String status;
  final String userId;
  final String invitedEmail;
  final String invitedFbUserId;
  final String createdAt;

  String get displayLabel {
    if (invitedEmail.isNotEmpty) return invitedEmail;
    if (invitedFbUserId.isNotEmpty) return 'Facebook ID: $invitedFbUserId';
    return 'Thành viên';
  }

  bool get isOwner => role == 'owner';
  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';
  bool get isRevoked => status == 'revoked';

  factory StaffMember.fromJson(Map<String, dynamic> j) {
    return StaffMember(
      id: (j['id'] ?? '').toString(),
      role: (j['role'] ?? 'staff').toString(),
      status: (j['status'] ?? 'pending').toString(),
      userId: (j['user_id'] ?? '').toString(),
      invitedEmail: (j['invited_email'] ?? '').toString(),
      invitedFbUserId: (j['invited_fb_user_id'] ?? '').toString(),
      createdAt: (j['created_at'] ?? '').toString(),
    );
  }
}

class StaffDirectory {
  const StaffDirectory({
    required this.members,
    required this.currentUserId,
  });

  final List<StaffMember> members;
  final String currentUserId;
}

class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.action,
    this.actorRole = '',
    this.targetType = '',
    this.targetId = '',
    this.metadata = const {},
    this.createdAt = '',
  });

  final String id;
  final String action;
  final String actorRole;
  final String targetType;
  final String targetId;
  final Map<String, dynamic> metadata;
  final String createdAt;

  factory AuditLogEntry.fromJson(Map<String, dynamic> j) {
    final rawMeta = j['metadata'];
    return AuditLogEntry(
      id: (j['id'] ?? '').toString(),
      action: (j['action'] ?? '').toString(),
      actorRole: (j['actor_role'] ?? '').toString(),
      targetType: (j['target_type'] ?? '').toString(),
      targetId: (j['target_id'] ?? '').toString(),
      metadata: rawMeta is Map
          ? Map<String, dynamic>.from(rawMeta)
          : const <String, dynamic>{},
      createdAt: (j['created_at'] ?? '').toString(),
    );
  }
}

class StaffService {
  const StaffService(this.api);

  final ApiClient api;

  Future<StaffDirectory> fetchMemberships() async {
    final body = await api.get(
      '/memberships',
      timeout: const Duration(seconds: 15),
    );
    final raw = body['memberships'];
    final list = raw is List
        ? raw.whereType<Map<String, dynamic>>().map(StaffMember.fromJson).toList()
        : const <StaffMember>[];
    return StaffDirectory(
      members: list,
      currentUserId: (body['currentUserId'] ?? '').toString(),
    );
  }

  Future<void> inviteStaff({
    String? email,
    String? fbUserId,
    String role = 'staff',
  }) async {
    final payload = <String, dynamic>{'role': role};
    if (email != null && email.trim().isNotEmpty) {
      payload['email'] = email.trim().toLowerCase();
    }
    if (fbUserId != null && fbUserId.trim().isNotEmpty) {
      payload['fbUserId'] = fbUserId.trim();
    }
    await api.post(
      '/memberships/invite',
      payload,
      timeout: const Duration(seconds: 15),
    );
  }

  Future<void> updateMemberRole({
    required String membershipId,
    required String role,
  }) async {
    final cleanId = Uri.encodeComponent(membershipId.trim());
    await api.patch(
      '/memberships/$cleanId',
      {'role': role},
      timeout: const Duration(seconds: 15),
    );
  }

  Future<void> revokeMember(String membershipId) async {
    final cleanId = Uri.encodeComponent(membershipId.trim());
    await api.post(
      '/memberships/$cleanId/revoke',
      const {},
      timeout: const Duration(seconds: 15),
    );
  }

  Future<void> reactivateMember(String membershipId) async {
    final cleanId = Uri.encodeComponent(membershipId.trim());
    await api.patch(
      '/memberships/$cleanId',
      {'status': 'active'},
      timeout: const Duration(seconds: 15),
    );
  }

  Future<List<AuditLogEntry>> fetchAuditLogs({int limit = 50}) async {
    final body = await api.get(
      '/audit-logs?limit=$limit',
      timeout: const Duration(seconds: 15),
    );
    final raw = body['logs'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(AuditLogEntry.fromJson)
        .toList();
  }
}
