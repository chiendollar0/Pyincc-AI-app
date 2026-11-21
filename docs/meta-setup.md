# Hướng dẫn cấu hình Meta for Developers & Page Test (meta-setup)

> **Lưu ý bảo mật:** Không bao giờ dán `META_APP_SECRET`, User Access Token, Page Access Token hay PSID thật vào repo, chat hoặc tài liệu.

## 1. Cấu hình App trên Meta for Developers

1. Tạo/mở app Meta (`META_APP_ID = 1555273769742937`).
2. Vào **App settings → Basic**:
   - **Privacy Policy URL:** `https://pyincccrm.bothelper.vn/privacy`
   - **Terms of Service URL:** `https://pyincccrm.bothelper.vn/terms`
   - **User Data Deletion URL:** `https://pyincccrm.bothelper.vn/data-deletion` (hoặc Callback `https://pyincccrm.bothelper.vn/auth/facebook/data-deletion`).
   - Copy **App Secret** đặt vào biến `META_APP_SECRET` trên Render Dashboard.
3. Thêm nền tảng **Android**:
   - **Package Name:** `vn.pyincc.aicrm`
   - **Class Name:** `vn.pyincc.aicrm.MainActivity`
   - **Key Hashes:** Thêm key hash từ keystore cố định đã ký APK (không dùng debug keystore tạm của GitHub Actions runner vì đổi mỗi lần build).
4. Vào **App settings → Advanced**: copy **Client Token** đặt vào GitHub Secret `FB_CLIENT_TOKEN`.

## 2. App Roles & Quyền (Development Mode)

1. Vào **App roles → Roles**: thêm tài khoản Facebook của chủ tiệm và người kiểm thử làm **Tester** (họ phải bấm chấp nhận lời mời trên developers.facebook.com).
2. Trong Use case **Messenger**, bật các quyền:
   - `pages_show_list`
   - `pages_messaging`
   - `pages_manage_metadata`
3. Xác nhận hộp thoại đăng nhập Facebook trên APK hỏi đủ 3 quyền trên và không báo lỗi URL/key hash.

## 3. Cấu hình Webhook

1. **Callback URL:** `https://pyincccrm.bothelper.vn/webhook`
2. **Verify Token:** Khớp chính xác với biến `VERIFY_TOKEN` trên Render.
3. **Subscribe các trường bắt buộc:**
   - `messages`
   - `messaging_handover`
   - `standby`
   - `messaging_postbacks`
   - `messaging_referral`
4. Bấm **Test** cho từng sự kiện và xác nhận Render log không báo lỗi chữ ký (`webhook_signature_rejected`).

## 4. Cấu hình Page Test & Conversation Routing (Điều kiện mở khóa Phase 8)

> Mọi bước thử nghiệm Luồng A phải chạy trên **Page test** (không dùng Page khách hàng thật).

1. Trong **Page Settings → Conversation routing**: đặt ứng dụng **PYINCC AI CRM** làm **Default app**.
2. Trong **Page Settings → Connected apps**: bật **"Take control of conversations with your Business Agent"** cho ứng dụng.
3. Dán prompt CSKH trong [docs/business-ai-prompt.md](business-ai-prompt.md) vào Business AI trên Meta Business Suite.
4. Kiểm thử Graph API trên Page test (bằng Page Access Token test — **che token khi gửi kết quả**):
   - `GET /{page-id}/thread_owner?recipient={psid}`
   - `POST /{page-id}/take_thread_control`
   - `POST /{page-id}/pass_thread_control`
   - Ghi lại nguyên văn payload webhook `standby` và `pass_thread_control` (đặc biệt trường `thread_control_metadata.handoff_reason`) trước khi triển khai Phase 8.

## 5. Trước khi phát hành rộng rãi (Phase 9)

- Hoàn tất **App Review** cho `pages_messaging` và `pages_manage_metadata` (và **Business Verification** nếu Meta yêu cầu) trước khi chuyển app sang chế độ **Live** cho các tiệm ngoài danh sách tester.
