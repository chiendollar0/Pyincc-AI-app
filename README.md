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
   - **API Hộp thư, Gửi tin, Lịch hẹn & Cấu hình (`/messages`, `/send-message`, `/send-tryon-image`, `/bookings`, `/settings`):** Mọi route đọc/ghi dữ liệu vận hành hoặc gửi tin đều bắt buộc đi qua middleware xác thực `requireAuth`.

3. **Supabase (`database/schema.sql` & `database/migrations/20261116_meta_webhook.sql`) + Edge Functions:**
   - **Edge Function `tryon-analyze`:** `https://ihufvqrxdswgbagzhydb.supabase.co/functions/v1/tryon-analyze` — nhận ảnh mặt khách và danh mục mẫu, gọi Gemini bằng `GEMINI_API_KEY` lưu trong Supabase Secrets (không nằm trong mã nguồn ứng dụng).
   - **PostgreSQL Tables:** `organizations`, `users`, `shifts`, `catalog_items`, `conversations`, `conversation_messages`, `customer_media`, `webhook_events`, `connected_pages`, `salon_settings`, `bookings`.
   - **Supabase Storage (`customer-media`):** Lưu trữ ảnh khách gửi (`facebook/...`) và ảnh ghép mẫu AI (`tryon/...`) ở chế độ **Private bucket**, cấp quyền truy cập tạm thời qua **Signed URL** (`createSignedUrl`, thời hạn 3600 giây).

---

## 2. Cơ chế Xác thực & Phân quyền theo từng Route (`backend_bridge/meta-webhook/index.js`)

Mọi route thay đổi dữ liệu hoặc gửi tin cho khách hàng đều bắt buộc đi qua middleware **`requireAuth`** (yêu cầu header `Authorization: Bearer <Supabase_User_JWT_hoặc_API_KEY>` hoặc `x-api-key: <API_KEY>`). Nếu không có token hợp lệ, server trả về ngay **`401 Unauthorized`**.

| Route | Phương thức | Yêu cầu Xác thực & Kiểm soát |
| :--- | :--- | :--- |
| `/health` | `GET` | Công khai — chỉ trả trạng thái `ok` và tên biến còn thiếu, không lộ giá trị bí mật. |
| `/webhook` | `GET` | Kiểm tra `hub.mode === 'subscribe'` và `hub.verify_token === VERIFY_TOKEN`. |
| `/webhook` | `POST` | Bắt buộc khớp chữ ký `x-hub-signature-256` (HMAC-SHA256 bằng `META_APP_SECRET` trên raw body); sai chữ ký trả `403 Forbidden`. |
| `/auth/facebook` | `GET` | Redirect sang trang đăng nhập OAuth của Facebook. |
| `/auth/facebook/callback` | `GET` | Đổi `code` dùng 1 lần từ Facebook OAuth sang `page_access_token` bằng `META_APP_SECRET` phía server. |
| `/auth/facebook/exchange-token` | `POST` | **Bắt buộc `requireAuth`** (`Authorization` hoặc `x-api-key`). |
| `/connected-pages` | `GET` | **Bắt buộc `requireAuth`** — chỉ trả `page_id`, `page_name`, không bao giờ trả `page_access_token`. |
| `/messages` | `GET` | **Bắt buộc `requireAuth`**. |
| `/send-message` | `POST` | **Bắt buộc `requireAuth`** + bắt buộc cờ xác nhận duyệt của nhân viên **`approved: true`** (`400 Bad Request` nếu thiếu). |
| `/send-tryon-image` | `POST` | **Bắt buộc `requireAuth`** + bắt buộc cờ xác nhận duyệt **`approved: true`**. |
| `/bookings` | `GET`, `POST` | **Bắt buộc `requireAuth`**. |
| `/settings` | `GET`, `PUT` | **Bắt buộc `requireAuth`**. |

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
│   │   ├── .env.example                        # Mẫu biến môi trường trên Render
│   │   ├── README.md                           # Tài liệu API & hướng dẫn vận hành webhook
│   │   ├── index.js                            # Express server: requireAuth, OAuth FB, Webhook HMAC, Signed URL
│   │   └── package.json
│   └── zalo-manager-bot/
├── database/
│   ├── schema.sql                              # Toàn bộ schema PostgreSQL cho project Supabase mới
│   └── migrations/
│       └── 20261116_meta_webhook.sql           # Migration bổ sung cột, unique index, connected_pages, salon_settings
└── README.md
```

---

## 4. Hướng dẫn Cài đặt & Cấu hình Môi trường (Dành cho Developer)

### A. Khởi tạo Supabase Database & Private Storage Bucket
1. Mở **Supabase SQL Editor**, chạy file [`database/schema.sql`](database/schema.sql) (nếu là project mới) hoặc [`database/migrations/20261116_meta_webhook.sql`](database/migrations/20261116_meta_webhook.sql) (nếu đã có các bảng cơ bản).
2. Tạo Storage bucket **`customer-media`** ở chế độ **Private (`public = false`)**:
   - Ảnh khuôn mặt khách hàng là dữ liệu nhạy cảm: **không bật public bucket**.
   - Backend sử dụng `createSignedUrl(path, 3600)` để cấp đường dẫn có chữ ký và tự hết hạn sau 1 giờ.
3. Đặt khóa Gemini cho Edge Function `tryon-analyze` trong Supabase Secrets:
   ```bash
   supabase secrets set GEMINI_API_KEY=<YOUR_GEMINI_API_KEY>
   ```

### B. Phân loại Biến môi trường trên Render (`https://pyincc-ai-app.onrender.com`)

#### 1. Nhóm Khóa Bí mật Bắt buộc (`REQUIRED SECRETS` — tuyệt đối không commit vào Git hoặc nhúng vào APK):
- `SUPABASE_SERVICE_ROLE_KEY`: Khóa `service_role` từ Supabase Dashboard (chỉ dùng ở backend Render).
- `META_APP_SECRET`: Khóa bí mật ứng dụng Meta để kiểm tra HMAC `x-hub-signature-256` và ký `appsecret_proof`.
- `API_KEY`: Khóa xác thực nội bộ cho middleware `requireAuth`.
- `VERIFY_TOKEN`: Chuỗi bí mật dùng cho bước bắt tay xác minh `GET /webhook` với Meta.

#### 2. Nhóm Cấu hình Công khai / Định danh (`PUBLIC / NON-SECRET CONFIG`):
- `SUPABASE_URL`: `https://ihufvqrxdswgbagzhydb.supabase.co`
- `SUPABASE_STORAGE_BUCKET`: `customer-media`
- `META_GRAPH_API_VERSION`: `v19.0`
- `META_APP_ID`: ID ứng dụng Meta phục vụ luồng OAuth `/auth/facebook`.
- `DEFAULT_ORG_ID`: UUID tổ chức mặc định trong bảng `organizations` (tùy chọn).

### C. Build & Chạy Ứng dụng Flutter
```bash
cd mobile_app
flutter pub get
flutter analyze --no-fatal-infos
flutter build apk --debug
```
> **Lưu ý khi dùng `--dart-define`:** Khi đóng gói APK, chỉ được truyền các địa chỉ endpoint công khai (`WEBHOOK_API_URL`, `TRYON_API_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`). Tuyệt đối không truyền `SUPABASE_SERVICE_ROLE_KEY`, `META_APP_SECRET`, hoặc `GEMINI_API_KEY` vào `--dart-define` vì mọi chuỗi trong APK đều có thể bị dịch ngược.

---

## 5. Bảo mật, Xoay vòng Khóa (Key Rotation) & Kiểm thử trước Production

### A. Xoay vòng & Thu hồi khóa cũ (Key Rotation) trước khi chạy Production
Nếu bất kỳ khóa hoặc token nào từng xuất hiện trong lịch sử commit hoặc môi trường thử nghiệm trước đây, **bắt buộc thực hiện xoay vòng khóa trước khi đưa vào vận hành thật**:
1. **Gemini API Key:** Thu hồi key cũ trong Google AI Studio, tạo key mới và cập nhật vào `supabase secrets set GEMINI_API_KEY=...`.
2. **Supabase Service Role Key & Database Password:** Xoay vòng key trong Supabase Settings nếu từng lộ ra ngoài.
3. **Meta App Secret & Page Access Token:** Reset `App Secret` trong Meta for Developers (việc này cũng tự động vô hiệu hóa các token cũ) và kết nối lại Fanpage qua `/auth/facebook`.
4. **`API_KEY` & `VERIFY_TOKEN` trên Render:** Đổi sang chuỗi ngẫu nhiên mới (tối thiểu 32 ký tự) trước khi golive.

### B. Danh mục Kiểm thử Bảo mật Bắt buộc trước khi dùng thật
Chạy 3 bài kiểm thử sau để xác nhận hệ thống đã khóa chặt trước khi kết nối khách hàng thật:

1. **Gọi `/send-message` không có token — Phải nhận `401 Unauthorized`:**
   ```bash
   curl -i -X POST "https://pyincc-ai-app.onrender.com/send-message" \
     -H "Content-Type: application/json" \
     -d '{"recipientId":"TEST_PSID","text":"Test","approved":true}'
   # Kỳ vọng: HTTP/1.1 401 Unauthorized
   ```

2. **Gửi `POST /webhook` giả với chữ ký sai — Phải nhận `403 Forbidden`:**
   ```bash
   curl -i -X POST "https://pyincc-ai-app.onrender.com/webhook" \
     -H "Content-Type: application/json" \
     -H "x-hub-signature-256: sha256=0000000000000000000000000000000000000000000000000000000000000000" \
     -d '{"object":"page","entry":[]}'
   # Kỳ vọng: HTTP/1.1 403 Forbidden
   ```

3. **Truy cập trực tiếp ảnh trong bucket `customer-media` bằng URL công khai (không có chữ ký) — Phải bị từ chối (`400`/`403`):**
   ```bash
   curl -i "https://ihufvqrxdswgbagzhydb.supabase.co/storage/v1/object/public/customer-media/facebook/test.jpg"
   # Kỳ vọng: Bị từ chối (Bucket not public / 400 / 403) khi bucket customer-media đặt ở chế độ Private.
   ```
