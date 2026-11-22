import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyincc_app/core/errors/api_exception.dart';
import 'package:pyincc_app/core/errors/user_message.dart';
import 'package:pyincc_app/data/crm_repo.dart';
import 'package:pyincc_app/main.dart';
import 'package:pyincc_app/services/api_client.dart';
import 'package:pyincc_app/services/auth_service.dart';
import 'package:pyincc_app/services/session_storage.dart';

class _InMemorySessionStorage extends SessionStorage {
  _InMemorySessionStorage([this._saved]);

  AuthSession? _saved;

  @override
  Future<AuthSession?> read() async => _saved;

  @override
  Future<void> write(AuthSession session) async => _saved = session;

  @override
  Future<void> clear() async => _saved = null;
}

class _FakeCrmRepo extends CrmRepo {
  _FakeCrmRepo({
    this.requireOnboarding = false,
    List<Map<String, dynamic>>? bookingsList,
    List<Map<String, dynamic>>? pagesList,
    List<Map<String, dynamic>>? newCasesList,
    List<Map<String, dynamic>>? logsList,
  })  : _bookings = List<Map<String, dynamic>>.from(bookingsList ?? const []),
        _pages = List<Map<String, dynamic>>.from(pagesList ?? const []),
        _newCases = List<Map<String, dynamic>>.from(newCasesList ?? const []),
        _logs = List<Map<String, dynamic>>.from(logsList ?? const []),
        super(const ApiClient(baseUrl: 'https://test.local'));

  bool requireOnboarding;
  final List<Map<String, dynamic>> _bookings;
  final List<Map<String, dynamic>> _pages;
  final List<Map<String, dynamic>> _newCases;
  final List<Map<String, dynamic>> _logs;
  final List<String> claimedCodes = <String>[];
  final List<String> disconnectedPageIds = <String>[];
  final List<String> analyzedCaseIds = <String>[];
  final List<String> markedFollowupIds = <String>[];

  @override
  Future<Map<String, dynamic>> tenant() async {
    if (requireOnboarding) {
      throw const ApiException(403, 'NO_MEMBERSHIP');
    }
    return {
      'id': 'org-1',
      'name': 'Tiệm Test',
      'specialty': '',
    };
  }

  @override
  Future<Map<String, dynamic>> claimOnboardingCode(String code) async {
    claimedCodes.add(code.trim());
    requireOnboarding = false;
    return {'success': true};
  }

  @override
  Future<Map<String, dynamic>> aiUsage() async => {'used': 2, 'cap': 50};

  @override
  Future<Map<String, dynamic>> connectionStatus() async => {
        'pages': _pages,
        'default_app': null,
        'take_control_enabled': null,
        'handover_subscribed': null,
        'receiving_events': null,
        'last_webhook_at': null,
      };

  @override
  Future<void> disconnectPage(String pageId) async {
    disconnectedPageIds.add(pageId);
    _pages.removeWhere((p) => p['page_id'] == pageId);
  }

  @override
  Future<List<Map<String, dynamic>>> handoffCases(String status) async {
    if (status == 'new') return _newCases;
    return const [];
  }

  @override
  Future<Map<String, dynamic>> analyzeCase(String id) async {
    analyzedCaseIds.add(id);
    return {
      'id': id,
      'status': 'pending_review',
      'analysis': {
        'summary': 'Quan sát mày tự nhiên',
        'draft_reply': 'Dạ em gợi ý dáng mày sợi tự nhiên ạ.',
      },
    };
  }

  @override
  Future<List<Map<String, dynamic>>> auditLogs({int limit = 50}) async => _logs;

  @override
  Future<List<Map<String, dynamic>>> catalog() async => const [];

  @override
  Future<List<Map<String, dynamic>>> bookings() async => _bookings;

  @override
  Future<void> markFollowupDone(String bookingId) async {
    markedFollowupIds.add(bookingId);
    for (final b in _bookings) {
      if (b['id'] == bookingId) {
        b['followup_done'] = true;
        b['follow_up_due'] = null;
      }
    }
  }
}

void main() {
  testWidgets(
    '1. Unauthenticated launch displays LoginScreen, validates empty input, and opens/closes Forgot Password dialog',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const BeautyCrmApp(initialAuthToken: ''));
      await tester.pumpAndSettle();

      expect(find.text('Pyincc AI CRM'), findsOneWidget);
      expect(find.text('Email đăng nhập'), findsOneWidget);
      expect(find.text('Mật khẩu'), findsOneWidget);
      expect(find.text('Quên mật khẩu?'), findsOneWidget);

      await tester.tap(find.text('Đăng nhập'));
      await tester.pumpAndSettle();

      expect(
        find.text('Vui lòng nhập đầy đủ Email và Mật khẩu.'),
        findsOneWidget,
      );
      expect(find.textContaining('API Key'), findsNothing);

      // Open and close Forgot Password dialog safely
      await tester.tap(find.text('Quên mật khẩu?'));
      await tester.pumpAndSettle();
      expect(find.text('Quên mật khẩu'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(find.text('Quên mật khẩu'), findsNothing);
    },
  );

  testWidgets(
    '1b. Persisted auth session auto-restores CrmShell on app restart without forcing login',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final storage = _InMemorySessionStorage(
        AuthSession(
          accessToken: 'persisted-valid-token',
          refreshToken: 'persisted-refresh-token',
          email: 'owner@salon.vn',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      await tester.pumpWidget(
        BeautyCrmApp(
          sessionStorage: storage,
          repoOverride: _FakeCrmRepo(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hộp thư'), findsWidgets);
      expect(find.text('Email đăng nhập'), findsNothing);
    },
  );

  testWidgets(
    '1c. Signed-in user with 403 NO_MEMBERSHIP sees OnboardingClaimScreen and activates salon',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _FakeCrmRepo(requireOnboarding: true);
      await tester.pumpWidget(
        BeautyCrmApp(
          initialAuthToken: 'new-user-token',
          repoOverride: repo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kích hoạt tiệm của bạn'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'SALON-2026-TEST');
      await tester.tap(find.text('Kích hoạt tiệm'));
      await tester.pumpAndSettle();

      expect(repo.claimedCodes, ['SALON-2026-TEST']);
      expect(find.text('Hộp thư'), findsWidgets);
    },
  );

  testWidgets(
    '2a. Inbox supports new handover cases (Phân tích AI + Trả Business AI) and Studio renders empty state',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _FakeCrmRepo(
        newCasesList: [
          {
            'id': 'case-new-1',
            'source': 'business_ai_handover',
            'status': 'new',
            'psid': 'psid-1',
            'page_id': 'page-1',
            'customer_text': 'Khách cần tư vấn mày cũ trổ xanh',
          },
        ],
      );

      await tester.pumpWidget(
        BeautyCrmApp(
          initialAuthToken: 'session-token-for-widget-test',
          repoOverride: repo,
        ),
      );
      await tester.pumpAndSettle();

      // Default tab 0: Hộp thư (pending_review empty)
      expect(find.text('Hộp thư'), findsWidgets);
      expect(find.text('Studio'), findsOneWidget);
      expect(find.text('Lịch'), findsOneWidget);
      expect(find.text('Cài đặt'), findsOneWidget);
      expect(find.text('Chưa có ca nào'), findsOneWidget);
      expect(find.text('Chị Minh Thư (FB)'), findsNothing);
      expect(find.text('Thanh Trúc (Zalo)'), findsNothing);

      // Switch to 'Mới' status chip and open Business AI handover case
      await tester.tap(find.text('Mới'));
      await tester.pumpAndSettle();
      expect(find.text('Khách chuyển từ Business AI (1)'), findsOneWidget);
      await tester.tap(find.text('Khách cần tư vấn mày cũ trổ xanh'));
      await tester.pumpAndSettle();
      expect(find.text('Phân tích AI'), findsOneWidget);
      expect(find.text('Trả Business AI'), findsOneWidget);

      // Run AI analysis inside sheet -> transitions to pending_review with Duyệt
      await tester.tap(find.text('Phân tích AI'));
      await tester.pumpAndSettle();
      expect(repo.analyzedCaseIds, ['case-new-1']);
      expect(find.text('Duyệt'), findsOneWidget);

      // Dismiss bottom sheet via system back (exercises PopScope)
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Tab 1: Studio (no default catalog, demo button disabled)
      await tester.tap(find.text('Studio').last);
      await tester.pumpAndSettle();
      expect(find.text('Chưa có ảnh khách'), findsOneWidget);
      expect(
        find.text('Chưa có mẫu. Thêm mẫu trong Cài đặt → Catalog mẫu.'),
        findsOneWidget,
      );
      expect(find.text('Tạo ảnh demo (chờ model)'), findsOneWidget);
    },
  );

  testWidgets(
    '2b. Schedule tab supports 7-day follow-up completion and opens/closes AddBookingDialog safely',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _FakeCrmRepo(
        bookingsList: [
          {
            'id': 'bk-7d-1',
            'customer_name': 'Khách 7 Ngày',
            'customer_phone': '0911222333',
            'service_name': 'Phun môi',
            'scheduled_at': '2026-11-10T09:00:00+07:00',
            'follow_up_due': '2026-11-17',
            'followup_done': false,
          },
        ],
      );

      await tester.pumpWidget(
        BeautyCrmApp(
          initialAuthToken: 'session-token-for-widget-test',
          repoOverride: repo,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lịch').last);
      await tester.pumpAndSettle();
      expect(find.text('Hẹn trong ngày (0)'), findsOneWidget);
      expect(find.text('Khách 7 Ngày'), findsOneWidget);
      expect(find.text('Đã kiểm tra'), findsOneWidget);

      // Mark 7-day follow-up done
      await tester.tap(find.text('Đã kiểm tra'));
      await tester.pumpAndSettle();
      expect(repo.markedFollowupIds, ['bk-7d-1']);
      expect(find.text('Chưa có khách đến mốc 7 ngày.'), findsOneWidget);

      // Dismiss confirmation SnackBar before tapping bottom-right FAB
      ScaffoldMessenger.of(tester.element(find.text('Thêm lịch')))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Thêm lịch'));
      await tester.pumpAndSettle();
      expect(find.text('Thêm lịch hẹn'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(find.text('Thêm lịch hẹn'), findsNothing);
    },
  );

  testWidgets(
    '2c. Settings tab shows 4 groups, Connection unlink & prompt copy, AuditLogsScreen, Catalog dialog, and SignOut',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _FakeCrmRepo(
        pagesList: [
          {'page_id': 'pg-1', 'page_name': 'Fanpage Test'},
        ],
        logsList: [
          {
            'id': 'log-1',
            'action': 'tenant.update',
            'created_at': '2026-11-22T01:00:00Z',
            'metadata': {'name': 'Tiệm Test'},
          },
        ],
      );

      await tester.pumpWidget(
        BeautyCrmApp(
          initialAuthToken: 'session-token-for-widget-test',
          repoOverride: repo,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cài đặt').last);
      await tester.pumpAndSettle();
      expect(find.text('Tiệm'), findsOneWidget);
      expect(find.text('Kết nối'), findsOneWidget);
      expect(find.text('Hệ thống'), findsOneWidget);
      expect(find.text('Tài khoản'), findsOneWidget);
      expect(find.text('Đã dùng 2 / 50 lượt'), findsOneWidget);
      expect(find.textContaining('Nhân viên'), findsNothing);

      // Open ConnectionScreen: verify connected page unlink + Business AI prompt copy + honest checklist
      await tester.tap(find.text('Facebook và Business AI'));
      await tester.pumpAndSettle();
      expect(find.text('Fanpage Test'), findsOneWidget);
      expect(find.text('Chưa kiểm tra'), findsNWidgets(4));
      expect(find.text('Sao chép Prompt Business AI'), findsOneWidget);

      await tester.tap(find.byTooltip('Gỡ liên kết'));
      await tester.pumpAndSettle();
      expect(find.text('Gỡ liên kết Fanpage?'), findsOneWidget);
      await tester.tap(find.text('Gỡ liên kết'));
      await tester.pumpAndSettle();
      expect(repo.disconnectedPageIds, ['pg-1']);
      expect(find.text('Chưa kết nối Fanpage nào.'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      // Open AuditLogsScreen
      await tester.ensureVisible(find.text('Nhật ký hoạt động'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhật ký hoạt động'));
      await tester.pumpAndSettle();
      expect(find.text('Cập nhật thông tin tiệm'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Open CatalogScreen and open/close _AddCatalogItemDialog cleanly
      await tester.tap(find.text('Catalog mẫu'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa có mẫu nào'), findsOneWidget);
      await tester.tap(find.text('Thêm mẫu'));
      await tester.pumpAndSettle();
      expect(find.text('Tên mẫu'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(find.text('Tên mẫu'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Verify sign out returns to LoginScreen
      await tester.ensureVisible(find.text('Đăng xuất'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đăng xuất'));
      await tester.pumpAndSettle();
      expect(find.text('Email đăng nhập'), findsOneWidget);
    },
  );

  test('3. userMessage hides raw HTTP codes and Exception internals', () {
    const cases = <Object>[
      ApiException(401, 'UNAUTHORIZED'),
      ApiException(403, 'FORBIDDEN_ROLE'),
      ApiException(422, 'OUTSIDE_24H_WINDOW'),
      ApiException(429, 'AI_DAILY_CAP'),
      ApiException(501, 'DEMO_NOT_ENABLED'),
      ApiException(502, 'META_SEND_FAILED'),
      ApiException(503, 'GEMINI_NOT_CONFIGURED'),
    ];
    for (final error in cases) {
      final msg = userMessage(error);
      expect(msg.trim().isNotEmpty, isTrue);
      expect(msg.contains('Exception'), isFalse);
      expect(msg.contains('HTTP'), isFalse);
      expect(msg.contains('401'), isFalse);
      expect(msg.contains('500'), isFalse);
    }
  });
}
