# PYINCC AI CRM

Ứng dụng quản lý tiệm phun xăm, spa và thẩm mỹ viện. Chủ tiệm (admin Fanpage) quản lý toàn bộ, duyệt mọi nội dung trước khi gửi tới khách hàng.

> **Repo công khai:** Không bao giờ commit `.env`, khóa API, token, keystore, hoặc ảnh khuôn mặt khách hàng thật.

## Mô hình hoạt động

- **Business AI của Meta** chăm sóc 100% khách trên Messenger (giá, giờ làm việc, địa chỉ, đặt lịch). Ứng dụng không trả lời khách thay AI khi chưa được chuyển.
- **Ứng dụng** nhận ca khi Business AI chuyển hội thoại (Conversation Routing) hoặc khi chủ tiệm chụp ảnh khách trực tiếp tại tiệm (Luồng B).
- **Gemini** chỉ làm việc trong ứng dụng, phục vụ chủ tiệm: phân tích ảnh khách, nhận xét tham khảo, nhắc lịch kiểm tra sau 7 ngày. Gemini không tự gửi tin cho Facebook.
- **Chủ tiệm** duyệt và bấm gửi mọi nội dung tới khách hàng. Server bắt buộc kiểm tra trạng thái `approved` và `approved_by` trong database trước khi gọi Graph API.

## Trạng thái đã xác minh

| Hạng mục | Trạng thái | Ghi chú |
|---|---|---|
| Domain backend `https://pyincccrm.bothelper.vn` | ✅ Đã chạy | `/health` trả `200`, chạy qua Cloudflare + Render |
| Supabase Postgres + 17 bảng bật RLS | ✅ Đã chạy | Đã chạy đủ migration bảo mật, `handoff_cases`, `audit_logs`, `onboarding_codes` |
| Đăng nhập email + kích hoạt quyền `owner` | ✅ Đã chạy | Hỗ trợ `POST /onboarding/claim` bằng mã thiết lập tiệm |
| Kết nối Fanpage Facebook (Android SDK) | ✅ Đã cấu hình | Đã thêm nền tảng Android (`vn.pyincc.aicrm`), xin đủ `pages_show_list`, `pages_messaging`, `pages_manage_metadata` |
| Catalog theo tiệm (không giá, không mặc định) | ✅ Đã chạy | `GET/POST/PUT/DELETE /catalog` cách ly theo `org_id` |
| Luồng B: Chụp ảnh tại tiệm + phân tích Gemini + duyệt/gửi | ✅ Đã chạy | Giới hạn 50 lượt/ngày/tiệm, kiểm thử tự động 6/6 kịch bản |
| Lịch hẹn & nhắc kiểm tra sau 7 ngày | ✅ Đã chạy | `GET /bookings/reminders`, `PATCH /bookings/:id/followup` (chỉ nhắc chủ tiệm, không tự nhắn khách) |
| Tạo ảnh demo ghép mày/môi | ⏳ Chờ model | `POST /api/tryon/generate` trả `501 NOT_IMPLEMENTED` |
| Luồng A: Nhận ca từ Business AI (Conversation Routing) | ⏳ Chờ Giai đoạn 0 | Chờ kết quả test `thread_owner` / `take_thread_control` / `pass_thread_control` trên Page test |
| Thông báo đẩy (FCM) | ⬜ Chưa làm | Giai đoạn 4 |
| App Review & Business Verification | ⬜ Chưa nộp | Bắt buộc trước khi mở cho tiệm ngoài danh sách tester |

## Thiết lập

### 1. Business Suite (chủ tiệm)
- Dán prompt CSKH trong [docs/business-ai-prompt.md](docs/business-ai-prompt.md) (có thể sao chép trực tiếp từ mục Cài đặt trong app).
- Bật **"Take control of conversations with your Business Agent"** cho ứng dụng.

### 2. Meta for Developers
- Thêm nền tảng Android: package `vn.pyincc.aicrm`, class `vn.pyincc.aicrm.MainActivity`, key hash đúng keystore đã ký APK.
- Đặt ứng dụng làm **default app** trong Conversation routing của Page test.
- Subscribe webhook: `messages`, `messaging_handover`, `standby`, `messaging_postbacks`, `messaging_referral`.

### 3. Supabase
- Chạy `database/schema.sql`, rồi lần lượt các file trong `database/migrations/`.
- Đảm bảo **RLS = `true`** cho mọi bảng trong schema `public`.
- Bucket `customer-media` ở chế độ **private**.

### 4. Render (backend `backend_bridge/meta-webhook`)
- Biến bí mật (chỉ đặt trong Render Dashboard): `SUPABASE_SERVICE_ROLE_KEY`, `META_APP_SECRET`, `VERIFY_TOKEN`, `PAGE_TOKEN_ENC_KEY`, `GEMINI_API_KEY`.
- Biến cấu hình: `NODE_ENV=production`, `SUPABASE_URL`, `SUPABASE_STORAGE_BUCKET`, `META_APP_ID`, `META_GRAPH_API_VERSION`, `PUBLIC_BASE_URL`, `BOOTSTRAP_OWNER_EMAIL`.
- **Không đặt** `DEFAULT_ORG_ID`, `PAGE_ID`, `PAGE_ACCESS_TOKEN`, `API_KEY` cho production.

### 5. Build APK (GitHub Actions)
- CI chạy `node --check`, `node --test`, `flutter analyze --no-fatal-infos`, `flutter test`, rồi build `app-debug.apk`.
- APK chỉ nhận `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `TRYON_API_URL` (không bao giờ nhúng `SERVICE_ROLE`, `META_APP_SECRET`, `GEMINI_API_KEY`).

## Bảo mật và quyền riêng tư

- Mọi khóa bí mật chỉ nằm trên Render và Supabase Secrets.
- Ảnh khuôn mặt khách chỉ xử lý khi có xác nhận đồng ý, đã xóa siêu dữ liệu EXIF/GPS trước khi tải lên, lưu private và truy cập qua signed URL 1 giờ.
- Gemini không tự gửi nội dung ra ngoài ứng dụng; mọi tin gửi đi đều đi qua nút Duyệt của chủ tiệm.
- Xem chi tiết tại `/privacy`, `/terms`, `/data-deletion` trên backend.
