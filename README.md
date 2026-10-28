# Sports Store

Project PRM393 dùng Flutter + Supabase, tổ chức theo feature-first MVVM, Riverpod và go_router. Tình trạng từng phần được ghi trong `docs/`; bản giao diện xem thử MH01, MH02, MH03 và MH19 nhập từ `prm` được mô tả bên dưới.

## Giao diện Dung An nhập từ prm

Đã nhập bốn màn MH01 đăng nhập, MH02 đăng ký, MH03 quản lý sản phẩm và MH19 danh sách hội thoại vào `lib/features/<feature>/presentation/pages/`, cùng ba ảnh STRIDE trong `assets/images/`. Các widget và theme của bản xem thử nằm trong `lib/shared/widgets/prm_preview_widgets.dart`.

Chạy bản xem thử bằng entrypoint riêng:

```powershell
flutter pub get
flutter run -d chrome -t tool/ui_preview/prm_main.dart
```

Phần nhập này giữ hành vi của source `prm`: MH01/MH02 chưa kết nối xác thực; MH03/MH19 dùng dữ liệu demo trong bộ nhớ. Điều hướng và theme trong entrypoint xem thử chỉ phục vụ demo. Việc nối các màn vào router, ViewModel, repository và backend dùng chung chưa nằm trong lần nhập source này. Điểm khởi động `lib/main.dart`, cấu hình Android và các module hiện có được giữ nguyên. Không nhập cache, build, cấu hình máy cá nhân hoặc các bản tài liệu Word/PDF từ thư mục nguồn.

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
