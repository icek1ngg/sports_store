# Sports Store

Base project PRM393 dùng Flutter + Supabase, tổ chức theo feature-first MVVM, Riverpod và go_router. Các thư mục feature hiện giữ bằng `.gitkeep`; chức năng nghiệp vụ MH01–MH20 chưa được triển khai.

## Chạy ứng dụng

Yêu cầu Flutter 3.47.2 / Dart 3.13.2 hoặc phiên bản tương thích với `pubspec.yaml`.
Chạy các lệnh từ thư mục gốc của repository:

```powershell
flutter pub get
flutter run -d chrome --dart-define-from-file=config/supabase.json
```

Với Android, mở emulator hoặc kết nối điện thoại, chạy `flutter devices`, sau đó:

```powershell
flutter run -d <device-id> --dart-define-from-file=config/supabase.json
```

`config/supabase.json` đã cấu hình project `bqoyfytmrtvjwrpshuhh`. Đây là URL và **publishable key** dành cho client, được lưu trong Git để cả nhóm dùng cùng cấu hình. Không thêm secret key, service-role key hoặc mật khẩu database vào file này. Quyền truy cập dữ liệu phải được kiểm soát bằng RLS ở backend.

Phải truyền `--dart-define-from-file` khi chạy hoặc build. Nếu thiếu cấu hình, ứng dụng hiển thị lỗi khởi động. Để dùng project riêng, tạo `config/supabase.local.json` với cùng hai trường; file `*.local.json` đã được Git bỏ qua.

## Kiểm tra

```powershell
flutter analyze
flutter test
dart run tool/check_supabase_connection.dart
flutter build web --dart-define-from-file=config/supabase.json
```

Script kết nối thực hiện GET tới Supabase Auth settings và Data API bằng publishable key; không tạo tài khoản, đọc bản ghi hoặc ghi dữ liệu. Data API được kiểm tra bằng tên bảng probe với `limit=0`; lỗi bảng không tồn tại `PGRST205` là phản hồi mong đợi cho phép kiểm tra này. Có thể truyền đường dẫn file cấu hình khác làm tham số đầu tiên.

Chi tiết khởi tạo client dùng chung và hướng dẫn cho thành viên: [docs/supabase_setup.md](docs/supabase_setup.md).

## Database dùng chung

Database cloud có 18 bảng nền tảng phục vụ phạm vi MH01–MH20. Schema và quyền Supabase được version trong `supabase/migrations/`; khi dựng mới phải chạy cả ba migration theo thứ tự. Xem [docs/database.md](docs/database.md) để biết bảng, RLS, Storage, kết quả áp dụng cloud và các luồng RPC còn cần triển khai. [docs/business_states.md](docs/business_states.md), [docs/api_contracts.md](docs/api_contracts.md) và [docs/screen_mapping.md](docs/screen_mapping.md) là hợp đồng dùng chung cho các thành viên.

`supabase/tests/database_security.sql` kiểm tra quyền và constraint bằng fixture trong transaction, kết thúc bằng ROLLBACK. Chạy nguyên file qua kết nối quản trị có quyền phù hợp; không dùng `db reset --linked` trên project dùng chung.
