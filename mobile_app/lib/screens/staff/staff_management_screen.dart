// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/errors/user_message.dart';
import '../../core/theme/app_theme.dart';
import '../../services/staff_service.dart';

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({
    super.key,
    required this.staffService,
  });

  final StaffService staffService;

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  List<StaffMember> _members = const [];
  List<AuditLogEntry> _logs = const [];
  String _currentUserId = '';
  bool _loading = true;
  String? _error;
  final Set<String> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.staffService.fetchMemberships(),
        widget.staffService.fetchAuditLogs(),
      ]);
      if (!mounted) return;
      final directory = results[0] as StaffDirectory;
      final logs = results[1] as List<AuditLogEntry>;
      setState(() {
        _members = directory.members;
        _currentUserId = directory.currentUserId;
        _logs = logs;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = userMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revoke(StaffMember member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thu hồi quyền truy cập'),
        content: Text(
          'Thu hồi bản ghi cũ của ${member.displayLabel}? '
          'Phiên bản hiện tại chỉ cho phép 1 tài khoản Chủ tiệm duy nhất.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Thu hồi quyền'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busyIds.add(member.id));
    try {
      await widget.staffService.revokeMember(member.id);
      if (!mounted) return;
      showAppMessage(context, 'Đã thu hồi quyền của ${member.displayLabel}.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, userMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(member.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhật ký & Tài khoản'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.history), text: 'Nhật ký'),
            Tab(icon: Icon(Icons.verified_user_outlined), text: 'Tài khoản'),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _members.isEmpty && _logs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _members.isEmpty && _logs.isEmpty) {
      return EmptyState(
        icon: Icons.lock_person_outlined,
        title: 'Chưa tải được nhật ký hoạt động',
        message: _error,
        onRetry: _load,
      );
    }
    return TabBarView(
      controller: _tabController,
      children: [
        _buildAuditLogsTab(),
        _buildMembersTab(),
      ],
    );
  }

  Widget _buildMembersTab() {
    if (_members.isEmpty) {
      return const EmptyState(
        icon: Icons.verified_user_outlined,
        title: 'Chưa có thông tin tài khoản',
        message: 'Mỗi tiệm vận hành bằng 1 tài khoản Chủ tiệm duy nhất.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Phiên bản hiện tại vận hành theo mô hình 1 Chủ tiệm duy nhất (toàn quyền, người duy nhất duyệt và gửi tin).',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          for (final m in _members) _buildMemberCard(m),
        ],
      ),
    );
  }

  Widget _buildMemberCard(StaffMember m) {
    final isSelf = _currentUserId.isNotEmpty && m.userId == _currentUserId;
    final busy = _busyIds.contains(m.id);

    final statusColor = m.isActive
        ? AppColors.success
        : (m.isPending ? Colors.orange.shade800 : AppColors.danger);
    final statusText = m.isActive
        ? 'Đang hoạt động'
        : (m.isPending ? 'Chờ xác nhận (cũ)' : 'Đã thu hồi');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isSelf ? '${m.displayLabel} (Chủ tiệm)' : m.displayLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    m.isOwner ? 'Chủ tiệm' : 'Tài khoản phụ (đã khóa)',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
            if (!isSelf && !m.isRevoked) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: busy ? null : () => _revoke(m),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                ),
                icon: const Icon(Icons.block, size: 16),
                label: const Text('Thu hồi quyền'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAuditLogsTab() {
    if (_logs.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        title: 'Chưa có nhật ký hoạt động',
        message:
            'Các thao tác thiết lập tiệm, danh mục dịch vụ và duyệt/gửi ca sẽ ghi nhận tại đây.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _logs.length,
        itemBuilder: (context, index) {
          final log = _logs[index];
          final email = (log.metadata['invited_email'] ?? '').toString();
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: const Icon(Icons.receipt_long, color: AppColors.primary),
              ),
              title: Text(
                _actionLabel(log.action),
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: Text(
                [
                  if (email.isNotEmpty) email,
                  if (log.actorRole.isNotEmpty) 'Thực hiện: Chủ tiệm',
                  if (log.createdAt.isNotEmpty) _formatTime(log.createdAt),
                ].join(' • '),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          );
        },
      ),
    );
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'membership.revoked':
        return 'Thu hồi bản ghi quyền truy cập';
      case 'handoff_case.approve':
        return 'Duyệt ca tư vấn';
      case 'handoff_case.reject':
        return 'Từ chối ca tư vấn';
      case 'handoff_case.send':
        return 'Gửi phản hồi Messenger cho khách';
      case 'handoff_case.release':
        return 'Trả quyền hội thoại về Business AI';
      case 'onboarding.claim':
        return 'Kích hoạt tiệm bằng mã thiết lập';
      case 'catalog.create':
        return 'Thêm dịch vụ vào danh mục';
      case 'catalog.update':
        return 'Cập nhật dịch vụ trong danh mục';
      case 'catalog.delete':
        return 'Xóa dịch vụ khỏi danh mục';
      default:
        return action;
    }
  }

  String _formatTime(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final local = parsed.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$dd/$mo $hh:$mm';
  }
}
