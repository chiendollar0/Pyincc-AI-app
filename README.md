# PYINCC AI CRM

Ứng dụng quản lý tiệm phun xăm, spa và thẩm mỹ viện. Một tài khoản chủ tiệm, toàn quyền, là admin Fanpage. Business AI của Meta chăm sóc khách. Gemini chỉ phục vụ chủ tiệm trong app. Chủ tiệm là người duy nhất duyệt và gửi cho khách.

> Nguồn chuẩn về phạm vi và quy tắc nghiệp vụ: [docs/SPEC.md](docs/SPEC.md). README chỉ tóm tắt; khi mâu thuẫn, SPEC thắng.

## Nguyên tắc vận hành

- **Business AI** trả lời khách 100% (giá, giờ, địa chỉ, đặt lịch, chuyển ca khi cần). App không trả lời khách thay AI.
- **Ứng dụng** nhận ca khi Business AI chuyển hội thoại (Conversation Routing). Chưa được chuyển thì app không can thiệp.
- **Gemini** chỉ làm việc trong app, phục vụ chủ tiệm: phân tích ảnh khách, tư vấn tham khảo, soạn nháp, tổng hợp lịch và nhắc việc. Gemini không đọc nội dung tin nhắn, không gọi Facebook, không gửi gì ra ngoài.
- **Mọi tin gửi đi** phải có bản nháp đã duyệt trong database. Server kiểm tra trước khi gọi Graph API.

## Trạng thái

Cập nhật lần cuối: 21/11/2026. Mỗi mục chỉ được đánh "Xong" khi có kết quả trong [docs/TEST-PLAN.md](docs/TEST-PLAN.md).

| Phase | Nội dung | Trạng thái |
|---|---|---|
| 0 | Nền tảng: CI, lockfile, quét bí mật, dọn mã chết | Đang làm |
| 1 | Xác thực, mã thiết lập tiệm, RLS | Chưa bắt đầu |
| 2 | Kết nối Facebook, lưu Page token mã hóa, gỡ liên kết | Chưa bắt đầu |
| 3 | Catalog theo tiệm (không giá, không mặc định) | Chưa bắt đầu |
| 4 | Studio và luồng B (phân tích, demo, duyệt, gửi) | Chưa bắt đầu |
| 5 | Hộp thư (ca, nháp, duyệt, gửi) | Chưa bắt đầu |
| 6 | Lịch và nhắc việc | Chưa bắt đầu |
| 7 | Cài đặt và nhật ký | Chưa bắt đầu |
| 8 | Luồng A: nhận ca từ Business AI (có điều kiện) | Chờ kết quả test Conversation Routing |
| 9 | Phát hành: chính sách, App Review, APK release | Chưa bắt đầu |

## Tài liệu

| File | Nội dung |
|---|---|
| [docs/SPEC.md](docs/SPEC.md) | Phạm vi, màn hình, quyền, quy tắc Gemini, nghiệp vụ |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Luồng dữ liệu, ranh giới Meta và Gemini |
| [docs/BUILD.md](docs/BUILD.md) | CI, môi trường, bảng secret và biến, lockfile |
| [docs/RUNBOOK.md](docs/RUNBOOK.md) | Mở tiệm, xoay khóa, failover Gemini, rollback, sự cố |
| [docs/TEST-PLAN.md](docs/TEST-PLAN.md) | Tiêu chí và kết quả kiểm thử theo phase |
| [docs/PRIVACY.md](docs/PRIVACY.md) | Dữ liệu thu thập, bên xử lý, thời hạn lưu, cách xóa |
| [docs/meta-setup.md](docs/meta-setup.md) | Cấu hình app Meta, Conversation routing, webhook |
| [docs/business-ai-prompt.md](docs/business-ai-prompt.md) | Prompt dán trong Business Suite |

## Cấu trúc repo

```
.github/workflows/build.yml     CI: pub get (lockfile), analyze, test thuần logic, build APK debug
.github/workflows/release.yml   Release: APK ký, deploy backend production (environment có người duyệt)
mobile_app/                     App Flutter (Android, iOS)
backend_bridge/meta-webhook/    Backend Express (index.js), package.json, package-lock.json
database/schema.sql             Schema cho project mới
database/migrations/            Migration tiến, đánh số theo ngày, không sửa file cũ
render.yaml                     Blueprint Render cho backend
scripts/smoke.sh                Kiểm tra sau deploy
docs/                           Tài liệu chuẩn (xem bảng trên)
```

## Chạy trên máy

**App**
```bash
cd mobile_app
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-infos
flutter run \
  --dart-define=SUPABASE_URL=<URL> \
  --dart-define=SUPABASE_ANON_KEY=<PUBLISHABLE_KEY> \
  --dart-define=TRYON_API_URL=<BACKEND_URL>
```

**Backend**
```bash
cd backend_bridge/meta-webhook
cp .env.example .env     # điền giá trị thật, không commit
npm ci
npm start
curl http://localhost:3000/health
```

Chi tiết biến và secret: [docs/BUILD.md](docs/BUILD.md).

## Bảo mật

- Khóa bí mật chỉ nằm trên Render và Supabase Secrets. APK chỉ chứa URL và publishable key.
- Không đưa `SUPABASE_SERVICE_ROLE_KEY`, `META_APP_SECRET`, `GEMINI_*`, `PAGE_ACCESS_TOKEN` vào APK, vào repo, vào chat hay vào tài liệu.
- Repo đang công khai: mọi khóa đã từng xuất hiện trong commit hoặc chat cần được thu hồi và thay mới. Quy trình ở [docs/RUNBOOK.md](docs/RUNBOOK.md).
- Ảnh khách là dữ liệu nhạy cảm: chỉ xử lý khi khách đồng ý, lưu bucket riêng tư, truy cập qua signed URL có thời hạn. Chi tiết: [docs/PRIVACY.md](docs/PRIVACY.md).
- Không đưa ảnh khuôn mặt thật, token, PSID thật vào repo hoặc tài liệu.

## Giới hạn đã biết

- Gửi tin qua Messenger chỉ trong 24 giờ kể từ tin cuối của khách, trừ khi dùng tag hợp lệ.
- Chưa có model tạo ảnh demo. Nút tạo ảnh bị ẩn cho đến khi có model.
- Chuyển ca từ Business AI (luồng A) chỉ hoạt động khi Conversation Routing đã được kiểm thử trên Page thật hoặc Page test.
- Chế độ Development chỉ cho tài khoản tester. Người ngoài cần App Review cho `pages_messaging` và `pages_manage_metadata`.

## Giấy phép

Mã nguồn đang trong giai đoạn phát triển nội bộ. Chưa có giấy phép phát hành.
