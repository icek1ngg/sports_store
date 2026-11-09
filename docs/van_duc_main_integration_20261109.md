# Hợp nhất phần Văn Đức vào main — 09/11/2026

Đã hợp nhất bộ catalog STRIDE, 52 ảnh theo màu, giỏ hàng chọn từng dòng và
checkout nhập địa chỉ trước bản đồ với main của nhóm tại `8d80a76`.

Theo lựa chọn mới của Văn Đức, 52 file ảnh không đưa vào Git. Main được
tạo lại trên nền main nhóm, chỉ chứa code/metadata; bản nguồn ảnh được giữ
riêng để [upload Storage](storage_color_images_20261109.md). Nhánh checkpoint
chứa ảnh chỉ ở local và không nằm trong lịch sử main sẽ push.

## Các điểm tích hợp

- Giữ `SupabaseOrderRepository` aggregate chính thức của Bảo cùng cơ chế
  kiểm tra phiên, journal và khôi phục lệnh; giữ production composition,
  notification adapter, profile revalidation khi resume và Auth/OAuth mới.
- Giữ MH08/MH09/MH17, UUID guards và modal teardown khi đổi phiên. Route
  đơn khách ở root qua `FourScreenRouteBoundary`, thanh khách nằm bên trong
  boundary; không thêm gate operational thứ hai hoặc trùng route.
- Checkout giữ scope các UUID giỏ đã chọn. Catalog/cart dùng thanh dưới
  Sản phẩm, Đơn hàng, Giỏ hàng, Tài khoản; chat mở qua mục Tài khoản.
- Giữ `catalogImageSource` phục vụ ảnh preview quản lý MH03 cùng xử lý
  `asset:`/ảnh lỗi của giao diện khách; không khôi phục nút đăng xuất header.
- Cập nhật test điều hướng tài khoản/thông báo và scenario mua hàng theo
  entry mới. Scenario kiểm tra đúng một đơn COD, nguyên UUID/số lượng, địa
  chỉ/tọa độ đã xác nhận và tiền hàng/phí/tổng; không gọi geocoding thật.

## Kiểm chứng

- `flutter pub get --enforce-lockfile`: đạt với lockfile đã có trên main,
  không nâng dependency trong bản hợp nhất.
- `flutter analyze --no-pub`: không lỗi.
- `flutter build apk --debug --no-pub --target lib/main.dart`: đạt.
- Test tài khoản/thông báo theo entry mới và toàn bộ scenario mua hàng đạt.

Ba test preview MH08/MH09 đã lỗi trên main trước khi hợp nhất. Đã kiểm tra
độc lập tại đúng `origin/main` commit
`8d80a766ef7421b7bfca269992526f607dea1343` trong detached worktree sạch:
12 test đạt, đúng 3 test sau lỗi:

1. `mh08_preview_lifecycle_test.dart`: confirm and reject dialogs remain unavailable and fail closed.
2. `mh09_preview_scenarios_test.dart`: confirm and reject preview commands repeat validation and fail closed.
3. `mh09_04a_dialog_test.dart`: MH09-04A reject dialog handles long text and keyboard insets.

Các assertion này đang chờ thông báo unavailable/biên từ chối của preview;
không sửa nghiệp vụ hoặc làm yếu test của module khác trong lượt đẩy code.
Không xem bộ test toàn dự án là đã sạch hoàn toàn.

Log cục bộ: `build/main_integration_analyze.log`,
`build/main_integration_android_build.log`,
`build/main_integration_all_tests.log`,
`build/main_remote_baseline_preview_tests.log`,
`build/main_integration_customer_entry_tests.log`,
`build/van_duc_address_first_purchase_flow_test.log`.

`.metadata` và lockfile đang sửa riêng trên máy được giữ ngoài commit này;
không gộp cập nhật dependency cục bộ vào tính năng của Văn Đức. Seed dữ liệu
vẫn là script có chủ ý; lần push Git này không chạy thêm SQL trên Supabase.
