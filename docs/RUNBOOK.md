# Sổ tay vận hành & xử lý sự cố (RUNBOOK) — PYINCC AI CRM

## 1. Mở tiệm mới (Onboarding bằng mã 1 lần)

1. Tạo mã thiết lập trong bảng `public.onboarding_codes` trên Supabase SQL Editor:
   ```sql
   insert into public.onboarding_codes (code, org_name)
   values ('PYINCC-SALON-01', 'Tên Tiệm Mới');
   ```
2. Tạo tài khoản email cho chủ tiệm trong **Supabase → Authentication → Users** (đảm bảo đã **Confirm email**).
3. Chủ tiệm đăng nhập trên app → vào **Quản lý tiệm → Kết nối & Chủ tiệm → Nhập mã thiết lập tiệm** → nhập mã `PYINCC-SALON-01` → hệ thống tạo `organizations`, gắn `role = 'owner'`, `status = 'active'` và ghi `audit_logs` (`onboarding.claim`).
4. Sau đó chủ tiệm bấm **Kết nối với Facebook** để liên kết Fanpage và cấu hình danh mục dịch vụ (không giá).

## 2. Quy trình xoay khóa (Key Rotation)

| Khóa | Quy trình xoay an toàn |
|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | Tạo/xoay trong Supabase Dashboard → cập nhật trên Render Environment → Manual Deploy → chạy `./scripts/smoke.sh`. |
| `META_APP_SECRET` | Reset trong Meta for Developers → cập nhật trên Render → Manual Deploy → gửi test webhook xác nhận chữ ký `200`. |
| `VERIFY_TOKEN` | Đổi giá trị mới trên Render → cập nhật đồng bộ trong Meta Webhooks → Verify lại. |
| `GEMINI_API_KEY` | Tạo key mới trên Google AI Studio → cập nhật `GEMINI_API_KEY` trên Render → test chụp 1 ảnh trong Studio AI → thu hồi key cũ. |
| `PAGE_TOKEN_ENC_KEY` | **Cảnh báo:** đổi khóa này sẽ làm toàn bộ Page Token đang mã hóa trong `connected_pages` không giải mã được. Luôn sao lưu khóa cũ; sau khi đổi khóa, yêu cầu các chủ tiệm bấm **Làm mới kết nối Facebook** để mã hóa lại token. |

> Nếu bất kỳ bí mật nào từng lộ trong commit Git hoặc đoạn chat, **thu hồi và thay mới ngay lập tức** trước khi tiếp tục dùng production.

## 3. Failover / Quá hạn mức Gemini

- Mỗi tiệm có trần **50 lượt phân tích/ngày** (tính theo ngày Việt Nam UTC+7). Khi chạm trần, API trả `429 AI_DAILY_CAP` mà không tốn dung lượng Storage.
- Nếu Google Gemini gián đoạn (`502 AI_FAILED`) hoặc chưa đặt khóa (`503 GEMINI_NOT_CONFIGURED`):
  - Chủ tiệm vẫn đọc, sửa nháp thủ công, duyệt và gửi tin bình thường trong Hộp thư.
  - Kiểm tra log Render (`gemini` / `AI_FAILED`), xác minh `GEMINI_API_KEY` còn hiệu lực và hạn mức billing trên Google AI Studio.

## 4. Rollback nhanh

1. **Backend (Render):** Vào **Render Dashboard → pyincc-meta-webhook → Events** → chọn bản deploy ổn định gần nhất → bấm **Rollback to this deploy** → chạy `./scripts/smoke.sh`.
2. **Database (Supabase):** Không xóa bảng hoặc sửa file migration cũ. Mọi điều chỉnh khắc phục phải viết thành file migration mới tiến theo ngày (`YYYYMMDD_<mo_ta>.sql`).
3. **Mobile APK:** Phát hành bản APK tăng `versionCode` mới từ commit ổn định trên `main`.

## 5. Sự cố thường gặp

| Triệu chứng | Nguyên nhân thường gặp | Cách xử lý |
|---|---|---|
| Render thoát ngay với `{"event":"config_missing","missing":[...]}` | Thiếu biến bắt buộc (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `META_APP_SECRET`, `VERIFY_TOKEN`) khi `NODE_ENV=production` | Bổ sung biến trên Render Environment và deploy lại |
| Bấm Đăng nhập trên APK báo `"Ứng dụng chưa được cấu hình đầy đủ"` | APK build thiếu `SUPABASE_ANON_KEY` | Kiểm tra GitHub Secret `SUPABASE_ANON_KEY` và build lại APK |
| Release APK không gọi được mạng | Thiếu quyền `INTERNET` trong `src/main/AndroidManifest.xml` | Đảm bảo `<uses-permission android:name="android.permission.INTERNET" />` có mặt trong manifest chính |
| Gửi tin trả `422 OUTSIDE_24H_WINDOW` | Đã quá 24 giờ kể từ tin nhắn cuối của khách | Chờ khách nhắn lại trước khi bấm gửi |
| Tài khoản phụ báo `403 FORBIDDEN_ROLE` hoặc `403 SINGLE_OWNER_ONLY` | Phiên bản v1 chỉ cho phép 1 tài khoản Chủ tiệm (`owner`) duy nhất | Đăng nhập bằng tài khoản Chủ tiệm đã kích hoạt của tiệm |
