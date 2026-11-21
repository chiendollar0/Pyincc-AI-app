# Quyền riêng tư và xử lý dữ liệu (PRIVACY) — PYINCC AI CRM

> Bản công khai cho người dùng được phục vụ trực tiếp trên backend tại `/privacy`, `/terms` và `/data-deletion`.

## 1. Dữ liệu thu thập và mục đích

- **Tài khoản chủ tiệm:** Email đăng nhập, vai trò `owner`, trạng thái hoạt động, nhật ký thao tác (`audit_logs`) — phục vụ xác thực và kiểm soát an toàn cho tài khoản chủ tiệm duy nhất.
- **Tích hợp Fanpage Facebook:** Mã Fanpage (`page_id`), tên Fanpage và Page Access Token (mã hóa AES-256-GCM trên máy chủ) — chỉ phục vụ nhận webhook chuyển ca và gửi phản hồi đã được chủ tiệm duyệt.
- **Ca tư vấn & ảnh khách hàng:** Ảnh khách hàng chụp tại tiệm (chỉ xử lý sau khi chủ tiệm xác nhận khách đã đồng ý) hoặc chuyển từ hội thoại Messenger, ghi chú ngắn, bản nháp phản hồi và lịch hẹn.
- **Siêu dữ liệu ảnh:** Trước khi tải lên máy chủ, ứng dụng tự động xoay đúng chiều, thu nhỏ và **xóa toàn bộ EXIF, tọa độ GPS và metadata thiết bị** (`ImagePreprocessor`).

## 2. Các bên thứ ba xử lý dữ liệu

| Bên xử lý | Vai trò | Phạm vi & biện pháp bảo vệ |
|---|---|---|
| **Supabase** | Cơ sở dữ liệu Postgres & Storage | Lưu trữ tách biệt theo từng tiệm (RLS), bucket `customer-media` ở chế độ **private**, truy cập qua signed URL hết hạn sau 60 phút. |
| **Google Gemini API** | Phân tích ảnh & soạn gợi ý nội bộ | Nhận ảnh đã xóa EXIF/GPS từ máy chủ PyinccCRM (giới hạn 50 lượt/ngày/tiệm). Gemini không kết nối Facebook và không tự gửi tin nhắn. |
| **Meta Platforms** | Messenger Webhook & Send API | Nhận sự kiện chuyển ca (xác thực HMAC SHA-256) và gửi phản hồi đã được chủ tiệm duyệt qua Graph API. |

## 3. Thời hạn lưu trữ

- Đường dẫn ảnh tạm (`signedUrl`): tự động hết hạn sau **60 phút**.
- Dữ liệu hội thoại, ca tư vấn, ảnh trong bucket riêng tư và nhật ký: lưu trong thời gian tiệm sử dụng dịch vụ hoặc cho đến khi chủ tiệm/khách hàng yêu cầu xóa.

## 4. Phân biệt hai mức thu hồi và xóa dữ liệu

1. **Thu hồi tích hợp Facebook (tự động qua callback):**
   - Khi người dùng gỡ **PyinccCRM** trong *Cài đặt Facebook → Tiện ích tích hợp cho doanh nghiệp (Business Integrations)*, backend nhận callback `/auth/facebook/data-deletion` và tự động:
     - Xóa bản ghi `connected_pages` và Page Token mã hóa do tài khoản Facebook đó kết nối.
     - Gỡ liên kết danh tính Facebook (`invited_fb_user_id = null`) trên `memberships` (không xóa dòng thành viên của người khác).
     - Ghi mã xác nhận vào `data_deletion_requests` để tra cứu tại `/data-deletion?code=<mã>`.
   - **Lưu ý quan trọng:** Thao tác gỡ trên Facebook **chỉ thu hồi tích hợp Facebook** và không tự xóa lịch sử hội thoại, ảnh tư vấn hay nhật ký đã lưu của tiệm trên Supabase.
2. **Xóa toàn bộ dữ liệu đã lưu trên Supabase:**
   - Gửi email yêu cầu xóa toàn bộ dữ liệu hội thoại, ảnh khách hàng, ca tư vấn và nhật ký về **phanhungkg03@gmail.com** (kèm tên tiệm hoặc mã xác nhận `/data-deletion` nếu có).
   - Yêu cầu được xử lý hoàn tất trong vòng **48 giờ**.
