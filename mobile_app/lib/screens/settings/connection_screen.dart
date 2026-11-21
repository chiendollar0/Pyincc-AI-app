import 'package:flutter/material.dart';

import '../../core/errors/user_message.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/widgets.dart';
import '../../data/crm_repo.dart';
import '../../services/facebook_connect_service.dart';

const _checks = <(String, String, String)>[
  (
    'default_app',
    'Ứng dụng là mặc định (default app)',
    'Page Settings → Conversation routing: chọn ứng dụng PYINCC làm mặc định.',
  ),
  (
    'take_control_enabled',
    'Bật "Take control of conversations with your Business Agent"',
    'Page Settings → Advanced Messaging → Connected apps, hoặc Business Suite → Settings → Conversation routing.',
  ),
  (
    'handover_subscribed',
    'Đã đăng ký sự kiện messaging_handover',
    'Developers → Webhooks → Page: bật messaging_handover.',
  ),
  (
    'receiving_events',
    'Đã nhận sự kiện trong 24 giờ gần nhất',
    'Gửi một tin thử tới Page. Nếu chưa thấy, kiểm tra subscribe và chữ ký webhook.',
  ),
];

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key, required this.repo});

  final CrmRepo repo;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  Map<String, dynamic> _status = {};
  bool _loading = true;
  bool _connecting = false;
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
      final s = await widget.repo.connectionStatus();
      if (mounted) setState(() => _status = s);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    try {
      final pages = await FacebookConnectService(widget.repo.api).connect();
      if (!mounted) return;
      showAppMessage(context, 'Đã kết nối ${pages.length} Fanpage.');
      await _load();
    } catch (e) {
      if (mounted) showAppMessage(context, userMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _hint(String title, String text) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đã hiểu'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pages = (_status['pages'] as List?) ?? const [];
    final lastWebhook = (_status['last_webhook_at'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(title: const Text('Facebook và Business AI')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Chưa tải được trạng thái',
                  message: _error,
                  action: OutlinedButton(
                    onPressed: _load,
                    child: const Text('Thử lại'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      SectionCard(
                        title: 'Fanpage',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (pages.isEmpty)
                              const Text(
                                'Chưa kết nối Fanpage nào.',
                                style: TextStyle(color: AppColors.textMuted),
                              )
                            else
                              for (final p in pages.whereType<Map>())
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.facebook,
                                    color: Color(0xFF1877F2),
                                  ),
                                  title: Text((p['page_name'] ?? '').toString()),
                                  subtitle: const Text('Đã kết nối'),
                                ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _connecting ? null : _connect,
                                icon: _connecting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.link),
                                label: Text(
                                  pages.isEmpty
                                      ? 'Kết nối với Facebook'
                                      : 'Kết nối Fanpage khác',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SectionCard(
                        title: 'Nhận ca từ Business AI',
                        child: Column(
                          children: [
                            for (final c in _checks)
                              _CheckRow(
                                label: c.$2,
                                value: _status[c.$1] is bool
                                    ? _status[c.$1] as bool
                                    : null,
                                onTap: () => _hint(c.$2, c.$3),
                              ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                lastWebhook.isEmpty
                                    ? 'Chưa nhận sự kiện nào.'
                                    : 'Sự kiện gần nhất: $lastWebhook',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SectionCard(
                        child: Text(
                          'Gửi tin chỉ được trong 24 giờ kể từ tin cuối của khách, trừ khi dùng tag hợp lệ. '
                          'Business AI vẫn trả lời khách theo cấu hình; app chỉ nhận ca khi Business AI chuyển.',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final bool? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (value) {
      true => (Icons.check_circle, AppColors.success, 'Đạt'),
      false => (Icons.cancel, AppColors.danger, 'Chưa đạt'),
      null => (Icons.help_outline, AppColors.textMuted, 'Chưa kiểm tra'),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(label),
      subtitle: Text(text, style: TextStyle(color: color)),
      trailing: const Icon(Icons.info_outline, size: 18),
    );
  }
}
