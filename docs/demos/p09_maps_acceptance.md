# P09 — Nghiệm thu MH18 bản đồ điểm đến

Ngày 28/10/2026. MH18 đọc lại `delivery_tasks.destination_*` từ projection có
quyền của shipper hiện tại. Route chỉ nhận `taskId` dạng UUID; không truyền tên,
số điện thoại hoặc địa chỉ qua URL. Task đã bị đổi người, logout, hết phiên,
terminal/restricted hoặc thiếu tọa độ không được dùng dữ liệu cache cũ để mở
bản đồ.

## Provider và cấu hình

Phần bản đồ dùng adapter trong `lib/core/maps/` và không thêm package mới:

- Nền bản đồ: OSM raster tiles qua HTTPS tại
  `https://tile.openstreetmap.org/{z}/{x}/{y}.png`. Adapter gửi `User-Agent`
  nhận diện ứng dụng, chỉ tải lưới tile nhỏ quanh điểm đến, hiển thị
  attribution và giữ cache trong phiên theo `Cache-Control` (fallback bảy
  ngày). Không dùng geocoding, GPS nền, tile prefetch hoặc ghim cửa hàng.
- Chỉ đường: `url_launcher` hiện có, mở Google Maps URL dạng
  `https://www.google.com/maps/dir/?api=1&destination=lat,long`. Chỉ tọa độ
  được đưa vào URL; không cần Google Maps API key khi chỉ mở Maps URL.
- Không có secret/key trong source. Nếu triển khai tải lớn, cần thay OSM tile
  endpoint bằng nhà cung cấp OSM-derived có SLA/cache và cập nhật
  `MapTileSource`, attribution, User-Agent và điều khoản sử dụng.

Tài liệu provider đã kiểm tra:

- [OpenStreetMap Tile Usage Policy](https://operations.osmfoundation.org/policies/tiles/)
- [Google Maps URLs — Get started](https://developers.google.com/maps/documentation/urls/get-started)

## Hành vi MH18

| Tình huống | Kết quả cần thấy |
| --- | --- |
| Task `assigned`, `accepted`, `in_transit` có snapshot hiện tại | Hiển thị một pin tại tọa độ đã lưu, tên, số điện thoại, địa chỉ và loại nhiệm vụ. |
| Nhấn **Gọi điện** | Chỉ mở trình quay số với số hợp lệ; không tự gọi. Nếu thiết bị không hỗ trợ, báo lỗi thật. |
| Nhấn **Sao chép địa chỉ** | Đọc lại task có quyền rồi chép đúng địa chỉ snapshot; không chép dữ liệu từ task cũ. |
| Nhấn **Mở chỉ đường** | Đọc lại quyền/session rồi mở Google Maps; unavailable/failed/invalid được báo rõ. |
| Nhấn **Đưa về điểm đến** hoặc double-tap | Trả viewport về pin snapshot; không đổi tọa độ. |
| Tile/API bản đồ lỗi | Giữ tên/địa chỉ/số điện thoại được cấp quyền, hiển thị nền fallback và cho thử lại/mở chỉ đường. Không báo tải bản đồ thành công. |
| Thiếu tọa độ, tọa độ ngoài Web Mercator, task restricted/history hoặc đổi người | Không render PII/map; hiển thị trạng thái quyền/dữ liệu và yêu cầu quay lại tải lại. |
| Logout/đổi tài khoản trong lúc MH18 mở | Provider mất dữ liệu cũ; hành động đang chờ bị từ chối với lỗi hết phiên. |

## Kịch bản demo

1. Đăng nhập shipper có task hiện tại thật, mở MH11 rồi chọn **Mở bản đồ**.
   Xác nhận URL chỉ có UUID ở route và MH18 hiển thị snapshot destination.
2. Tắt mạng hoặc chặn tile endpoint. Xác nhận địa chỉ vẫn đọc được, nền tile
   hiển thị fallback và snackbar hướng dẫn thử lại/sao chép/chỉ đường.
3. Nhấn sao chép địa chỉ, gọi điện và mở chỉ đường. Kiểm tra lần lượt
   clipboard, trình quay số và Google Maps; không có thao tác server write.
4. Đổi assignment hoặc đăng xuất ở một phiên khác, quay lại MH18 và nhấn
   refresh/action. Xác nhận server read trả lỗi quyền/hết phiên, không còn PII
   của task trước.

## Kiểm tra đã chạy

```text
dart format lib/core/maps \
  lib/features/deliveries/presentation/pages/delivery_task_map_page.dart \
  lib/features/deliveries/presentation/view_models/delivery_task_map_view_model.dart \
  test/core/maps/map_contract_test.dart \
  test/features/deliveries/delivery_task_map_view_model_test.dart
flutter analyze --no-pub
flutter test --no-pub test/core/maps/map_contract_test.dart \
  test/features/deliveries/delivery_task_map_view_model_test.dart
```

Các test dùng fake directions launcher/repository được đánh dấu rõ trong test;
chúng chỉ kiểm tra URL, cache/adapter contract, recheck quyền và session race,
không giả mạo kết nối Supabase hoặc tile provider live.

## Điểm tích hợp còn lại

Đã thay child của `DeliveryTaskMapRoutePage` trong `delivery_route_pages.dart`
bằng `DeliveryTaskMapPage(taskId: taskId)`. Tám tests maps/page/VM PASS;
router/navigation tests trong full suite PASS. Không thay router, Supabase
client, theme hoặc route contract. Provider docs HTTP 200 kiểm tra 28/10/2026.
Nghiệm thu widget với Auth/Supabase thật được ghi trong báo cáo hoàn thiện chung.
