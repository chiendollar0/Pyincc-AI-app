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
  _FakeCrmRepo() : super(const ApiClient(baseUrl: 'https://test.local'));

  @override
  Future<Map<String, dynamic>> tenant() async => {
        'id': 'org-1',
        'name': 'Tiệm Test',
        'specialty': '',
      };

  @override
  Future<Map<String, dynamic>> aiUsage() async => {'used': 2, 'cap': 50};

  @override
  Future<Map<String, dynamic>> connectionStatus() async => {
        'pages': <Map<String, dynamic>>[],
        'default_app': null,
        'take_control_enabled': null,
        'handover_subscribed': null,
        'receiving_events': null,
        'last_webhook_at': null,
      };

  @override
  Future<List<Map<String, dynamic>>> handoffCases(String status) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> catalog() async => const [];

  @override
  Future<List<Map<String, dynamic>>> bookings() async => const [];
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
    '2a. Inbox and Studio tabs render honest empty states and disabled demo',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        BeautyCrmApp(
          initialAuthToken: 'session-token-for-widget-test',
          repoOverride: _FakeCrmRepo(),
        ),
      );
      await tester.pumpAndSettle();

      // Default tab 0: Hộp thư
      expect(find.text('Hộp thư'), findsWidgets);
      expect(find.text('Studio'), findsOneWidget);
      expect(find.text('Lịch'), findsOneWidget);
      expect(find.text('Cài đặt'), findsOneWidget);
      expect(find.text('Chưa có ca nào'), findsOneWidget);
      expect(find.text('Chị Minh Thư (FB)'), findsNothing);
      expect(find.text('Thanh Trúc (Zalo)'), findsNothing);

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
    '2b. Schedule tab renders empty state and opens/closes AddBookingDialog safely',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        BeautyCrmApp(
          initialAuthToken: 'session-token-for-widget-test',
          repoOverride: _FakeCrmRepo(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lịch').last);
      await tester.pumpAndSettle();
      expect(find.text('Hẹn trong ngày (0)'), findsOneWidget);
      expect(find.text('Chưa có khách đến mốc 7 ngày.'), findsOneWidget);

      await tester.tap(find.text('Thêm lịch'));
      await tester.pumpAndSettle();
      expect(find.text('Thêm lịch hẹn'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(find.text('Thêm lịch hẹn'), findsNothing);
    },
  );

  testWidgets(
    '2c. Settings tab shows 4 groups, honest Connection checklist, Catalog dialog, and SignOut',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        BeautyCrmApp(
          initialAuthToken: 'session-token-for-widget-test',
          repoOverride: _FakeCrmRepo(),
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

      // Open ConnectionScreen and verify honest "Chưa kiểm tra" checklist
      await tester.tap(find.text('Facebook và Business AI'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa kết nối Fanpage nào.'), findsOneWidget);
      expect(find.text('Chưa kiểm tra'), findsNWidgets(4));
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
