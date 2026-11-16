# PYINCC — Hệ thống quản lý vận hành & chăm sóc khách hàng

Ứng dụng Flutter và các dịch vụ backend đang được phát triển cho cơ sở phun xăm thẩm mỹ, spa và salon. Mục tiêu là kết nối hội thoại khách hàng, tư vấn, lịch hẹn, chăm sóc sau dịch vụ và xử lý ảnh theo luồng an toàn, có kiểm soát con người.

> Trạng thái hiện tại: Android/iOS scaffold đã có trong repo. GitHub Actions gần nhất đã chạy thành công bước CI mang tên Build APK; điều này xác nhận workflow hiện tại có thể build ứng dụng Flutter cơ bản. Tuy nhiên, các dịch vụ backend và luồng business logic cần được bổ sung/kiểm tra kỹ trước khi đưa ra production.

## Mục tiêu sản phẩm

- Tiếp nhận và chăm sóc khách qua Meta Business Suite/Messenger; hỗ trợ chủ tiệm quản lý nội dung, trả lời bình luận và bài đăng theo quyền/API Meta được cấp.
- Dùng Gemini ở backend để phân loại hội thoại, tóm tắt nhu cầu, soạn gợi ý tư vấn và nhận diện khách tiềm năng cần chăm sóc.
- Cho nhân viên chọn ảnh khách và mẫu trong catalog, tạo ảnh demo trước/sau qua backend; nhân viên/chủ tiệm duyệt trước khi gửi cho khách.
- Quản lý lịch hẹn, trạng thái đặt lịch, kỹ thuật viên phụ trách, ca làm và giờ làm.
- Theo dõi nhắc hẹn và chăm sóc sau dịch vụ, với báo cáo cho chủ tiệm.
- Cung cấp bot Zalo như một kênh hỗ trợ điều hành tùy chọn; không thay thế luồng Meta hoặc quyền kiểm duyệt của nhân viên.

## Kiến trúc dự kiến

1. Meta Business / Messenger — kênh tiếp nhận: inbox, bình luận và nội dung trang được xử lý thông qua API, webhook, quyền ứng dụng và chính sách của Meta. Tự động hóa không thay thế quy trình phê duyệt của nhân viên.
2. Backend — lớp nghiệp vụ và bảo mật: xác thực người dùng, kiểm tra tổ chức/quyền, gọi Gemini, xử lý ảnh, lưu dữ liệu và tích hợp Meta/Supabase. Không nên để AI trực tiếp quyết định các hành động nhạy cảm mà không có kiểm soát người dùng.
3. Gemini — trợ lý: phân loại, tóm tắt, gợi ý tư vấn/nhắc chăm sóc và hỗ trợ tạo demo ảnh thông qua dịch vụ backend. AI chỉ đề xuất; nhân viên hoặc chủ tiệm mới là người phê duyệt cuối cùng.
4. Flutter app — bảng điều khiển: inbox/triage, Try-On, lịch/ca và tác vụ chủ tiệm.
5. Zalo bot — kênh phụ: phục vụ thông báo/lệnh quản lý sau khi có ánh xạ người dùng–tổ chức, phân quyền và ghi nhận thao tác.

Không nên giả định Meta AI/Business Suite hoặc các gói miễn phí cung cấp mọi tính năng tự động hóa miễn phí. Phạm vi API, quyền truy cập, hạn mức và chi phí triển khai cần được xác nhận trước khi đặt lịch và phê duyệt dữ liệu thật.

## Kiến trúc Human-in-the-loop và hướng ưu tiên an toàn

Mô hình đề xuất cho spa/salon/phun xăm là:

- App/điều khiển: nơi nhân viên/chủ tiệm xem và xác nhận thông tin khách hàng, ảnh, tư vấn, lịch hẹn, nhắc nhở.
- Gemini: chỉ thực thi theo lệnh đã định nghĩa sẵn (classify, summarize, draft recommendation, detect leads), không tự gửi tin hoặc làm thay đổi dữ liệu nhạy cảm mà không có người phê duyệt.
- Backend: là lớp trung gian kiểm tra, xác thực, lưu ảnh, ghi dữ liệu và công bố sự kiện t��i Supabase/App.

Mục tiêu của mô hình này là giảm rủi ro AI tư vấn sai, gửi nhầm ảnh, hoặc lưu nhầm nội dung nhạy cảm. Đối với ngành thẩm mỹ, nơi ảnh khuôn mặt và dữ liệu khách hàng là nhạy cảm, việc có "người trong vòng kiểm soát" là bắt buộc thay vì cho AI tự động phản hồi không kiểm tra.

## Hướng dẫn triển khai backend Meta/Webhook an toàn

### 1) Xử lý ảnh Facebook và Supabase Storage

Khi nhận `imageUrl` từ Facebook CDN, không nên lưu trực tiếp URL đó vào database vì:

- URL có thể hết hạn sau vài ngày.
- Nhiều môi trường API bên thứ ba (ví dụ Gemini hoặc các hệ thống khác) có thể không tải được hình từ CDN công khai hoặc bị chặn.
- Ảnh khách hàng và dữ liệu hình ảnh cần có thời gian lưu trữ rõ ràng và có nơi lưu an toàn.

Giải pháp khuyến nghị:

- Trong `app.post('/webhook')`, tải hình từ `payload.url` về dạng buffer bằng `axios` hoặc `fetch`.
- Upload trực tiếp lên Supabase Storage trong một bucket riêng cho ảnh khách hàng hoặc ảnh marketing.
- Lưu URL Supabase mới tạo vào database thay vì lưu đường dẫn Facebook CDN nguyên bản.
- Nếu cần, lưu thêm metadata: `source_url`, `bucket_path`, `uploaded_at`, `expires_at`, `provider`.

Khi làm backend, nên lưu URL trên Supabase là nguồn dữ liệu chuẩn cho App Flutter và các dịch vụ downstream.

### 2) Bảo mật endpoint `/send-message` và webhook Meta

- `/send-message` không nên mở công khai. Cần có lớp xác thực tối thiểu bằng header như `x-api-key` hoặc token JWT từ Supabase/Auth.
- Giá trị API key nên được đặt trong biến môi trường trên Render / hosting, không hardcode trong source code.
- Nên giới hạn IP / domain nếu có thể, đồng thời chỉ cho phép các client đã được cấp quyền gửi tin nhắn tới trang của tiệm.
- Với Facebook webhook, cần xác minh chữ ký `x-hub-signature-256` bằng `APP_SECRET` của Meta bằng Node.js `crypto`, như đã ghi trong README kỹ thuật của dự án.

Luồng kiểm tra đáng dùng:

- Nhận request từ Meta.
- Tính HMAC SHA-256 trên raw body với `APP_SECRET`.
- So sánh với `x-hub-signature-256`.
- Chỉ xử lý nếu khớp; nếu không, trả về 403 và không lưu dữ liệu.

### 3) Bổ sung package.json cho backend_bridge/meta-webhook

Để Render build được server Node.js, cần có một `package.json` trong thư mục `backend_bridge/meta-webhook/` với dependency tối thiểu:

- `express`
- `axios`
- `@supabase/supabase-js`

Nội dung này quan trọng để process webhook có thể chạy riêng trên Render hoặc một service backend dạng Node.js tương tự. Đồng thời cũng giúp App Flutter nhận được cập nhật Realtime dựa trên dữ liệu mới ghi vào Supabase.

Ví dụ package mẫu:

```json
{
  "name": "meta-webhook",
  "version": "1.0.0",
  "private": true,
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "express": "^4.19.2",
    "axios": "^1.7.7",
    "@supabase/supabase-js": "^2.45.0"
  }
}
```

## Chức năng và trạng thái triển khai

| Hạng mục | Trạng thái repo hiện tại |
| --- | --- |
| Flutter app và scaffold Android/iOS | Có trong `mobile_app/`; workflow Build APK gần nhất thành công |
| UI dashboard và Try-On | Có mã UI; cần tiếp tục kiểm tra theo CI/thiết bị; dữ liệu chưa nối backend đầy đủ |
| Gemini Try-On proxy `/analyze`, `/generate` | Chưa có trong repo; cần triển khai trước khi dùng an toàn từ app |
| Meta webhook/API cho inbox, bình luận, đăng bài | Chưa có thư mục/dịch vụ triển khai trong repo hiện tại |
| Supabase schema ban đầu | Có `database/schema.sql`; cần bổ sung RLS, chính sách và migration trước khi dùng dữ liệu thật |
| Zalo manager bot | Có mã khởi tạo trong `backend_bridge/zalo-manager-bot/`; tích hợp nghiệp vụ và kiểm soát quyền còn cần hoàn thiện |
| Lịch/ca, CRM và chăm sóc sau dịch vụ | Schema/UI còn ở mức nền tảng hoặc mock; chưa xác nhận luồng CRUD end-to-end |
| Báo cáo khách tiềm năng và báo cáo định kỳ | Chưa có dịch vụ báo cáo/cron hoàn chỉnh trong repo |

## Cấu trúc repo hiện có

```text
Pyincc-AI-app/
├── .github/workflows/build.yml
├── mobile_app/
│   ├── android/                     # Native scaffold Android
│   ├── ios/                         # Native scaffold iOS
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/tryon/tryon_studio_screen.dart
│   │   └── services/tryon_image_service.dart
│   └── pubspec.yaml
├── backend_bridge/
│   ├── zalo-manager-bot/
│   │   ├── .env.example
│   │   ├── index.js
│   │   └── package.json
│   └── meta-webhook/              # cần bổ sung nếu triển khai webhook Meta riêng
├── database/schema.sql
└── README.md
```

Các thư mục như `backend_bridge/tryon-proxy`, `backend_bridge/meta-webhook`, `mobile_app/lib/core`, `models`, `screens/inbox`, `screens/schedule` và `screens/settings` là hạng mục kiến trúc cần bổ sung hoặc xác nhận trước khi triển khai production.

## Chạy ứng dụng Flutter

Cần cài Flutter SDK và Android SDK/JDK phù hợp trên môi trường phát triển.

```bash
cd mobile_app
flutter pub get
flutter analyze
flutter run
```

Build APK debug:

```bash
flutter build apk --debug
```

### Màn hình khởi động

Ảnh chụp được cung cấp hiển thị logo Flutter trên nền trắng — đây là màn hình khởi động của ứng dụng. Nếu màn hình này chỉ xuất hiện thoáng qua, đó là hành vi bình thường của Flutter.

CI GitHub Actions:

- Workflow: [Build APK](https://github.com/chiendollar0/Pyincc-AI-app/actions/workflows/build.yml)
- Run gần nhất được kiểm tra: [Run #15](https://github.com/chiendollar0/Pyincc-AI-app/actions/runs/43848441675) — kết quả success.

## Backend và dữ liệu — kế hoạch triển khai

### Try-On proxy

Tạo dịch vụ `backend_bridge/tryon-proxy/` với các endpoint dự kiến:

- `POST /api/tryon/analyze` — nhận ảnh và catalog, trả JSON đã được backend xác thực/kiểm tra cấu trúc.
- `POST /api/tryon/generate` — tạo ảnh demo và trả dữ liệu ảnh hoặc URL lưu trữ an toàn.

Cần giới hạn kích thước/định dạng ảnh, thời gian xử lý, tốc độ gọi, xác thực người dùng, kiểm tra quyền theo tổ chức và xử lý/xóa ảnh theo chính sách lưu trữ.

### Supabase

Schema nền nằm ở `database/schema.sql`, gồm `organizations`, `users`, `shifts`, `catalog_items`, `conversations` và `bookings`. Trước khi đưa dữ liệu thật vào app, cần:

- bật RLS cho các bảng và viết policy giới hạn dữ liệu theo tổ chức/người dùng đã xác thực;
- không đặt `service_role` key trong Flutter hoặc client;
- bổ sung bảng/lược đồ cho tin nhắn, tác vụ chăm sóc, consent, audit log và quan hệ cần thiết nếu nghiệp vụ yêu cầu;
- thêm index, ràng buộc dữ liệu và migration có thể lặp lại;
- kiểm tra phân quyền bằng tài khoản thuộc các tổ chức khác nhau.

### Meta Business

Meta webhook/API cần được thiết kế riêng: xác minh chữ ký webhook, cấu hình quyền ứng dụng/page, quản lý token phía server, chống xử lý sự kiện trùng lặp và giữ cho luồng tin nhắn an toàn theo chính sách Meta.

### Zalo bot

Mã cơ sở hiện có tại `backend_bridge/zalo-manager-bot/`. Cần hoàn thiện ánh xạ Zalo ID tới người dùng và tổ chức, quyền owner/nhân viên, truy vấn dữ liệu để đồng bộ trạng thái và hành động trên dashboard.

## Lộ trình ưu tiên

1. Chuyển Try-On khỏi gọi Gemini trực tiếp từ app sang backend có xác thực; thống nhất hợp đồng JSON và giới hạn ảnh.
2. Bổ sung RLS/policies và kiểm thử cách ly dữ liệu tổ chức trong Supabase.
3. Hoàn thiện mô hình hội thoại/tin nhắn, khách tiềm năng, nhắc lịch và chăm sóc sau dịch vụ.
4. Xây Meta webhook/API cho inbox và bình luận; thêm quy trình duyệt trước khi gửi hoặc đăng.
5. Hoàn thiện lịch hẹn, phân công kỹ thuật viên/ca làm, chống trùng lịch và ghi audit log.
6. Tích hợp báo cáo và nhắc chăm sóc sau dịch vụ; kiểm thử nghiệp vụ end-to-end.
7. Chạy `flutter analyze`, test backend, build APK và kiểm thử trên thiết bị; chỉ sau đó đánh giá mức sẵn sàng phát hành.

## Bảo mật, quyền riêng tư và vận hành

- Không commit `.env`, Gemini API key, Meta token, Supabase service-role key hoặc thông tin đăng nhập Zalo.
- Ảnh khuôn mặt và dữ liệu khách hàng chỉ được tải lên khi có thông báo/đồng ý phù hợp; cần nêu rõ mục đích, dịch vụ bên nhận, thời hạn lưu và chính sách xóa dữ liệu.
- Mã hóa truyền tải, giới hạn truy cập, hạn chế log dữ liệu cá nhân và có quy trình xóa dữ liệu/ứng phó sự cố.
- Cần rà soát quy định bảo vệ dữ liệu cá nhân áp dụng tại nơi triển khai (bao gồm Nghị định 13/2023/NĐ-CP khi phù hợp) trước khi xử lý dữ liệu khách hàng thật.
- Gemini có thể tạo nội dung sai; nhân viên cần duyệt tư vấn, hình demo, lịch và nội dung đăng trước khi thực hiện.

## Đóng góp

Mỗi tính năng nên đi kèm cập nhật README, kiểm thử phù hợp và trạng thái triển khai chính xác. Không ghi nhận một chức năng là hoàn tất cho đến khi có kiểm thử và thông tin thiết kế rõ ràng.

## Ghi chú triển khai callback Meta/Webhook

Đối với luồng webhook Meta đến App/Backend, ưu tiên thực hiện theo thứ tự sau:

1. Kiểm tra chữ ký webhook (`x-hub-signature-256`) bằng `APP_SECRET`.
2. Parse payload và lọc sự kiện không hợp lệ hoặc trùng lặp.
3. Tải ảnh Facebook CDN về buffer nếu có `imageUrl`.
4. Upload ảnh vào Supabase Storage bucket riêng.
5. Lưu URL Supabase vào bảng dữ liệu thay vì URL CDN gốc.
6. Ghi sự kiện vào Supabase, đồng thời phát ra `Realtime` để Flutter nhận thông báo.
7. Chỉ sau đó mới phân loại/đánh dấu khách tiềm năng hoặc khởi tạo Gemini workflow.

Cách làm này giữ cho toàn bộ luồng Image → Storage → Supabase → App có tính ổn định, bền vững và tuân thủ yêu cầu bảo mật nền tảng.
