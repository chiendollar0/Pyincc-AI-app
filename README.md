# PYINCC — Hệ thống Quản lý Vận hành & CSKH AI cho Thẩm mỹ viện / Spa

Ứng dụng **PYINCC AI Beauty Manager** (Flutter) kết hợp cùng **Meta Webhook Backend** (Render) và **Supabase** (Database, Storage, Realtime, Edge Functions) dành cho cơ sở phun xăm thẩm mỹ, spa và salon. Hệ thống tuân thủ chặt chẽ nguyên tắc **Human-in-the-loop** (AI phân tích & gợi ý, nhân viên/chủ tiệm duyệt trước khi gửi) và **Zero-Key UI** (người dùng cuối không bao giờ nhìn thấy hay phải nhập API Key, App Secret hay Page Access Token).

---

## 1. Kiến trúc Tổng thể

1. **Ứng dụng Flutter (`mobile_app/`) — Giao diện 3 Tab hợp nhất (`IndexedStack`):**
   - **Tab 1 — `Hộp thư AI` (`Trung tâm CSKH AI`):** Hiển thị thống kê nhanh (KPI Strip), lọc hội thoại theo phân loại AI (*Ca khó / Sửa mày*, *Hỏi giá & Lịch*, *Khách gửi ảnh*, *Đã trả lời*), xem ảnh khách gửi từ Supabase Storage, mở nhanh Studio AI cho từng khách và duyệt/chỉnh sửa câu trả lời trước khi gửi qua `POST /send-message`.
   - **Tab 2 — `Studio AI` (`Studio AI • Thử Mày & Môi`):** Tải/chụp ảnh mặt mộc, gọi Supabase Edge Function `tryon-analyze` để phân tích dáng mặt & tông da, ghép mẫu Trước/Sau (`BeforeAfter`), và bấm **Duyệt gửi khách** (`POST /send-tryon-image`) để lưu ảnh lên Supabase Storage và gửi thẳng qua Messenger cho khách.
   - **Tab 3 — `Quản lý Tiệm` (`SalonOperationsHubScreen`):** Gộp gọn 2 nhánh vận hành trong 1 màn hình:
     - **Nhánh `Ca trực & Lịch hẹn`:** Đồng bộ công tắc nhận khách trong ca (`GET/PUT /settings`) và danh sách lịch hẹn (`GET/POST /bookings`).
     - **Nhánh `Kết nối & Chủ tiệm`:** Nút duy nhất **“Kết nối với Facebook”** (tự động đổi Page Access Token ngầm ở máy chủ) và khung lưu **Kịch bản & Bảng giá chuẩn của Chủ tiệm** (`GET/PUT /settings`).

2. **Meta Webhook & Operations Backend (`backend_bridge/meta-webhook/` — chạy trên Render):**
   - URL triển khai: `https://pyincc-ai-app.onrender.com` (cấu hình sẵn trong `render.yaml`).
   - **Xác thực & Liên kết Fanpage tự động (`/auth/facebook`, `/auth/facebook/callback`, `/auth/facebook/exchange-token`, `/connected-pages`):** Đổi `User Access Token` của chủ tiệm sang Long-Lived Token, ký `appsecret_proof` bằng `META_APP_SECRET` trên server, gọi `GET /me/accounts` lấy danh sách Fanpage kèm `page_access_token`, tự động đăng ký Webhook (`/{page_id}/subscribed_apps`) và lưu vào bảng `connected_pages` trên Supabase.
   - **Nhận sự kiện Meta (`GET /webhook`, `POST /webhook`):** Kiểm tra chữ ký `x-hub-signature-256` bằng HMAC-SHA256 trên raw body, lọc ảnh từ domain CDN hợp lệ của Facebook (`fbcdn.net`, `fbsbx.com`), tải về buffer và upload lên Supabase Storage bucket `customer-media`, ghi idempotent vào `webhook_events`, `conversation_messages`, `customer_media`.
   - **API Hộp thư, Gửi tin, Lịch hẹn & Cấu hình (`/messages`, `/send-message`, `/send-tryon-image`, `/bookings`, `/settings`):** Phục vụ toàn bộ thao tác thực tế từ ứng dụng Flutter.

3. **Supabase (`database/schema.sql` & `database/migrations/20261116_meta_webhook.sql`) + Edge Functions:**
   - **Edge Function `tryon-analyze`:** `https://ihufvqrxdswgbagzhydb.supabase.co/functions/v1/tryon-analyze` — nhận ảnh mặt khách và danh mục mẫu, gọi Gemini bằng `GEMINI_API_KEY` lưu trong Supabase Secrets (không nằm trong mã nguồn ứng dụng).
   - **PostgreSQL Tables:** `organizations`, `users`, `shifts`, `catalog_items`, `conversations`, `conversation_messages`, `customer_media`, `webhook_events`, `connected_pages`, `salon_settings`, `bookings`.
   - **Supabase Storage:** Bucket `customer-media` lưu trữ bền vững ảnh khách gửi (`facebook/...`) và ảnh ghép mẫu AI (`tryon/...`).

---

## 2. Trạng thái Triển khai Hiện tại

| Hạng mục | Trạng thái | Chi tiết |
| :--- | :--- | :--- |
| **CI/CD Build APK (GitHub Actions)** | Hoàn tất (`success`) | Các run liên tiếp từ `#14` đến `#20` đều xanh, tự động kiểm tra `flutter analyze` và xuất artifact `app-debug-apk` (~70.8 MB). |
| **Giao diện Flutter 3 Tab (`IndexedStack`)** | Hoàn tất | `Hộp thư AI`, `Studio AI`, `Quản lý Tiệm` (`Ca trực & Lịch hẹn` + `Kết nối & Chủ tiệm`), loại bỏ toàn bộ ô nhập API Key khỏi UI. |
| **Phân tích khuôn mặt (`tryon-analyze`)** | Đã nối Supabase Edge Function | `TryOnImageService.analyzeFace()` gọi `https://ihufvqrxdswgbagzhydb.supabase.co/functions/v1/tryon-analyze`. |
| **Gửi ảnh thử AI cho khách (`/send-tryon-image`)** | Đã nối Backend & Storage | Upload ảnh demo lên bucket `customer-media` và gửi qua Messenger Graph API kèm lời tư vấn. |
| **Meta Webhook & Tự động đổi Page Token** | Đã triển khai trên Render | Dịch vụ `https://pyincc-ai-app.onrender.com` đã Live với `render.yaml` Blueprint. |
| **Lịch hẹn & Cấu hình Ca trực / Kịch bản** | Đã nối Backend (`/bookings`, `/settings`) | Lưu vào bảng `bookings` và `salon_settings` trên Supabase (có fallback bộ nhớ đệm khi chưa cấu hình DB). |

---

## 3. Cấu trúc Thư mục

```text
Pyincc-AI-app/
├── .github/workflows/build.yml                 # CI kiểm tra flutter analyze & build debug APK (Flutter 3.50.0)
├── render.yaml                                 # Render Blueprint triển khai tự động dịch vụ meta-webhook
├── mobile_app/
│   ├── android/                                # Android native scaffold
│   ├── ios/                                    # iOS native scaffold
│   ├── lib/
│   │   ├── main.dart                           # Giao diện 3 tab: Hộp thư AI, Studio AI, Quản lý Tiệm
│   │   ├── screens/tryon/
│   │   │   └── tryon_studio_screen.dart        # Màn hình thử mẫu Mày/Môi Trước & Sau + Duyệt gửi khách
│   │   └── services/
│   │       ├── inbox_service.dart              # Kết nối /messages, /send-message, /bookings, /settings, /connected-pages
│   │       └── tryon_image_service.dart        # Kết nối Supabase Edge Function tryon-analyze & /send-tryon-image
│   └── pubspec.yaml
├── backend_bridge/
│   ├── meta-webhook/
│   │   ├── .env.example                        # Mẫu biến môi trường cho nhà phát triển trên Render
│   │   ├── README.md                           # Tài liệu API & hướng dẫn vận hành webhook
│   │   ├── index.js                            # Express server: OAuth Facebook, Webhook HMAC, Storage, Inbox, Bookings
│   │   └── package.json
│   └── zalo-manager-bot/
├── database/
│   ├── schema.sql                              # Toàn bộ schema PostgreSQL cho project Supabase mới
│   └── migrations/
│       └── 20261116_meta_webhook.sql           # Migration bổ sung cột, unique index, connected_pages, salon_settings
└── README.md
```

---

## 4. Hướng dẫn Cài đặt & Vận hành (Dành cho Developer)

### A. Khởi tạo Supabase Database & Storage
1. Mở **Supabase SQL Editor**, chạy file [`database/schema.sql`](database/schema.sql) (nếu là project mới) hoặc [`database/migrations/20261116_meta_webhook.sql`](database/migrations/20261116_meta_webhook.sql) (nếu đã có các bảng cơ bản).
2. Tạo Storage bucket tên **`customer-media`** (giới hạn 15 MB, cho phép `image/jpeg`, `image/png`, `image/webp`).
3. Đặt khóa Gemini cho Edge Function `tryon-analyze` trong Supabase Secrets:
   ```bash
   supabase secrets set GEMINI_API_KEY=<YOUR_GEMINI_API_KEY>
   ```

### B. Cấu hình Biến môi trường trên Render (`https://pyincc-ai-app.onrender.com`)
Nhà phát triển cấu hình một lần duy nhất trong mục **Environment** trên Render (Chủ tiệm không bao giờ phải chạm vào các biến này):
- `SUPABASE_URL`: `https://ihufvqrxdswgbagzhydb.supabase.co`
- `SUPABASE_STORAGE_BUCKET`: `customer-media`
- `META_GRAPH_API_VERSION`: `v19.0`
- `VERIFY_TOKEN`: Chuỗi xác minh Webhook với Meta for Developers
- `API_KEY`: Khóa bảo vệ nội bộ của Server
- `SUPABASE_SERVICE_ROLE_KEY`: Khóa `service_role` từ Supabase Dashboard
- `META_APP_ID` & `META_APP_SECRET`: App ID và App Secret từ Meta for Developers

### C. Build & Chạy Ứng dụng Flutter
```bash
cd mobile_app
flutter pub get
flutter analyze --no-fatal-infos
flutter run
```
Để xuất file APK cài đặt:
```bash
flutter build apk --debug
```

---

## 5. Bảo mật & Quyền riêng tư
- **Không lộ khóa ở Client:** `GEMINI_API_KEY`, `META_APP_SECRET`, `SUPABASE_SERVICE_ROLE_KEY` và `page_access_token` chỉ tồn tại trên Supabase Secrets / Render Server.
- **Xác thực chữ ký Webhook:** Mọi sự kiện `POST /webhook` từ Meta đều được kiểm tra chữ ký `x-hub-signature-256` bằng `crypto.timingSafeEqual` trên raw request body.
- **Kiểm soát con người (Human-in-the-loop):** AI chỉ đóng vai trò phân loại, tóm tắt và gợi ý câu trả lời/ảnh mẫu; mọi tin nhắn và hình ảnh gửi tới khách hàng đều phải được nhân viên hoặc chủ tiệm bấm xác nhận duyệt.
