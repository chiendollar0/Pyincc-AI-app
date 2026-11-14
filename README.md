# PYINCC - Hệ thống CSKH 2 tầng AI

Quản lý vận hành & CSKH cho cơ sở phun xăm, spa, salon.
- **Tầng 1:** Meta AI / Messenger (miễn phí, tiếp đón 24/7)
- **Tầng 2:** Google Gemini (phân loại ca khó, soạn trả lời, báo cáo cuối ngày)

## Cấu trúc
- `mobile_app/` — App Flutter (Android & iOS), 4 tab
- `backend_bridge/zalo-manager-bot/` — Bot Zalo điều hành không cần cài app
- `database/schema.sql` — Schema Supabase

## Chạy thử
### App Flutter
    cd mobile_app
    flutter pub get
    flutter run

### Bot Zalo
    cd backend_bridge/zalo-manager-bot
    npm install
    cp .env.example .env   # rồi điền key thật
    node --env-file=.env index.js

## Bảo mật
Không commit file `.env` hay API key. Mọi key đọc từ biến môi trường.
