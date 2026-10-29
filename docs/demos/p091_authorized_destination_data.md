# P09.1 — Dữ liệu điểm đến có quyền cho MH18

**Cập nhật P09.4:** quyết định null tọa độ bên dưới được thay riêng cho MH18
bởi map-only reader: contact current đầy đủ vẫn được dùng cho text/copy/dialer,
directions bị chặn; mapper MH10/MH11 vẫn strict.
[Contract mới](p094_navigation_failures_access_revocation.md).

Ngày 28/10/2026. Tái sử dụng lớp đọc production hiện có, chỉ siết dữ liệu/
authorization lifecycle của MH18; không triển khai thêm map UI/provider,
điều hướng/GPS hoặc phase sau trong lượt này.

## Hợp đồng đã có và quyết định dữ liệu

- Route `/shipper/tasks/:taskId/map` chỉ mang task UUID. Recipient name/phone,
  address/coordinates/notes không ở route/query/fragment.
- MH18 dùng `deliveryTaskMapViewModelProvider` → session-keyed shared
  `deliveryTaskDetailsProvider` → `SupabaseDeliveryRepository.getTaskDetails`
  → RPC **hiện có** `get_my_delivery_task(p_task_id uuid)`.
  RPC phối hợp các projection `read_my_delivery_tasks` và
  `read_my_delivery_task_items`; không thêm RPC chuyên biệt.
- Quyền hiện hữu: identity auth/server profile shipper, assignment hiện tại,
  đúng task UUID; trạng thái current assigned/accepted/in_transit mới cung cấp
  destination. History/restricted không có recipient/location/items để mở map.
  Historical assignment không cho xem task mới cùng order/request. Server kiểm
  lại mỗi fetch; UI guard không thay RLS/RPC authorization.
- Ba loại outbound/return_pickup/redelivery dùng đúng destination_* snapshot
  server; không lấy địa chỉ từ orders/return_requests hoặc geocode tự đoán.
  Redelivery thực tế có immutable item plan vẫn dùng cùng task read an toàn.
- Notes hiện **chưa có trong schema delivery task**: RPC trả notes=null,
  notes_source=unavailable_schema. Không lấy lý do return, video/bank/refund
  evidence làm ghi chú thay thế; không hiển thị một ghi chú giả như dữ liệu thật.

## Null/tọa độ thiếu hoặc sai

DB destination_* có NOT NULL/coordinate constraints; DTO hiện hữu yêu cầu bộ
destination đầy đủ khi current, kiểm UUID/kiểu/số hữu hạn/lat [-90,90], lon
[-180,180]. Nếu payload thiếu một hoặc cả tọa độ hoặc trường recipient bắt
buộc, repository trả invalidData: MH18 không dựng snapshot nửa vời, không dùng
0,0/pin cửa hàng/địa chỉ người trước. Mốc P09.1 chọn **fail closed** với dữ liệu
điểm đến không hợp lệ; giữ address fallback chỉ khi snapshot trước đã hợp lệ và
lỗi mới là network/backend unavailable, không phải quyền bị thu hồi.

ViewModel kiểm thêm task UUID khớp, scope current, destination không null và
tọa độ hữu hạn/range, kể cả adapter test/custom bỏ qua DTO. Tọa độ địa lý hợp
lệ nhưng vượt Web Mercator không bị đổi thành điểm khác; khả năng render tile
thuộc map adapter đã có. Không cho chỉnh destination hoặc ghi server.

## Thay đổi trong lượt này

- `delivery_task_map_view_model.dart`: UUID không hợp lệ bị chặn trước đọc;
  validate current destination ở cả initial projection và recheck; quyền/
  assignment/session/data không hợp lệ xóa snapshot cũ ngay. Revision và identity
  session chặn kết quả muộn không khôi phục/xóa snapshot của tài khoản mới.
- Recheck đọc server thật trước hành động cung cấp thông tin. Coordinate handoff
  có kiểm identity cùng session cả trước/giữa/sau await; không cho session B dùng
  điểm đến đã được cấp quyền cho A. Không thêm action/launcher mới.
- Tests `delivery_task_map_view_model_test.dart`: ba kind, UUID sai/foreign,
  missing coordinates, denial clears PII, restricted/reassigned, logout,
  late-account response và chính cửa sổ account switch sau authorized read
  nhưng trước launcher. Fake repository/session/launcher chỉ nằm trong test.

Không mutation, migration, API signature, table grant/RLS, router, dependency,
theme hoặc Supabase client mới. Chỉ chỉnh ViewModel/tests và tài liệu liên quan;
không chỉnh UI teammate hoặc `outputs/`.

## Kiểm chứng

- `flutter test --no-pub test/features/deliveries/delivery_task_map_view_model_test.dart
  test/features/deliveries/delivery_task_map_page_test.dart
  test/features/deliveries/delivery_mapper_test.dart
  test/app/router/operational_navigation_test.dart`: **43 PASS** trước ba cases
  bổ sung denial-clears-state; các cases thêm nằm trong full suite cuối.
- `node supabase/tests/run_delivery_read_fixture.mjs p011_p091_destination_read`:
  **PASS**, 22 migrations; SQL tests task/detail authorization, hai shipper,
  denied UUID, reassignment/history boundaries và concurrency regression; fixture
  rollback/cleanup sạch. Đây là native PG17/auth stubs có nhãn, không cloud/JWT.
  Server test do coordinator khởi động đã được dừng sau chạy; không reset DB.
- `dart format` hai Dart files thay đổi: PASS.
- `flutter analyze --no-pub`: No issues found.
- `flutter test --no-pub --concurrency=1 --reporter expanded`: **505 PASS,
  4 opt-in live skipped**. Bao gồm ba denial-clear cases bổ sung và toàn bộ
  compatibility suite outbound/pickup/redelivery/COD/router hiện có.
- `git diff --check`: exit 0, chỉ cảnh báo LF/CRLF.
- Review độc lập xác nhận không còn finding P09.1 sau sửa epoch handoff và
  stale snapshot. Không có thay đổi migration cần deploy.

RPC đọc đã có bằng chứng live từ lượt trước; P09.1 không deploy backend và
không gọi lại live để giả chứng minh thay đổi không có ở SQL. Không tuyên bố
realtime sẽ tự phát hiện đổi assignment ngay khi chưa có fetch/session event:
mọi fetch/refresh/action đều phải kiểm tra lại; sau denial dữ liệu cũ bị xóa.

Không còn blocker cho read-safe destination trong scope P09.1. Notes là
unavailable schema được ghi rõ, không phải tích hợp notes đầy đủ đã có backend.
