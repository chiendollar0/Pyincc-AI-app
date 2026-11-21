# Hướng dẫn Build, CI/CD, Biến môi trường & Lockfile (BUILD)

## 1. Bảng Biến môi trường & Secrets

### A. GitHub Actions Secrets (Repo Settings → Secrets and variables → Actions)

| Tên Secret | Bắt buộc cho | Ghi chú |
|---|---|---|
| `SUPABASE_URL` | `build.yml`, `release.yml` | URL project Supabase (`https://<ref>.supabase.co`) |
| `SUPABASE_ANON_KEY` | `build.yml`, `release.yml` | Publishable/Anon key (an toàn trong APK) |
| `TRYON_API_URL` | `build.yml`, `release.yml` | URL backend (`https://pyincccrm.bothelper.vn`) |
| `FB_CLIENT_TOKEN` | `build.yml`, `release.yml` | Facebook Client Token truyền qua `ORG_GRADLE_PROJECT_FB_CLIENT_TOKEN` |
| `ANDROID_KEYSTORE_B64` | `release.yml` (production) | Keystore release mã hóa base64 |
| `ANDROID_STORE_PASSWORD` | `release.yml` (production) | Mật khẩu keystore |
| `ANDROID_KEY_PASSWORD` | `release.yml` (production) | Mật khẩu key |
| `ANDROID_KEY_ALIAS` | `release.yml` (production) | Alias của key ký APK |

> **Tuyệt đối không** đưa `SUPABASE_SERVICE_ROLE_KEY`, `META_APP_SECRET`, `PAGE_TOKEN_ENC_KEY`, `GEMINI_API_KEY`, `PAGE_ACCESS_TOKEN` vào APK hay `--dart-define`.

### B. Render Dashboard Environment (`pyincc-meta-webhook`)

| Biến | Loại | Ghi chú |
|---|---|---|
| `NODE_ENV` | Config | `production` |
| `TRUST_PROXY_HOPS` | Config | `2` (Cloudflare → Render) |
| `PUBLIC_BASE_URL` | Config | `https://pyincccrm.bothelper.vn` |
| `SUPABASE_URL` | Config | URL Supabase project |
| `SUPABASE_STORAGE_BUCKET` | Config | `customer-media` (bucket private) |
| `META_APP_ID` | Config | `1555273769742937` |
| `META_GRAPH_API_VERSION` | Config | `v21.0` |
| `BOOTSTRAP_OWNER_EMAIL` | Config (tùy chọn) | Email chủ tiệm đầu tiên khi `organizations` trống (có thể dùng `POST /onboarding/claim` thay thế) |
| `SUPABASE_SERVICE_ROLE_KEY` | **Secret** | Khóa service role của Supabase |
| `META_APP_SECRET` | **Secret** | App Secret từ Meta for Developers (bắt buộc ở production) |
| `VERIFY_TOKEN` | **Secret** | Chuỗi xác minh webhook Meta |
| `PAGE_TOKEN_ENC_KEY` | **Secret** | Khóa AES-256-GCM mã hóa Page Token — **phải sao lưu ngoài Render** |
| `GEMINI_API_KEY` | **Secret** | Khóa Google Gemini API cho Luồng B |

> **Không đặt trên production:** `DEFAULT_ORG_ID`, `PAGE_ID`, `PAGE_ACCESS_TOKEN`, `API_KEY` (nếu không dùng endpoint nội bộ).

## 2. Quy trình CI/CD

- **`.github/workflows/build.yml`** (chạy trên `push`/`pull_request` vào `main` và `workflow_dispatch`):
  1. Quét bí mật trên toàn bộ file tracked trong Git.
  2. Kiểm tra cú pháp & chạy toàn bộ unit test backend (`node --check`, `node --test`).
  3. Chạy `flutter pub get`, `flutter analyze --no-fatal-infos`, `flutter test`.
  4. Build `app-debug.apk` và upload artifact (tự động bỏ qua bước cần secret nếu là PR từ fork).
- **`.github/workflows/release.yml`** (chạy khi push tag `v*.*.*` hoặc `workflow_dispatch`):
  - Chạy đầy đủ quét bí mật, test backend, giải mã keystore release (nếu đã cấu hình), build `app-release.apk` và upload artifact.

## 3. Lockfile (`pubspec.lock` & `package-lock.json`)

- **Flutter (`mobile_app/pubspec.lock`):** Mỗi khi thay đổi `pubspec.yaml`, chạy `cd mobile_app && flutter pub get` trên máy phát triển và commit `pubspec.lock`. Khi `pubspec.lock` đã đồng bộ đầy đủ với `pubspec.yaml`, đổi bước CI sang `flutter pub get --enforce-lockfile`.
- **Node.js (`backend_bridge/meta-webhook/package-lock.json`):** Chạy `cd backend_bridge/meta-webhook && npm install --package-lock-only` trên máy phát triển có truy cập npm registry và commit `package-lock.json`. Sau đó đổi `render.yaml` (`buildCommand`) từ `npm install` sang `npm ci`.

## 4. Kiểm tra sau deploy

```bash
./scripts/smoke.sh https://pyincccrm.bothelper.vn
```
