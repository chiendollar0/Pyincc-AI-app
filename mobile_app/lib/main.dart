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

  late final InboxService _inboxService = InboxService(
    webhookBaseUrl: const String.fromEnvironment(
      'WEBHOOK_API_URL',
      defaultValue: InboxService.defaultBackendUrl,
    ),
    supabaseUrl: const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'https://ihufvqrxdswgbagzhydb.supabase.co',
    ),
    supabaseAnonKey: const String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: '',
    ),
  );

  final String _tryOnApiUrl = const String.fromEnvironment(
    'TRYON_API_URL',
    defaultValue: InboxService.defaultBackendUrl,
  );

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      AiTriageInboxScreen(inboxService: _inboxService),
      TryOnStudioScreen(apiBaseUrl: _tryOnApiUrl),
      const ShiftAndBookingScreen(),
      OwnerSettingsScreen(inboxService: _inboxService),
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
    _pollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshMessages(silent: true),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
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
    if (!silent && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final liveChats = await widget.inboxService.fetchMessages();
      if (!mounted) return;
      setState(() {
        _isLiveMode = liveChats.isNotEmpty;
        if (liveChats.isNotEmpty) {
          _chats = liveChats;
          _statusBanner =
              'Đang đồng bộ trực tiếp (${liveChats.length} tin nhắn gần nhất).';
        } else {
          _chats = _demoChats;
          _statusBanner = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _chats = _demoChats;
        _isLiveMode = false;
        _statusBanner = null;
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
  final InboxService inboxService;

  const OwnerSettingsScreen({
    super.key,
    required this.inboxService,
  });

  @override
  State<OwnerSettingsScreen> createState() => _OwnerSettingsScreenState();
}

class _OwnerSettingsScreenState extends State<OwnerSettingsScreen> {
  List<Map<String, dynamic>> _connectedPages = const [];
  bool _isCheckingPages = false;

  @override
  void initState() {
    super.initState();
    _loadConnectedPages();
  }

  Future<void> _loadConnectedPages() async {
    setState(() => _isCheckingPages = true);
    try {
      final pages = await widget.inboxService.fetchConnectedPages();
      if (!mounted) return;
      setState(() => _connectedPages = pages);
    } finally {
      if (mounted) {
        setState(() => _isCheckingPages = false);
      }
    }
  }

  Future<void> _onTapConnectFacebook() async {
    await _loadConnectedPages();
    if (!mounted) return;

    if (_connectedPages.isNotEmpty) {
      final names = _connectedPages
          .map((p) => (p['page_name'] ?? p['page_id']).toString())
          .join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã kết nối tự động với Fanpage: $names'),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kết nối với Facebook'),
        content: const Text(
          'Hệ thống sẽ chuyển sang đăng nhập Facebook của bạn và tự động liên kết Fanpage của tiệm (không cần nhập bất kỳ mã khóa nào).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Đóng'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _loadConnectedPages();
            },
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Đã đăng nhập xong'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _connectedPages.isNotEmpty;
    final connectedLabel = isConnected
        ? _connectedPages
            .map((p) => (p['page_name'] ?? p['page_id']).toString())
            .join(', ')
        : 'Chưa kết nối Fanpage';

    return Scaffold(
      appBar: AppBar(title: const Text('Chủ tiệm')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isConnected
                              ? Icons.verified
                              : Icons.facebook_outlined,
                          color: isConnected ? Colors.green : Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isConnected
                                ? 'Đã liên kết: $connectedLabel'
                                : 'Liên kết Fanpage của tiệm',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Chỉ cần đăng nhập tài khoản Facebook quản lý Fanpage. Máy chủ sẽ tự động đồng bộ tin nhắn và gửi phản hồi khi bạn duyệt.',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed:
                          _isCheckingPages ? null : _onTapConnectFacebook,
                      icon: const Icon(Icons.facebook),
                      label: Text(
                        isConnected
                            ? 'Làm mới kết nối Facebook'
                            : 'Kết nối với Facebook',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1877F2),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Kịch bản & Bảng giá để AI đóng vai Chủ tiệm:',
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
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã lưu kịch bản tư vấn của Chủ tiệm!'),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              child: const Text('Lưu kịch bản tư vấn'),
            ),
          ],
        ),
      ),
    );
  }
}
