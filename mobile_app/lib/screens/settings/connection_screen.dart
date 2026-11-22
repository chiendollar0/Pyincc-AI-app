import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/errors/user_message.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/widgets.dart';
import '../../data/crm_repo.dart';
import '../../services/facebook_connect_service.dart';

const _businessAiPrompt = '''Bạn là trợ lý CSKH của [TÊN TIỆM].

1. PHẠM VI
Chỉ trả lời về: giá dịch vụ, giờ làm việc, địa chỉ, cách đặt lịch theo thông tin trong "Câu hỏi thường gặp".
Giọng điệu lịch sự, xưng "Dạ - Em - Chị/Anh", ngắn gọn, tối đa 1 emoji.

2. ĐẶT LỊCH
Hỏi lần lượt: Tên, Số điện thoại, Dịch vụ, Ngày giờ mong muốn.
Xác nhận lại một lần, rồi báo: "Em đã ghi nhận, tiệm sẽ gọi xác nhận lại cho chị ạ."

3. CHUYỂN CA (QUAN TRỌNG)
Áp dụng khi khách:
- xin xem mẫu hình ảnh trước/sau
- gửi ảnh mặt mộc để tư vấn
- có ca khó: trổ xanh, sửa mày, dị ứng, đau, khiếu nại, biến chứng

Thực hiện đúng 3 bước:
Bước 1: Không tự tư vấn, không chẩn đoán, không hứa kết quả.
Bước 2: Gửi đúng 1 câu: "Dạ ca này để chuyên viên xem kỹ hơn cho chính xác ạ. Chị chờ em một chút nhé."
Bước 3: Chuyển hội thoại sang ứng dụng quản lý (Handover). Sau đó không trả lời thêm.

4. DẤU HIỆU NGUY HIỂM
Nếu khách mô tả sưng nhiều, chảy mủ, sốt, khó thở, hoặc đau dữ dội sau khi làm:
"Dạ chị vui lòng liên hệ ngay hotline [SỐ HOTLINE] hoặc đến cơ sở gần nhất để được kiểm tra sớm ạ."
Sau đó vẫn chuyển ca theo bước 3.

5. NGOÀI PHẠM VI
Với câu hỏi khác: "Dạ vấn đề này em xin phép để chuyên viên tư vấn trực tiếp cho chị được đầy đủ hơn ạ." Rồi chuyển ca theo bước 3.''';

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
  String? _disconnectingPageId;
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

  Future<void> _confirmDisconnect(String pageId, String pageName) async {
    if (pageId.isEmpty || _disconnectingPageId != null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gỡ liên kết Fanpage?'),
        content: Text(
          'Page Token của "${pageName.isEmpty ? pageId : pageName}" sẽ bị xóa khỏi hệ thống. '
          'Bạn có thể kết nối lại bất cứ lúc nào.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Gỡ liên kết'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _disconnectingPageId = pageId);
    try {
      await widget.repo.disconnectPage(pageId);
      if (!mounted) return;
      showAppMessage(context, 'Đã gỡ liên kết Fanpage.');
      await _load();
    } catch (e) {
      if (mounted) showAppMessage(context, userMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _disconnectingPageId = null);
    }
  }

  Future<void> _copyPrompt() async {
    await Clipboard.setData(const ClipboardData(text: _businessAiPrompt));
    if (!mounted) return;
    showAppMessage(context, 'Đã sao chép Prompt Business AI.');
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
                                  trailing: IconButton(
                                    tooltip: 'Gỡ liên kết',
                                    onPressed: _disconnectingPageId != null
                                        ? null
                                        : () => _confirmDisconnect(
                                              (p['page_id'] ?? '').toString(),
                                              (p['page_name'] ?? '').toString(),
                                            ),
                                    icon: _disconnectingPageId ==
                                            (p['page_id'] ?? '').toString()
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.link_off,
                                            color: AppColors.danger,
                                          ),
                                  ),
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
                      SectionCard(
                        title: 'Prompt Business AI (Meta Business Suite)',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Sao chép mẫu chỉ dẫn chuyển ca và dán vào mục Business AI trong Meta Business Suite (thay [TÊN TIỆM] và [SỐ HOTLINE]).',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _copyPrompt,
                                icon: const Icon(Icons.copy, size: 18),
                                label: const Text('Sao chép Prompt Business AI'),
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
