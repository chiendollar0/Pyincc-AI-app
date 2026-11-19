# PYINCC Meta Webhook

Node.js service for receiving Meta webhook events, validating Meta signatures, storing customer messages/media in Supabase, and sending staff-approved Messenger replies.

## Deploy lên Render bằng Blueprint (`render.yaml`)

1. Mở [Render Dashboard](https://dashboard.render.com) → **New +** → **Blueprint** và chọn repository `chiendollar0/Pyincc-AI-app`.
2. Điền các biến bảo mật `sync: false` trên Render Dashboard (không lưu trong repo):
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `META_APP_SECRET`
   - `BOOTSTRAP_OWNER_EMAIL` (email Chủ tiệm đầu tiên; chỉ dùng khi bảng `organizations` đang trống)
3. `VERIFY_TOKEN` và `PAGE_TOKEN_ENC_KEY` được sinh tự động (`generateValue: true`) ở lần tạo service đầu tiên.
   - **QUAN TRỌNG:** Sao lưu giá trị `PAGE_TOKEN_ENC_KEY` ra nơi an toàn ngoài Render (trình quản lý mật khẩu). Nếu mất hoặc thay đổi khóa này sau khi đã kết nối Fanpage, toàn bộ Page Access Token đã mã hóa trong `connected_pages` sẽ không giải mã được.
4. Không đặt `DEFAULT_ORG_ID`, `PAGE_ID`, hoặc `PAGE_ACCESS_TOKEN` trên production (xóa các biến cũ khỏi Dashboard nếu trước đó từng đặt). Mỗi tiệm kết nối Fanpage riêng qua OAuth (`/auth/facebook/exchange-token`).
5. `autoDeploy: false` được bật trong `render.yaml` để kiểm soát thời điểm phát hành production (deploy thủ công hoặc qua Render Deploy Hook).

## Local run

```bash
cp .env.example .env
npm install
npm start
```

## Database Migrations (chạy trên Supabase trước khi deploy)

1. Với project mới: chạy `database/schema.sql`, sau đó chạy `database/migrations/20261119_rls_and_security.sql`.
2. Với project đang chạy: chạy lần lượt các migration idempotent:
   - `database/migrations/20261119_rls_and_security.sql`
   - `database/migrations/20261119_p0_p1_hardening.sql`
   - `database/migrations/20261119_production_hardening.sql` (đảm bảo bảng `data_deletion_requests`, cột `customer_media.created_by`, `customer_media.page_id`, và unique partial indexes `memberships_pending_email_uidx`, `memberships_pending_fb_uidx`).
3. Tạo bucket Storage riêng tư `customer-media` (truy cập qua signed URL có thời hạn 1 giờ; đường dẫn ảnh Facebook cách ly theo `facebook/<org_id>/<hash>.<ext>`).

## Quy trình duyệt ảnh thử (`Try-On Drafts`)

- `POST /tryon-drafts`: tạo bản nháp ảnh ở trạng thái `pending`, lưu `created_by` (UUID người tạo) và `page_id` (Fanpage đích).
- `POST /tryon-drafts/:id/approve`:
  - **Nhân viên (`staff`) không được phép tự duyệt bản nháp do chính mình tạo** (ràng buộc `created_by != req.authUser.id`, trả `403 SELF_APPROVAL_NOT_ALLOWED`).
  - **Ngoại lệ cho tiệm 1 người:** Chủ tiệm (`owner`) được phép duyệt bản nháp của chính mình để vẫn vận hành được khi tiệm chưa có nhân viên thứ hai.
- `POST /send-tryon-image` & `POST /send-message`: bắt buộc có `page_id` tường minh (không đoán Page đầu tiên của tiệm), khóa nguyên tử `sending` trước khi gọi Meta Graph API và hoàn trạng thái `approved` nếu gửi thất bại.

## Meta configuration & Data Deletion

- Webhook callback: `https://<your-domain>/webhook` (xác thực `VERIFY_TOKEN` trên `GET` và HMAC-SHA256 `x-hub-signature-256` trên `POST`).
- Data Deletion callback: `POST /auth/facebook/data-deletion` (xác thực `signed_request`, xóa `connected_pages` theo `connected_by_fb_user_id`, chỉ gỡ liên kết `invited_fb_user_id = null` trên `memberships` chứ không xóa dòng membership, ghi bảng `data_deletion_requests` và trả `500` nếu không ghi được).

## Checklist kiểm thử trước khi deploy production

1. Chạy migration `20261119_production_hardening.sql` trên Supabase.
2. Kiểm tra `POST /auth/facebook/data-deletion` với `signed_request` test → mở URL `/data-deletion?code=...` xác nhận hiển thị `completed`.
3. Kiểm tra `POST /tryon-drafts/:id/approve` bằng tài khoản `staff` tự duyệt bản nháp của mình → xác nhận trả `403 SELF_APPROVAL_NOT_ALLOWED`.
4. Kiểm tra các route ghi (`/auth/facebook/exchange-token`, `/memberships/invite`, `/send-message`, `/send-tryon-image`, `/bookings`) đã áp dụng `express-rate-limit` và cách ly tuyệt đối theo `org_id`.
