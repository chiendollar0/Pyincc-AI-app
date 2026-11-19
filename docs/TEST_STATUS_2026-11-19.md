# Trạng thái kiểm thử thực tế — 19/11/2026

Tài liệu này ghi nhận kết quả được cung cấp từ thiết bị người dùng và đối chiếu với mã nguồn. Đây không phải báo cáo kiểm thử end-to-end do CI thực hiện.

## Đã kiểm tra

| Hạng mục | Kết quả quan sát | Kết luận |
| --- | --- | --- |
| `GET /health` | Người dùng nhận `HTTP 200` cùng HTTP headers của Express/Render. | Dịch vụ Render đang phản hồi. Kết quả này không xác nhận webhook Meta hoạt động hoặc dữ liệu Supabase được ghi. |
| `GET /internal/webhook-status` | Người dùng nhận `HTTP/2 401` với `{"error":"Unauthorized"}`. | Request không được xác thực bằng `x-api-key` hợp lệ. Chưa lấy được bộ đếm webhook. Cần xác minh biến `API_KEY` trên Render và bảo đảm lệnh gửi đúng header; không chia sẻ key. |
| Thao tác lưu lịch trong app | Ảnh chụp hiển thị `HTTP 401`. | Lỗi chưa được sửa/xác minh. App hiện chưa tích hợp Supabase Auth; các request backend chỉ thêm bearer token nếu `BACKEND_AUTH_TOKEN` được build vào, mặc định rỗng. |
| Duyệt tin trong app | Ảnh chụp hiển thị `HTTP 401`. | Lỗi chưa được sửa/xác minh; cùng nguyên nhân thiếu JWT runtime như lưu lịch. |
| Tạo ảnh thử | Ảnh chụp hiển thị `HTTP 401` từ backend Render. | Lỗi chưa được sửa/xác minh. Phân tích khuôn mặt Gemini qua Edge Function là luồng riêng và không chứng minh các endpoint Render được xác thực. Route `/api/tryon/generate` hiện chỉ trả dữ liệu ảnh đầu vào làm fallback, chưa thực sự gọi Gemini để tạo ảnh. |
| Webhook nhận tin Facebook | Chưa có log `meta_webhook_event_received` hoặc kết quả body `/internal/webhook-status` được cung cấp. | Chưa xác minh được Meta gửi webhook, page được map tới tổ chức, hoặc tin được lưu vào `conversation_messages`. |

## Kết luận hiện tại

Chưa có bằng chứng cho thấy các lỗi chức năng đã được sửa. Chỉ xác nhận được healthcheck Render phản hồi `200`. Hai ảnh app cùng cho thấy endpoint được bảo vệ trả `401`; endpoint status nội bộ cũng trả `401` do request chưa xác thực được. Không nên coi việc mở được trang Facebook/Story hoặc healthcheck `200` là bằng chứng webhook nhận tin.

## Các việc còn lại, theo thứ tự ưu tiên

1. **Xác nhận webhook Facebook nhận và lưu tin:** gửi tin trực tiếp qua Messenger tới Fanpage đã kết nối (không phải chỉ mở Story), rồi xem Render → Logs. Tìm `meta_webhook_event_received`, `webhook_message_unmapped_page`, `webhook_processing_failed` và `Could not persist conversation message`. Ghi lại `eventType`, `pageId`, `orgMapped` nhưng không chia sẻ token/key.
2. **Khôi phục quyền xem diagnostics:** kiểm tra `API_KEY` tồn tại trong Render Environment và gọi `/internal/webhook-status` với header đúng. Chỉ chia sẻ status code và JSON đã loại bỏ dữ liệu nhạy cảm.
3. **Sửa đăng nhập ứng dụng:** thêm Supabase Auth/session và gửi access token hiện hành trong `Authorization: Bearer ...` cho API backend. Sau đó kiểm tra `/messages`, `/bookings`, `/settings`, duyệt tin và try-on bằng user có membership phù hợp.
4. **Loại dữ liệu demo khi backend lỗi:** không hiển thị khách/lịch hard-code như dữ liệu thật sau khi request API thất bại; hiển thị trạng thái lỗi/rỗng rõ ràng.
5. **Nối Gemini cho tạo ảnh:** thay fallback echo của `/api/tryon/generate` bằng tích hợp tạo ảnh thực hoặc báo rõ tính năng chưa khả dụng.

## Kiểm thử cần ghi nhận tiếp

- `GET /health`: status và JSON body.
- `GET /internal/webhook-status`: status và JSON body khi đã xác thực; không cung cấp API key.
- Log Render sau khi gửi tin Messenger trực tiếp đến Page đã liên kết.
- `GET /messages?limit=5` với Supabase JWT hợp lệ: chỉ gửi status và body đã ẩn thông tin người dùng/token.
- Kiểm tra app: đồng bộ hộp thư, lưu lịch, lưu cấu hình, duyệt/gửi tin, tạo ảnh thử.

Không đặt JWT, anon key bí mật, service role key, `API_KEY`, Facebook Page access token hoặc mật khẩu trong log công khai hay chat.
