import 'package:flutter/material.dart';

import '../../core/errors/user_message.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/widgets.dart';
import '../../data/crm_repo.dart';

const _actionLabels = <String, String>{
  'onboarding.claim': 'Kích hoạt tiệm bằng mã thiết lập',
  'tenant.update': 'Cập nhật thông tin tiệm',
  'catalog.create': 'Thêm mẫu vào Catalog',
  'catalog.update': 'Cập nhật mẫu Catalog',
  'catalog.delete': 'Xóa mẫu khỏi Catalog',
  'connected_page.disconnect': 'Gỡ liên kết Fanpage',
  'handoff_case.approve': 'Duyệt bản nháp trả lời khách',
  'handoff_case.reject': 'Từ chối ca tư vấn',
  'handoff_case.send': 'Gửi tin nhắn cho khách',
  'handoff_case.release': 'Trả hội thoại về Business AI',
  'membership.revoked': 'Thu hồi quyền tài khoản cũ',
};

class AuditLogsScreen extends StatefulWidget {
  const AuditLogsScreen({super.key, required this.repo});

  final CrmRepo repo;

  @override
  State<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends State<AuditLogsScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.repo.auditLogs();
      if (mounted) setState(() => _logs = rows);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatTime(dynamic raw) {
    final dt = DateTime.tryParse((raw ?? '').toString())?.toLocal();
    if (dt == null) return '';
    final dd = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$dd/$mo/${dt.year} $hh:$mm';
  }

  String _detailText(Map<String, dynamic> row) {
    final parts = <String>[];
    final time = _formatTime(row['created_at']);
    if (time.isNotEmpty) parts.add(time);
    final meta = row['metadata'];
    if (meta is Map) {
      final name = (meta['name'] ?? meta['page_name'] ?? '').toString().trim();
      if (name.isNotEmpty) parts.add(name);
    }
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nhật ký hoạt động')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Chưa tải được nhật ký',
                  message: _error,
                  action: OutlinedButton(
                    onPressed: _load,
                    child: const Text('Thử lại'),
                  ),
                )
              : _logs.isEmpty
                  ? const EmptyState(
                      icon: Icons.history,
                      title: 'Chưa có hoạt động nào',
                      message:
                          'Các thao tác duyệt, gửi tin, đổi catalog và cài đặt của tiệm sẽ được ghi lại tại đây.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _logs.length,
                        itemBuilder: (_, i) {
                          final row = _logs[i];
                          final action = (row['action'] ?? '').toString();
                          final label = _actionLabels[action] ?? action;
                          final detail = _detailText(row);
                          return SectionCard(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.history,
                                color: AppColors.primaryDark,
                              ),
                              title: Text(
                                label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: detail.isEmpty
                                  ? null
                                  : Text(
                                      detail,
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
