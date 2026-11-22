# Kế hoạch và kết quả kiểm thử (TEST-PLAN) — PYINCC AI CRM

> Quy tắc: Mỗi Phase trong `README.md` chỉ được chuyển sang trạng thái **"Xong"** khi toàn bộ tiêu chí nghiệm thu của Phase đó có bằng chứng đạt (ngày chạy, người/CI chạy, kết quả) ghi nhận trong tài liệu này.

## Phase 0 — Nền tảng: CI, lockfile, quét bí mật, dọn mã chết

| # | Tiêu chí kiểm thử | Kết quả | Ghi chú |
|---|---|---|---|
| 0.1 | Bước quét bí mật trong `.github/workflows/build.yml` và `release.yml` chạy sạch (`0` phát hiện) | Đạt (22/11/2026) | CI `Build APK` xanh liên tiếp trên PR #3–#6 (`main` run `44996813614`) |
| 0.2 | `node --check`, `node --test` (14/14 test), `flutter analyze --no-fatal-infos`, `flutter test` đều xanh | Đạt (22/11/2026) | Chạy tự động trên GitHub Actions |
| 0.3 | Dọn mã chết (`tryon_image_service.dart`, 7 file UI cũ, biến legacy trong `.env.example`) | Đạt (21/11/2026) | Hoàn tất qua PR #3 và PR #5 |
| 0.4 | Đồng bộ `mobile_app/pubspec.lock` (`--enforce-lockfile`) và `backend_bridge/meta-webhook/package-lock.json` (`npm ci`) | Chưa xong | Cần chạy trên máy có quyền truy cập pub.dev & npm registry |
| 0.5 | `./scripts/smoke.sh https://pyincccrm.bothelper.vn` pass sau deploy | Chưa chạy trên production | Chạy sau khi deploy bản mới nhất lên Render |

## Phase 1 — Xác thực, mã thiết lập tiệm, RLS

- [ ] Đăng nhập email/mật khẩu của Chủ tiệm thành công trên APK thật, giữ phiên sau khi tắt mở lại app, quên mật khẩu hoạt động qua `/reset-password`. *(Đã có unit/widget test tự động cho `SessionStorage`, `/reset-password`, `/auth/complete-password-reset` và `OnboardingClaimScreen`.)*
- [ ] `POST /onboarding/claim`: email đã xác thực claim mã 1 lần thành công → tạo `organizations` + `memberships(role='owner', status='active')` + `audit_logs`; claim lần 2 trả `409`; email chưa xác thực trả `403`. *(Đã có test tự động backend & widget test `OnboardingClaimScreen`; cần test E2E trên Supabase thật.)*
- [ ] Toàn bộ bảng `public.*` bật RLS owner-only (`public.user_org_ids()` chỉ cho `owner` đang `active`); mọi tài khoản không phải `owner` bị chặn `403 FORBIDDEN_ROLE`.
- [ ] Chạy `database/migrations/20261121_security_and_invariants.sql` và `20261121_ui_v2_schema.sql` trên Supabase và kiểm chứng trigger `prevent_zero_active_owners` (vẫn cho phép cascade xóa tổ chức).

## Phase 2 — Kết nối Facebook, lưu Page token mã hóa, gỡ liên kết

- [ ] Đăng nhập Facebook trên APK (`vn.pyincc.aicrm`) hỏi đủ `pages_show_list`, `pages_messaging`, `pages_manage_metadata` và không báo lỗi URL/key hash.
- [ ] `POST /auth/facebook/exchange-token` lưu Page Token mã hóa AES-256-GCM trong `connected_pages`, không lưu token trên điện thoại.
- [ ] Gỡ liên kết trong app (`DELETE /connected-pages/:pageId` trên `ConnectionScreen`) và gỡ ứng dụng trong Facebook Business Integrations → webhook `/auth/facebook/data-deletion` trả mã xác nhận, mở `/data-deletion?code=...` hiện `completed`, chỉ xóa `connected_pages` và gỡ `invited_fb_user_id = null`. *(Đã có test tự động backend & widget test cho `DELETE /connected-pages/:pageId`.)*

## Phase 3 — Catalog theo tiệm (không giá, không mặc định)

- [ ] Chủ tiệm (`owner`) tạo/sửa/bật-tắt mẫu qua màn **Catalog mẫu** (`/catalog`), không có trường giá, ghi `audit_logs`. *(Đã có test tự động backend & widget test.)*
- [ ] Studio tải danh mục thật của tiệm và tự làm mới ngay khi chủ tiệm sửa danh mục; dữ liệu tách biệt hoàn toàn giữa 2 `org_id`.

## Phase 4 — Studio và Luồng B (phân tích, duyệt, gửi)

- [ ] Chụp/chọn ảnh thật từ camera → bắt buộc xác nhận khách đồng ý → EXIF/GPS bị xóa 100% (`image_preprocessor_test.dart` pass).
- [ ] `POST /handoff-cases/capture` tạo ca `pending_review` trong <= 45s (có fallback model + tự tạo bucket `customer-media` nếu thiếu), **không** gọi Meta Send API. *(Đã có test tự động backend.)*
- [ ] `POST /handoff-cases/:id/approve` lưu `approved_by` + `approved_at`, **không** gửi tin đi. *(Đã có test tự động backend.)*
- [ ] Gửi trước khi duyệt trả `403 NOT_APPROVED`; gửi 2 lần trả `409 ALREADY_SENDING`; lỗi quá 24h trả `422 OUTSIDE_24H_WINDOW`; quá 50 lượt/ngày trả `429 AI_DAILY_CAP` (lượt 50 chạy được, lượt 51 bị chặn trước upload); tài khoản bị thu hồi hoặc không phải `owner` bị chặn `403`. *(Đã có test tự động backend.)*
- [ ] `POST /api/tryon/generate` trả `501 NOT_IMPLEMENTED`; nút tạo ảnh demo khóa trên UI.

## Phase 5 — Hộp thư (ca, nháp, duyệt, gửi)

- [ ] Danh sách ca `Chờ duyệt`/`Mới`/`Đã duyệt`/`Lỗi` tự làm mới mỗi 30 giây; ca `Mới`/`Lỗi` bấm **Phân tích AI** được; ca từ Business AI bấm **Trả Business AI** được. *(Đã có test tự động backend & widget test.)*
- [ ] Sửa nháp → duyệt → gửi qua Messenger (có `psid`/`page_id`) thành công, không gửi trùng.
- [ ] Từ chối ca chuyển trạng thái `rejected` và biến mất khỏi danh sách chờ.

## Phase 6 — Lịch hẹn và nhắc kiểm tra sau 7 ngày

- [ ] Tạo lịch hẹn mới lưu lên Supabase; xung đột khung giờ trả `409 BOOKING_SLOT_CONFLICT`.
- [ ] `GET /bookings` & `GET /bookings/reminders` hiển thị đúng danh sách khách đến hạn 7 ngày; bấm **Đã kiểm tra** gọi `PATCH /bookings/:id/followup` (xóa khỏi danh sách cần nhắc và không tự nhắn tin cho khách). *(Đã có test tự động backend & widget test.)*

## Phase 7 — Cài đặt và nhật ký

- [ ] Màn **Nhật ký hoạt động** (`AuditLogsScreen`) hiển thị đầy đủ các sự kiện `onboarding.claim`, `tenant.update`, `catalog.*`, `connected_page.disconnect`, `handoff_case.*`, `membership.revoked`. *(Đã có test tự động backend & widget test.)*
- [ ] Khóa mô hình 1 Chủ tiệm duy nhất: `POST /memberships/invite` trả `403 SINGLE_OWNER_ONLY`, tài khoản không phải `owner` bị chặn `403 FORBIDDEN_ROLE`, vẫn cho phép chủ tiệm thu hồi bản ghi cũ nếu có (`POST /memberships/:id/revoke`). *(Đã có test tự động backend.)*
- [ ] Sao chép Prompt Business AI từ `ConnectionScreen` hoạt động đúng. *(Đã có widget test.)*

## Phase 8 — Luồng A: nhận ca từ Business AI (chờ điều kiện tiên quyết)

- [ ] Có kết quả nguyên văn `thread_owner`, `take_thread_control`, `pass_thread_control`, `standby` trên Page test.
- [ ] Khách nhắn khi Business AI giữ → `standby` ghi nhận, app không trả lời.
- [ ] Business AI chuyển ca → `pass_thread_control` tạo ca kèm `handoff_reason` (không parse text).
- [ ] Duyệt & gửi thành công khi app giữ thread; nếu app khác giữ trả `409 THREAD_OWNED_BY_OTHER_APP`.
- [ ] Chuyển cho Page Inbox (`263902037430900`) và **Trả Business AI** (`release_thread_control`) hoạt động đúng.

## Phase 9 — Phát hành (Chính sách, App Review, Release APK)

- [ ] `/privacy`, `/terms`, `/data-deletion` công khai, minh bạch Supabase/Gemini/Meta và phân biệt thu hồi tích hợp Facebook vs xóa dữ liệu Supabase.
- [ ] Hoàn tất App Review cho `pages_messaging` và `pages_manage_metadata`.
- [ ] Cấu hình đủ 4 secret keystore release trên GitHub, chạy `release.yml` tạo APK release ký cố định và smoke test trên thiết bị thật.
