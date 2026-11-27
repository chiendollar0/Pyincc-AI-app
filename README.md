# PYINCC AI CRM

Ứng dụng quản lý tiệm phun xăm, spa và thẩm mỹ viện. Mỗi tiệm dùng **1 tài khoản chủ tiệm (`owner`) duy nhất** (không có vai trò nhân viên), kết nối Fanpage qua Meta Messenger Webhook. Chatbot AI dùng Google Gemini (khóa Pro tách biệt cho dữ liệu khách) để soạn **bản nháp trả lời**; chủ tiệm là người duy nhất duyệt và gửi cho khách, và chatbot **không báo giá**.

> Nguồn chuẩn về phạm vi, quy tắc và lộ trình triển khai: [docs/SPEC.md](docs/SPEC.md) và [docs/PLAN-AI-CODING.md](docs/PLAN-AI-CODING.md). README chỉ tóm tắt; khi mâu thuẫn, SPEC thắng.

## Nguyên tắc vận hành

- **Một chủ tiệm duy nhất:** Không có tài khoản nhân viên. Thiết bị phụ (Phase 2) sử dụng phiên thiết bị có thời hạn gắn với tiệm của chủ tiệm.
- **Chatbot AI soạn nháp, không tự gửi:** Tin nhắn khách từ Messenger đi qua pipeline (xin đồng ý ảnh, FAQ, chuyển chủ khi hỏi giá, Gemini khóa Pro) tạo bản nháp `pending`. AI mặc định chỉ nháp (`AI_REPLY_ENABLED=false`).
- **Không báo giá:** Danh mục dịch vụ (`catalog_items`) và kho kiến thức (`kb_entries`) không chứa giá; mọi câu hỏi về giá đều chuyển chủ tiệm trả lời trực tiếp.
- **Routing khóa Gemini tách biệt:** Dữ liệu khách (`customer`) chỉ dùng `GEMINI_PRO_KEY_1` / `GEMINI_PRO_KEY_2` và không bao giờ fallback sang `GEMINI_FREE_KEY` (chỉ dùng nội bộ/dev).
- **Business AI của Meta không phải lõi:** Nếu Page đang bật Business AI thì tắt để tránh xung đột với webhook của ứng dụng.
- **Mọi tin gửi đi phải được duyệt & trong 24 giờ:** Server kiểm tra bản nháp `approved` trong database và cửa sổ 24 giờ kể từ tin cuối của khách trước khi gọi Graph API.

## Trạng thái

Cập nhật lần cuối: 26/11/2026 theo lộ trình tại [docs/PLAN-AI-CODING.md](docs/PLAN-AI-CODING.md).

| Phase | Nội dung | Trạng thái |
|---|---|---|
| 0 | Dọn nền: bỏ mã nhân viên, bỏ Zalo bot, routing khóa AI, schema chatbot | Đang hoàn tất |
| 1 | Giao diện khung 4 tab và đăng nhập | Tiếp theo |
| 2 | Tiệm, mã thiết lập, phiên thiết bị | Chưa bắt đầu |
| 3 | Khách, catalog không giá, kho kiến thức chatbot | Chưa bắt đầu |
| 4 | Chatbot pipeline (chưa gửi tự động) | Chưa bắt đầu |
| 5 | Giao diện chat 24h, lịch và Studio | Chưa bắt đầu |
| 6 | Báo cáo cuối ngày (SQL) và cài đặt | Chưa bắt đầu |

## Tài liệu

| File | Nội dung |
|---|---|
| [docs/SPEC.md](docs/SPEC.md) | Phạm vi, màn hình, quyền, quy tắc Gemini, nghiệp vụ |
| [docs/PLAN-AI-CODING.md](docs/PLAN-AI-CODING.md) | Kế hoạch thực hiện chi tiết theo Phase 0–6 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Luồng dữ liệu, ranh giới Meta và Gemini |
| [docs/BUILD.md](docs/BUILD.md) | CI, môi trường, bảng secret và biến, lockfile |
| [docs/RUNBOOK.md](docs/RUNBOOK.md) | Mở tiệm, xoay khóa, failover Gemini, rollback, sự cố |
| [docs/TEST-PLAN.md](docs/TEST-PLAN.md) | Tiêu chí và kết quả kiểm thử theo phase |
| [docs/PRIVACY.md](docs/PRIVACY.md) | Dữ liệu thu thập, bên xử lý, thời hạn lưu, cách xóa |
| [docs/meta-setup.md](docs/meta-setup.md) | Cấu hình app Meta, webhook, quyền Messenger |

## Cấu trúc repo

```
.github/workflows/build.yml     CI: pub get (lockfile), analyze, test thuần logic, build APK debug
.github/workflows/release.yml   Release: APK ký, deploy backend production (environment có người duyệt)
mobile_app/                     App Flutter (Android, iOS)
backend_bridge/meta-webhook/    Backend Express (index.js, src/ai/gemini.js, src/chat/window.js, test/)
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

- Gửi tin tự do qua Messenger chỉ trong 24 giờ kể từ tin cuối của khách.
- Chưa có model tạo ảnh demo. Nút tạo ảnh bị ẩn cho đến khi có model.
- Chế độ Development chỉ cho tài khoản tester. Người ngoài cần App Review cho `pages_messaging` và `pages_manage_metadata`.

## Giấy phép

Mã nguồn đang trong giai đoạn phát triển nội bộ. Chưa có giấy phép phát hành.
