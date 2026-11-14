# HỆ THỐNG QUẢN LÝ VẬN HÀNH & CSKH 2 TẦNG AI (ANDROID / iOS & ZALO BOT)

Giải pháp quản lý vận hành chuyên biệt cho cơ sở dịch vụ (**Phun xăm thẩm mỹ, Spa, Salon**) kết hợp hạ tầng **Meta Business Suite** và **Google Gemini AI**. 

Hệ thống hỗ trợ song song **2 chế độ sử dụng**:
1. **Ứng dụng di động chuyên nghiệp (Android & iOS):** Giao diện trực quan đầy đủ tính năng cho Chủ tiệm, Sale và Kỹ thuật viên.
2. **Chế độ Zalo Bot "Không cần cài App":** Điều hành, nhận báo cáo, duyệt ca khó và gửi ảnh demo trực tiếp qua tin nhắn Zalo dành cho chủ tiệm/nhân viên ngại cài thêm ứng dụng.

---

## 1. Kiến trúc "2 Tầng AI" Tối Ưu Chi Phí (Zero-Cost Architecture)

* **Tầng 1 — Meta AI (Tuyến đầu tiếp đón miễn phí 100%):**
  * Tận dụng trực tiếp hạ tầng lưu trữ và Bot mặc định của **Meta Business Suite / Messenger**.
  * Tự động chào hỏi, trả lời câu hỏi cơ bản (giờ mở cửa, địa chỉ, bảng giá chung) và thu thập ảnh mặt mộc của khách hàng 24/7 mà không tốn tài nguyên máy chủ.
* **Tầng 2 — Google Gemini AI (Tuyến cuối đóng vai Chủ tiệm):**
  * Chỉ kích hoạt ở bước phân loại cuối cùng khi có sự kiện quan trọng từ Meta Webhook (sử dụng gói **Google AI Studio Free Tier** theo cơ chế mỗi tiệm tự nhập API Key miễn phí).
  * **Sàng lọc & Phân loại:** Đọc kết quả từ Meta AI để tách bạch *Khách hỏi dạo*, *Khách cần gấp*, *Ca khó/Khiếu nại*, và *Khách muốn đặt lịch*.
  * **Xử lý Ca khó & Điều phối:** Gắn cờ đỏ khẩn cấp, soạn sẵn câu trả lời chuẩn phong cách chủ tiệm và tự động đẩy hội thoại cho nhân viên giỏi nhất đang trong ca trực.
  * **Edit ảnh Demo Mày/Môi (Virtual Try-On):** Tiếp nhận ảnh khách gửi + mã mẫu chọn từ Catalog của tiệm, tự động ghép dáng mày/màu môi xem trước và gửi trả lại khung chat.
  * **Báo cáo tổng hợp cuối ngày:** Tự động đọc toàn bộ hội thoại trong ngày và gửi bản tóm tắt tình hình chốt đơn, hiệu suất nhân viên cho chủ tiệm lúc 21h00.

---

## 2. Chế độ vận hành linh hoạt (App Mobile hoặc Bot Zalo)

### 2.1. Giao diện App Mobile (Android & iOS - Flutter)
Thiết kế tối giản, chia 4 tab điều hướng chính (Bottom Navigation Bar) giúp thao tác bằng 1 tay trên điện thoại:
* **Tab 1 — Hộp thư & Sàng lọc AI (`Inbox & Triage`):**
  * Hiển thị danh sách hội thoại từ Facebook Messenger & Zalo đã được Gemini gắn nhãn ưu tiên (*Gấp, Ca khó, Đã thử mẫu, Thường*).
  * Thanh gợi ý câu trả lời thông minh của Gemini nằm ngay trên bàn phím để nhân viên bấm gửi 1 chạm.
* **Tab 2 — Thử mẫu AI (`Virtual Try-On Studio`):**
  * Kho Catalog mẫu Mày / Môi của tiệm dạng lưới hình ảnh.
  * Bấm chọn ảnh khách + chọn mẫu → Xem trước ảnh AI ghép hoàn thiện và gửi thẳng vào cuộc trò chuyện.
* **Tab 3 — Lịch hẹn & Ca trực (`Shifts & Booking`):**
  * Bảng phân ca trực nhân viên (Sáng/Chiều/Tối) với nút bật/tắt trạng thái *Đang trực* để tự động chia khách.
  * Lịch hẹn khách hàng gắn kèm ảnh mẫu mày/môi đã chốt và tên kỹ thuật viên phụ trách.
* **Tab 4 — Trợ lý Chủ tiệm (`Owner Dashboard`):**
  * Báo cáo tổng hợp cuối ngày do Gemini biên soạn.
  * Mục cài đặt 1 chạm: Nút kết nối **Facebook Login for Business**, quét mã QR Zalo và ô dán **Gemini API Key miễn phí**.

### 2.2. Chế độ Bot Zalo "Lười cài App" (Zero-Install Mode)
Dành cho chủ tiệm hoặc nhân viên không muốn cài App lên điện thoại, toàn bộ việc quản lý diễn ra ngay trong khung chat Zalo quen thuộc:
* **Nhận cảnh báo & Báo cáo:** Bot Zalo tự động nhắn tin cho Chủ tiệm mỗi khi Gemini phát hiện *Ca khó*, *Khách VIP* hoặc gửi *Báo cáo tổng hợp 21h00*.
* **Điều khiển bằng câu lệnh tự nhiên:** Chủ tiệm chỉ cần nhắn tin cho Bot Zalo (ví dụ: *"Hôm nay có bao nhiêu khách đặt lịch?"*, *"Chuyển ca cho bé Lan trực chiều nay"*, *"Duyệt giảm giá 10% cho khách Nguyễn Thị A"*), Gemini sẽ tự hiểu ý định và cập nhật thẳng vào hệ thống.
* **Nhận ảnh Demo qua Zalo:** Khi khách trên Fanpage gửi ảnh thử mẫu, Bot Zalo chuyển ảnh demo cho chủ/nhân viên xem duyệt chỉ với 1 nút bấm.

---

## 3. Cấu trúc thư mục dự án (Repository Structure)

```text
app-cskh/
├── mobile_app/                  # Mã nguồn Giao diện App Android & iOS (Flutter)
│   ├── lib/
│   │   ├── core/                # Theme UI, Màu sắc thương hiệu thẩm mỹ, Constants
│   │   ├── models/              # Data Models (Organization, User, Shift, Catalog, Booking)
│   │   ├── services/
│   │   │   ├── meta_service.dart        # Gọi Meta Graph API đọc/gửi tin nhắn & bình luận
│   │   │   ├── gemini_owner_agent.dart  # AI phân loại cuối, xử lý ca khó & báo cáo
│   │   │   └── tryon_image_service.dart # Gọi AI ghép mẫu mày/môi lên ảnh khách
│   │   ├── screens/
│   │   │   ├── inbox/           # UI Hộp thư hợp nhất & Thẻ phân loại Gemini
│   │   │   ├── tryon/           # UI Catalog chọn mẫu & So sánh ảnh trước/sau (Before-After)
│   │   │   ├── schedule/        # UI Phân ca trực & Lịch hẹn kỹ thuật viên
│   │   │   └── settings/        # UI Kết nối Meta Business & Nhập Gemini API Key
│   │   └── main.dart
│   └── pubspec.yaml             # Khai báo thư viện UI & SDK
├── backend_bridge/              # Dịch vụ nền & Bot Zalo (Node.js / TypeScript)
│   ├── meta-webhook/            # Nhận sự kiện từ Meta AI & ẩn comment chứa SĐT
│   ├── zalo-manager-bot/        # Bot Zalo điều hành không cần cài App (dùng zca-js)
│   └── cron-daily-report/       # Tự động gọi Gemini tổng hợp báo cáo lúc 21h00
├── database/
│   └── schema.sql               # Mã SQL khởi tạo bảng trên Supabase
└── README.md
```

---

## 4. Cấu hình Giao diện App Mobile (`pubspec.yaml` chuẩn)

Sử dụng các thư viện UI mã nguồn mở nhẹ, mượt mà và chuẩn thiết kế hiện đại cho cả Android (Material 3) và iOS (Cupertino):

```yaml
dependencies:
  flutter:
    sdk: flutter
  # Backend & Xác thực miễn phí
  supabase_flutter: ^2.8.0
  # Trí tuệ nhân tạo Google Gemini (Đóng vai Chủ tiệm)
  google_generative_ai: ^0.4.6
  # Giao diện Chat & So sánh ảnh trước/sau (Before/After)
  flutter_chat_ui: ^1.6.15
  before_after: ^3.1.0
  # Giao diện Lịch hẹn & Phân ca trực
  table_calendar: ^3.1.2
  # Kết nối đăng nhập Facebook Business
  flutter_facebook_auth: ^7.1.1
  # Quản lý trạng thái & Lưu cấu hình cục bộ
  provider: ^6.1.2
  flutter_dotenv: ^5.1.0
```

---

## 5. Hướng dẫn Build & Triển khai nhanh

### Bước 1: Dựng Database miễn phí (Supabase)
1. Tạo dự án trên [Supabase](https://supabase.com).
2. Chạy file `database/schema.sql` để tạo 6 bảng cốt lõi (`organizations`, `users`, `shifts`, `catalog_items`, `conversations`, `bookings`).

### Bước 2: Kích hoạt Bot Zalo điều hành (Không cần cài App)
1. Cài đặt Node.js trên máy chủ miễn phí (Oracle Cloud Free Tier hoặc Render).
2. Chạy thư mục `backend_bridge/zalo-manager-bot`, quét mã QR đăng nhập tài khoản Zalo của Bot điều hành để kích hoạt tính năng nhận báo cáo và ra lệnh qua tin nhắn Zalo.

### Bước 3: Build App Android & iOS (Flutter)
```bash
cd mobile_app
flutter pub get

# Chạy thử nghiệm trên điện thoại thật hoặc máy ảo
flutter run

# Đóng gói file cài đặt Android (.apk / .aab)
flutter build apk --release
flutter build appbundle --release

# Đóng gói file cài đặt iOS (.ipa - trên macOS hoặc Codemagic)
flutter build ipa --release
```

---

## 6. Nguồn tham khảo & Thư viện mã nguồn mở (Giấy phép thương mại)

* **Flutter Chat UI (MIT):** https://github.com
* **Before After Image Slider (MIT):** https://pub.dev *(Dùng làm thanh kéo so sánh khuôn mặt khách trước và sau khi AI ghép mẫu mày/môi)*
* **Table Calendar (Apache 2.0):** https://github.com *(Dùng làm giao diện xếp ca trực và lịch hẹn)*
* **Google Generative AI Dart SDK (Apache 2.0):** https://github.com
* **Meta Messenger Platform & Webhooks:** https://facebook.com
* **zca-js — Bot Zalo điều hành không cần cài App (MIT):** https://github.com
* **MediaPipe Face Landmarker (Apache 2.0):** https://github.com
* **ComfyUI Virtual Try-On Workflow (GPL-3.0):** https://github.com
