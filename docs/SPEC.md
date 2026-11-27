# Đặc tả sản phẩm (SPEC) — PYINCC AI CRM

> Đây là nguồn chuẩn về phạm vi, màn hình, quyền, quy tắc Gemini và nghiệp vụ. Khi README hoặc ghi chú khác mâu thuẫn với tài liệu này, **SPEC thắng**.

## 1. Mục tiêu và mô hình vận hành

- **Một tài khoản chủ tiệm duy nhất:** Mỗi tiệm vận hành bằng **1 tài khoản Chủ tiệm (`owner`) toàn quyền**, đồng thời là quản trị viên Fanpage. Hệ thống **không có vai trò nhân viên**; thiết bị phụ (nếu cần ở Phase 2) dùng phiên thiết bị có thời hạn gắn với `org_id` của chủ tiệm.
- **Chatbot AI qua Messenger Webhook (của ứng dụng):** Nhận tin nhắn khách từ Meta Messenger Webhook, tra cứu kho kiến thức nội bộ (`kb_entries`) hoặc dùng Gemini soạn bản nháp trả lời. **Mặc định AI chỉ tạo bản nháp (`pending`) chờ chủ tiệm duyệt**, chưa tự động gửi; cờ `AI_REPLY_ENABLED` mặc định là `false`.
- **Chatbot không báo giá:** Tuyệt đối không lưu trường giá trong danh mục (`catalog_items`) và không tạo loại kiến thức `price` trong `kb_entries`. Khi khách hỏi giá, hệ thống tạo bản nháp cố định chuyển chủ tiệm báo trực tiếp.
- **Business AI của Meta không phải lõi:** Ứng dụng không phụ thuộc vào Business AI của Meta để trả lời khách. Nếu Fanpage đang bật Business AI thì cần tắt khi chuyển sang luồng chatbot của ứng dụng.
- **Routing khóa Gemini tách biệt (`src/ai/gemini.js`):**
  - Nhóm `customer` (`GEMINI_PRO_KEY_1`, `GEMINI_PRO_KEY_2`): dùng cho mọi dữ liệu khách hàng (tin nhắn Messenger, ảnh khách trong Studio). **Không bao giờ fallback sang khóa free**; nếu hết khóa hoặc hết hạn mức sẽ trả lỗi `AI_QUOTA_EXHAUSTED`.
  - Nhóm `internal` (`GEMINI_FREE_KEY`): chỉ dùng cho tác vụ nội bộ/dev, tuyệt đối không dùng cho tin khách hay ảnh khách.
- **Giới hạn & kiểm duyệt bắt buộc (Human-in-the-loop):** Giới hạn **50 lượt AI/ngày/tiệm** (theo múi giờ Việt Nam UTC+7). Mọi tin nhắn tự do gửi tới khách qua Messenger chỉ được gửi trong **cửa sổ 24 giờ** tính từ tin nhắn cuối của khách và phải có bản nháp ở trạng thái `approved` với `approved_by` và `approved_at` trong database trước khi server gọi Graph API.

## 2. Hai đầu vào ca tư vấn

1. **Luồng B (chủ tiệm chụp/chọn ảnh tại tiệm):** Chủ tiệm chụp hoặc chọn ảnh khách trong **Studio AI** → xác nhận khách đã đồng ý → app xóa EXIF/GPS & nén ảnh → `POST /handoff-cases/capture` → lưu ảnh private trên Supabase Storage → gọi Gemini (`scope: 'customer'`) → tạo ca ở trạng thái `pending_review` (chưa gửi gì).
2. **Luồng A (Messenger Webhook → Chatbot pipeline):** Nhận sự kiện từ Messenger Webhook (xác thực chữ ký HMAC-SHA256, khử trùng lặp theo `mid`), lưu hội thoại & cập nhật `last_inbound_at` trong `conversations`, tạo bản nháp trong `reply_drafts` / `handoff_cases` để chủ tiệm sửa, duyệt và gửi trong cửa sổ 24 giờ.

## 3. Phân quyền (Owner-only)

- **Chỉ tài khoản Chủ tiệm (`owner`) đang `active` được phép truy cập toàn bộ API nghiệp vụ và dữ liệu Supabase.**
- Mọi tài khoản không phải `owner` đều bị chặn `403 FORBIDDEN_ROLE` trên toàn bộ endpoint backend và bị chặn trực tiếp ở tầng RLS Postgres (`public.user_owner_org_ids()` chỉ trả về `org_id` khi `role = 'owner' and status = 'active'`).
- Không tồn tại tính năng mời hay quản lý nhân viên (`/team`, `/memberships/invite`, `/support/users` đã bị loại bỏ).
- Mọi thao tác quan trọng (`onboarding.claim`, `tenant.update`, `catalog.*`, `connected_page.disconnect`, `handoff_case.approve/reject/send/release`) đều ghi vào `audit_logs` (RLS chỉ cho `owner` đọc).

## 4. Các màn hình chính trong ứng dụng Flutter

| Màn hình | Chức năng cốt lõi |
|---|---|
| Đăng nhập (`LoginScreen`) | Đăng nhập Chủ tiệm qua Supabase Auth, lưu phiên đăng nhập tự động (`SessionStorage` + tự làm mới token khi `401`), bật/ẩn mật khẩu, **Quên mật khẩu** (gửi link đặt lại mật khẩu về `/reset-password`) |
| Kích hoạt tiệm (`OnboardingClaimScreen`) | Tự động hiện khi tài khoản đã đăng nhập nhưng chưa gắn tiệm (`403 NO_MEMBERSHIP`); nhập mã thiết lập dùng một lần (`POST /onboarding/claim`) để mở quyền Chủ tiệm |
| Hộp thư (`InboxScreen`) | Tab 1 của `CrmShell`: quản lý ca từ Messenger & ảnh chủ tiệm chụp; lọc trạng thái (`Chờ duyệt`, `Mới`, `Đã duyệt`, `Đang gửi`, `Đã gửi`, `Đã từ chối`, `Lỗi`), chạy **Phân tích AI** (`scope: 'customer'`), sửa nháp & duyệt, từ chối, gửi Messenger (chống gửi trùng, khóa ngoài 24 giờ), tự làm mới mỗi 30 giây |
| Studio (`StudioScreen`) | Tab 2 của `CrmShell`: chọn/chụp ảnh, hộp thoại xác nhận khách đồng ý bắt buộc, tiền xử lý xóa EXIF/GPS, chọn mẫu từ Catalog không giá của tiệm, phân tích Gemini (`scope: 'customer'`), chuyển sang Hộp thư để duyệt (nút tạo ảnh demo vô hiệu hóa đến khi có model, endpoint giữ `501`) |
| Lịch (`ScheduleScreen`) | Tab 3 của `CrmShell`: xem & tạo lịch hẹn theo ngày (`POST /bookings`) và danh sách **Cần nhắc kiểm tra sau dịch vụ** (mốc 7 ngày) kèm nút **Đã kiểm tra** (`PATCH /bookings/:id/followup`, nhắc nội bộ cho chủ tiệm, không tự nhắn khách) |
| Cài đặt (`SettingsScreen`) | Tab 4 của `CrmShell` gồm 4 nhóm gọn: **Tiệm** (Thông tin tiệm, `CatalogScreen` không giá), **Kết nối** (`ConnectionScreen`: kết nối/gỡ liên kết Fanpage, kiểm tra webhook), **Hệ thống** (Hạn mức AI hôm nay, `AuditLogsScreen` Nhật ký hoạt động), **Tài khoản** (Đăng xuất, Hướng dẫn xóa dữ liệu) |

## 5. Giới hạn & quy tắc nghiệp vụ

- **Danh mục không giá (`catalog_items`) & Kho kiến thức (`kb_entries`):** `catalog_items` chỉ lưu `name`, `category` (`eyebrow` | `lip` | `other`), `group_label`, `active`, `description` (và tùy chọn `image_url`). `kb_entries` chỉ hỗ trợ `hours`, `address`, `service`, `booking`, `policy`, `faq` — **không có loại `price`**.
- **Cửa sổ 24 giờ Messenger:** Chỉ được gửi tin nhắn tự do khi còn trong vòng 24 giờ kể từ tin nhắn cuối của khách (`canReplyFreeform`). Ngoài 24 giờ, server trả `422 OUTSIDE_24H_WINDOW` và hoàn trạng thái về `approved`.
- **Tạo ảnh demo (`/api/tryon/generate`):** Giữ `501 NOT_IMPLEMENTED`; nút tạo ảnh demo bị khóa trên UI cho đến khi chốt model tạo ảnh.
