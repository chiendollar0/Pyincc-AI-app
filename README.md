# PYINCC AI CRM

Ứng dụng quản lý vận hành cho thẩm mỹ viện, spa và cơ sở phun xăm, gồm:
- **App Flutter** (Android, iOS) dành cho chủ tiệm và nhân viên.
- **Backend** Node.js (`backend_bridge/meta-webhook`) chạy trên Render, nhận sự kiện Meta và cung cấp API cho app.
- **Supabase** làm cơ sở dữ liệu, xác thực người dùng, lưu trữ ảnh riêng tư và Edge Function phân tích ảnh.

> **Repo này công khai.** Không bao giờ commit `.env`, khóa API, token, keystore, hoặc ảnh khách hàng thật. Mọi khóa từng xuất hiện trong lịch sử commit phải được coi là đã lộ và thu hồi (xem mục 9).

---

## 1. Trạng thái hiện tại

| Hạng mục | Trạng thái | Ghi chú |
|---|---|---|
| CI build APK debug (GitHub Actions) | ✅ | Các run gần nhất xanh, có artifact APK |
| Domain backend `https://pyincccrm.bothelper.vn` | ✅ | `/health` trả 200, TLS do Render cấp |
| Cloudflare đứng trước Render | ✅ | Header `server: cloudflare` xác nhận |
| Edge Function phân tích mặt Gemini (`tryon-analyze`) | ✅ | Đã cấu hình `GEMINI_API_KEY` trong Supabase Secrets, trả `200` với `analysis` JSON |
| Đăng nhập Supabase trong app | ⬜ | Cần kiểm tra end-to-end với tài khoản thật |
| `GET /messages` với JWT hợp lệ trả 200 | ⬜ | Đã nối JWT từ màn đăng nhập, chờ xác nhận trên thiết bị |
| Webhook POST có chữ ký đúng trả 200 qua domain | ⬜ | Chưa kiểm tra qua domain mới |
| Xác minh Callback URL trên Meta | ⬜ | Chưa đổi sang domain mới |
| Bootstrap owner an toàn | ✅ | Đã bắt buộc khớp `BOOTSTRAP_OWNER_EMAIL` trong `index.js` |
| Gửi tin Messenger thật | ⬜ | Thuộc giai đoạn 2, cần App Review |
| Tạo ảnh ghép mày/môi thật | ❌ | `/api/tryon/generate` đang trả 501, chưa có model |
| Release APK có chữ ký | ⬜ | Đã có workflow `release.yml`, chờ tạo keystore production |

Chỉ đánh dấu ✅ khi có bằng chứng (ảnh, log, kết quả curl).

---

## 2. Phạm vi sản phẩm

**Giai đoạn 1 (bản phát hành đầu tiên):**
- Đăng nhập email cho chủ tiệm và nhân viên.
- Quản lý lịch hẹn, ca làm, kỹ thuật viên, danh mục dịch vụ, bảng giá.
- Studio AI nội bộ: phân tích ảnh khách để tư vấn, chỉ hiển thị cho nhân viên.
- Lưu ảnh khách ở bucket riêng tư, truy cập qua signed URL có thời hạn.

**Giai đoạn 2 (chỉ làm sau khi có App Review):**
- Kết nối Fanpage qua Facebook Login for Business.
- Nhận và gửi tin Messenger, duyệt tin trước khi gửi.
- Đăng bài và lên lịch đăng.

Bản đầu không yêu cầu quyền `pages_messaging`. Tính năng giai đoạn 2 phải được tắt hoặc ẩn trong bản phát hành đầu.

**Nguyên tắc con người duyệt:** AI chỉ đề xuất (tư vấn, phân loại, ảnh mô phỏng, lịch). Mọi nội dung gửi tới khách hoặc ghi vào lịch đều phải có một người đã đăng nhập bấm duyệt. Server ghi người duyệt vào database, không nhận từ body của request.

---

## 3. Kiến trúc

```
App Flutter (Android/iOS)
   │  Supabase Auth (email, lấy JWT)
   │  Authorization: Bearer <JWT>
   ▼
Backend Render  https://pyincccrm.bothelper.vn   (Cloudflare → Render)
   │  service_role (chỉ ở server)
   ▼
Supabase: Postgres • Storage (customer-media, private) • Auth • Edge Function tryon-analyze
                                                              │
                                                              ▼
                                                        Gemini API (khóa trong Supabase Secrets)

Meta Webhook ──► POST /webhook (kiểm tra x-hub-signature-256) ──► Supabase
```

- **App không giữ bất kỳ khóa bí mật nào.** Chỉ có `SUPABASE_URL` và `SUPABASE_ANON_KEY` (công khai, bảo vệ bằng RLS).
- **Backend giữ** `SUPABASE_SERVICE_ROLE_KEY`, `META_APP_SECRET`, `VERIFY_TOKEN` và các token Facebook.
- **Gemini key** chỉ nằm trong Supabase Secrets, được Edge Function đọc.

Cấu trúc thư mục:

```
.github/workflows/
  build.yml              CI: analyze, test, build APK debug
  release.yml            Release: build APK ký, deploy backend production
mobile_app/
  lib/                   Mã Dart (main.dart, screens/, services/)
  test/                  Widget test
  android/ ios/          Scaffold nền tảng
  pubspec.yaml
backend_bridge/
  meta-webhook/          Express server (index.js), .env.example, package.json
  zalo-manager-bot/      Bot Zalo (tùy chọn, chưa dùng trong production)
database/
  schema.sql             Schema cho project Supabase mới
  migrations/            Migration tiến (forward-only), đánh số theo ngày
render.yaml              Blueprint Render cho backend
```

---

## 4. Môi trường

| | Local | Staging | Production |
|---|---|---|---|
| Backend | `npm start` trên máy | Render `pyincc-api-staging` | Render `pyincc-api-prod` |
| Supabase | Project dev | Project `pyincc-staging` | Project `pyincc-prod` |
| Meta | App test, Page test | App test, Page test | App Live, Fanpage thật (giai đoạn 2) |
| Flutter | `flutter run` | APK debug cho tester | APK release ký bằng keystore production |

Quy tắc: không dùng chung khóa giữa các môi trường. Staging không bao giờ trỏ vào database production.

---

## 5. Biến môi trường

### 5.1 Backend (Render, theo từng service)

**Bí mật (chỉ đặt trong Dashboard Render, không đưa vào Git):**

| Biến | Dùng để | Ghi chú |
|---|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | Đọc/ghi database, tạo signed URL | Tuyệt đối không đưa vào app |
| `META_APP_SECRET` | Kiểm tra `x-hub-signature-256`, ký `appsecret_proof` | |
| `VERIFY_TOKEN` | Xác minh Callback URL với Meta | Chuỗi tự đặt, phải khớp ở Meta |
| `PAGE_TOKEN_ENC_KEY` | Mã hóa page token trong database | Khuyến nghị dùng khóa riêng, không lấy từ `META_APP_SECRET` |
| `API_KEY` | Chỉ cho tiến trình nội bộ (nếu có) | Không đưa vào APK, không dùng cho app |
| `PAGE_ACCESS_TOKEN` | Gửi tin khi chỉ có một Fanpage | Chỉ dùng ở giai đoạn 2 |

**Cấu hình (không bí mật):**

| Biến | Giá trị | Ghi chú |
|---|---|---|
| `NODE_ENV` | `production` | Bật kiểm tra cấu hình khi khởi động |
| `SUPABASE_URL` | `https://ihufvqrxdswgbagzhydb.supabase.co` | |
| `SUPABASE_STORAGE_BUCKET` | `customer-media` | |
| `META_GRAPH_API_VERSION` | `v19.0` | |
| `META_APP_ID` | ID app Meta | |
| `PAGE_ID` | ID Fanpage | |
| `DEFAULT_ORG_ID` | UUID tổ chức | Chỉ cho giai đoạn một tổ chức |
| `BOOTSTRAP_OWNER_EMAIL` | Email chủ tiệm đầu tiên | Chỉ dùng để tạo owner lần đầu |

Render Blueprint (`render.yaml`) tự điền các biến cấu hình và tự sinh `VERIFY_TOKEN`, `API_KEY`. Bạn chỉ cần nhập bí mật khi Render yêu cầu, và copy `VERIFY_TOKEN` sang Meta.

### 5.2 Supabase Edge Function

```bash
supabase secrets set GEMINI_API_KEY=<KHÓA_MỚI>
```

### 5.3 Flutter (truyền lúc build, `--dart-define`)

Chỉ truyền giá trị công khai:

| Biến | Ví dụ |
|---|---|
| `APP_ENV` | `production` |
| `SUPABASE_URL` | `https://ihufvqrxdswgbagzhydb.supabase.co` |
| `SUPABASE_ANON_KEY` | Anon key (công khai) |
| `TRYON_API_URL` | `https://pyincccrm.bothelper.vn` |

**Không bao giờ truyền** `SUPABASE_SERVICE_ROLE_KEY`, `META_APP_SECRET`, `GEMINI_API_KEY`, `API_KEY` hay `PAGE_ACCESS_TOKEN` vào `--dart-define`. Giá trị trong `--dart-define` vẫn nằm trong APK và có thể bị đọc.

### 5.4 GitHub Actions

- **Variables** (công khai): `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `TRYON_API_URL`, `PROD_SUPABASE_URL`, `PROD_SUPABASE_ANON_KEY`, `PROD_API_URL`.
- **Secrets** (environment `production`):
  - `ANDROID_KEYSTORE_B64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`
  - `RENDER_DEPLOY_HOOK_PROD`

---

## 6. Thiết lập Supabase

1. **Tạo project** `pyincc-prod` (và `pyincc-staging`).
2. **Schema:** chạy `database/schema.sql` trên project mới. Với project đã có bảng, chạy các file trong `database/migrations/` theo thứ tự ngày.
3. **RLS:** bật Row Level Security cho mọi bảng. Mỗi bảng có policy giới hạn dữ liệu theo `org_id` của người dùng đăng nhập. Không cấp quyền đọc cho `anon` nếu không có policy rõ ràng.
4. **Authentication → Sign In / Providers:**
   - Tắt đăng ký công khai (chỉ tạo tài khoản qua mời hoặc qua quản trị).
   - Bật xác nhận email.
5. **Storage:** tạo bucket `customer-media`, chế độ **Private**. Ảnh chỉ được truy cập qua signed URL (backend tạo, có thời hạn, ví dụ 3600 giây).
6. **Backup:** kiểm tra Settings → Database có backup tự động.
7. **Tài khoản owner đầu tiên:** tạo người dùng trong Authentication, xác nhận email, rồi thêm membership:

```sql
insert into memberships (user_id, org_id, role, status)
values ('<USER_UUID>', '<ORG_UUID>', 'owner', 'active');
```

Với nhân viên, chủ tiệm tạo tài khoản và membership với `role = 'staff'`.

---

## 7. Thiết lập backend trên Render

### 7.1 Triển khai bằng Blueprint

1. Render Dashboard → **New +** → **Blueprint** → chọn repo.
2. Nhập các bí mật khi được hỏi.
3. Sau khi tạo, mở tab **Environment** và copy `VERIFY_TOKEN` và `API_KEY` (nếu dùng).

### 7.2 Chạy cục bộ

```bash
cd backend_bridge/meta-webhook
cp .env.example .env        # điền giá trị thật, KHÔNG commit
npm install
npm start
```

Kiểm tra: `curl http://localhost:3000/health` trả `{"ok":true,...}`.

### 7.3 Custom domain

Đã cấu hình cho `pyincccrm.bothelper.vn`:
- DNS: một bản ghi **CNAME**, tên `pyincccrm`, giá trị `pyincc-ai-app.onrender.com`, không proxy ở nơi quản lý DNS.
- Không còn bản ghi A/AAAA hoặc chuyển hướng (forward) trùng tên.
- Render báo đã verify và cấp chứng chỉ.

Lưu ý: response có `server: cloudflare`, nghĩa là Cloudflare đang đứng trước. Khi kiểm tra chữ ký webhook, cần đảm bảo body không bị sửa.

### 7.4 Cold start

Gói free trên Render ngủ sau một thời gian không dùng. Request đầu có thể mất khoảng 50 giây. Với webhook, Meta sẽ thử lại nếu không nhận 200 kịp, nên backend phải ghi sự kiện nhanh rồi trả 200.

---

## 8. Thiết lập Meta

### 8.1 Webhook (giai đoạn 1 có thể để trống, giai đoạn 2 bắt buộc)

- **Callback URL:** `https://pyincccrm.bothelper.vn/webhook`
- **Verify token:** đúng giá trị `VERIFY_TOKEN` trên Render.
- Bấm **Verify and save**.
- Subscribe trang: `messages` (và `messaging_handovers`, `standby` nếu dùng Handover Protocol).

```bash
curl -X POST "https://graph.facebook.com/v19.0/$PAGE_ID/subscribed_apps?subscribed_fields=messages&access_token=$PAGE_ACCESS_TOKEN"
```

### 8.2 Facebook Login

- Valid OAuth Redirect URIs: `https://pyincccrm.bothelper.vn/auth/facebook/callback`.
- App Domains: `bothelper.vn`.
- Privacy Policy URL và Data Deletion Instructions URL phải là địa chỉ công khai.

### 8.3 App Review (cần thiết để người ngoài dùng)

- Xác minh doanh nghiệp (Business Verification).
- Xin quyền theo đúng nhu cầu. Bản đầu chỉ xin những quyền thật sự dùng.
- Video quay luồng sử dụng, mô tả cách dữ liệu được xử lý.
- Trong giai đoạn Development, chỉ admin, developer và tester của app đăng nhập được.

---

## 9. Xoay vòng khóa (bắt buộc trước production)

Repo đã công khai, nên mọi khóa từng xuất hiện trong commit hoặc chat cần được thay. Thứ tự **không được đảo**:

1. **Tạo khóa mới trước:** Gemini key (Google AI Studio), `SUPABASE_SERVICE_ROLE_KEY` (Supabase → API), `META_APP_SECRET` (Meta → Settings → Basic), `API_KEY` và `VERIFY_TOKEN` mới, page token mới nếu dùng.
2. **Cập nhật nơi chứa:** `supabase secrets set GEMINI_API_KEY=...`, Render Environment, GitHub Secrets.
3. **Deploy và kiểm tra:** chờ deploy xong, chạy smoke test (mục 11).
4. **Thu hồi khóa cũ** trên Google AI Studio, Supabase, Meta. Chỉ làm sau khi bước 3 đạt.

Kiểm tra lịch sử repo có khóa lộ không:

```bash
git log -p | grep -nE "AIza[0-9A-Za-z_-]{20,}|eyJhbGciOi|APP_SECRET=|service_role"
```

Nếu có kết quả là chuỗi thật (không phải tên biến), coi là đã lộ.

---

## 10. Build và phát hành

### 10.1 Chạy app trên máy

```bash
cd mobile_app
flutter pub get
flutter analyze
flutter test
flutter run \
  --dart-define=APP_ENV=development \
  --dart-define=SUPABASE_URL=https://ihufvqrxdswgbagzhydb.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<ANON_KEY> \
  --dart-define=TRYON_API_URL=https://pyincccrm.bothelper.vn
```

### 10.2 Keystore production (làm một lần)

```bash
keytool -genkey -v -keystore pyincc-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias pyincc
```

- Lưu keystore và mật khẩu ở nơi an toàn, có bản sao offline.
- **Mất keystore đồng nghĩa không cập nhật được app trên Google Play.**
- Thêm vào `.gitignore`: `*.jks`, `*.keystore`, `key.properties`.
- Mã hóa keystore base64 để đưa vào GitHub Secrets:

```bash
base64 -w0 pyincc-release.jks > keystore.b64
```

### 10.3 Định danh ứng dụng

- Application ID: `vn.pyincc.aicrm` (đặt trong `build.gradle` và Bundle ID iOS). **Không đổi được sau lần upload đầu tiên lên Play.**
- Tên hiển thị dưới icon: `PyinccAICRM`. Tên đầy đủ: `Pyincc AI CRM`.

### 10.4 Icon và splash

Từ file `assets/brand/logo_master.svg`, sinh các kích thước bằng `rsvg-convert` rồi chạy:

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

Feature graphic 1024×500 và icon 512×512 cho Play Store làm riêng.

### 10.5 Quy trình release

1. Mở PR vào `main`. CI phải xanh (analyze, test, build debug).
2. Deploy staging, chạy smoke test.
3. Tạo tag `vX.Y.Z` trên `main`. Workflow `release.yml` chạy, người duyệt (environment `production`) bấm xác nhận.
4. Sau deploy, chạy smoke test trên production.
5. Nếu lỗi: rollback service Render về bản trước (Events → Rollback). Với database, dùng migration tiến, không xóa bảng khẩn cấp.

---

## 11. Kiểm thử bảo mật và smoke test

Chạy sau mỗi lần deploy. Kết quả mong đợi ghi bên cạnh.

```bash
BASE=https://pyincccrm.bothelper.vn
curl -fsS $BASE/health                                     # 200, {"ok":true,...}
curl -i $BASE/messages                                     # 401 khi không có token
curl -i -H "Authorization: Bearer abc.def.ghi" $BASE/messages   # 401 với JWT giả
curl -i -X POST $BASE/webhook -H "x-hub-signature-256: sha256=0000" -d '{}'   # 403
curl -i "$BASE/webhook?hub.mode=subscribe&hub.verify_token=<VERIFY_TOKEN>&hub.challenge=123"   # 200, body 123
curl -i $BASE/internal/status                              # 404 trên production
```

Kiểm tra bucket riêng tư: truy cập trực tiếp URL public của một object phải bị từ chối (400 hoặc 403).

Chữ ký webhook đúng (chạy trên Git Bash hoặc WSL, vì cần `openssl`):

```bash
BODY='{"object":"page","entry":[{"id":"1","time":1,"messaging":[{"sender":{"id":"u1"},"recipient":{"id":"1"},"timestamp":1,"message":{"mid":"smoke-001","text":"hi"}}]}]}'
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$META_APP_SECRET" | sed 's/^.* //')
curl -i -X POST "$BASE/webhook" -H "Content-Type: application/json" \
  -H "x-hub-signature-256: sha256=$SIG" --data-binary "$BODY"
```
Kỳ vọng: `200`. Gửi lại đúng request đó vẫn `200`, và database không có bản ghi thứ hai với `mid = smoke-001`.

Luồng app (trên điện thoại thật, APK release):
1. Đăng nhập bằng tài khoản owner thử → vào được app.
2. Tab Quản lý Tiệm: tải được cấu hình và lịch hẹn, không lỗi 401.
3. Tab Studio AI: chọn ảnh, phân tích trả kết quả, không có banner "DEBUG" hay lỗi 401.
4. Đăng xuất → quay về màn đăng nhập.

---

## 12. Xử lý sự cố

| Triệu chứng | Nguyên nhân thường gặp | Cách xử lý |
|---|---|---|
| App báo `HTTP 401` ở mọi chức năng | Chưa đăng nhập, không gắn `Authorization` | Kiểm tra `currentSession` và header; đăng nhập lại |
| `401 {"error":"Unauthorized"}` | Phiên hết hạn hoặc JWT không hợp lệ | Đăng xuất, đăng nhập lại |
| `403 NO_MEMBERSHIP` | Tài khoản chưa có bản ghi `memberships` active | Thêm membership (mục 6) |
| `403` khi POST `/webhook` | Chữ ký sai, hoặc `META_APP_SECRET` không khớp | Kiểm tra secret; kiểm tra body không bị sửa qua proxy |
| `301` từ domain | Còn bản ghi forward hoặc A/AAAA cũ | Xóa forward và bản ghi cũ, chỉ giữ CNAME |
| `503` từ backend | Thiếu biến cấu hình | Xem log Render, tên biến thiếu |
| Request đầu chậm ~50 giây | Render free ngủ | Gọi `/health` trước khi test |
| Meta báo Verify thất bại | `VERIFY_TOKEN` không khớp, hoặc domain chưa sẵn sàng | Kiểm tra `curl` verify ở mục 11 |
| `501` từ `/api/tryon/generate` | Chưa có model ghép ảnh | Chờ triển khai model; không coi là lỗi |

---

## 13. Bảo mật và quyền riêng tư

- **Không đưa khóa bí mật vào app.** Mọi kiểm tra `flutter analyze` và code review phải xác nhận không có `service_role`, `META_APP_SECRET`, `GEMINI_API_KEY`, `API_KEY` trong `lib/`.
- **Ảnh khuôn mặt là dữ liệu nhạy cảm.** Chỉ thu thập khi có đồng ý rõ ràng, ghi thời điểm đồng ý. Ghi rõ mục đích, bên nhận (Supabase, Gemini), thời hạn lưu và cách xóa.
- **Xóa dữ liệu theo yêu cầu.** Có quy trình xóa tài khoản trong app và đường dẫn công khai (Data Deletion URL).
- **Tuân thủ quy định bảo vệ dữ liệu cá nhân tại Việt Nam** (Nghị định 13/2023/NĐ-CP) trước khi xử lý dữ liệu khách thật.
- **Nội dung AI** có thể sai. Không dùng cam kết kết quả điều trị ("đảm bảo", "100%", "không để lại sẹo"). Ảnh demo phải có nhãn "ảnh mô phỏng bằng AI".
- **Đăng nhập:** tắt đăng ký công khai, tránh tự tạo tiệm hoặc tự vào tiệm khác.

---

## 14. Việc còn lại trước khi phát hành

1. Thu hồi và thay mọi khóa đã từng lộ (mục 9).
2. Đăng nhập được trong app, `/messages` trả 200 với JWT owner.
3. Sửa backend theo rà soát: bọc async handler, xử lý `standby`, chặn ghi đè `org_id` của `connected_pages`, khóa chống gửi trùng, đặt lịch đúng múi giờ Việt Nam, chống trùng giờ.
4. Bật RLS và kiểm tra quyền giữa hai tổ chức.
5. Tạo keystore production và build APK release.
6. Chạy toàn bộ smoke test (mục 11) trên staging, rồi production.
7. Chuẩn bị tài liệu store: mô tả, ảnh chụp không chứa khuôn mặt khách thật, chính sách bảo mật, hướng dẫn xóa dữ liệu.

---

## 15. Liên hệ và đóng góp

Mọi thay đổi đi qua Pull Request vào `main`, có CI xanh và được duyệt. Không push trực tiếp vào `main`. Mỗi tính năng phải cập nhật README (mục 1 và mục liên quan) và ghi rõ trạng thái đã kiểm chứng.
