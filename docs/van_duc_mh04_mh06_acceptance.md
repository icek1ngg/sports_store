# Nghiệm thu MH04, MH05 và MH06 của Văn Đức

> Cập nhật 27/10/2026: giỏ hợp lệ đã mở được MH16. Lượt live trong tài liệu này
> vẫn chỉ kiểm tra MH04–MH06, không tạo đơn cloud. Test bốn màn hình và phạm vi
> backend mới xem tại [bàn giao hiện hành](van_duc_completion.md).

Ngày chuẩn bị: 25/10/2026. Project Supabase: `bqoyfytmrtvjwrpshuhh`.
Chỉ kiểm tra sản phẩm và giỏ hàng; MH16 chưa thuộc lượt này.

## Hiện trạng thực tế

| Hạng mục | Trạng thái |
| --- | --- |
| Truy cập đúng project qua connector | Đã xác nhận, project đang hoạt động |
| Dữ liệu trước chuẩn bị | 0 tài khoản, 0 sản phẩm, 0 biến thể, 0 đơn, 0 dòng giỏ |
| Dữ liệu mẫu trên cloud | Đã chạy `supabase/seed_catalog_demo.sql`: 3 sản phẩm, 5 biến thể có nhãn DEMO |
| Quyền dữ liệu | Đã kiểm tra RLS đang bật; không đổi schema, policy hoặc cấu hình xác nhận email |
| Hai tài khoản khách thử | Chờ tạo bằng Supabase Auth administration |
| Nhập mật khẩu an toàn tại máy | Đã có script lưu bằng Windows DPAPI, không ghi mật khẩu vào chat/Git |
| Kiểm tra mã/công cụ mới | Phân tích mã sạch; 117 kiểm thử hồi quy đạt; hai script PowerShell không có lỗi cú pháp |
| Biên dịch bộ nghiệm thu Android | APK debug biên dịch thành công với cấu hình công khai, chưa truyền tài khoản |
| Thiết bị nghiệm thu | Pixel 5 đã khởi động; Android SDK nhận `emulator-5554` |
| Nghiệm thu đăng nhập và UI trên Android | Chưa chạy; cần tài khoản đăng nhập thật và máy ảo được kết nối |
| Ảnh sản phẩm private | Seed chưa tải ảnh; chỉ nghiệm thu trạng thái chưa có ảnh trong lượt này |

Không dùng dữ liệu giả thay cho lỗi API. Dữ liệu mẫu trên cloud là dữ liệu được
lưu thật, nhận biết bằng tên `[DEMO]` và SKU `DEMO-CATALOG-*`.

## 1. Tạo hai tài khoản thử

Kết nối Supabase hiện có cung cấp SQL/Data API, chưa cung cấp Auth Admin API
hoặc khóa server để tạo tài khoản đăng nhập theo API chính thức. Không chèn tay
vào các bảng Auth để giả lập một tài khoản đã được đăng ký.

1. Mở [Authentication → Users](https://supabase.com/dashboard/project/bqoyfytmrtvjwrpshuhh/auth/users).
2. Tạo hai tài khoản khách dùng riêng cho nghiệm thu, mỗi tài khoản có email
   và mật khẩu khác nhau. Hoàn tất xác nhận email hoặc dùng lựa chọn xác nhận
   của thao tác tạo user quản trị.
3. Trong `public.profiles`, kiểm tra hai UUID có `role = customer` do trigger
   dự án tạo. Không cấp manager/shipper cho các tài khoản này.
4. Không dùng tài khoản đang có dữ liệu mua hàng. Giỏ của cả hai phải trống khi
   bắt đầu nghiệm thu; test sẽ dừng nếu gặp dữ liệu có sẵn.

## 2. Nhập thông tin tại máy Windows

Từ thư mục gốc dự án, chạy:

```powershell
.\tool\set_catalog_acceptance_credentials.ps1
```

Script hỏi lần lượt hai email và hai mật khẩu. Mật khẩu được nhập ẩn và lưu
bằng DPAPI trong `config/catalog_acceptance.local.json`; file được Git bỏ qua
và chỉ giải mã được bằng tài khoản Windows đã lưu nó. Script không tạo user
trên server và không tự coi việc lưu file là đăng nhập thành công.

## 3. Chạy trên máy ảo

```powershell
flutter emulators --launch Pixel_5
flutter devices
.\tool\run_catalog_acceptance.ps1 -DeviceId emulator-5554
```

Dùng đúng device ID do `flutter devices` trả về. Script chạy `flutter drive`
với kiểm thử trong `integration_test/catalog_cart_live_test.dart` và driver
`test_driver/catalog_live_driver.dart`.

Thông tin đăng nhập được giải mã vào biến môi trường của tiến trình host, rồi
truyền vào bộ kiểm thử qua kênh driver lúc chạy. Mật khẩu không được đưa vào
`--dart-define`, mã nguồn, JSON tạm hoặc APK. Các biến môi trường được khôi phục
khi script kết thúc; driver tắt ghi nhật ký trao đổi và test đăng xuất cuối lượt.
Chỉ cấu hình URL/publishable key công khai được dùng khi biên dịch ứng dụng.

## 4. Các điều kiện nghiệm thu

| Bước | Kết quả cần xác nhận |
| --- | --- |
| Đăng nhập tài khoản A | Đến MH04 bằng phiên Supabase thật |
| MH04 tìm kiếm và lọc Giày | Thấy đúng sản phẩm `[DEMO] Giày chạy bộ Daily Run` |
| MH05 chọn Đen / 40 | Giá 690.000đ, chọn số lượng 2 |
| Thêm giỏ và mở MH06 | Một dòng hàng, số lượng 2, tạm tính 1.380.000đ |
| Tăng rồi giảm | Số lượng 3/tạm tính 2.070.000đ, sau đó về 2/1.380.000đ |
| Tải lại và mở lại giỏ | Còn đúng dữ liệu đã lưu; đối chiếu API cùng tài khoản |
| Chuyển sang tài khoản B | Giỏ B trống; truy vấn trực tiếp giỏ A bằng phiên B trả rỗng |
| Quay lại tài khoản A | Dòng giỏ của A còn nguyên |
| Xóa dòng thử bằng UI | Giỏ A rỗng cả trên màn hình và API |
| Kiểm tra tồn trước/sau | `on_hand` và `reserved` không đổi do thao tác giỏ |
| Kiểm tra nút đặt hàng | Bật khi giỏ hợp lệ; lượt live MH04–MH06 này không tạo đơn |

Kết quả kiểm thử tự động trước đây không thay thế lượt nghiệm thu live này.
Chỉ đánh dấu đạt sau khi lệnh chạy trên Android hoàn tất thành công và có log.

## 5. Nếu lượt chạy bị gián đoạn

Test không tự xóa toàn bộ giỏ để vượt qua điều kiện ban đầu. Nếu thất bại sau
bước thêm, đăng nhập đúng tài khoản thử A trong công cụ chạy thử, mở MH06 và
xóa riêng dòng `[DEMO] Giày chạy bộ Daily Run / Đen / 40`, rồi chạy lại. Nếu có
dòng không phải dữ liệu thử hoặc không nhận biết được nguồn, giữ nguyên và
kiểm tra trước khi tiếp tục. Không reset database hoặc dọn giỏ của người khác.

Tham chiếu chính thức: [Auth Admin tạo user](https://supabase.com/docs/reference/dart/auth-admin-createuser),
[đăng nhập bằng mật khẩu](https://supabase.com/docs/reference/dart/auth-signinwithpassword),
[kiểm thử tích hợp Flutter](https://docs.flutter.dev/testing/integration-tests).
