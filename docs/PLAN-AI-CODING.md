# PLAN CHO AI CODE: PYINCC AI CRM

Tài liệu này dùng để giao cho một AI lập trình (Claude Code, Codex, Cursor...) thực hiện. Đặt file này ở `docs/PLAN-AI-CODING.md` trong repo, rồi giao cho AI đọc trước khi làm bất cứ việc gì.

---

## 0. Quy tắc bắt buộc cho AI

1. **Đọc `docs/SPEC.md` và file này trước.** Không tự thêm tính năng ngoài phạm vi.
2. **Làm theo thứ tự task.** Không nhảy task. Một task xong mới sang task sau.
3. **Mỗi task kết thúc bằng lệnh kiểm tra.** Không đánh dấu xong nếu lệnh chưa đạt.
4. **Không debug vòng lặp.** Nếu một lệnh kiểm tra thất bại quá 2 lần, dừng và báo cáo nguyên văn lỗi cùng file liên quan. Không tự sửa lan sang file khác.
5. **Không đưa bí mật vào code, test, log, hay commit.** Không tạo file `.env` thật. Không in giá trị secret ra màn hình.
6. **Không gửi tin thật, không gọi API Meta thật, không gọi Gemini thật** trong bất kỳ bước nào của plan này. Chỉ dùng mock hoặc để trống.
7. **Một nhánh, một PR.** Nhánh `phase0-cleanup` cho phase 0. Các phase sau có nhánh riêng.
8. **Báo cáo theo mẫu** (mục 8) sau mỗi task.

---

## 1. Ngữ cảnh ngắn

- Sản phẩm: CRM mobile cho tiệm phun xăm, spa, thẩm mỹ.
- Một tài khoản chủ tiệm (owner). Không có vai trò nhân viên. Thiết bị phụ dùng phiên có hạn.
- Chatbot AI trả lời khách trên Messenger qua webhook. Chủ tiệm duyệt trước khi gửi.
- Chatbot **không báo giá**.
- Gemini: tin khách và ảnh khách dùng khóa Pro. Khóa free chỉ cho dev.
- Business AI của Meta không phải lõi. Nếu bật thì phải tắt trên Page.

---

## 2. Cấu trúc repo mục tiêu

```
mobile_app/lib/
  app/crm_shell.dart
  core/theme/tokens.dart, app_theme.dart
  core/ui/widgets.dart
  core/errors/user_message.dart
  data/crm_repo.dart
  screens/auth/login_screen.dart
  screens/home/home_screen.dart
  screens/customers/customers_screen.dart, customer_detail_screen.dart
  screens/chat/conversation_list.dart, conversation_screen.dart
  screens/studio/studio_screen.dart
  screens/schedule/schedule_screen.dart
  screens/settings/settings_screen.dart, catalog_screen.dart, connection_screen.dart, devices_screen.dart
backend_bridge/meta-webhook/
  index.js                 (chỉ là entry, gọi các module dưới)
  src/config.js
  src/auth.js              (requireOwner, phiên thiết bị)
  src/routes/*.js
  src/ai/gemini.js         (routing khóa theo scope)
  src/chat/pipeline.js     (FAQ, nháp, cửa sổ 24 giờ)
  src/meta/graph.js
  src/meta/webhook.js
  test/*.test.js
database/migrations/       (file mới, không sửa file cũ)
docs/SPEC.md, PRIVACY.md, TEST-PLAN.md, BUILD.md, RUNBOOK.md
```

Nếu `index.js` hiện là một file lớn, **tách dần** theo task 3–6. Không viết lại toàn bộ trong một lần.

---

## 3. Các task theo phase

### PHASE 0: Dọn nền (nhánh `phase0-cleanup`)

**Task 0.1: Xóa mã nhân viên và quản trị nền tảng**
- Xóa: `screens/team/`, `services/team_service.dart`, các route `/team`, `/team/*`, `/memberships`, `/memberships/invite`, `/support/users`, hàm `requirePlatformAdmin`.
- Giữ: `requireOwner`.
- Kiểm tra:
  ```bash
  grep -rniE "team|memberships/invite|support/users|requirePlatformAdmin|TeamScreen" backend_bridge mobile_app/lib
  ```
  Kết quả phải rỗng.

**Task 0.2: Xóa Zalo bot và mã chết**
- Xóa `backend_bridge/zalo-manager-bot/`.
- Xóa các màn và class cũ nếu còn: `VirtualTryOnScreen`, `AiTriageInboxScreen`, `ShiftAndBookingScreen`, `OwnerSettingsScreen`, dữ liệu mẫu "Chị Minh Thư", "Thanh Trúc", các chuỗi có giá cứng.
- Kiểm tra:
  ```bash
  grep -rnE "VirtualTryOnScreen|AiTriageInboxScreen|ShiftAndBookingScreen|OwnerSettingsScreen|Minh Thư|Thanh Trúc|Giá niêm yết" mobile_app/lib
  ```

**Task 0.3: Routing khóa AI**
- Tạo `src/ai/gemini.js` (hoặc tương đương trong `index.js` nếu chưa tách):
  - `AI_KEYS.customer` = `GEMINI_PRO_KEY_1`, `GEMINI_PRO_KEY_2`.
  - `AI_KEYS.internal` = `GEMINI_FREE_KEY`.
  - Hàm `callGemini(scope, body)`. Scope `customer` không bao giờ fallback sang `internal`.
  - Khi hết khóa customer: trả lỗi `AI_QUOTA_EXHAUSTED`, không chuyển sang free.
- Biến `AI_REPLY_ENABLED` mặc định `false`.
- Kiểm tra: test đơn vị (xem task 0.5) xác nhận scope `customer` không bao giờ dùng khóa free.

**Task 0.4: Migration chatbot**
- Tạo `database/migrations/20261126_chatbot.sql` với các bảng `kb_entries`, `conversations`, `reply_drafts` và `enable row level security` cho cả ba.
- Không sửa `schema.sql` hay migration cũ.
- Kiểm tra: file tồn tại; không có câu lệnh `drop` trong file.

**Task 0.5: Test đơn vị tối thiểu**
- Tạo `test/` với Node test runner (`node --test`), không thêm thư viện ngoài.
- Test bắt buộc:
  - `scope customer` không chọn khóa free.
  - `canReplyFreeform` trả `false` khi tin cuối khách quá 24 giờ.
  - Chữ ký webhook sai bị từ chối.
- Kiểm tra: `cd backend_bridge/meta-webhook && node --test`

**Task 0.6: Tài liệu**
- Cập nhật `docs/SPEC.md`: bỏ nhân viên, bỏ Business AI khỏi lõi, ghi chatbot không báo giá, routing khóa.
- Cập nhật `docs/PRIVACY.md`: Gemini đọc tin nhắn khách để soạn trả lời; thời hạn lưu; cách xóa.
- Cập nhật `README.md`: bỏ mục nhân viên và Business AI là lõi.

**Cổng nghiệm thu Phase 0:**
```bash
cd backend_bridge/meta-webhook && node --check index.js && node --test
cd mobile_app && flutter pub get --enforce-lockfile && flutter analyze --no-fatal-infos
```
Cả hai phải thành công. Sau đó mở PR, chờ CI xanh, merge.

---

### PHASE 1: Giao diện khung và đăng nhập

**Task 1.1: Token thiết kế** (`core/theme/tokens.dart`, `app_theme.dart`)
- Màu, bo góc, khoảng cách theo `docs/SPEC.md`. Không dùng màu neon.
- Kiểm tra: `flutter analyze` sạch.

**Task 1.2: Widget dùng chung** (`core/ui/widgets.dart`)
- Tạo: `SoftCard`, `StatTile`, `StatusChip`, `ServiceChip`, `EmptyState`, `BrandHeader`.
- Mọi widget không có dữ liệu mẫu.

**Task 1.3: Khung 4 tab** (`app/crm_shell.dart`)
- Tab: Hôm nay, Khách, Studio, Lịch. Cài đặt mở từ icon góc trên phải.
- Dùng `LazyTabs`: chỉ dựng tab khi lần đầu mở.
- Kiểm tra: mở app, chuyển 4 tab, không crash.

**Task 1.4: Màn đăng nhập**
- Hai nút: Facebook, Google. Liên kết nhỏ "Dùng email".
- Không dán secret. Dùng `Supabase.instance.client.auth.signInWithOAuth`.

**Task 1.5: Điều hướng sau đăng nhập**
- Chưa có phiên: màn đăng nhập. Có phiên nhưng chưa có tiệm: màn nhập mã thiết lập. Có tiệm: khung 4 tab.

**Cổng nghiệm thu Phase 1:** `flutter analyze` sạch; APK debug build được; mở app trên máy thật không lỗi; không có dữ liệu mẫu.

---

### PHASE 2: Tiệm, mã thiết lập, phiên thiết bị

**Task 2.1:** Endpoint `POST /onboarding/claim` (theo SPEC), bảng `setup_codes`.
**Task 2.2:** Phiên thiết bị: bảng `device_sessions`, `device_link_codes`; endpoint tạo mã liên kết, nhập mã, liệt kê, thu hồi. Middleware nhận cả JWT owner và token thiết bị, đều ra `org_id` của owner.
**Task 2.3:** Màn Cài đặt → Thiết bị.
**Task 2.4:** Đổi mật khẩu owner thì thu hồi toàn bộ phiên thiết bị.

**Cổng nghiệm thu:** test đơn vị cho middleware; thu hồi có hiệu lực ngay ở request tiếp theo; mã đã dùng không dùng lại được.

---

### PHASE 3: Khách, catalog (không giá)

**Task 3.1:** Bảng và API khách (tên, SĐT, dịch vụ đã làm, ngày làm, mốc 7 ngày).
**Task 3.2:** Catalog: API và màn hình. Không có trường giá ở bất kỳ tầng nào.
**Task 3.3:** Kho kiến thức chatbot (`kb_entries`): giờ, địa chỉ, dịch vụ, đặt lịch, chính sách. **Không có loại `price`.**

**Cổng nghiệm thu:** test: request có trường `price` bị bỏ qua hoặc từ chối; owner tiệm A không đọc được dữ liệu tiệm B.

---

### PHASE 4: Chatbot pipeline (chưa gửi tự động)

**Task 4.1:** Webhook: xác thực chữ ký, khử trùng lặp theo `mid`, ghi tin vào `conversations`, cập nhật `last_inbound_at`. Không gọi AI trong webhook.
**Task 4.2:** Pipeline `src/chat/pipeline.js`:
  1. Tin có ảnh → trả câu xin đồng ý, tạo nháp.
  2. Khớp FAQ (giờ, địa chỉ, đặt lịch) → nháp `source = faq`.
  3. Hỏi giá → câu cố định "chuyên viên sẽ báo chị chi tiết ạ", tạo ca chuyển chủ.
  4. Còn lại → Gemini (scope customer) soạn nháp, JSON theo schema, có `action` và `risk`.
  5. `risk = high` hoặc `action = escalate` → câu "chuyên viên sẽ trả lời sớm", thông báo chủ.
**Task 4.3:** Mọi nháp đều `pending`. Chế độ tự gửi (`auto_faq`) **chưa bật** ở phase này.
**Task 4.4:** Gửi nháp đã duyệt: chỉ trong 24 giờ, có khóa `sending` chống gửi trùng, kiểm tra người duyệt là owner.

**Cổng nghiệm thu:** test đơn vị cho từng nhánh của pipeline với Gemini mock; không có đường gọi Graph API nào nếu không có nháp `approved`.

---

### PHASE 5: Giao diện chat và lịch

**Task 5.1:** Tab Khách có danh sách hội thoại (20 mục, phân trang), chi tiết hội thoại, khung nháp (Sửa, Duyệt, Bỏ).
**Task 5.2:** Nút gửi bị khóa ngoài 24 giờ, kèm giải thích.
**Task 5.3:** Lịch: đặt, chống trùng giờ, hiển thị ngày, danh sách mốc 7 ngày.
**Task 5.4:** Studio: chọn ảnh, xác nhận đồng ý, phân tích (scope customer), nút "Làm demo" sang Studio từ ảnh khách.

**Cổng nghiệm thu:** kiểm thử thủ công theo `docs/TEST-PLAN.md` trên máy yếu; danh sách không tải ảnh gốc.

---

### PHASE 6: Báo cáo cuối ngày và cài đặt

**Task 6.1:** Báo cáo: khách mới, đã làm, đặt lịch mai, việc cần làm. Số liệu tính bằng SQL, không để AI tính.
**Task 6.2:** Hạn mức AI đã dùng hôm nay.
**Task 6.3:** Nhật ký thao tác (gửi, duyệt, kết nối).

---

## 4. Những việc AI **không** được làm trong plan này

- Thêm chức năng đăng bài, reel, kiểm soát Page (thuộc Ver 2).
- Thêm chiến dịch gửi hàng loạt, mini game, nhắc ngoài 24 giờ không có tag.
- Bật chế độ tự gửi (`auto_ai`).
- Dùng khóa free cho tin khách hay ảnh khách.
- Nhúng Messenger, Business Suite, hay WebView của Meta vào app.
- Thêm thư viện thương mại nặng hoặc Firebase.
- Đổi tên package, application ID, hay keystore.

---

## 5. Quy trình làm việc của AI trong mỗi task

1. Đọc task và các file liên quan.
2. Liệt kê file sẽ tạo/sửa/xóa, chờ xác nhận nếu danh sách khác plan.
3. Làm thay đổi tối thiểu.
4. Chạy lệnh kiểm tra của task.
5. Nếu đạt: báo cáo theo mẫu mục 8, sang task sau.
6. Nếu không đạt sau 2 lần: dừng, báo cáo, không sửa thêm.

---

## 6. Lệnh kiểm tra chuẩn

```bash
# Backend
cd backend_bridge/meta-webhook && node --check index.js && node --test

# App
cd mobile_app && flutter pub get --enforce-lockfile && flutter analyze --no-fatal-infos && flutter test

# Rà soát bí mật và mã chết
grep -rnE "AIza[0-9A-Za-z_-]{20,}|eyJhbGciOi|service_role|META_APP_SECRET=|PAGE_ACCESS_TOKEN=" . --exclude-dir=node_modules --exclude-dir=.git
```

Lệnh rà soát bí mật phải không có kết quả là chuỗi thật.

---

## 7. Thứ tự và điều kiện chuyển phase

```
Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6
```
Phase 4 (gửi tin thật) chỉ bắt đầu khi cổng Meta đã đạt trên Page test (xem `docs/meta-setup.md`).

---

## 8. Mẫu báo cáo sau mỗi task

```
Task: <số và tên>
File đã đổi: <danh sách>
Lệnh kiểm tra: <lệnh>
Kết quả: <đạt / không đạt>
Lỗi nguyên văn (nếu có): <nội dung>
Việc chưa làm trong task: <nếu có>
```

---

## 9. Điểm dừng cần người quyết định

Dừng và hỏi chủ dự án trước khi làm nếu gặp:
- Danh sách file cần xóa khác với plan quá 3 file.
- Test thất bại sau 2 lần sửa.
- Yêu cầu thêm quyền Meta, thêm dịch vụ bên thứ ba, hoặc đổi model Gemini.
- Bất kỳ thao tác nào liên quan đến khóa, token, hoặc dữ liệu khách thật.
