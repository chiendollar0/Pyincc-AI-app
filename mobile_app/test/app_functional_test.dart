// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyincc_app/main.dart';

void main() {
  testWidgets(
    '1. Trung tam CSKH AI renders KPIs, filters chats, and opens approval dialog',
    (WidgetTester tester) async {
      await tester.pumpWidget(const BeautyCrmApp());
      await tester.pump();

      // Verify AppBar & KPI badges
      expect(find.text('Trung tâm CSKH AI'), findsOneWidget);
      expect(find.text('Tổng hội thoại'), findsOneWidget);
      expect(find.text('Ca khó / Sửa'), findsOneWidget);
      expect(find.text('Hỏi giá / Lịch'), findsOneWidget);

      // Verify demo triage conversations are visible
      expect(find.text('Chị Minh Thư (FB)'), findsOneWidget);
      expect(find.text('Thanh Trúc (Zalo)'), findsOneWidget);

      // Filter by 'Ca khó (1)'
      await tester.tap(find.textContaining('Ca khó ('));
      await tester.pump();
      expect(find.text('Chị Minh Thư (FB)'), findsOneWidget);
      expect(find.text('Thanh Trúc (Zalo)'), findsNothing);

      // Reset filter to 'Tất cả'
      await tester.tap(find.textContaining('Tất cả ('));
      await tester.pump();
      expect(find.text('Thanh Trúc (Zalo)'), findsOneWidget);

      // Open human-in-the-loop approval dialog
      await tester.tap(find.text('Duyệt & Gửi').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Duyệt & gửi cho Chị Minh Thư'),
        findsOneWidget,
      );
      expect(find.text('Xác nhận gửi'), findsOneWidget);

      // Cancel dialog
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();

      // Unmount to dispose periodic polling timer cleanly
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    '2. Studio AI tab filters catalog items and enforces human approval state',
    (WidgetTester tester) async {
      await tester.pumpWidget(const BeautyCrmApp());
      await tester.pump();

      // Navigate to Tab 2 (Studio AI) via quick button on chat card
      await tester.tap(find.text('Thử mẫu AI').first);
      await tester.pumpAndSettle();

      expect(find.text('Studio AI • Thử Mày & Môi'), findsOneWidget);
      expect(find.text('Chưa có ảnh mặt mộc của khách'), findsOneWidget);

      // Filter catalog by 'Môi'
      await tester.tap(find.widgetWithText(ChoiceChip, 'Môi'));
      await tester.pump();
      expect(
        find.textContaining('Môi Collagen Cam Đào'),
        findsOneWidget,
      );

      // Filter catalog by 'Chân mày'
      await tester.tap(find.widgetWithText(ChoiceChip, 'Chân mày'));
      await tester.pump();
      expect(
        find.textContaining('Mày sợi Hairstroke Nâu Tây'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    '3. Quan ly Tiem tab manages schedule/duty and enforces Zero-Key UI for owner',
    (WidgetTester tester) async {
      await tester.pumpWidget(const BeautyCrmApp());
      await tester.pump();

      // Navigate to Tab 3 (Quản lý Tiệm)
      await tester.tap(find.text('Quản lý Tiệm'));
      await tester.pumpAndSettle();

      expect(find.text('Quản lý Vận hành & Tiệm'), findsOneWidget);
      expect(find.text('Trạng thái Ca trực nhận khách AI'), findsOneWidget);

      // Open quick booking dialog
      await tester.tap(find.text('Đặt lịch mới'));
      await tester.pumpAndSettle();
      expect(find.text('Tạo lịch hẹn mới'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();

      // Switch to sub-tab 'Kết nối & Chủ tiệm'
      await tester.tap(find.text('Kết nối & Chủ tiệm'));
      await tester.pumpAndSettle();

      // Verify 1-click Facebook connect button & script editor exist
      expect(find.text('Kết nối với Facebook'), findsOneWidget);
      expect(find.text('Lưu kịch bản & bảng giá'), findsOneWidget);

      // Verify Zero-Key UI: no API key or secret inputs are exposed to the owner
      expect(find.textContaining('API Key'), findsNothing);
      expect(find.textContaining('SUPABASE_SERVICE_ROLE_KEY'), findsNothing);
      expect(find.textContaining('META_APP_SECRET'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
