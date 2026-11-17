# PYINCC — Hệ thống Quản lý Vận hành & CSKH AI cho Thẩm mỹ viện / Spa

Ứng dụng **PYINCC AI Beauty Manager** (Flutter) kết hợp cùng **Meta Webhook Backend** (`backend_bridge/meta-webhook/index.js` trên Render) và **Supabase** (Database, Private Storage, Realtime, Edge Functions) dành cho cơ sở phun xăm thẩm mỹ, spa và salon. Hệ thống tuân thủ nguyên tắc **Human-in-the-loop xác thực ở Database** (trạng thái duyệt `approval_status = 'approved'`, `approved_by`, `approved_at` được lưu và đọc trực tiếp từ cơ sở dữ liệu trước khi gửi) và **Zero-Key UI** (người dùng cuối không bao giờ nhìn thấy hay phải nhập API Key, App Secret hay Page Access Token).

---

## 1. Kiến trúc Tổng thể

1. **Ứng dụng Flutter (`mobile_app/`) — Giao diện 3 Tab hợp nhất (`IndexedStack`):**
   - **Tab 1 — `Hộp thư AI` (`Trung tâm CSKH AI`):** Hiển thị thống kê nhanh (KPI Strip), lọc hội thoại theo phân loại AI (*Ca khó / Sửa mày*, *Hỏi giá & Lịch*, *Khách gửi ảnh*, *Đã trả lời*), xem ảnh khách gửi từ Supabase Storage qua Signed URL, mở nhanh Studio AI cho từng khách và duyệt câu trả lời (`POST /messages/:id/approve` → `POST /send-message`).
   - **Tab 2 — `Studio AI` (`Studio AI • Thử Mày & Môi`):** Tải/chụp ảnh mặt mộc, gọi Supabase Edge Function `tryon-analyze` để phân tích dáng mặt & tông da, ghép mẫu Trước/Sau (`BeforeAfter`), và bấm **Duyệt gửi khách** (`POST /tryon-drafts` → `POST /send-tryon-image`) để lưu bản ghi duyệt trong bảng `customer_media`, tạo Signed URL và gửi qua Messenger cho khách.
   - **Tab 3 — `Quản lý Tiệm` (`SalonOperationsHubScreen`):** Gộp gọn 2 nhánh vận hành trong 1 màn hình:
     - **Nhánh `Ca trực & Lịch hẹn`:** Đồng bộ công tắc nhận khách trong ca (`GET/PUT /settings`) và danh sách lịch hẹn (`GET/POST /bookings`).
     - **Nhánh `Kết nối & Chủ tiệm`:** Nút duy nhất **“Kết nối với Facebook”** (tự động đổi Page Access Token ngầm ở máy chủ) và khung lưu **Kịch bản & Bảng giá chuẩn của Chủ tiệm** (`GET/PUT /settings`).

2. **Meta Webhook & Operations Backend (`backend_bridge/meta-webhook/index.js` — chạy trên Render):**
   - URL triển khai: `https://pyincc-ai-app.onrender.com` (cấu hình trong `render.yaml`).
   - **Xác thực & Liên kết Fanpage tự động (`/auth/facebook`, `/auth/facebook/callback`, `/auth/facebook/exchange-token`, `/connected-pages`):** Đổi `User Access Token` của chủ tiệm sang Long-Lived Token, ký `appsecret_proof` bằng `META_APP_SECRET` trên server, gọi `GET /me/accounts` lấy danh sách Fanpage kèm `page_access_token`, tự động đăng ký Webhook (`/{page_id}/subscribed_apps`) và lưu vào bảng `connected_pages` trên Supabase.
   - **Nhận sự kiện Meta (`GET /webhook`, `POST /webhook`):** Kiểm tra chữ ký `x-hub-signature-256` bằng HMAC-SHA256 trên raw body, lọc ảnh từ domain CDN hợp lệ của Facebook (`fbcdn.net`, `fbsbx.com`), tải về buffer và upload lên Private bucket `customer-media`, tạo Signed URL qua `createSignedUrl(path, 3600)` và ghi idempotent vào `webhook_events`, `conversation_messages`, `customer_media`.
   - **Kiểm soát duyệt trong Database (`/messages/:id/approve`, `/send-message`, `/tryon-drafts`, `/send-tryon-image`):** Server không tin vào cờ `approved` gửi trong body mà truy vấn trực tiếp bảng `conversation_messages` / `customer_media` để kiểm tra `approval_status === 'approved'`, `approved_by` và `approved_at` trước khi gọi Facebook Graph API.

3. **Supabase (`database/schema.sql` & `database/migrations/20261116_meta_webhook.sql`) + Edge Functions:**
   - **Edge Function `tryon-analyze`:** `https://ihufvqrxdswgbagzhydb.supabase.co/functions/v1/tryon-analyze` — nhận ảnh mặt khách và danh mục mẫu, gọi Gemini bằng `GEMINI_API_KEY` lưu trong Supabase Secrets.
   - **PostgreSQL Tables:** `organizations`, `users`, `shifts`, `catalog_items`, `conversations`, `conversation_messages`, `customer_media`, `webhook_events`, `connected_pages`, `salon_settings`, `bookings`.
   - **Supabase Storage (`customer-media`):** Bucket đặt ở chế độ **Private (`public = false`)**; mọi truy cập ảnh đều thông qua hàm `createSignedUrl(path, 3600)` có thời hạn 1 giờ (không fallback về public URL).

---

## 2. Bảng Phân quyền & Cơ chế Xác thực (`backend_bridge/meta-webhook/index.js`)

Tuyệt đối không nhúng `API_KEY` nội bộ vào APK. Ứng dụng người dùng xác thực bằng Supabase User JWT (`Authorization: Bearer <JWT>`), còn tiến trình server nội bộ dùng `x-api-key`.

| Nhóm | Route | Cơ chế Xác thực & Kiểm soát |
| :--- | :--- | :--- |
| **Webhook Meta** | `GET /webhook`, `POST /webhook` | `VERIFY_TOKEN` (cho `GET`) và chữ ký HMAC-SHA256 `x-hub-signature-256` trên raw body (cho `POST`). Không dùng `requireAuth`. |
| **Người dùng App** | `/messages`, `/bookings`, `/settings`, `/connected-pages`, `/auth/facebook/exchange-token` | Middleware `requireAuth`: bắt buộc JWT Supabase hợp lệ (`Authorization: Bearer <JWT>`), xác thực qua `supabase.auth.getUser(token)`. |
| **Duyệt & Gửi tin/ảnh** | `POST /messages/:id/approve`, `POST /send-message`, `POST /tryon-drafts`, `POST /send-tryon-image` | Middleware `requireAuth` (JWT Supabase) + kiểm tra trực tiếp bản ghi trong DB có `approval_status === 'approved'`, `approved_by` và `approved_at` trước khi gửi. |
| **Nội bộ (Server)** | `GET /internal/status` | Middleware `requireInternalApiKey`: bắt buộc header `x-api-key` khớp `API_KEY` bằng `crypto.timingSafeEqual`. |

---

## 3. Cấu trúc Thư mục

```text
Pyincc-AI-app/
├── .github/workflows/build.yml                 # CI kiểm tra flutter analyze & build debug APK (Flutter 3.50.0)
├── render.yaml                                 # Render Blueprint triển khai dịch vụ meta-webhook
├── mobile_app/
│   ├── android/                                # Android native scaffold
│   ├── ios/                                    # iOS native scaffold
│   ├── lib/
│   │   ├── main.dart                           # Giao diện 3 tab: Hộp thư AI, Studio AI, Quản lý Tiệm
│   │   ├── screens/tryon/
│   │   │   └── tryon_studio_screen.dart        # Màn hình thử mẫu Mày/Môi Trước & Sau + Duyệt gửi khách
│   │   └── services/
│   │       ├── inbox_service.dart              # Kết nối /messages, /messages/:id/approve, /send-message, /bookings, /settings
│   │       └── tryon_image_service.dart        # Kết nối Edge Function tryon-analyze, /tryon-drafts & /send-tryon-image
│   └── pubspec.yaml
├── backend_bridge/
│   ├── meta-webhook/
│   │   ├── .env.example                        # Mẫu biến môi trường trên Render
│   │   ├── README.md                           # Tài liệu API & hướng dẫn vận hành webhook
│   │   ├── index.js                            # Express server: requireAuth (JWT), DB approval check, createSignedUrl
│   │   └── package.json
│   └── zalo-manager-bot/
├── database/
│   ├── schema.sql                              # Toàn bộ schema PostgreSQL cho project Supabase mới
│   └── migrations/
│       └── 20261116_meta_webhook.sql           # Migration bổ sung cột duyệt (approval_status, approved_by, approved_at)
└── README.md
```

---

## 4. Hướng dẫn Cài đặt & Cấu hình Môi trường (Dành cho Developer)

### A. Khởi tạo Supabase Database & Private Storage Bucket
1. Mở **Supabase SQL Editor**, chạy file [`database/schema.sql`](database/schema.sql) (nếu là project mới) hoặc [`database/migrations/20261116_meta_webhook.sql`](database/migrations/20261116_meta_webhook.sql) (nếu đã có các bảng cơ bản).
2. Tạo Storage bucket **`customer-media`** ở chế độ **Private (`public = false`)**:
   - Backend sử dụng `createSignedUrl(path, 3600)` trong `backend_bridge/meta-webhook/index.js` để tạo đường dẫn có chữ ký tự hết hạn sau 1 giờ; nếu không tạo được Signed URL, hàm sẽ báo lỗi chứ không trả về URL công khai.
3. Đặt khóa Gemini cho Edge Function `tryon-analyze` trong Supabase Secrets:
   ```bash
   supabase secrets set GEMINI_API_KEY=<YOUR_GEMINI_API_KEY>
   ```

### B. Phân loại Biến môi trường trên Render (`https://pyincc-ai-app.onrender.com`)

#### 1. Nhóm Khóa Bí mật Bắt buộc (`REQUIRED SECRETS` — chỉ đặt trên Render, tuyệt đối không đưa vào Git hoặc APK):
- `SUPABASE_SERVICE_ROLE_KEY`: Khóa `service_role` từ Supabase Dashboard.
- `META_APP_SECRET`: Khóa bí mật ứng dụng Meta để kiểm tra HMAC `x-hub-signature-256` và ký `appsecret_proof`.
- `VERIFY_TOKEN`: Chuỗi bí mật dùng cho bước bắt tay xác minh `GET /webhook` với Meta.
- `API_KEY`: Khóa xác thực dành riêng cho tiến trình nội bộ (`requireInternalApiKey`).

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
> **Quy tắc `--dart-define`:** Khi build APK, chỉ truyền các cấu hình định danh công khai (`WEBHOOK_API_URL`, `TRYON_API_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`). Không truyền `SUPABASE_SERVICE_ROLE_KEY`, `META_APP_SECRET`, `GEMINI_API_KEY` hay `API_KEY` nội bộ vào APK.

---

## 5. Quy trình Xoay vòng Khóa (Key Rotation) & Kiểm thử Bảo mật trước Production

### A. Quy trình Xoay vòng Khóa Không Gián đoạn (Zero-Downtime Key Rotation)
Thực hiện đúng theo thứ tự 4 bước sau để không làm gián đoạn hệ thống khi thay khóa:
1. **Bước 1 — Tạo khóa mới trước (chưa xóa khóa cũ):** Tạo `GEMINI_API_KEY` mới trên Google AI Studio, tạo `API_KEY` / `VERIFY_TOKEN` mới, và chuẩn bị `SUPABASE_SERVICE_ROLE_KEY` / `META_APP_SECRET` mới.
2. **Bước 2 — Cập nhật lên Render & Supabase Secrets:**
   - Chạy `supabase secrets set GEMINI_API_KEY=<NEW_KEY>` cho Edge Function.
   - Cập nhật các biến môi trường mới trong tab **Environment** trên Render Dashboard và cấu hình Webhook trên Meta.
3. **Bước 3 — Deploy & Kiểm tra hoạt động:** Chờ Render hoàn tất deploy phiên bản mới, kiểm tra `/health` và gửi thử sự kiện test để xác nhận khóa mới đã hoạt động ổn định.
4. **Bước 4 — Thu hồi (Revoke) khóa cũ:** Chỉ sau khi bước 3 thành công mới xóa/vô hiệu hóa các khóa cũ trên Google AI Studio, Supabase và Meta.

### B. Các lệnh `curl` Kiểm thử Bảo mật Thực tế (Chạy sau khi đã điền đủ `SUPABASE_SERVICE_ROLE_KEY` & `META_APP_SECRET` trên Render)
Khi chưa điền `SUPABASE_SERVICE_ROLE_KEY` và `META_APP_SECRET` trên Render, các route sẽ trả về `503 Service Unavailable`. Sau khi điền đủ 2 biến này, chỉ kết luận đạt chuẩn bảo mật khi cả **4 bài kiểm thử** dưới đây trả về đúng mã HTTP kỳ vọng:

```bash
BASE_URL="https://pyincc-ai-app.onrender.com"
PUBLIC_BUCKET_TEST_URL="https://ihufvqrxdswgbagzhydb.supabase.co/storage/v1/object/public/customer-media/facebook/test.jpg"

# 1. Gọi /send-message với JWT giả (khi đã có SUPABASE_SERVICE_ROLE_KEY) -> Kỳ vọng: HTTP 401 {"error":"Unauthorized"}
curl -i -X POST "$BASE_URL/send-message" \
  -H "Authorization: Bearer invalid.token.here" \
  -H "Content-Type: application/json" \
  -d '{"messageRecordId":"00000000-0000-0000-0000-000000000000"}'

# 2. Gửi POST /webhook với chữ ký HMAC sai (khi đã có META_APP_SECRET) -> Kỳ vọng: HTTP 403 Forbidden
curl -i -X POST "$BASE_URL/webhook" \
  -H "Content-Type: application/json" \
  -H "x-hub-signature-256: sha256=0000" \
  -d '{"object":"page","entry":[]}'

# 3. Gửi POST /webhook với chữ ký HMAC đúng (ký bằng META_APP_SECRET thật) -> Kỳ vọng: HTTP 200 EVENT_RECEIVED
BODY='{"object":"page","entry":[]}'
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$META_APP_SECRET" | sed 's/^.* //')
curl -i -X POST "$BASE_URL/webhook" \
  -H "Content-Type: application/json" \
  -H "x-hub-signature-256: sha256=$SIG" \
  -d "$BODY"

# 4. Truy cập trực tiếp bucket private bằng URL công khai (không có chữ ký) -> Kỳ vọng: HTTP 400 hoặc 403
curl -i "$PUBLIC_BUCKET_TEST_URL"
```
