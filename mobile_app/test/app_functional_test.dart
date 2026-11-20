// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyincc_app/main.dart';

void main() {
  testWidgets(
    '1. Login screen renders Pyincc brand header and validates empty credentials',
    (WidgetTester tester) async {
      await tester.pumpWidget(const BeautyCrmApp());
      await tester.pump();

      expect(find.text('Pyincc AI CRM'), findsOneWidget);
      expect(find.text('Email đăng nhập'), findsOneWidget);
      expect(find.text('Mật khẩu'), findsOneWidget);
      expect(find.text('Đăng nhập'), findsOneWidget);

      // Verify password field starts obscured and toggles visibility on eye tap
      final passwordFieldFinder = find.widgetWithText(TextField, 'Mật khẩu');
      expect(tester.widget<TextField>(passwordFieldFinder).obscureText, isTrue);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(tester.widget<TextField>(passwordFieldFinder).obscureText, isFalse);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();
      expect(tester.widget<TextField>(passwordFieldFinder).obscureText, isTrue);

      // Submit empty credentials -> friendly Vietnamese message without raw technical text
      await tester.tap(find.text('Đăng nhập'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.text('Vui lòng nhập đầy đủ Email và Mật khẩu.'),
        findsOneWidget,
      );
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('HTTP'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    '2. Signed-in dashboard renders BrandHeader, KPIs, Studio AI catalog, and Logout',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const BeautyCrmApp(initialAuthToken: 'session-token-for-widget-test'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tab 1: Hộp thư AI (no hardcoded customer names; shows error/empty state when offline)
      expect(find.text('Hộp thư AI'), findsWidgets);
      expect(find.text('Chị Minh Thư (FB)'), findsNothing);
      expect(find.text('Thanh Trúc (Zalo)'), findsNothing);

      // Switch to Tab 2: Studio AI
      await tester.tap(find.text('Studio AI').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Chưa có ảnh mặt mộc của khách'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Môi'));
      await tester.pump();
      expect(find.textContaining('Môi Collagen Cam Đào'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Chân mày'));
      await tester.pump();
      expect(find.textContaining('Mày sợi Hairstroke Nâu Tây'), findsOneWidget);

      // Verify Logout button on the active tab returns to LoginScreen
      await tester.tap(find.byIcon(Icons.logout).hitTestable().first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Email đăng nhập'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    '3. Quan ly tiem tab manages Facebook connect and enforces Zero-Key UI',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const BeautyCrmApp(initialAuthToken: 'session-token-for-widget-test'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Quản lý tiệm').last);
      await tester.pump(const Duration(milliseconds: 300));

      // Switch to sub-tab 'Kết nối & Chủ tiệm'
      await tester.tap(find.text('Kết nối & Chủ tiệm'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Kết nối với Facebook'), findsOneWidget);
      expect(find.text('Lưu kịch bản & bảng giá'), findsOneWidget);

      // Zero-Key UI: never expose backend secrets
      expect(find.textContaining('API Key'), findsNothing);
      expect(find.textContaining('SUPABASE_SERVICE_ROLE_KEY'), findsNothing);
      expect(find.textContaining('META_APP_SECRET'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
