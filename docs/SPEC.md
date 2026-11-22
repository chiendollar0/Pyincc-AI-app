# Đặc tả sản phẩm (SPEC) — PYINCC AI CRM

> Đây là nguồn chuẩn về phạm vi, màn hình, quyền, quy tắc Gemini và nghiệp vụ. Khi README hoặc ghi chú khác mâu thuẫn với tài liệu này, **SPEC thắng**.

## 1. Mục tiêu và mô hình vận hành

- **Một tài khoản chủ tiệm duy nhất:** Mỗi tiệm vận hành bằng **1 tài khoản Chủ tiệm (`owner`) toàn quyền**, đồng thời là quản trị viên Fanpage. Phiên bản hiện tại **không có vai trò nhân viên (`staff`)**; chủ tiệm là người duy nhất duyệt và gửi mọi nội dung cho khách.
- **Business AI của Meta:** Trả lời khách 100% (giá, giờ làm việc, địa chỉ, đặt lịch cơ bản, chuyển ca khi cần). Ứng dụng **không** trả lời khách thay Business AI khi chưa được chuyển ca.
- **Gemini (nội bộ trong ứng dụng):** Chỉ phục vụ chủ tiệm trong app — phân tích ảnh khách, tư vấn tham khảo, soạn bản nháp, tổng hợp lịch và nhắc việc. Gemini **không** đọc nội dung tin nhắn ngoài ca được chuyển, **không** gọi Facebook và **không** tự gửi gì ra ngoài. Giới hạn **50 lượt/ngày/tiệm** (theo múi giờ Việt Nam UTC+7).
- **Kiểm duyệt bắt buộc (Human-in-the-loop):** Mọi tin nhắn gửi tới khách qua Messenger đều phải có bản nháp ở trạng thái `approved` với `approved_by` và `approved_at` trong database trước khi server gọi Graph API. Không có đường gửi tự động.

## 2. Hai đầu vào ca tư vấn

1. **Luồng B (chủ tiệm chụp/chọn ảnh tại tiệm):** Chủ tiệm chụp hoặc chọn ảnh khách trong **Studio AI** → xác nhận khách đã đồng ý → app xóa EXIF/GPS & nén ảnh → `POST /handoff-cases/capture` → lưu ảnh private trên Supabase Storage → gọi Gemini → tạo ca ở trạng thái `pending_review` (chưa gửi gì).
2. **Luồng A (Business AI chuyển ca — có điều kiện):** Chỉ kích hoạt đầy đủ ở Phase 8 sau khi có kết quả kiểm thử nguyên văn Conversation Routing (`thread_owner`, `take_thread_control`, `pass_thread_control`, `standby`) trên Page test.

## 3. Phân quyền (Owner-only v1)

- **Chỉ `owner` đang `active` được phép truy cập toàn bộ API nghiệp vụ và dữ liệu Supabase.**
- Mọi tài khoản không phải `owner` (bao gồm các bản ghi `staff` cũ nếu có) đều bị chặn `403 FORBIDDEN_ROLE` trên toàn bộ endpoint backend và bị chặn trực tiếp ở tầng RLS Postgres (`public.user_org_ids()` chỉ trả về `org_id` khi `role = 'owner' and status = 'active'`).
- `POST /memberships/invite` và các thao tác nâng/khôi phục tài khoản thứ hai bị khóa `403 SINGLE_OWNER_ONLY`. Chủ tiệm vẫn có thể xem `GET /memberships` và thu hồi các bản ghi cũ không phải `owner` (`POST /memberships/:id/revoke`), trong khi database trigger `prevent_zero_active_owners` ngăn không cho xóa/thu hồi chủ tiệm duy nhất của tổ chức còn tồn tại.
- Mọi thao tác quan trọng (`onboarding.claim`, `tenant.update`, `catalog.*`, `connected_page.disconnect`, `handoff_case.approve/reject/send/release`, `membership.revoked`) đều ghi vào `audit_logs` (RLS chỉ cho `owner` đọc).

## 4. Các màn hình chính trong ứng dụng Flutter

| Màn hình | Chức năng cốt lõi |
|---|---|
| Đăng nhập (`LoginScreen`) | Đăng nhập email/mật khẩu của Chủ tiệm qua Supabase Auth, lưu phiên đăng nhập tự động (`SessionStorage` + tự làm mới token khi `401`), bật/ẩn mật khẩu, **Quên mật khẩu** (gửi link đặt lại mật khẩu về `/reset-password`) |
| Kích hoạt tiệm (`OnboardingClaimScreen`) | Tự động hiện khi tài khoản đã đăng nhập nhưng chưa gắn tiệm (`403 NO_MEMBERSHIP`); nhập mã thiết lập dùng một lần (`POST /onboarding/claim`) để mở quyền Chủ tiệm |
| Hộp thư (`InboxScreen`) | Tab 1 của `CrmShell`: tách nhóm *Khách chuyển từ Business AI* và *Ảnh chủ tiệm chụp*; lọc theo trạng thái (`Chờ duyệt`, `Mới`, `Đã duyệt`, `Đang gửi`, `Đã gửi`, `Đã từ chối`, `Lỗi`), chạy **Phân tích AI** cho ca `Mới`/`Lỗi`, sửa nháp & duyệt, từ chối, gửi Messenger (claim nguyên tử chống gửi trùng), **Trả Business AI** (`release`), tự làm mới mỗi 30 giây |
| Studio (`StudioScreen`) | Tab 2 của `CrmShell`: chọn/chụp ảnh, hộp thoại xác nhận khách đồng ý bắt buộc, tiền xử lý xóa EXIF/GPS, chọn mẫu từ Catalog thật của tiệm, phân tích Gemini (`POST /handoff-cases/capture`), chuyển sang Hộp thư để duyệt (nút tạo ảnh demo vô hiệu hóa đến khi có model, endpoint giữ `501`) |
| Lịch (`ScheduleScreen`) | Tab 3 của `CrmShell`: xem & tạo lịch hẹn theo ngày (`POST /bookings`) và danh sách **Cần nhắc kiểm tra sau dịch vụ** (mốc 7 ngày) kèm nút **Đã kiểm tra** (`PATCH /bookings/:id/followup`, nhắc nội bộ cho chủ tiệm, không tự nhắn khách) |
| Cài đặt (`SettingsScreen`) | Tab 4 của `CrmShell` gồm 4 nhóm gọn: **Tiệm** (Thông tin tiệm, `CatalogScreen` không giá), **Kết nối** (`ConnectionScreen`: kết nối/gỡ liên kết Fanpage, checklist nhận ca trung thực, sao chép Prompt Business AI), **Hệ thống** (Hạn mức AI hôm nay, `AuditLogsScreen` Nhật ký hoạt động), **Tài khoản** (Đăng xuất, Hướng dẫn xóa dữ liệu) |

## 5. Giới hạn & quy tắc nghiệp vụ

- **Danh mục không giá (`catalog_items`):** Chỉ lưu `name`, `category` (`eyebrow` | `lip` | `other`), `group_label`, `active`, `description` (và tùy chọn `image_url`). Bảng giá khách xem do Business AI quản lý trên Meta Business Suite.
- **Cửa sổ 24 giờ Messenger:** Nếu quá 24 giờ từ tin cuối của khách, server trả `422 OUTSIDE_24H_WINDOW` và hoàn trạng thái về `approved`.
- **Tạo ảnh demo (`/api/tryon/generate`):** Giữ `501 NOT_IMPLEMENTED`; nút tạo ảnh demo bị khóa trên UI cho đến khi chốt model tạo ảnh.
