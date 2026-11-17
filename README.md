# PYINCC — Hệ thống Quản lý Vận hành & CSKH AI cho Thẩm mỹ viện / Spa

Ứng dụng **PYINCC AI Beauty Manager** (Flutter) kết hợp cùng **Meta Webhook & Operations Backend** (`backend_bridge/meta-webhook/index.js` trên Render) và **Supabase** (PostgreSQL Database, Private Storage, Realtime, Edge Functions) dành cho cơ sở phun xăm thẩm mỹ, spa và salon.

Hệ thống được thiết kế theo 3 nguyên tắc cốt lõi:
1. **Zero-Key UI:** Chủ tiệm và nhân viên không bao giờ nhìn thấy hay phải nhập bất kỳ `API Key`, `App Secret` hay `Page Access Token` nào trên ứng dụng.
2. **Human-in-the-loop xác thực ở Database:** AI chỉ phân loại, tóm tắt và gợi ý tư vấn/ảnh mẫu; server kiểm tra trực tiếp trạng thái duyệt (`approval_status = 'approved'`, `approved_by`, `approved_at`) trong cơ sở dữ liệu trước khi gửi.
3. **Multi-tenant & RBAC (`memberships`):** Quyền truy cập (`owner` / `staff`) và định danh tiệm (`org_id`) được tra cứu trực tiếp từ bảng `memberships` trong Supabase theo JWT của người đăng nhập, tuyệt đối không nhận `org_id` hay `role` từ phía client.

---

## 1. Trạng thái Triển khai đến Thời điểm Hiện tại (Cập nhật 17/11/2026)

| Hạng mục | Trạng thái | Chi tiết thực tế |
| :--- | :--- | :--- |
| **Flutter Mobile App (`mobile_app/`)** | **Hoàn tất & Build xanh (Run #25)** | Giao diện 3 tab hợp nhất (`IndexedStack`): `Hộp thư AI` • `Studio AI` • `Quản lý Tiệm`. GitHub Actions từ Run `#14` → `#25` đều `success`, xuất bản cài `app-debug-apk` (`67.54 MiB`). |
| **AI Phân tích Khuôn mặt (`tryon-analyze`)** | **Hoạt động độc lập qua Supabase** | `TryOnImageService.analyzeFace()` gọi trực tiếp Supabase Edge Function `https://ihufvqrxdswgbagzhydb.supabase.co/functions/v1/tryon-analyze` (hoạt động ngay cả khi chưa kết nối Meta). |
| **Backend trên Render (`srv-dbtmrs3l550s738n7v00`)** | **Đã Live (`https://pyincc-ai-app.onrender.com`)** | Đã cấu hình đầy đủ 6 biến trên Render: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_STORAGE_BUCKET`, `META_GRAPH_API_VERSION`, `VERIFY_TOKEN`, `API_KEY`. Đã kiểm chứng xác thực JWT thật với Supabase (`401 Unauthorized` với JWT giả). |
| **Phân quyền `memberships` (`owner` / `staff`)** | **Đã có trong Code & Schema (`70a3c46`)** | Hỗ trợ tự tạo `organization` + `owner` cho chủ tiệm đầu tiên, mời nhân viên (`POST /memberships/invite`), kích hoạt khi nhân viên đăng nhập, và lọc `.eq('org_id', req.orgId)` trên toàn bộ truy vấn. |
| **Bảo mật Token & Storage** | **Đã có trong Code (`70a3c46`)** | Mã hóa `page_access_token` bằng **AES-256-GCM** trước khi lưu vào `connected_pages`, kiểm tra `/debug_token`, hỗ trợ `/auth/facebook/deauthorize`, và dùng `createSignedUrl(path, 3600)` trên private bucket `customer-media`. |
| **Tài khoản Meta for Developers (`META_APP_ID`, `META_APP_SECRET`)** | **Đang tạm hoãn (Chờ SĐT xác minh Meta)** | Do tài khoản Meta Developer đang chờ số điện thoại mới để xác minh mở App, 2 biến `META_APP_ID` và `META_APP_SECRET` trên Render tạm thời để trống. Trong thời gian này, App Flutter, Studio AI (`tryon-analyze`), Lịch hẹn (`/bookings`) và Cấu hình Tiệm (`/settings`) vẫn hoạt động độc lập. |

---

## 2. Kiến trúc Chi tiết các Phân hệ

### A. Ứng dụng Flutter (`mobile_app/`) — Giao diện 3 Tab (`IndexedStack`)
- **Tab 1 — `Hộp thư AI` (`Trung tâm CSKH AI`):**
  - Thanh thống kê nhanh (KPI Strip): *Tổng hội thoại*, *Ca khó / Sửa*, *Hỏi giá / Lịch*.
  - Bộ lọc theo phân loại AI (*Tất cả*, *Ca khó*, *Hỏi giá & Lịch*, *Gửi ảnh*, *Đã trả lời*).
  - Hiển thị ảnh khách hàng từ Supabase Storage qua Signed URL, nút chuyển nhanh sang **Studio AI** kèm thông tin khách, và quy trình 2 bước **Duyệt & Gửi** (`POST /messages/:id/approve` → `POST /send-message`).
- **Tab 2 — `Studio AI` (`Studio AI • Thử Mày & Môi`):**
  - Chọn ảnh từ thư viện hoặc chụp trực tiếp, phân tích dáng mặt & tông da qua Edge Function `tryon-analyze`, xem so sánh Trước/Sau (`BeforeAfter`), lọc mẫu theo danh mục (*Chân mày* / *Môi*) kèm giá niêm yết.
  - Nút **Duyệt gửi khách** (`POST /tryon-drafts` → `POST /send-tryon-image`) lưu ảnh lên bucket `customer-media` kèm `approved_by` / `approved_at` trong DB.
- **Tab 3 — `Quản lý Tiệm` (`SalonOperationsHubScreen`):**
  - **Nhánh `Ca trực & Lịch hẹn`:** Bật/tắt trạng thái nhận khách tự động (`GET/PUT /settings`) và quản lý lịch hẹn trong ngày (`GET/POST /bookings`).
  - **Nhánh `Kết nối & Chủ tiệm`:** Nút 1 chạm **“Kết nối với Facebook”** và khung lưu **Kịch bản & Bảng giá chuẩn của Chủ tiệm** (`GET/PUT /settings`).

### B. Phân quyền & Xác thực trên Backend (`backend_bridge/meta-webhook/index.js`)

```text
Chủ tiệm đăng nhập lần đầu → Server tạo organization + memberships(owner, active)
Chủ tiệm mời nhân viên     → POST /memberships/invite → memberships(staff, pending)
Nhân viên đăng nhập        → Server khớp email/FB ID → memberships(staff, active)
Mọi request từ App         → requireAuth đọc user từ JWT → tra memberships → gắn req.orgId + req.userRole
```

| Nhóm | Route | Middleware & Kiểm soát |
| :--- | :--- | :--- |
| **Healthcheck** | `GET /health` | Công khai — chỉ trả `{"ok":true,"service":"pyincc-meta-webhook"}`, không lộ trạng thái biến môi trường. |
| **Webhook Meta** | `GET /webhook`, `POST /webhook` | `VERIFY_TOKEN` (cho `GET`) và chữ ký HMAC-SHA256 `x-hub-signature-256` trên raw body (cho `POST`). Tự động ánh xạ `page_id` → `org_id` qua bảng `connected_pages`. |
| **Thu hồi quyền FB** | `POST /auth/facebook/deauthorize` | Xác minh `signed_request` bằng HMAC-SHA256 (`META_APP_SECRET`) và xóa `connected_pages` của người dùng đó. |
| **Chỉ Chủ tiệm (`owner`)** | `GET /memberships`, `POST /memberships/invite`, `POST /auth/facebook/exchange-token` | `requireAuth` (JWT Supabase) + `requireRole('owner')`. Kiểm tra `/debug_token` của Facebook và mã hóa `page_access_token` bằng AES-256-GCM. |
| **Chủ tiệm & Nhân viên (`owner`, `staff`)** | `GET /connected-pages`, `GET /messages`, `GET/POST /bookings`, `GET/PUT /settings` | `requireAuth` + `requireRole('owner', 'staff')`. Mọi dữ liệu cách ly theo `req.orgId`; riêng sửa `consultationScript` trong `PUT /settings` yêu cầu `role === 'owner'`. |
| **Duyệt & Gửi tin/ảnh** | `POST /messages/:id/approve`, `POST /send-message`, `POST /tryon-drafts`, `POST /send-tryon-image` | `requireAuth` + `requireRole('owner', 'staff')` + kiểm tra trực tiếp bản ghi trong DB của đúng `req.orgId` có `approval_status === 'approved'`, `approved_by` và `approved_at`. |
| **Nội bộ (Server)** | `GET /internal/status` | `requireInternalApiKey`: bắt buộc header `x-api-key` khớp `API_KEY` bằng `crypto.timingSafeEqual`. |

---

## 3. Cấu trúc Thư mục Repo

```text
Pyincc-AI-app/
├── .github/workflows/build.yml                 # CI kiểm tra flutter analyze & build debug APK (Flutter 3.50.0)
├── render.yaml                                 # Render Blueprint cho dịch vụ pyincc-meta-webhook
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
│   │   ├── index.js                            # Express server: JWT + memberships RBAC, AES-256-GCM, DB approval, Signed URL
│   │   └── package.json
│   └── zalo-manager-bot/
├── database/
│   ├── schema.sql                              # Toàn bộ schema PostgreSQL (organizations, memberships, connected_pages...)
│   └── migrations/
│       └── 20261116_meta_webhook.sql           # Migration bổ sung memberships, salon_settings, connected_pages, cột duyệt
└── README.md
```

---

## 4. Hướng dẫn Cấu hình & Bổ sung Meta sau khi có SĐT Xác minh

### A. Những gì ĐÃ cấu hình xong trên Render (`https://pyincc-ai-app.onrender.com`)
Trên dịch vụ Render `srv-dbtmrs3l550s738n7v00`, 6 biến sau đã được thiết lập và hoạt động:
- `SUPABASE_URL` = `https://ihufvqrxdswgbagzhydb.supabase.co`
- `SUPABASE_SERVICE_ROLE_KEY` = *(Đã lưu bảo mật trên Render)*
- `SUPABASE_STORAGE_BUCKET` = `customer-media`
- `META_GRAPH_API_VERSION` = `v19.0`
- `VERIFY_TOKEN` = *(Đã lưu bảo mật trên Render)*
- `API_KEY` = *(Đã lưu bảo mật trên Render)*

### B. Việc cần làm trên Supabase (Làm ngay được không cần Meta)
1. Mở **Supabase SQL Editor** của project `ihufvqrxdswgbagzhydb`, chạy file [`database/schema.sql`](database/schema.sql) (nếu chưa tạo bảng) hoặc [`database/migrations/20261116_meta_webhook.sql`](database/migrations/20261116_meta_webhook.sql) để tạo đủ bảng `memberships`, `connected_pages`, `salon_settings` và các cột duyệt.
2. Tạo Storage bucket tên **`customer-media`** ở chế độ **Private (`public = false`)**.
3. Đảm bảo `GEMINI_API_KEY` đã được lưu trong Supabase Secrets cho Edge Function `tryon-analyze`:
   ```bash
   supabase secrets set GEMINI_API_KEY=<YOUR_GEMINI_API_KEY>
   ```

### C. Việc cần làm sau khi mở được tài khoản Meta for Developers
Khi bạn có số điện thoại mới để xác minh tài khoản Meta for Developers và tạo App Facebook:
1. Lấy **`App ID`** và **`App Secret`** tại **Meta for Developers → App Settings → Basic**.
2. Vào Render Dashboard (`https://dashboard.render.com/web/srv-dbtmrs3l550s738n7v00/env`) thêm 2 biến:
   - `META_APP_ID` = `<App ID của bạn>`
   - `META_APP_SECRET` = `<App Secret của bạn>`
3. Trong sản phẩm **Webhook** trên Meta for Developers, đặt:
   - **Callback URL:** `https://pyincc-ai-app.onrender.com/webhook`
   - **Verify Token:** Giá trị `VERIFY_TOKEN` trên Render
   - Đăng ký trường `messages` và `messaging_postbacks`.

---

## 5. Quy trình Xoay vòng Khóa & Kiểm thử Bảo mật

### A. Quy trình Xoay vòng Khóa Không Gián đoạn (Zero-Downtime Key Rotation)
1. **Bước 1 — Tạo khóa mới trước (chưa xóa khóa cũ)** trên Google AI Studio / Supabase / Meta.
2. **Bước 2 — Cập nhật khóa mới** vào Supabase Secrets và Render Environment.
3. **Bước 3 — Deploy & Kiểm tra hoạt động** trên phiên bản mới.
4. **Bước 4 — Thu hồi (Revoke) khóa cũ** sau khi xác nhận hệ thống mới chạy ổn định.

### B. 4 Bài Kiểm thử Bảo mật trên Render (`https://pyincc-ai-app.onrender.com`)

```bash
BASE_URL="https://pyincc-ai-app.onrender.com"
PUBLIC_BUCKET_TEST_URL="https://ihufvqrxdswgbagzhydb.supabase.co/storage/v1/object/public/customer-media/facebook/test.jpg"

# 1. [ĐÃ ĐẠT] Gọi /send-message với JWT giả (đã kiểm chứng với SUPABASE_SERVICE_ROLE_KEY thật)
# Kết quả thực tế: HTTP/1.1 401 Unauthorized {"error":"Unauthorized"}
curl -i -X POST "$BASE_URL/send-message" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIwMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDAifQ.fake_sig" \
  -H "Content-Type: application/json" \
  -d '{"messageRecordId":"00000000-0000-0000-0000-000000000000"}'

# 2. [ĐÃ ĐẠT] Truy cập trực tiếp bucket private bằng URL công khai (không có chữ ký)
# Kết quả thực tế: HTTP/1.1 400 Bad Request (Từ chối truy cập công khai)
curl -i "$PUBLIC_BUCKET_TEST_URL"

# 3. [CHỜ META_APP_SECRET] Gửi POST /webhook với chữ ký HMAC sai -> Kỳ vọng: HTTP 403 Forbidden
curl -i -X POST "$BASE_URL/webhook" \
  -H "Content-Type: application/json" \
  -H "x-hub-signature-256: sha256=0000" \
  -d '{"object":"page","entry":[]}'

# 4. [CHỜ META_APP_SECRET] Gửi POST /webhook với chữ ký HMAC đúng -> Kỳ vọng: HTTP 200 EVENT_RECEIVED
BODY='{"object":"page","entry":[]}'
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$META_APP_SECRET" | sed 's/^.* //')
curl -i -X POST "$BASE_URL/webhook" \
  -H "Content-Type: application/json" \
  -H "x-hub-signature-256: sha256=$SIG" \
  -d "$BODY"
```
