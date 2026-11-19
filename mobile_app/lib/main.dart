// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/material.dart';

import 'core/errors/user_message.dart';
import 'core/theme/app_theme.dart';
import 'screens/tryon/tryon_studio_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/facebook_connect_service.dart';
import 'services/inbox_service.dart';

void main() {
  runApp(const BeautyCrmApp());
}

class BeautyCrmApp extends StatefulWidget {
  final String? initialAuthToken;

  const BeautyCrmApp({
    super.key,
    this.initialAuthToken,
  });

  @override
  State<BeautyCrmApp> createState() => _BeautyCrmAppState();
}

class _BeautyCrmAppState extends State<BeautyCrmApp> {
  static const String _supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ihufvqrxdswgbagzhydb.supabase.co',
  );
  static const String _supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  final AuthService _authService = const AuthService(
    supabaseUrl: _supabaseUrl,
    supabaseAnonKey: _supabaseAnonKey,
  );

  late String _accessToken = (widget.initialAuthToken ??
          const String.fromEnvironment('BACKEND_AUTH_TOKEN', defaultValue: ''))
      .trim();

  bool get _isSignedIn => _accessToken.isNotEmpty;

  void _onSignedIn(AuthSession session) {
    setState(() {
      _accessToken = session.accessToken.trim();
    });
  }

  Future<void> _onSignOut() async {
    final tokenToRevoke = _accessToken;
    setState(() {
      _accessToken = '';
    });
    await _authService.signOut(tokenToRevoke);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pyincc AI CRM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: _isSignedIn
          ? MainDashboardScreen(
              authToken: _accessToken,
              onSignOut: _onSignOut,
            )
          : LoginScreen(
              authService: _authService,
              onSignedIn: _onSignedIn,
            ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final AuthService authService;
  final void Function(AuthSession session) onSignedIn;

  const LoginScreen({
    super.key,
    required this.authService,
    required this.onSignedIn,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorText;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      final session = await widget.authService.signInWithPassword(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      widget.onSignedIn(session);
    } catch (error) {
      if (!mounted) return;
      final friendly = userMessage(error);
      setState(() => _errorText = friendly);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/brand/hero.png',
                            width: 112,
                            height: 112,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.spa_outlined,
                              size: 56,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Pyincc AI CRM',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Đăng nhập bằng tài khoản Chủ tiệm hoặc Nhân viên đã được cấp quyền.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 22),
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Email đăng nhập',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _isLoading ? null : _submitLogin(),
                        decoration: InputDecoration(
                          labelText: 'Mật khẩu',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Hiện mật khẩu'
                                : 'Ẩn mật khẩu',
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                      ),
                      if (_errorText != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _errorText!,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _isLoading ? null : _submitLogin,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(
                          _isLoading ? 'Đang đăng nhập...' : 'Đăng nhập',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MainDashboardScreen extends StatefulWidget {
  final String authToken;
  final VoidCallback? onSignOut;

  const MainDashboardScreen({
    super.key,
    this.authToken = '',
    this.onSignOut,
  });

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  static const String _tryOnApiUrl = String.fromEnvironment(
    'TRYON_API_URL',
    defaultValue: '',
  );
  static const String _webhookApiUrl = String.fromEnvironment(
    'WEBHOOK_API_URL',
    defaultValue: '',
  );
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String _firstNonEmpty(List<String> candidates, String fallback) {
    for (final raw in candidates) {
      final trimmed = raw.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return fallback;
  }

  int _selectedIndex = 0;

  late final InboxService _inboxService = InboxService(
    webhookBaseUrl: _firstNonEmpty(
      const [_tryOnApiUrl, _webhookApiUrl, _apiBaseUrl],
      InboxService.defaultBackendUrl,
    ),
    supabaseUrl: const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'https://ihufvqrxdswgbagzhydb.supabase.co',
    ),
    supabaseAnonKey: const String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: '',
    ),
    authToken: widget.authToken,
  );

  late final String _studioApiBaseUrl = _firstNonEmpty(
    const [_tryOnApiUrl, _apiBaseUrl, _webhookApiUrl],
    InboxService.defaultBackendUrl,
  );

  String? _activeTryOnPsid;
  String? _activeTryOnCustomerName;
  String? _activeTryOnPageId;

  void _openTryOnTab({
    String? psid,
    String? customerName,
    String? pageId,
  }) {
    setState(() {
      _activeTryOnPsid = psid;
      _activeTryOnCustomerName = customerName;
      _activeTryOnPageId = (pageId ?? '').trim().isNotEmpty ? pageId!.trim() : null;
      _selectedIndex = 1;
    });
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
            onSignOut: widget.onSignOut,
          ),
          TryOnStudioScreen(
            apiBaseUrl: _studioApiBaseUrl,
            authToken: widget.authToken,
            customerPsid: _activeTryOnPsid,
            customerName: _activeTryOnCustomerName,
            pageId: _activeTryOnPageId,
            onSignOut: widget.onSignOut,
          ),
          SalonOperationsHubScreen(
            inboxService: _inboxService,
            onSignOut: widget.onSignOut,
          ),
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
            label: 'Quản lý tiệm',
          ),
        ],
      ),
    );
  }
}

class AiTriageInboxScreen extends StatefulWidget {
  final InboxService inboxService;
  final void Function({
    String? psid,
    String? customerName,
    String? pageId,
  }) onOpenTryOn;
  final VoidCallback? onSignOut;

  const AiTriageInboxScreen({
    super.key,
    required this.inboxService,
    required this.onOpenTryOn,
    this.onSignOut,
  });

  @override
  State<AiTriageInboxScreen> createState() => _AiTriageInboxScreenState();
}

class _AiTriageInboxScreenState extends State<AiTriageInboxScreen> {
  List<Map<String, dynamic>> _chats = const [];
  String _selectedFilter = 'all';
  bool _isLoading = true;
  String? _loadError;
  final Set<String> _sendingIds = <String>{};
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _refreshMessages();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 20),
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
        return AppColors.danger;
      case 'image':
        return Colors.purple;
      case 'lead':
        return Colors.orange.shade800;
      case 'replied':
        return AppColors.success;
      default:
        return AppColors.primary;
    }
  }

  Future<void> _refreshMessages({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final liveChats = await widget.inboxService.fetchMessages();
      if (!mounted) return;
      setState(() {
        _chats = liveChats;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      if (!silent || _chats.isEmpty) {
        setState(() {
          _loadError = userMessage(error);
        });
      }
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
        messageRecordId: chatId,
        recipientId: psid,
        text: approvedText,
      );
      if (!mounted) return;
      showAppMessage(context, 'Đã gửi phản hồi cho ${chat['name']}.');
      await _refreshMessages(silent: true);
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, userMessage(error), isError: true);
    } finally {
      if (mounted) {
        setState(() => _sendingIds.remove(chatId));
      }
    }
  }

  Widget _buildBody() {
    if (_isLoading && _chats.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _chats.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Chưa tải được dữ liệu',
        message: _loadError,
        onRetry: _refreshMessages,
      );
    }
    if (_chats.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshMessages,
        child: ListView(
          children: const [
            SizedBox(height: 48),
            EmptyState(
              icon: Icons.inbox_outlined,
              title: 'Chưa có hội thoại',
              message: 'Hội thoại mới sẽ hiện ở đây.',
            ),
          ],
        ),
      );
    }

    final visibleChats = _filteredChats;
    if (visibleChats.isEmpty) {
      return const EmptyState(
        icon: Icons.filter_list_off,
        title: 'Không có hội thoại phù hợp',
        message: 'Hãy chọn mục lọc khác để xem danh sách hội thoại.',
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshMessages,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: visibleChats.length,
        itemBuilder: (context, index) {
          final chat = visibleChats[index];
          final tagColor = _colorForTagType(chat['tagType']?.toString());
          final imageUrl = (chat['imageUrl'] ?? '').toString();
          final chatId = (chat['id'] ?? chat['psid'] ?? '$index').toString();
          final isSending = _sendingIds.contains(chatId);

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
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
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: tagColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          (chat['tag'] ?? 'MỚI').toString(),
                          style: TextStyle(
                            color: tagColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Khách nhắn: ${chat['summary']}',
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  if (imageUrl.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        imageUrl,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Text(
                          'Không tải được ảnh đính kèm.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const Divider(height: 18),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Gợi ý phản hồi từ AI (cần nhân viên duyệt):',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (chat['aiSuggestion'] ?? '').toString(),
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => widget.onOpenTryOn(
                                psid: (chat['psid'] ?? '').toString(),
                                customerName: (chat['name'] ?? '').toString(),
                                pageId: (chat['pageId'] ?? '').toString(),
                              ),
                              icon: const Icon(
                                Icons.face_retouching_natural,
                                size: 16,
                              ),
                              label: const Text('Thử mẫu AI'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed:
                                  isSending ? null : () => _editAndSend(chat),
                              icon: isSending
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.send, size: 16),
                              label: Text(
                                isSending ? 'Đang gửi...' : 'Duyệt & Gửi',
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            BrandHeader(
              subtitle: 'Hộp thư AI',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: _isLoading ? null : () => _refreshMessages(),
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Đồng bộ tin nhắn',
                  ),
                  if (widget.onSignOut != null)
                    IconButton(
                      onPressed: widget.onSignOut,
                      icon: const Icon(Icons.logout),
                      tooltip: 'Đăng xuất',
                    ),
                ],
              ),
            ),
            if (_isLoading && _chats.isNotEmpty)
              const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Row(
                children: [
                  _KpiStatBadge(
                    label: 'Tổng hội thoại',
                    value: '${_chats.length}',
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  _KpiStatBadge(
                    label: 'Ca khó / Sửa',
                    value: '${_countByType('urgent')}',
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: 8),
                  _KpiStatBadge(
                    label: 'Hỏi giá / Lịch',
                    value: '${_countByType('lead')}',
                    color: Colors.orange.shade800,
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
            Expanded(child: _buildBody()),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: color,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class SalonOperationsHubScreen extends StatefulWidget {
  final InboxService inboxService;
  final VoidCallback? onSignOut;

  const SalonOperationsHubScreen({
    super.key,
    required this.inboxService,
    this.onSignOut,
  });

  @override
  State<SalonOperationsHubScreen> createState() =>
      _SalonOperationsHubScreenState();
}

class _SalonOperationsHubScreenState extends State<SalonOperationsHubScreen> {
  int _subTab = 0;
  bool _onDuty = true;
  bool _isLoadingOps = true;
  String? _opsError;
  bool _isSavingSettings = false;
  bool _isConnectingFacebook = false;
  List<Map<String, dynamic>> _connectedPages = const [];
  List<Map<String, String>> _bookings = const [];
  final TextEditingController _scriptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _scriptController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoadingOps = true;
      _opsError = null;
    });
    try {
      final results = await Future.wait([
        widget.inboxService.fetchSettings(),
        widget.inboxService.fetchBookings(),
        widget.inboxService.fetchConnectedPages(),
      ]);
      if (!mounted) return;
      final settings = results[0] as Map<String, dynamic>;
      final bookings = results[1] as List<Map<String, String>>;
      final pages = results[2] as List<Map<String, dynamic>>;

      setState(() {
        if (settings['onDuty'] is bool) {
          _onDuty = settings['onDuty'] as bool;
        }
        final script = (settings['consultationScript'] ?? '').toString().trim();
        if (script.isNotEmpty && _scriptController.text.isEmpty) {
          _scriptController.text = script;
        }
        _bookings = bookings;
        _connectedPages = pages;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _opsError = userMessage(error);
      });
    } finally {
      if (mounted) setState(() => _isLoadingOps = false);
    }
  }

  Future<void> _toggleDutyStatus(bool value) async {
    final previous = _onDuty;
    setState(() => _onDuty = value);
    try {
      await widget.inboxService.saveSettings(onDuty: value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _onDuty = previous);
      showAppMessage(context, userMessage(error), isError: true);
    }
  }

  Future<void> _saveConsultationScript() async {
    setState(() => _isSavingSettings = true);
    try {
      await widget.inboxService.saveSettings(
        onDuty: _onDuty,
        consultationScript: _scriptController.text,
      );
      if (!mounted) return;
      showAppMessage(context, 'Đã lưu kịch bản & bảng giá lên máy chủ.');
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, userMessage(error), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSavingSettings = false);
      }
    }
  }

  Future<void> _onTapConnectFacebook() async {
    setState(() => _isConnectingFacebook = true);
    try {
      final connector = FacebookConnectService(widget.inboxService.apiClient);
      final pages = await connector.connect();
      if (!mounted) return;
      setState(() => _connectedPages = pages);
      showAppMessage(context, 'Đã kết nối ${pages.length} Fanpage.');
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        error.status == 403
            ? 'Tài khoản chưa được cấp quyền quản lý tiệm.'
            : userMessage(error),
        isError: true,
      );
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, userMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _isConnectingFacebook = false);
    }
  }

  Future<void> _addQuickBookingDialog() async {
    final nameCtrl = TextEditingController();
    final timeCtrl = TextEditingController(text: '17:30');
    final serviceCtrl =
        TextEditingController(text: 'Môi Collagen Cam Đào');

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
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tên & SĐT khách hàng',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: serviceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Dịch vụ & Kỹ thuật viên',
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
      try {
        final saved = await widget.inboxService.createBooking(
          time: timeCtrl.text.trim(),
          customerName: nameCtrl.text.trim(),
          serviceName: serviceCtrl.text.trim(),
        );
        if (!mounted) return;
        setState(() => _bookings = [saved, ..._bookings]);
        showAppMessage(context, 'Đã lưu lịch hẹn lên máy chủ.');
      } catch (error) {
        if (!mounted) return;
        showAppMessage(context, userMessage(error), isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            BrandHeader(
              subtitle: 'Quản lý tiệm',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_subTab == 0)
                    IconButton(
                      onPressed: _addQuickBookingDialog,
                      icon: const Icon(Icons.add_alarm),
                      tooltip: 'Thêm lịch hẹn',
                    ),
                  if (widget.onSignOut != null)
                    IconButton(
                      onPressed: widget.onSignOut,
                      icon: const Icon(Icons.logout),
                      tooltip: 'Đăng xuất',
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
    if (_isLoadingOps && _bookings.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_opsError != null && _bookings.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Chưa tải được lịch hẹn',
        message: _opsError,
        onRetry: _loadAllData,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile(
              title: const Text(
                'Trạng thái Ca trực nhận khách AI',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                _onDuty
                    ? 'Đang bật: Hệ thống tự động phân khách mới cho ca trực'
                    : 'Đang tạm nghỉ: Chuyển khách cho nhân viên ca kế tiếp',
              ),
              value: _onDuty,
              onChanged: _toggleDutyStatus,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Lịch hẹn hôm nay (${_bookings.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
              TextButton.icon(
                onPressed: _addQuickBookingDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Đặt lịch mới'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_bookings.isEmpty)
            const EmptyState(
              icon: Icons.event_available_outlined,
              title: 'Chưa có lịch hẹn',
              message: 'Bấm "Đặt lịch mới" để thêm lịch hẹn cho khách.',
            )
          else
            for (final item in _bookings)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: const Icon(Icons.schedule, color: AppColors.primary),
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
      ),
    );
  }

  Widget _buildOwnerSettingsSubView() {
    final isConnected = _connectedPages.isNotEmpty;
    final connectedLabel = isConnected
        ? _connectedPages
            .map((p) => (p['name'] ?? p['page_name'] ?? p['id'] ?? p['page_id']).toString())
            .join(', ')
        : 'Chưa kết nối Fanpage';

    return SingleChildScrollView(
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
                        isConnected ? Icons.verified : Icons.facebook_outlined,
                        color: isConnected
                            ? AppColors.success
                            : const Color(0xFF1877F2),
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
                    'Chủ tiệm chỉ cần bấm nút bên dưới để đăng nhập Facebook. Ứng dụng không lưu khóa Fanpage; toàn bộ quyền truy cập được mã hóa an toàn trên máy chủ.',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed:
                        _isConnectingFacebook ? null : _onTapConnectFacebook,
                    icon: _isConnectingFacebook
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.facebook),
                    label: Text(
                      _isConnectingFacebook
                          ? 'Đang kết nối...'
                          : (isConnected
                              ? 'Làm mới kết nối Facebook'
                              : 'Kết nối với Facebook'),
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
          const SizedBox(height: 12),
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
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _scriptController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText:
                          'VD: Mày sợi Hairstroke 3tr5, Môi Collagen 4tr. Ca khó sửa mày trổ xanh/đỏ cần xin ảnh cận mặt để chuyên gia lên phác đồ...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed:
                        _isSavingSettings ? null : _saveConsultationScript,
                    icon: const Icon(Icons.save_outlined),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    label: Text(
                      _isSavingSettings
                          ? 'Đang lưu...'
                          : 'Lưu kịch bản & bảng giá',
                    ),
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
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.14)
          : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? AppColors.primaryDark : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                    fontSize: 13,
                    color: selected
                        ? AppColors.primaryDark
                        : AppColors.textPrimary,
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
