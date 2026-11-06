# Sports Store

Ứng dụng dùng tiếng Việt cho giao diện, thông báo, nút điều hướng và các menu
mặc định của Flutter, kể cả khi thiết bị đang dùng ngôn ngữ khác. Cấu hình chung
nằm trong `lib/app/localization/app_localization.dart`; mã nguồn và API giữ tên
tiếng Anh theo quy ước nhóm.

## Phần Văn Đức: MH04, MH05, MH06 và MH16

Danh sách chức năng, backend đặt COD, cách chạy trên Android và kết quả kiểm
tra: [bàn giao MH04–MH16](docs/van_duc_completion.md).

Quy trình nghiệm thu trên Android với hai tài khoản riêng, cách nhập mật khẩu
tại máy và kết quả cloud hiện hành:
[nghiệm thu MH04–MH06](docs/van_duc_mh04_mh06_acceptance.md).

```powershell
flutter pub get
flutter run -d chrome -t tool/catalog_live/main.dart --dart-define-from-file=config/supabase.json
```

Đăng nhập bằng tài khoản `customer` của project. Xem
[hướng dẫn Supabase từng bước](docs/supabase_catalog_guide.md) để tạo user,
xem bảng, thêm dữ liệu mẫu có nhãn DEMO và upload ảnh private. Công cụ không
bỏ qua RLS và không lưu phiên xuống đĩa. MH04 đã nối repository Supabase;
MH05 đọc chi tiết/chọn biến thể và thêm giỏ. Mở biểu tượng giỏ từ MH04/MH05
để vào `/customer/cart`: sửa số lượng, xóa và tải lại để kiểm tra lưu theo
tài khoản. Giỏ chưa giữ tồn. Giỏ hợp lệ mở `/customer/checkout` để nhập người
nhận, chọn vị trí trong Hà Nội và đặt COD; máy chủ giữ tồn khi tạo đơn.
Giá/tồn đã đổi hoặc hàng ngừng bán có cảnh báo; lỗi ghi không báo thành công.
Hợp đồng checkout/tồn kho bàn giao với phần Bảo nằm tại
[docs/van_duc_catalog_checkout_contract.md](docs/van_duc_catalog_checkout_contract.md).

Project PRM393 dùng Flutter + Supabase, tổ chức theo feature-first MVVM,
Riverpod và go_router. Nhánh tích hợp giữ catalog/giỏ/checkout của Văn Đức cùng
các cập nhật giao hàng, COD và bản đồ từ main.
Các màn và luồng còn lại xem trạng thái cụ thể trong `docs/screen_mapping.md`;
không coi toàn bộ MH01–MH20 đã hoàn thành.

Cập nhật 30/10: đã sửa điều hướng trang chính theo vai trò, giữ lịch sử khi chat
tự tải lại, đồng bộ số chưa đọc và chọn/upload ảnh sản phẩm. Sau đồng bộ main,
trang customer dùng catalog/giỏ/checkout của Văn Đức; MH08 chưa bind repository
thật nên trang chính manager báo dịch vụ chưa tích hợp và vẫn có navigation
tới phần Dung An. Xem
[phạm vi, phụ thuộc và kiểm thử](docs/features/dung_an_supabase.md).

## Các màn Dung An đã nối Supabase

MH01 đăng nhập và MH02 đăng ký dùng Supabase Auth. MH03 quản lý sản phẩm đọc dữ liệu thật và lưu sản phẩm/biến thể/giá/tồn kho qua RPC giao dịch. MH19 đọc hội thoại, mở MH20 và gửi/đọc tin nhắn có lưu trữ. Các màn đã nối router chính và đọc quyền từ `profiles`.

**Đã kiểm tra sau migration trên cloud:** Auth/Data API kết nối được tới project `bqoyfytmrtvjwrpshuhh`; cả năm RPC mới đã tồn tại và từ chối caller chưa đăng nhập đúng quyền (`42501`). Lượt kiểm tra lại có 30 test chức năng/điều hướng và 37 kiểm tra database cô lập thành công. Chưa kiểm thử thao tác ghi bằng tài khoản đăng nhập thật trên cloud. Chi tiết chức năng, giới hạn và kết quả ở [docs/features/dung_an_supabase.md](docs/features/dung_an_supabase.md).

Entrypoint cũ `tool/ui_preview/prm_main.dart` nay chuyển vào ứng dụng chính, dùng cùng cấu hình Supabase và không còn dữ liệu demo.

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

Khi chạy `lib/main.dart` không có `--dart-define`, ứng dụng tự đọc `config/supabase.json` được đóng gói trong assets. Có thể dùng `flutter run` hoặc nút Run thông thường. Để dùng project riêng, tạo `config/supabase.local.json` với cùng hai trường và truyền `--dart-define-from-file=config/supabase.local.json`; file `*.local.json` đã được Git bỏ qua. Nếu truyền cấu hình riêng thiếu hoặc sai, ứng dụng báo lỗi và không tự chuyển sang project mặc định.

Trong VS Code, mở thư mục gốc repository, chọn thiết bị, chọn cấu hình **Sports Store** ở Run and Debug rồi nhấn **F5**. File `.vscode/launch.json` đã truyền cấu hình Supabase cho lần chạy này.

Trong Android Studio, vào **Run → Edit Configurations**, chọn cấu hình Flutter chạy `lib/main.dart`, thêm `--dart-define-from-file=config/supabase.json` vào **Additional run args**, rồi chạy lại.

Nếu log báo `Application startup failed: ArgumentError` ngay sau khi APK build thành công, kiểm tra cấu hình mặc định hoặc tham số ghi đè trên. Sau khi thay đổi assets/cấu hình, dừng phiên chạy cũ và chạy lại hoàn toàn; hot reload không cập nhật các giá trị `String.fromEnvironment`.

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

Database nền có 18 bảng phục vụ phạm vi MH01–MH20. Schema và quyền Supabase
được version trong `supabase/migrations/`; khi dựng mới áp dụng tất cả migration
theo thứ tự, gồm các migration nền, checkout và các cập nhật giao hàng/COD/trả hàng.
Xem [docs/database.md](docs/database.md) để phân biệt schema đã triển khai,
kết quả kiểm tra cloud lịch sử và các luồng RPC còn cần làm.
[docs/business_states.md](docs/business_states.md),
[docs/api_contracts.md](docs/api_contracts.md) và
[docs/screen_mapping.md](docs/screen_mapping.md) là hợp đồng dùng chung.

Với cloud đang có dữ liệu, đối chiếu lịch sử và chỉ áp dụng migration còn thiếu.

`supabase/tests/database_security.sql` kiểm tra quyền và constraint bằng fixture trong transaction, kết thúc bằng ROLLBACK. Chạy nguyên file qua kết nối quản trị có quyền phù hợp; không dùng `db reset --linked` trên project dùng chung.
