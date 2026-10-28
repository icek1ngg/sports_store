# P09.4 — Navigation, fallback và thu hồi quyền MH18

Ngày 28/10/2026. Chỉ P09.4; giữ nguyên các thay đổi P09.1–P09.3 chưa commit.

## Hành vi

- External navigation dùng đúng tọa độ đã lưu và được server cấp quyền lại;
  không URL chứa tên, phone, address hoặc task/order UUID. Google Maps URL
  là dịch vụ ngoài, không route engine trong app. `tel:` chỉ yêu cầu mở dialer,
  không quyền CALL_PHONE hoặc tự đặt cuộc gọi.
- Web dùng `webOnlyWindowName: '_self'` để tránh phụ thuộc popup sau network
  recheck bất đồng bộ; native vẫn `LaunchMode.externalApplication`. Kết quả
  `opened` chỉ hiện **đã gửi yêu cầu mở**, không khẳng định browser/app đích
  đã tải, có mạng, hoặc người dùng đã thực hiện cuộc gọi.
- Navigation unavailable/failed/invalid giữ địa chỉ hợp lệ và hiện feedback
  bền trên màn hình, hướng dẫn dùng Sao chép hoặc bấm Chỉ đường để thử lại.
  Không tự đổi sang URL tìm kiếm bằng địa chỉ. Dialer failure không fake success.
- Tile failure độc lập với quyền đọc task; vẫn giữ text được cấp quyền, có
  retry tiles/recenter/copy. Không tạo marker/tọa độ thay thế.

## Contract thiếu tọa độ — thay quyết định fail-closed toàn bộ của P09.1

Đây là thay đổi client model theo yêu cầu fallback của P09.4, không thay
schema hay trả thêm dữ liệu từ server:

- `DeliveryDestination.latitude/longitude` nullable; `hasValidCoordinates`
  chỉ true khi cả hai finite và trong range. Không dùng 0,0/NaN làm sentinel.
- `DeliveryMapReader.getMapTaskDetails(taskId)` là **interface Dart đã triển
  khai**, không tên RPC mới. Supabase repository gọi lại chính
  `get_my_delivery_task(p_task_id)` trong `OperationalReadAccess.run` role
  shipper và epoch guards hiện có. Cùng allowlist payload task/items/notes.
- Chỉ mapper map-mode `allowMissingDestinationCoordinates=true` chấp nhận
  null lat/lon nếu tên/phone/address đầy đủ và snapshot current. Sai kiểu,
  nonfinite hoặc ngoài range vẫn invalidData. Thiếu contact hoặc history/
  restricted không mở fallback PII. Mapper MH10/MH11 thông thường vẫn strict.
- MH18 map state được khóa theo session identity + taskId; initial read và
  recheck dùng chung revision fence để phản hồi cũ không phục hồi PII sau
  denial mới hơn. Retry/actions dùng map reader, không lấy raw JSON từ widgets
  hoặc đọc order/return records. Text fallback vẫn recheck trước call/copy.
- Nếu thiếu location: không map/marker/coordinates/recenter, disable directions,
  hiện giải thích + refresh; contact/address hợp lệ vẫn có call/copy. Dữ liệu
  hiện tại trong DB có NOT NULL coordinates, nên null scenario được kiểm bằng
  fixture/mapper tests, không sửa production database để tạo null giả.

## Thu hồi quyền và lifecycle

- Session/logout/account switch: session-scoped provider gỡ dữ liệu cũ; pending
  response không khôi phục snapshot cũ. Denied/stale trên bất kỳ recheck nào
  lập tức chuyển error và gỡ marker/contact/actions.
- App inactive/paused/hidden: che toàn bộ body PII, tăng visibility epoch để
  vô hiệu hóa action đang chờ. Resume giữ che cho tới khi authorized read mới
  thành công. Resume offline/denied không hiện lại cache cũ. Ngay trước OS
  handoff kiểm session + visibility epoch; quay nền rồi trở lại không cứu
  thao tác cũ. Không cho SelectableText bypass nút copy có recheck.
- Khi foreground, màn hình recheck mỗi 15 giây (không chồng poll khi đang
  action/check); dispose hủy timer/observer. Đây **không phải realtime feed**.
  Reassignment server-side lúc idle được phát hiện ở lần đọc kế tiếp, không
  thể cam kết zero-latency hoặc phát hiện khi mất mạng. Network failure lúc
  màn vẫn foreground chỉ giữ snapshot gần nhất đã được cấp quyền; external
  actions vẫn bị chặn nếu không recheck được. Không gọi đây là quyền offline.
- Nếu yêu cầu nghiệm thu là xóa ngay tại thời điểm DB commit trong mọi tình
  huống, còn cần một contract/server invalidation channel có quyền theo user;
  hiện repository chưa có feed đó. Không mở SELECT bảng gốc hoặc suy Realtime
  UPDATE mất quyền là một kênh thu hồi bảo đảm.

## Files thuộc P09.4

- Domain: `delivery_task.dart`, `delivery_repository.dart`.
- Data: `delivery_task_dto.dart`, `delivery_task_details_dto.dart`,
  `supabase_delivery_repository.dart`, `platform_delivery_phone_dialer.dart`.
- Presentation: `delivery_task_map_view_model.dart`, `delivery_task_map_page.dart`;
  `delivery_task_detail_page.dart` chỉ đổi kiểm tọa độ sang helper nullable-safe.
- Core: `map_directions.dart` chỉ cấu hình Web launch target.
- Tests: `delivery_map_missing_coordinates_test.dart`,
  `delivery_task_map_page_test.dart`, `delivery_task_map_view_model_test.dart`; probe riêng
  `test/core/maps/fixtures/p094_platform_probe.dart`.
- Docs: API contracts/screen mapping, biên bản này, ghi chú supersede P09.1/3.

Không thêm migration/RPC/RLS/Storage, dependency/router/theme/client; không
mutate task, tồn kho, COD hoặc dữ liệu live. Các thay đổi core cache/config/
pubspec đang dirty còn lại thuộc P09.2; `outputs/` giữ nguyên.

## Kiểm tra và giới hạn nghiệm thu

- `dart format` các Dart files thay đổi: PASS.
- `flutter analyze --no-pub`: **No issues found**.
- `flutter test --no-pub`: **556 PASS / 4 opt-in skipped**.
  Bao gồm launched/unavailable/failed/invalid outcomes, feedback/retained text,
  missing-coordinate copy/dialer/nav-disabled, strict normal mapper, same RPC
  map-only repository, foreground reassignment, logout, pause pending ba action,
  resume authorized/denied/offline, account races và regression các kinds.
- `flutter test --no-pub test/features/deliveries/delivery_task_map_page_test.dart test/features/deliveries/delivery_task_map_view_model_test.dart test/features/deliveries/delivery_map_missing_coordinates_test.dart test/core/maps`:
  **71 PASS**, gồm late-initial-read sau denial và rapid-resume counter.
- `flutter build web --no-pub`: **PASS**, `build/web`; warning CupertinoIcons
  có sẵn từ trước. Independent review hai race đã đóng, không còn finding ở
  phạm vi tái kiểm tra đó.
- `flutter build web --no-pub -t test/core/maps/fixtures/p094_platform_probe.dart --output build/p094_probe`:
  **PASS**. Probe ghi rõ FIXTURE ONLY, tọa độ công khai, không Supabase/customer.
- `flutter devices`: Windows, Chrome 156, Edge 154; **không Android kết nối**.
- Browser automation `cua.createBrowserTab` và Computer Use `node_repl`/sky
  initialization đều lỗi **failed to write kernel assets: The system cannot
  find the path specified (os error 3)**. Không có kết quả click launcher thật
  để báo PASS. Không sửa runtime máy ngoài project để né lỗi.

Có thể nghiệm thu probe bằng:

```powershell
flutter run -d chrome -t test/core/maps/fixtures/p094_platform_probe.dart
```

Thử navigation sau delay 500ms với popup protection mặc định, kiểm đích chỉ có
tọa độ; quay lại thử dialer (không đặt cuộc gọi). Sau đó trên Android thật
nghiệm thu MH18 authorized task: native navigation/dialer, thiết bị thiếu handler,
tile offline, background/resume/reassignment/logout và che thông tin trong recents.
Probe không thay thế nghiệm thu end-to-end có Auth/RLS trên thiết bị.

**Code/tests đã hoàn thành trong scope; chưa thể kết luận P09.4 nghiệm thu
trọn vẹn** vì actual platform handoff/OS recents chưa xác minh và không có
server push revocation bảo đảm tức thì. Không có business contract mới bị
tự đoán; không claim deployment hoặc stakeholder agreement. Chưa commit/push.

Nguồn kiểm tra: [url_launcher 6.3.3](https://pub.dev/packages/url_launcher/versions/6.3.3),
[Flutter integration tests](https://docs.flutter.dev/testing/integration-tests).
Supabase changelog đã tải bằng Invoke-WebRequest (web reader không hỗ trợ
content-type Markdown); không có thay đổi SDK/server API trong lượt này.
