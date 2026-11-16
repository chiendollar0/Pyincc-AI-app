# PYINCC — Hệ thống quản lý vận hành & chăm sóc khách hàng

Ứng dụng Flutter và các dịch vụ backend đang được phát triển cho cơ sở phun xăm thẩm mỹ, spa và salon. Mục tiêu là kết nối hội thoại khách hàng, tư vấn, demo ảnh, lịch hẹn, phân ca và chăm sóc sau dịch vụ trong một quy trình có chủ tiệm kiểm soát.

> Trạng thái hiện tại: Android/iOS scaffold đã có trong repo. GitHub Actions gần nhất đã chạy thành công bước CI mang tên Build APK; điều này xác nhận workflow hiện tại xanh, không thay thế kiểm thử trên thiết bị hoặc xác nhận sẵn sàng phát hành. Các màn hình Flutter vẫn còn dữ liệu/mock và chưa có backend Try-On, Meta webhook hoặc kết nối dữ liệu Supabase hoàn chỉnh.

## Mục tiêu sản phẩm

- Tiếp nhận và chăm sóc khách qua Meta Business Suite/Messenger; hỗ trợ chủ tiệm quản lý nội dung, trả lời bình luận và bài đăng theo quyền/API Meta được cấp.
- Dùng Gemini ở backend để phân loại hội thoại, tóm tắt nhu cầu, soạn gợi ý tư vấn và nhận diện khách tiềm năng cần chăm sóc.
- Cho nhân viên chọn ảnh khách và mẫu trong catalog, tạo ảnh demo trước/sau qua backend; nhân viên/chủ tiệm duyệt trước khi gửi cho khách.
- Quản lý lịch hẹn, trạng thái đặt lịch, kỹ thuật viên phụ trách, ca làm và giờ làm.
- Theo dõi nhắc hẹn và chăm sóc sau dịch vụ, với báo cáo cho chủ tiệm.
- Cung cấp bot Zalo như một kênh hỗ trợ điều hành tùy chọn; không thay thế luồng Meta hoặc quyền kiểm duyệt của nhân viên.

## Kiến trúc dự kiến

1. Meta Business / Messenger — kênh tiếp nhận: inbox, bình luận và nội dung trang được xử lý thông qua API, webhook, quyền ứng dụng và chính sách của Meta. Tự động hóa chỉ bật sau khi cấu hình và xác minh quyền tích hợp.
2. Backend — lớp nghiệp vụ và bảo mật: xác thực người dùng, kiểm tra tổ chức/quyền, gọi Gemini, xử lý ảnh, lưu dữ liệu và tích hợp Meta/Supabase. Không đưa Gemini API key hoặc khóa dịch vụ có quyền cao vào APK.
3. Gemini — trợ lý: phân loại, tóm tắt, gợi ý tư vấn/nhắc chăm sóc và hỗ trợ tạo demo ảnh thông qua dịch vụ backend. AI chỉ đề xuất; nhân viên hoặc chủ tiệm duyệt nội dung và thao tác quan trọng.
4. Flutter app — bảng điều khiển: inbox/triage, Try-On, lịch/ca và tác vụ chủ tiệm.
5. Zalo bot — kênh phụ: phục vụ thông báo/lệnh quản lý sau khi có ánh xạ người dùng–tổ chức, phân quyền và ghi nhận thao tác.

Không nên giả định Meta AI/Business Suite hoặc các gói miễn phí cung cấp mọi tính năng tự động hóa miễn phí. Phạm vi API, quyền truy cập, hạn mức và chi phí cần được kiểm tra theo cấu hình tài khoản thực tế.

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
│   └── zalo-manager-bot/
│       ├── .env.example
│       ├── index.js
│       └── package.json
├── database/schema.sql
└── README.md
```

Các thư mục như `backend_bridge/tryon-proxy`, `backend_bridge/meta-webhook`, `mobile_app/lib/core`, `models`, `screens/inbox`, `screens/schedule` và `screens/settings` là hạng mục kiến trúc dự kiến, chưa nên coi là đã được triển khai nếu chưa xuất hiện trong repo.

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

CI GitHub Actions:

- Workflow: [Build APK](https://github.com/chiendollar0/Pyincc-AI-app/actions/workflows/build.yml)
- Run gần nhất được kiểm tra: [Run #15](https://github.com/chiendollar0/Pyincc-AI-app/actions/runs/43848441675) — kết quả success.

## Backend và dữ liệu — kế hoạch triển khai

### Try-On proxy

Tạo dịch vụ `backend_bridge/tryon-proxy/` với các endpoint dự kiến:

- `POST /api/tryon/analyze` — nhận ảnh và catalog, trả JSON đã được backend xác thực/kiểm tra cấu trúc.
- `POST /api/tryon/generate` — tạo ảnh demo và trả dữ liệu ảnh hoặc URL lưu trữ an toàn.

Cần giới hạn kích thước/định dạng ảnh, thời gian xử lý, tốc độ gọi, xác thực người dùng, kiểm tra quyền theo tổ chức và xử lý/xóa ảnh theo chính sách rõ ràng. API key Gemini chỉ nằm trong secrets của server. Không dùng một token tĩnh nhúng trong app làm cơ chế xác thực.

### Supabase

Schema nền nằm ở `database/schema.sql`, gồm `organizations`, `users`, `shifts`, `catalog_items`, `conversations` và `bookings`. Trước khi đưa dữ liệu thật vào app, cần:

- bật RLS cho các bảng và viết policy giới hạn dữ liệu theo tổ chức/người dùng đã xác thực;
- không đặt `service_role` key trong Flutter hoặc client;
- bổ sung bảng/lược đồ cho tin nhắn, tác vụ chăm sóc, consent, audit log và quan hệ cần thiết nếu nghiệp vụ yêu cầu;
- thêm index, ràng buộc dữ liệu và migration có thể lặp lại;
- kiểm tra phân quyền bằng tài khoản thuộc các tổ chức khác nhau.

### Meta Business

Meta webhook/API cần được thiết kế riêng: xác minh chữ ký webhook, cấu hình quyền ứng dụng/page, quản lý token phía server, chống xử lý sự kiện trùng lặp và tuân thủ chính sách nền tảng. Gợi ý trả lời/bài đăng nên ở trạng thái nháp để chủ tiệm duyệt; chỉ tự gửi/đăng khi đã cấu hình quyền và có lựa chọn rõ ràng.

### Zalo bot

Mã cơ sở hiện có tại `backend_bridge/zalo-manager-bot/`. Cần hoàn thiện ánh xạ Zalo ID tới người dùng và tổ chức, quyền owner/nhân viên, truy vấn dữ liệu đúng tổ chức, xác nhận thao tác sau khi ghi database thành công, logging an toàn và xử lý lỗi. Không khẳng định đã đổi ca/đặt lịch nếu thao tác chưa được lưu thành công.

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
- Ảnh khuôn mặt và dữ liệu khách hàng chỉ được tải lên khi có thông báo/đồng ý phù hợp; cần nêu rõ mục đích, dịch vụ bên nhận, thời hạn lưu và cách yêu cầu xóa.
- Mã hóa truyền tải, giới hạn truy cập, hạn chế log dữ liệu cá nhân và có quy trình xóa dữ liệu/ứng phó sự cố.
- Cần rà soát quy định bảo vệ dữ liệu cá nhân áp dụng tại nơi triển khai (bao gồm Nghị định 13/2023/NĐ-CP khi phù hợp) trước khi xử lý dữ liệu khách hàng thực.
- Gemini có thể tạo nội dung sai; nhân viên cần duyệt tư vấn, hình demo, lịch và nội dung đăng trước khi thực hiện.

## Đóng góp

Mỗi tính năng nên đi kèm cập nhật README, kiểm thử phù hợp và trạng thái triển khai chính xác. Không ghi nhận một chức năng là hoàn tất cho đến khi có kiểm thử hoặc CI chứng minh được.
