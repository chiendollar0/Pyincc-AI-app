import 'package:flutter/material.dart';

import '../../core/errors/user_message.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/widgets.dart';
import '../../data/crm_repo.dart';
import 'audit_logs_screen.dart';
import 'catalog_screen.dart';
import 'connection_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repo,
    required this.onSignOut,
    this.onCatalogChanged,
  });

  final CrmRepo repo;
  final VoidCallback onSignOut;
  final VoidCallback? onCatalogChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic> _tenant = {};
  Map<String, dynamic> _ai = {};
  Map<String, dynamic> _conn = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    String? firstError;
    Future<Map<String, dynamic>?> safe(Future<Map<String, dynamic>> call) async {
      try {
        return await call;
      } catch (e) {
        firstError ??= userMessage(e);
        return null;
      }
    }

    try {
      final results = await Future.wait<Map<String, dynamic>?>([
        safe(widget.repo.tenant()),
        safe(widget.repo.aiUsage()),
        safe(widget.repo.connectionStatus()),
      ]);
      if (!mounted) return;
      setState(() {
        if (results[0] != null) _tenant = results[0]!;
        if (results[1] != null) _ai = results[1]!;
        if (results[2] != null) _conn = results[2]!;
      });
      if (firstError != null) {
        showAppMessage(context, firstError!, isError: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editTenant() async {
    final result = await showDialog<({String name, String specialty})>(
      context: context,
      builder: (_) => _EditTenantDialog(
        initialName: (_tenant['name'] ?? '').toString(),
        initialSpecialty: (_tenant['specialty'] ?? '').toString(),
      ),
    );
    if (result == null) return;
    try {
      await widget.repo.updateTenant({
        'name': result.name,
        'specialty': result.specialty,
      });
      if (!mounted) return;
      setState(() {
        _tenant = {
          ..._tenant,
          'name': result.name,
          'specialty': result.specialty,
        };
      });
      showAppMessage(context, 'Đã lưu thông tin tiệm.');
      _load();
    } catch (e) {
      if (mounted) showAppMessage(context, userMessage(e), isError: true);
    }
  }

  void _open(Widget page, {bool notifyCatalog = false}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)).then((_) {
        if (notifyCatalog) widget.onCatalogChanged?.call();
        _load();
      });

  @override
  Widget build(BuildContext context) {
    final pages = (_conn['pages'] as List?) ?? const [];
    final connText = pages.isEmpty
        ? 'Chưa kết nối Fanpage'
        : 'Đã kết nối ${pages.length} Fanpage';
    final used = _ai['used'] ?? 0;
    final cap = _ai['cap'] ?? '-';
    final tenantName = (_tenant['name'] ?? '').toString().trim();
    final specialty = (_tenant['specialty'] ?? '').toString().trim();

    return Column(
      children: [
        BrandHeader(
          title: 'Cài đặt',
          subtitle: tenantName.isEmpty ? 'Chưa đặt tên tiệm' : tenantName,
          actions: [
            IconButton(
              tooltip: 'Làm mới',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              SectionCard(
                title: 'Tiệm',
                child: Column(
                  children: [
                    _tile(
                      Icons.storefront_outlined,
                      'Thông tin tiệm',
                      specialty.isEmpty ? 'Chưa đặt chuyên môn' : specialty,
                      _editTenant,
                    ),
                    _tile(
                      Icons.collections_outlined,
                      'Catalog mẫu',
                      'Mẫu do tiệm tự tạo, không có giá',
                      () => _open(
                        CatalogScreen(
                          repo: widget.repo,
                          onChanged: widget.onCatalogChanged,
                        ),
                        notifyCatalog: true,
                      ),
                    ),
                  ],
                ),
              ),
              SectionCard(
                title: 'Kết nối',
                child: Column(
                  children: [
                    _tile(
                      Icons.link,
                      'Facebook và Business AI',
                      connText,
                      () => _open(ConnectionScreen(repo: widget.repo)),
                    ),
                  ],
                ),
              ),
              SectionCard(
                title: 'Hệ thống',
                child: Column(
                  children: [
                    _tile(
                      Icons.bolt_outlined,
                      'Hạn mức AI hôm nay',
                      'Đã dùng $used / $cap lượt',
                      null,
                    ),
                    _tile(
                      Icons.history,
                      'Nhật ký hoạt động',
                      'Lịch sử duyệt, gửi tin và thay đổi cài đặt',
                      () => _open(AuditLogsScreen(repo: widget.repo)),
                    ),
                  ],
                ),
              ),
              SectionCard(
                title: 'Tài khoản',
                child: Column(
                  children: [
                    _tile(
                      Icons.logout,
                      'Đăng xuất',
                      'Đăng xuất khỏi thiết bị này',
                      widget.onSignOut,
                    ),
                    _tile(
                      Icons.delete_outline,
                      'Xóa dữ liệu và tài khoản',
                      'Xem hướng dẫn xóa dữ liệu',
                      _showDeletionHelp,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback? onTap, {
    bool enabled = true,
  }) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        enabled: enabled,
        leading: Icon(
          icon,
          color: enabled ? AppColors.primaryDark : AppColors.textMuted,
        ),
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppColors.textMuted),
        ),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
        onTap: enabled ? onTap : null,
      );

  void _showDeletionHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa dữ liệu'),
        content: const Text(
          'Gỡ liên kết trong Facebook (Cài đặt → Tiện ích tích hợp doanh nghiệp → PYINCC → Gỡ) '
          'để xóa token và liên kết Fanpage. Để xóa toàn bộ dữ liệu tiệm, gửi yêu cầu tới '
          'địa chỉ liên hệ trong chính sách quyền riêng tư.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }
}

class _EditTenantDialog extends StatefulWidget {
  const _EditTenantDialog({
    required this.initialName,
    required this.initialSpecialty,
  });

  final String initialName;
  final String initialSpecialty;

  @override
  State<_EditTenantDialog> createState() => _EditTenantDialogState();
}

class _EditTenantDialogState extends State<_EditTenantDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);
  late final TextEditingController _specialty =
      TextEditingController(text: widget.initialSpecialty);
  String? _validationError;

  @override
  void dispose() {
    _name.dispose();
    _specialty.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _validationError = 'Vui lòng nhập tên tiệm.');
      return;
    }
    Navigator.pop(context, (
      name: name,
      specialty: _specialty.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Thông tin tiệm'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            onChanged: (_) {
              if (_validationError != null) {
                setState(() => _validationError = null);
              }
            },
            decoration: const InputDecoration(labelText: 'Tên tiệm'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _specialty,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Chuyên môn (ví dụ: phun môi, xóa xăm)',
            ),
          ),
          if (_validationError != null) ...[
            const SizedBox(height: 8),
            Text(
              _validationError!,
              style: const TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}
