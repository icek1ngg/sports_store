# P09.3 — MH18 bản đồ điểm đến

Ghi chú sau P09.4: null-coordinate policy của biên bản này đã được thay riêng
cho map reader/text fallback; lifecycle/privacy/launch feedback cũng được bổ sung.
[Biên bản mới](p094_navigation_failures_access_revocation.md).

Ngày 28/10/2026. Chỉ hoàn thiện frontend MH18; giữ các thay đổi P09.1/P09.2
đang có trong working tree. Không thêm màn hình, router/client/theme thứ hai.

## Giao diện và dữ liệu

- Mở từ MH11 qua `/shipper/tasks/:taskId/map`; route chỉ UUID, không query
  tên, số điện thoại, địa chỉ hoặc tọa độ.
- Dùng `get_my_delivery_task(uuid)` đã có qua repository/ViewModel P09.1,
  display/navigation adapter P09.2; không truy cập orders/returns trực tiếp.
- Cả outbound, return_pickup và redelivery hiển thị marker đúng tọa độ lưu
  trong task, loại nhiệm vụ, trạng thái, người nhận, điện thoại, địa chỉ đầy đủ
  và ghi chú được cấp quyền. Chỉ outbound hiển thị số lần giao.
- Bố cục tham chiếu mock HTML người dùng gửi: tiêu đề bản đồ giao nhận, bản đồ
  với nút về điểm đến, tọa độ, card người nhận/địa chỉ, gọi điện, sao chép và
  chỉ đường. Dùng theme Nike chung (đen/trắng/xám, marker đỏ), không màu xanh
  chủ đạo. Không đưa dữ liệu NV001/DH001, tab đổi mẫu, mô phỏng lỗi hoặc địa
  danh minh họa của mock vào production. Không có store/GPS pin hay sửa vị trí.
- Call chỉ mở dialer `tel:`. Navigation chỉ nhận `MapLocation`, Google Maps
  URL chỉ có `api=1` và tọa độ destination, không truyền recipient snapshot.
- Trước gọi/sao chép/chỉ đường: đọc lại quyền, kiểm tra session đang hiển thị
  và điểm đến so với snapshot lúc bấm. Điểm đến đổi thì cập nhật màn hình,
  từ chối thao tác cũ và yêu cầu bấm lại. Session đổi/mất quyền thì không
  chuyển dữ liệu sang clipboard/dialer/navigation; snapshot cũ bị gỡ.
  Contact dùng Text thường, không có menu copy của SelectableText bỏ qua
  bước kiểm quyền của nút sao chép.

## Trạng thái và giới hạn

- Loading không giữ PII của session cũ. Error/denied/restricted không hiện
  contact hoặc marker; có thử lại. Missing/null/invalid coordinates theo
  P09.1 báo invalidData, không bịa 0,0, không dùng vị trí cửa hàng.
- Lỗi tile giữ thông tin điểm đến đã được cấp quyền, hiện banner và nút thử
  lại bản đồ. Recenter đặt lại viewport về đúng destination, không GPS.
- API hiện chưa có schema ghi chú: `notes=null`, `notes_source=unavailable_schema`.
  Màn hình ghi rõ ghi chú chưa có trong dữ liệu được cấp quyền, không suy từ
  lý do trả hàng, video hoặc thông tin ngân hàng.
- Không thêm/sửa RPC, migration, RLS, Storage policy hoặc business transition.
  Không có backend dependency mới bị chặn trong scope frontend này.

## Files thuộc lượt P09.3

- `lib/features/deliveries/presentation/pages/delivery_task_map_page.dart`
- `lib/features/deliveries/presentation/view_models/delivery_task_map_view_model.dart`
- `test/features/deliveries/delivery_task_map_page_test.dart`
- `test/features/deliveries/delivery_task_map_view_model_test.dart`
- `docs/screen_mapping.md` và biên bản này.

Các files core maps/platform/dependencies khác đang dirty thuộc P09.2, không
coi là được tạo mới bởi P09.3. `outputs/` được giữ nguyên.

## Kiểm tra

- `dart format lib/features/deliveries/presentation/pages/delivery_task_map_page.dart lib/features/deliveries/presentation/view_models/delivery_task_map_view_model.dart test/features/deliveries/delivery_task_map_page_test.dart test/features/deliveries/delivery_task_map_view_model_test.dart`: PASS.
- `flutter test --no-pub test/features/deliveries/delivery_task_map_page_test.dart test/features/deliveries/delivery_task_map_view_model_test.dart test/core/maps test/app/router/operational_navigation_test.dart test/app/router/delivery_task_detail_navigation_test.dart`: **66 PASS**.
- `flutter test --no-pub`: **535 PASS, 4 opt-in tests skipped**.
- `flutter analyze --no-pub`: **No issues found**.
- `flutter build web --no-pub`: **PASS**, `build/web`; warning font
  CupertinoIcons có sẵn từ trước, không thêm package ngoài scope để che warning.
- Tests bao phủ ba kind, tọa độ/marker, recenter, loading/denied/retry,
  restricted/missing location, tile outage, dialer/copy/navigation và lỗi
  launcher, disable submission đang chờ, đổi contact, logout trong lúc copy,
  màn nhỏ 320px/chữ 1.5x và route UUID không private query. Provider tests giữ
  kiểm tra reassignment, session race và phản hồi cũ.

Không gọi mutation Supabase hoặc tạo dữ liệu live để kiểm tra frontend.
Không coi widget tests/build là nghiệm thu ứng dụng trên điện thoại thật;
manual checks browser host/Referer và app dialer/navigation trên thiết bị vẫn
theo biên bản P09.2. Không tự commit/push trong lượt P09.3.
