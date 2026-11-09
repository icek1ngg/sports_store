# Địa chỉ giao hàng MH16 — 09/11/2026

Luồng hiện tại đã chuyển sang [nhập địa chỉ trước bản đồ](van_duc_address_first_checkout_20261109.md).
Phần dưới ghi nhận chẩn đoán và bản ghim trực tiếp trước lần đổi UX này.

Ô bản đồ xám do DNS mặc định trả NXDOMAIN cho `tile.openstreetmap.org`.
Giả lập vẫn kết nối được Supabase. Đã khởi động lại đúng Pixel_5 với
`-dns-server 1.1.1.1,8.8.8.8`, giữ dữ liệu ứng dụng và DNS Windows.
Kiểm thử Android đã tải qua HTTPS và giải mã một tile Hà Nội 256×256.

## Hành vi sau sửa

- Preview và hộp chọn dùng chung `CheckoutLocationMap`, kết nối
  `FlutterMapTileProvider` với `mapTileSourceProvider` hiện có. Giữ cache,
  nhận diện ứng dụng và nguồn OpenStreetMap; không thêm SDK/provider/API key.
- Có tiến trình tải, thông báo mất kết nối và nút thử lại. Không cho chạm
  chọn trên nền chưa tải hoặc bị lỗi; vẫn có thể nhập tọa độ chính xác.
- Tâm Hà Nội ban đầu chỉ là viewport; không hiện ghim và không cho xác nhận
  ngầm thành địa chỉ nhận hàng. Khách chạm bản đồ hoặc nhập tọa độ để chọn.
- Có thể chạm ngay bản đồ nhỏ trên checkout để ghim; vị trí và tọa độ cập
  nhật cùng lúc. Nút chọn vị trí mở bản đồ lớn để chỉnh chi tiết; xác nhận
  quay về checkout giữ ghim đó. Khi yêu cầu đặt hàng đang khóa, không đổi ghim.
- Tắt nhận nhấn đúp để cập nhật ghim ngay khi chạm một lần; vẫn kéo và
  dùng hai ngón để thu/phóng. Điều này tránh xác nhận nhanh trả về điểm cũ
  trong lúc sự kiện chạm còn chờ nhận nhấn đúp.
- Nhập tọa độ cập nhật ghim và di chuyển viewport theo đúng điểm; từ chối
  tọa độ không hữu hạn/ngoài miền bản đồ. Mở lại giữ vị trí đã chọn.
- Khách tiếp tục nhập số nhà, đường, phường/xã trong ô địa chỉ chi tiết.
  Không suy đoán địa chỉ từ tâm bản đồ. Máy chủ vẫn kiểm tra vùng Hà Nội
  khi đặt đơn; vị trí chọn trên client không tự chứng minh được phục vụ.

## Chạy và kiểm tra

Nếu DNS mạng lại không phân giải được OpenStreetMap, đóng đúng giả lập rồi
khởi động lại bằng tùy chọn DNS riêng của Android Emulator; không cần đổi
DNS Windows hoặc gán IP vào mã ứng dụng:

```powershell
& '<ANDROID_SDK>/emulator/emulator.exe' -avd Pixel_5 -no-boot-anim -dns-server '1.1.1.1,8.8.8.8'
flutter run --no-pub -d emulator-5554 --target lib/main.dart
```

Kiểm thử UI: 18 bài checkout/địa chỉ đạt, gồm chạm ghim trong một frame;
5 bài adapter đã đạt. Hai kiểm tra Android đạt: HTTPS decode và chạm ghim
trên map nhỏ → chỉnh trong picker → xác nhận giữ đúng tọa độ. Chạy bằng
`flutter test --no-pub -d emulator-5554 integration_test/checkout_map_connectivity_test.dart`.
Probe chỉ tải tile đang hiển thị, không đăng nhập hay tạo đơn, không tải vùng.
Log: `build/checkout_location_map_test.log`,
`build/flutter_map_tile_provider_test.log`,
`build/checkout_pin_final_tests.log`, `build/checkout_pin_android_verified.log`,
`build/checkout_pin_final_analyze.log`.

Tham khảo API: [Android Emulator startup options](https://developer.android.com/studio/run/emulator-commandline),
[flutter_map Tile Providers](https://docs.fleaflet.dev/layers/raster-tile-layer/tile-providers).
