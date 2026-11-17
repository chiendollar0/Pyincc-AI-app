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
      title: 'PYINCC AI Beauty Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD81B60)),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
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

  void _openTryOnTab() {
    setState(() => _selectedIndex = 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          AiTriageInboxScreen(
            inboxService: _inboxService,
            onOpenTryOn: _openTryOnTab,
          ),
          TryOnStudioScreen(apiBaseUrl: _tryOnApiUrl),
          SalonOperationsHubScreen(inboxService: _inboxService),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum),
            label: 'Hộp thư AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.face_retouching_natural_outlined),
            selectedIcon: Icon(Icons.face_retouching_natural),
            label: 'Studio AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Quản lý Tiệm',
          ),
        ],
      ),
    );
  }
}

class AiTriageInboxScreen extends StatefulWidget {
  final InboxService inboxService;
  final VoidCallback onOpenTryOn;

  const AiTriageInboxScreen({
    super.key,
    required this.inboxService,
    required this.onOpenTryOn,
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
      'tag': 'HỎI GIÁ / ĐẶT LỊCH',
      'tagType': 'lead',
      'summary':
          'Đã chọn mẫu Môi Cam Đào #02, hỏi lịch trống chiều nay lúc 15h.',
      'imageUrl': '',
      'aiSuggestion':
          'Dạ mẫu Môi Cam Đào #02 rất tôn da chị Trúc ạ! Chiều nay 15h bên em còn trống lịch chuyên viên trưởng, em giữ chỗ cho chị nhé?',
    },
  ];

  List<Map<String, dynamic>> _chats = _demoChats;
  String _selectedFilter = 'all';
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

  List<Map<String, dynamic>> get _filteredChats {
    if (_selectedFilter == 'all') return _chats;
    return _chats
        .where((c) => (c['tagType'] ?? 'normal') == _selectedFilter)
        .toList();
  }

  int _countByType(String type) {
    return _chats.where((c) => (c['tagType'] ?? '') == type).length;
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
              'Đang đồng bộ trực tiếp (${liveChats.length} hội thoại gần nhất).';
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
    final visibleChats = _filteredChats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trung tâm CSKH AI'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : () => _refreshMessages(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Đồng bộ tin nhắn',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_isLoading) const LinearProgressIndicator(),
            if (_statusBanner != null)
              Container(
                width: double.infinity,
                color:
                    _isLiveMode ? Colors.green.shade50 : Colors.amber.shade50,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

            // Thanh thống kê nhanh (KPI Strip)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  _KpiStatBadge(
                    label: 'Tổng hội thoại',
                    value: '${_chats.length}',
                    color: Colors.pink,
                  ),
                  const SizedBox(width: 8),
                  _KpiStatBadge(
                    label: 'Ca khó / Sửa',
                    value: '${_countByType('urgent')}',
                    color: Colors.red,
                  ),
                  const SizedBox(width: 8),
                  _KpiStatBadge(
                    label: 'Hỏi giá / Lịch',
                    value: '${_countByType('lead')}',
                    color: Colors.orange,
                  ),
                ],
              ),
            ),

            // Bộ lọc nhanh theo phân loại AI
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _buildFilterChip('all', 'Tất cả (${_chats.length})'),
                  _buildFilterChip(
                    'urgent',
                    'Ca khó (${_countByType('urgent')})',
                  ),
                  _buildFilterChip(
                    'lead',
                    'Hỏi giá & Lịch (${_countByType('lead')})',
                  ),
                  _buildFilterChip(
                    'image',
                    'Gửi ảnh (${_countByType('image')})',
                  ),
                  _buildFilterChip(
                    'replied',
                    'Đã trả lời (${_countByType('replied')})',
                  ),
                ],
              ),
            ),

            // Danh sách hội thoại
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshMessages,
                child: visibleChats.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 80),
                          Center(
                            child: Text(
                              'Không có hội thoại nào trong mục lọc này.',
                              style: TextStyle(color: Colors.black54),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: visibleChats.length,
                        itemBuilder: (context, index) {
                          final chat = visibleChats[index];
                          final tagColor =
                              _colorForTagType(chat['tagType']?.toString());
                          final imageUrl =
                              (chat['imageUrl'] ?? '').toString();
                          final chatId =
                              (chat['id'] ?? chat['psid'] ?? '$index')
                                  .toString();
                          final isSending = _sendingIds.contains(chatId);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          (chat['name'] ?? 'Khách hàng')
                                              .toString(),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
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
                                          borderRadius:
                                              BorderRadius.circular(8),
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
                                    'Khách nhắn: ${chat['summary']}',
                                    style:
                                        const TextStyle(color: Colors.black87),
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
                                        errorBuilder: (_, __, ___) =>
                                            const Text(
                                          'Không tải được ảnh đính kèm.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  const Divider(height: 18),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.pink.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '✨ Gợi ý phản hồi chuẩn giọng Chủ tiệm:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: Colors.pink,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          (chat['aiSuggestion'] ?? '')
                                              .toString(),
                                          style:
                                              const TextStyle(fontSize: 13),
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            OutlinedButton.icon(
                                              onPressed: widget.onOpenTryOn,
                                              icon: const Icon(
                                                Icons.face_retouching_natural,
                                                size: 16,
                                              ),
                                              label: const Text('Thử mẫu AI'),
                                            ),
                                            const SizedBox(width: 8),
                                            FilledButton.icon(
                                              onPressed: isSending
                                                  ? null
                                                  : () => _editAndSend(chat),
                                              icon: isSending
                                                  ? const SizedBox(
                                                      width: 14,
                                                      height: 14,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    )
                                                  : const Icon(
                                                      Icons.send,
                                                      size: 16,
                                                    ),
                                              label: Text(
                                                isSending
                                                    ? 'Đang gửi...'
                                                    : 'Duyệt & Gửi',
                                              ),
                                            ),
                                          ],
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
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _selectedFilter == value,
        onSelected: (_) => setState(() => _selectedFilter = value),
      ),
    );
  }
}

class _KpiStatBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _KpiStatBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: color,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab 3 gộp gọn: Ca trực & Lịch hẹn + Cấu hình Chủ tiệm & Kết nối Facebook
class SalonOperationsHubScreen extends StatefulWidget {
  final InboxService inboxService;

  const SalonOperationsHubScreen({
    super.key,
    required this.inboxService,
  });

  @override
  State<SalonOperationsHubScreen> createState() =>
      _SalonOperationsHubScreenState();
}

class _SalonOperationsHubScreenState extends State<SalonOperationsHubScreen> {
  int _subTab = 0; // 0: Lịch & Ca trực, 1: Chủ tiệm & Kết nối
  bool _onDuty = true;
  List<Map<String, dynamic>> _connectedPages = const [];
  bool _isCheckingPages = false;

  final List<Map<String, String>> _bookings = [
    {
      'time': '14:30',
      'customer': 'Chị Lan Anh (0909xxxxxx)',
      'service': 'Mày Hairstroke Nâu Tây • Master Linh',
      'status': 'Đã chốt',
    },
    {
      'time': '16:00',
      'customer': 'Chị Minh Thư (FB)',
      'service': 'Xử lý mày trổ xanh + Đi sợi • Master Linh',
      'status': 'Chờ xác nhận',
    },
  ];

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

  Future<void> _addQuickBookingDialog() async {
    final nameCtrl = TextEditingController();
    final timeCtrl = TextEditingController(text: '17:30');
    final serviceCtrl =
        TextEditingController(text: 'Môi Collagen Cam Đào • Master Linh');

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tạo lịch hẹn mới'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: timeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Giờ hẹn (VD: 17:30)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tên & SĐT khách hàng',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: serviceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Dịch vụ & Kỹ thuật viên',
                  border: OutlineInputBorder(),
                ),
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
            child: const Text('Lưu lịch hẹn'),
          ),
        ],
      ),
    );

    if (created == true && nameCtrl.text.trim().isNotEmpty) {
      setState(() {
        _bookings.add({
          'time': timeCtrl.text.trim(),
          'customer': nameCtrl.text.trim(),
          'service': serviceCtrl.text.trim(),
          'status': 'Đã chốt',
        });
      });
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
          'Chủ tiệm chỉ cần đăng nhập tài khoản Facebook quản lý Fanpage. Máy chủ sẽ tự động lấy quyền Fanpage và đồng bộ tin nhắn mà không cần nhập bất kỳ mã khóa nào.',
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
            label: const Text('Kiểm tra lại kết nối'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý Vận hành & Tiệm'),
        actions: [
          if (_subTab == 0)
            IconButton(
              onPressed: _addQuickBookingDialog,
              icon: const Icon(Icons.add_alarm),
              tooltip: 'Thêm lịch hẹn',
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Thanh chuyển nhánh gọn trong 1 màn hình
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _SubTabButton(
                      selected: _subTab == 0,
                      icon: Icons.calendar_month,
                      label: 'Ca trực & Lịch hẹn',
                      onTap: () => setState(() => _subTab = 0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SubTabButton(
                      selected: _subTab == 1,
                      icon: Icons.admin_panel_settings,
                      label: 'Kết nối & Chủ tiệm',
                      onTap: () => setState(() => _subTab = 1),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _subTab == 0
                  ? _buildScheduleSubView()
                  : _buildOwnerSettingsSubView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleSubView() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: SwitchListTile(
            title: const Text(
              'Trạng thái Ca trực nhận khách AI',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              _onDuty
                  ? 'Đang bật: Hệ thống tự động phân khách mới từ Messenger & Zalo'
                  : 'Đang tạm nghỉ: Chuyển khách cho nhân viên ca kế tiếp',
            ),
            value: _onDuty,
            onChanged: (val) => setState(() => _onDuty = val),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Lịch hẹn hôm nay (${_bookings.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            TextButton.icon(
              onPressed: _addQuickBookingDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Đặt lịch mới'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final item in _bookings)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.pink.shade50,
                child: const Icon(Icons.schedule, color: Colors.pink),
              ),
              title: Text(
                '${item['time']} - ${item['customer']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(item['service'] ?? ''),
              trailing: Chip(
                label: Text(
                  item['status'] ?? 'Đã chốt',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOwnerSettingsSubView() {
    final isConnected = _connectedPages.isNotEmpty;
    final connectedLabel = isConnected
        ? _connectedPages
            .map((p) => (p['page_name'] ?? p['page_id']).toString())
            .join(', ')
        : 'Chưa kết nối Fanpage';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
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
                        isConnected ? Icons.verified : Icons.facebook_outlined,
                        color: isConnected ? Colors.green : Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isConnected
                              ? 'Đã liên kết: $connectedLabel'
                              : 'Kết nối Fanpage Facebook của tiệm',
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
                    'Chủ tiệm chỉ cần bấm nút bên dưới để đăng nhập Facebook. Hệ thống tự động lấy quyền Fanpage và bảo mật toàn bộ khóa ở máy chủ.',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _isCheckingPages ? null : _onTapConnectFacebook,
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
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kịch bản & Bảng giá chuẩn của Chủ tiệm:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'AI sẽ dựa vào bảng giá và lưu ý này để soạn sẵn câu trả lời cho nhân viên duyệt.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  const TextField(
                    maxLines: 4,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      hintText:
                          'VD: Mày sợi Hairstroke 3tr5, Môi Collagen 4tr. Ca khó sửa mày trổ xanh/đỏ cần xin ảnh cận mặt để Master lên phác đồ...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Đã lưu kịch bản tư vấn chuẩn của Chủ tiệm!',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.save_outlined),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 46),
                    ),
                    label: const Text('Lưu kịch bản & bảng giá'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubTabButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SubTabButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.primaryContainer
          : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? colorScheme.onPrimaryContainer
                    : Colors.black54,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                    color: selected
                        ? colorScheme.onPrimaryContainer
                        : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
