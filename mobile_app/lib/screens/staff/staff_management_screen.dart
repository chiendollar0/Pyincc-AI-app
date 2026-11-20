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

  Future<void> _showInviteDialog() async {
    final emailCtrl = TextEditingController();
    String selectedRole = 'staff';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Mời nhân viên mới'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nhập email đăng nhập của nhân viên. Quyền sẽ tự kích hoạt khi họ đăng nhập bằng email đã xác thực.',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email nhân viên',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Vai trò',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Nhân viên'),
                      selected: selectedRole == 'staff',
                      onSelected: (_) =>
                          setDialogState(() => selectedRole = 'staff'),
                    ),
                    ChoiceChip(
                      label: const Text('Chủ tiệm'),
                      selected: selectedRole == 'owner',
                      onSelected: (_) =>
                          setDialogState(() => selectedRole = 'owner'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Gửi lời mời'),
            ),
          ],
        ),
      ),
    );

    final email = emailCtrl.text.trim();
    emailCtrl.dispose();
    if (confirmed != true || email.isEmpty) return;

    try {
      await widget.staffService.inviteStaff(email: email, role: selectedRole);
      if (!mounted) return;
      showAppMessage(context, 'Đã tạo lời mời cho $email.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, userMessage(error), isError: true);
    }
  }

  Future<void> _toggleRole(StaffMember member) async {
    final nextRole = member.isOwner ? 'staff' : 'owner';
    final nextLabel = nextRole == 'owner' ? 'Chủ tiệm' : 'Nhân viên';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi quyền thành viên'),
        content: Text(
          'Chuyển ${member.displayLabel} sang vai trò "$nextLabel"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busyIds.add(member.id));
    try {
      await widget.staffService.updateMemberRole(
        membershipId: member.id,
        role: nextRole,
      );
      if (!mounted) return;
      showAppMessage(context, 'Đã đổi vai trò sang $nextLabel.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, userMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(member.id));
    }
  }

  Future<void> _revoke(StaffMember member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thu hồi quyền truy cập'),
        content: Text(
          'Thu hồi quyền của ${member.displayLabel}? '
          'Tài khoản này sẽ bị chặn ngay lập tức khỏi mọi thao tác duyệt và gửi tin.',
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

  Future<void> _reactivate(StaffMember member) async {
    setState(() => _busyIds.add(member.id));
    try {
      await widget.staffService.reactivateMember(member.id);
      if (!mounted) return;
      showAppMessage(context, 'Đã khôi phục quyền cho ${member.displayLabel}.');
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
        title: const Text('Nhân viên & Nhật ký'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Mời nhân viên',
            onPressed: _showInviteDialog,
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.group_outlined), text: 'Nhân viên'),
            Tab(icon: Icon(Icons.history), text: 'Nhật ký'),
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
    if (_error != null && _members.isEmpty) {
      return EmptyState(
        icon: Icons.lock_person_outlined,
        title: 'Chưa tải được danh sách nhân viên',
        message: _error,
        onRetry: _load,
      );
    }
    return TabBarView(
      controller: _tabController,
      children: [
        _buildMembersTab(),
        _buildAuditLogsTab(),
      ],
    );
  }

  Widget _buildMembersTab() {
    if (_members.isEmpty) {
      return EmptyState(
        icon: Icons.group_add_outlined,
        title: 'Chưa có nhân viên nào',
        message: 'Bấm biểu tượng thêm người ở góc trên để mời nhân viên vào tiệm.',
        retryLabel: 'Mời nhân viên',
        onRetry: _showInviteDialog,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _members.length,
        itemBuilder: (context, index) {
          final m = _members[index];
          final isSelf = _currentUserId.isNotEmpty && m.userId == _currentUserId;
          final busy = _busyIds.contains(m.id);

          final statusColor = m.isActive
              ? AppColors.success
              : (m.isPending ? Colors.orange.shade800 : AppColors.danger);
          final statusText = m.isActive
              ? 'Đang hoạt động'
              : (m.isPending ? 'Chờ nhận lời mời' : 'Đã thu hồi');

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
                          isSelf ? '${m.displayLabel} (Bạn)' : m.displayLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Chip(
                        label: Text(
                          m.isOwner ? 'Chủ tiệm' : 'Nhân viên',
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
                  if (!isSelf) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (!m.isRevoked)
                          OutlinedButton.icon(
                            onPressed: busy ? null : () => _toggleRole(m),
                            icon: const Icon(Icons.swap_horiz, size: 16),
                            label: Text(
                              m.isOwner ? 'Hạ xuống Nhân viên' : 'Nâng lên Chủ tiệm',
                            ),
                          ),
                        if (!m.isRevoked)
                          OutlinedButton.icon(
                            onPressed: busy ? null : () => _revoke(m),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                            ),
                            icon: const Icon(Icons.block, size: 16),
                            label: const Text('Thu hồi quyền'),
                          ),
                        if (m.isRevoked && m.userId.isNotEmpty)
                          FilledButton.icon(
                            onPressed: busy ? null : () => _reactivate(m),
                            icon: const Icon(Icons.restore, size: 16),
                            label: const Text('Khôi phục quyền'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAuditLogsTab() {
    if (_logs.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        title: 'Chưa có nhật ký hoạt động',
        message: 'Các thao tác mời, đổi quyền, thu hồi nhân viên và duyệt/gửi ca sẽ ghi nhận tại đây.',
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
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: Text(
                [
                  if (email.isNotEmpty) email,
                  if (log.actorRole.isNotEmpty)
                    'Người thực hiện: ${log.actorRole == 'owner' ? 'Chủ tiệm' : 'Nhân viên'}',
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
      case 'membership.invite':
        return 'Mời nhân viên mới';
      case 'membership.role_changed':
        return 'Thay đổi vai trò thành viên';
      case 'membership.revoked':
        return 'Thu hồi quyền thành viên';
      case 'membership.reactivated':
        return 'Khôi phục quyền thành viên';
      case 'handoff_case.approve':
        return 'Duyệt ca tư vấn';
      case 'handoff_case.reject':
        return 'Từ chối ca tư vấn';
      case 'handoff_case.send':
        return 'Gửi phản hồi Messenger cho khách';
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
