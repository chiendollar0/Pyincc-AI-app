// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/tryon/tryon_studio_screen.dart';
import 'services/inbox_service.dart';

void main() {
  runApp(const BeautyCrmApp());
}

class BeautyCrmApp extends StatelessWidget {
  const BeautyCrmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Beauty Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD81B60)),
        useMaterial3: true,
      ),
      home: const MainDashboardScreen(),
    );
  }
}

class MainDashboardScreen extends StatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  int _selectedIndex = 0;

  String _webhookApiUrl = const String.fromEnvironment(
    'WEBHOOK_API_URL',
    defaultValue: 'https://pyincc-ai-app.onrender.com',
  );
  String _webhookApiKey = const String.fromEnvironment(
    'WEBHOOK_API_KEY',
    defaultValue: '',
  );
  final String _supabaseUrl = const String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ihufvqrxdswgbagzhydb.supabase.co',
  );
  final String _supabaseAnonKey = const String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );
  final String _tryOnApiUrl = const String.fromEnvironment(
    'TRYON_API_URL',
    defaultValue: '',
  );

  void _updateWebhookConfig({
    required String webhookUrl,
    required String webhookKey,
  }) {
    setState(() {
      _webhookApiUrl = webhookUrl.trim();
      _webhookApiKey = webhookKey.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      AiTriageInboxScreen(
        inboxService: InboxService(
          webhookBaseUrl: _webhookApiUrl,
          webhookApiKey: _webhookApiKey,
          supabaseUrl: _supabaseUrl,
          supabaseAnonKey: _supabaseAnonKey,
        ),
      ),
      TryOnStudioScreen(apiBaseUrl: _tryOnApiUrl),
      const ShiftAndBookingScreen(),
      OwnerSettingsScreen(
        initialWebhookUrl: _webhookApiUrl,
        initialWebhookKey: _webhookApiKey,
        onSaveConfig: _updateWebhookConfig,
      ),
    ];

    return Scaffold(
      body: screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            label: 'Hộp thư AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.face_retouching_natural),
            label: 'Thử Mày/Môi',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month),
            label: 'Ca & Lịch',
          ),
          NavigationDestination(
            icon: Icon(Icons.admin_panel_settings),
            label: 'Chủ tiệm',
          ),
        ],
      ),
    );
  }
}

class AiTriageInboxScreen extends StatefulWidget {
  final InboxService inboxService;

  const AiTriageInboxScreen({
    super.key,
    required this.inboxService,
  });

  @override
  State<AiTriageInboxScreen> createState() => _AiTriageInboxScreenState();
}

class _AiTriageInboxScreenState extends State<AiTriageInboxScreen> {
  static const List<Map<String, dynamic>> _demoChats = [
    {
      'id': 'demo-1',
      'psid': 'DEMO_PSID_MINH_THU',
      'name': 'Chị Minh Thư (FB)',
      'tag': 'CA KHÓ / SỬA MÀY',
      'tagType': 'urgent',
      'summary':
          'Từng làm mày nơi khác bị trổ xanh, cần hút màu và làm sợi mới gấp.',
      'imageUrl': '',
      'aiSuggestion':
          'Dạ chị Thư ơi, bên em chuyên xử lý nền mày trổ xanh bằng công nghệ Laser kết hợp đi sợi Hairstroke tự nhiên. Chị gửi em xin ảnh cận chân mày hiện tại để chuyên gia bên em lên phác đồ cho mình nhé!',
    },
    {
      'id': 'demo-2',
      'psid': 'DEMO_PSID_THANH_TRUC',
      'name': 'Thanh Trúc (Zalo)',
      'tag': 'ĐÃ THỬ MẪU MÔI',
      'tagType': 'lead',
      'summary':
          'Đã chọn mẫu Môi Cam Đào #02, hỏi lịch trống chiều nay lúc 15h.',
      'imageUrl': '',
      'aiSuggestion':
          'Dạ mẫu Môi Cam Đào #02 rất tôn da chị Trúc ạ! Chiều nay 15h bên em còn trống lịch chuyên viên trưởng, em giữ chỗ cho chị nhé?',
    },
  ];

  List<Map<String, dynamic>> _chats = _demoChats;
  bool _isLoading = false;
  bool _isLiveMode = false;
  String? _statusBanner;
  final Set<String> _sendingIds = <String>{};
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _refreshMessages();
    _startPollingIfConfigured();
  }

  @override
  void didUpdateWidget(covariant AiTriageInboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inboxService.webhookBaseUrl !=
            widget.inboxService.webhookBaseUrl ||
        oldWidget.inboxService.webhookApiKey !=
            widget.inboxService.webhookApiKey) {
      _refreshMessages();
      _startPollingIfConfigured();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPollingIfConfigured() {
    _pollTimer?.cancel();
    if (widget.inboxService.hasWebhookConfig ||
        widget.inboxService.hasSupabaseRestConfig) {
      _pollTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _refreshMessages(silent: true),
      );
    }
  }

  Color _colorForTagType(String? tagType) {
    switch (tagType) {
      case 'urgent':
        return Colors.red;
      case 'image':
        return Colors.purple;
      case 'lead':
        return Colors.orange;
      case 'replied':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  Future<void> _refreshMessages({bool silent = false}) async {
    if (!widget.inboxService.hasWebhookConfig &&
        !widget.inboxService.hasSupabaseRestConfig) {
      if (mounted) {
        setState(() {
          _chats = _demoChats;
          _isLiveMode = false;
          _statusBanner =
              'Đang hiển thị dữ liệu mẫu. Nhập URL & API Key của Meta Webhook trong mục "Chủ tiệm" để nhận tin nhắn thật.';
        });
      }
      return;
    }

    if (!silent && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final liveChats = await widget.inboxService.fetchMessages();
      if (!mounted) return;
      setState(() {
        _isLiveMode = true;
        if (liveChats.isNotEmpty) {
          _chats = liveChats;
          _statusBanner =
              'Đang đồng bộ trực tiếp (${liveChats.length} tin nhắn gần nhất).';
        } else {
          _chats = _demoChats;
          _statusBanner =
              'Đã kết nối backend nhưng chưa có tin nhắn mới trong Supabase (đang hiển thị mẫu).';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusBanner = 'Lỗi đồng bộ: $e';
      });
    } finally {
      if (!silent && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _editAndSend(Map<String, dynamic> chat) async {
    final controller = TextEditingController(
      text: (chat['aiSuggestion'] ?? '').toString(),
    );
    final psid = (chat['psid'] ?? '').toString();
    final chatId = (chat['id'] ?? psid).toString();

    final approvedText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Duyệt & gửi cho ${chat['name']}'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Nội dung phản hồi (nhân viên duyệt)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            icon: const Icon(Icons.send, size: 16),
            label: const Text('Xác nhận gửi'),
          ),
        ],
      ),
    );

    if (approvedText == null || approvedText.isEmpty) return;

    setState(() => _sendingIds.add(chatId));
    try {
      await widget.inboxService.sendMessage(
        recipientId: psid,
        text: approvedText,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã gửi phản hồi cho ${chat['name']}!')),
      );
      await _refreshMessages(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) {
        setState(() => _sendingIds.remove(chatId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sàng lọc AI (Meta & Zalo)'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : () => _refreshMessages(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới hộp thư',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading) const LinearProgressIndicator(),
          if (_statusBanner != null)
            Container(
              width: double.infinity,
              color: _isLiveMode ? Colors.green.shade50 : Colors.amber.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                _statusBanner!,
                style: TextStyle(
                  fontSize: 12,
                  color: _isLiveMode
                      ? Colors.green.shade900
                      : Colors.amber.shade900,
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshMessages,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _chats.length,
                itemBuilder: (context, index) {
                  final chat = _chats[index];
                  final tagColor =
                      _colorForTagType(chat['tagType']?.toString());
                  final imageUrl = (chat['imageUrl'] ?? '').toString();
                  final chatId =
                      (chat['id'] ?? chat['psid'] ?? '$index').toString();
                  final isSending = _sendingIds.contains(chatId);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  (chat['name'] ?? 'Khách hàng').toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: tagColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  (chat['tag'] ?? 'MỚI').toString(),
                                  style: TextStyle(
                                    color: tagColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Nội dung: ${chat['summary']}',
                            style: const TextStyle(color: Colors.black87),
                          ),
                          if (imageUrl.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                imageUrl,
                                height: 160,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Text(
                                  'Không tải được ảnh đính kèm.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const Divider(),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.pink.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '✨ Gợi ý chốt đơn chuẩn giọng Chủ tiệm:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.pink,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  (chat['aiSuggestion'] ?? '').toString(),
                                  style: const TextStyle(fontSize: 13),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton.icon(
                                    onPressed: isSending
                                        ? null
                                        : () => _editAndSend(chat),
                                    icon: isSending
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.send, size: 16),
                                    label: Text(
                                      isSending
                                          ? 'Đang gửi...'
                                          : 'Duyệt & Gửi cho khách',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ShiftAndBookingScreen extends StatelessWidget {
  const ShiftAndBookingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ca trực & Lịch hẹn hôm nay')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text(
              'Trạng thái Ca trực của bạn',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Bật để hệ thống tự động chia khách từ Meta & Zalo',
            ),
            value: true,
            onChanged: (val) {},
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.schedule, color: Colors.pink),
            title: Text('14:30 - Chị Lan Anh (0909xxxxxx)'),
            subtitle: Text(
              'Dịch vụ: Mày Hairstroke Nâu Tây • Thợ: Master Linh',
            ),
            trailing: Chip(label: Text('Đã chốt')),
          ),
        ],
      ),
    );
  }
}

class OwnerSettingsScreen extends StatefulWidget {
  final String initialWebhookUrl;
  final String initialWebhookKey;
  final void Function({
    required String webhookUrl,
    required String webhookKey,
  }) onSaveConfig;

  const OwnerSettingsScreen({
    super.key,
    required this.initialWebhookUrl,
    required this.initialWebhookKey,
    required this.onSaveConfig,
  });

  @override
  State<OwnerSettingsScreen> createState() => _OwnerSettingsScreenState();
}

class _OwnerSettingsScreenState extends State<OwnerSettingsScreen> {
  late final TextEditingController _webhookUrlController;
  late final TextEditingController _webhookKeyController;

  @override
  void initState() {
    super.initState();
    _webhookUrlController =
        TextEditingController(text: widget.initialWebhookUrl);
    _webhookKeyController =
        TextEditingController(text: widget.initialWebhookKey);
  }

  @override
  void dispose() {
    _webhookUrlController.dispose();
    _webhookKeyController.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSaveConfig(
      webhookUrl: _webhookUrlController.text,
      webhookKey: _webhookKeyController.text,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã lưu cấu hình Meta Webhook cho Hộp thư AI!'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cấu hình Chủ tiệm')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'URL Meta Webhook Backend (Render):',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _webhookUrlController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'VD: https://pyincc-meta-webhook.onrender.com',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Webhook API Key (x-api-key):',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _webhookKeyController,
              obscureText: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Nhập API_KEY cấu hình trên Render',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Kịch bản & Bảng giá để Gemini đóng vai Chủ tiệm:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const TextField(
              maxLines: 4,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                hintText:
                    'VD: Mày sợi 3tr5, Môi collagen 4tr. Ca khó sửa mày cũ báo chủ tiệm duyệt...',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              child: const Text('Lưu cấu hình hệ thống'),
            ),
          ],
        ),
      ),
    );
  }
}
