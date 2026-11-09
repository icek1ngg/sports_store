# Sports Store

Ứng dụng cửa hàng thể thao tại Hà Nội, dùng Flutter + Supabase, kiến trúc
feature-first MVVM, Riverpod và go_router. Phạm vi giữ nguyên 20 mã màn hình
MH01–MH20 và ba vai trò customer, manager, shipper.

Tài liệu đối chiếu codebase ngày 09/11/2026 nằm tại
[docs/README.md](docs/README.md). Đây là điểm bắt đầu để đọc trạng thái tích hợp,
hợp đồng hiện hành và phân biệt tài liệu lịch sử với bản chạy thực tế.

## Chạy bản kết nối Supabase

Yêu cầu Dart tương thích `^3.13.2` và Flutter tương thích; dependencies được
cố định trong `pubspec.yaml`, phiên bản giải quyết nằm trong `pubspec.lock`.
Chạy lệnh từ thư mục gốc dự án:

```powershell
flutter pub get
flutter devices
flutter run -d <device-id> -t lib/main.dart --dart-define-from-file=config/supabase.json
```

Có thể chọn `chrome` làm thiết bị. Nếu không truyền cấu hình biên dịch,
`lib/main.dart` đọc asset `config/supabase.json`. Cấu hình ghi đè thiếu/sai
sẽ báo lỗi khởi động, không tự trộn với cấu hình mặc định. Project riêng dùng
`config/supabase.local.json` và truyền bằng `--dart-define-from-file`.
Không thêm secret/service-role key hoặc mật khẩu vào cấu hình client.

Bản này dùng Supabase Auth và repository thật. Orders/Notifications được gắn
qua `lib/app/integration/production_feature_composition.dart`; không còn là
placeholder chưa bind repository. Phiên chỉ giữ trong bộ nhớ
(`persistSession: false`), nên khởi động process mới cần đăng nhập lại.
Giao diện và menu Flutter dùng tiếng Việt từ cấu hình localization chung.

Có repository và migration trong repo không chứng minh backend đã được triển
khai đầy đủ. Các điểm chưa tích hợp được ghi ở
[screen_mapping.md](docs/screen_mapping.md). Cấu hình Auth/OAuth và client xem
[supabase_setup.md](docs/supabase_setup.md).

## Ứng dụng thống nhất trên Android

Chỉ dùng một runtime Supabase Auth/repositories và canonical router:

```powershell
flutter run -d emulator-5554 -t lib/main.dart --no-dds
```

Các fixtures chỉ phục vụ automated tests dưới test/support; không có app mode local riêng.

## Tài liệu dùng chung

- [Màn hình, route, owner và mức tích hợp](docs/screen_mapping.md).
- [Schema, migration và quyền dữ liệu](docs/database.md).
- [Trạng thái nghiệp vụ](docs/business_states.md).
- [Repository và RPC](docs/api_contracts.md).
- [Mục lục và các khác biệt so với báo cáo tham khảo](docs/README.md).

Áp dụng migration theo thứ tự trong `supabase/migrations/`; với môi trường đã
có dữ liệu, đối chiếu lịch sử và chỉ áp dụng phần còn thiếu. Không dùng
`db reset --linked` trên project dùng chung. Hướng dẫn và kết quả kiểm tra
lịch sử của từng module vẫn được giữ trong `docs/` với phạm vi riêng.

## Kiểm tra khi thay đổi code

```powershell
flutter analyze
flutter test
```

Kiểm tra kết nối và build riêng khi cần:

```powershell
dart run tool/check_supabase_connection.dart
flutter build web --dart-define-from-file=config/supabase.json
```

Script kết nối chỉ probe Auth settings và Data API bằng publishable key;
không kiểm chứng luồng nghiệp vụ có đăng nhập. Các kiểm thử trong `test/live/`,
`integration_test/` và `supabase/tests/` cần môi trường/fixture phù hợp.
Không suy kết quả đạt từ việc file kiểm thử tồn tại. Lần cập nhật tài liệu
09/11/2026 chỉ đối chiếu tĩnh mã nguồn, không chạy lại Flutter hay backend.
