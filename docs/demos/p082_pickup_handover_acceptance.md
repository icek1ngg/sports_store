# P08.2 bổ sung — RPC bàn giao pickup và nghiệm thu

Người dùng yêu cầu hoàn thiện RPC và nghiệm thu sau khi xác nhận đây là phần
shipper MH11 của Minh Đức. Phạm vi: shipper báo đã bàn giao đủ hàng thu hồi cho
cửa hàng; **không manager receipt, inspection, restock, refund hoặc redelivery**.

## API và schema

Migration tạo bằng CLI 2.122.0:
`20261028011128_return_pickup_store_handover.sql`.

- `report_return_pickup_handover(p_task_id uuid,p_request_id uuid,p_items jsonb)`:
  shipper hiện được gán và thực giữ hàng; p_items là exact-full array UUID
  `return_item_id`/quantity int32 dương tăng theo UUID, giống collect.
- `get_my_return_pickup_handover(p_task_id uuid)`:
  marker đọc hẹp `{task_id,reported,reported_at}`; không contact, giá, bank,
  evidence hoặc nguyên request. Kiểm tra lại actor/assignment/custody mỗi fetch.
- ACK report: task_id/order_id/return_request_id, operation
  `report_return_pickup_handover`, task_status `in_transit`, return_status
  `returning_to_store`, reported_at=occurred_at server, event_id/request_id.

RPC mới riêng cho pickup, không đổi chữ ký/owner hoặc dispatch của outbound
`report_store_handover`. Ledger P08.1 actor/request thêm operation handover;
same key/payload replay, khác operation/target/payload conflict. Bảng private
`return_pickup_handover_reports` append-only/RLS FORCE, unique request và task;
key mới sau report bị STATE_CONFLICT, không tạo event/notification thứ hai.

Reuse role writer P08.1 NOLOGIN/NOBYPASSRLS, search_path rỗng, chỉ authenticated
EXECUTE và role shipper server-managed mới gọi được. Không grant base-table read
cho client. Thêm SELECT(reason) cho writer nội bộ để kiểm tra event notification;
không cấp quyền đọc business_events cho shipper.

Khóa request namespace P08.1 → order advisory chung → order → request → tasks
theo UUID → return_items theo UUID. Snapshot/custody immutable không cấp UPDATE
chỉ để khóa. Đối chiếu task/request/order/holder, accepted_at=started_at từ
custody, exact snapshot và quantity_collected=quantity_to_collect trước ghi.
Report mới chỉ task in_transit/request returning_to_store/order delivered,
completed_at null. Same-key replay vẫn reauthorize custody, không bắt buộc giữ
trạng thái tạm thời khi manager receipt tương lai đã xảy ra.

Transaction chỉ ghi report, idempotency ACK, event `return_pickup_handover_reported`
và notification chung cho store-owner manager hiện tại. Không đổi trạng thái,
số lần outbound, inventory, COD, receipt/inspection hoặc refund. Deep link chỉ
task UUID, không đưa item/địa chỉ/lý do cá nhân vào inbox/URL.

## Kiểm thử và giới hạn

Production SQL suite P08.1 thêm tests handover: exact-full, wrong shipper/manager,
marker tối thiểu, same-key replay, new-key conflict, payload mismatch, rollback
lỗi notification, one-event/owner notification và task/request/stock/COD giữ
nguyên. Multi-connection suite kiểm hai report cùng key chỉ một báo cáo.

Đã kiểm chứng backend:

- `node supabase/tests/run_return_pickup_production.mjs p011_pickup_handover_c`:
  21 migrations, pickup SQL PASS/ROLLBACK, handover race exactly once PASS.
- `node supabase/tests/run_delivery_read_fixture.mjs p011_pickup_handover_regression_a`:
  21 migrations, 15 SQL suites, 8 concurrency groups PASS, cleanup sạch cả
  ledger handover mới.
- CLI 2.122.0 `migration list --linked`: chỉ thiếu migration handover trước deploy.
- `db push --linked --dry-run`: chỉ một migration nêu trên.
- `db push --linked --yes`: SUCCESS trên project `bqoyfytmrtvjwrpshuhh`.
- `db query --linked --file supabase/tests/return_pickup_production.sql`:
  cloud PASS/ROLLBACK. Không seed/reset cloud hoặc sửa migration history bằng tay.

Review độc lập đã kiểm tra restricted owner/RLS/ACL/locking/proof/replay và sửa
regression permission ở policy notification (SELECT reason chỉ role nội bộ).
45 tests pickup repository/ViewModel/widget PASS, gồm marker retry không gửi
write mới, late response sau account switch, collect → handover trên cùng màn,
exact-full dialog, chống double submit và ACK/marker strict DTO.

Manifest bổ sung: migration handover; SQL/concurrency suite pickup + sharedrunner;
`return_pickup_handover_dto.dart`, pickup domain/repository/VM/widget/tests;
`supabase/tests/run_live_pickup_handover.mjs` và
`test/live/live_pickup_handover_ui_test.dart`; bốn shared contract docs và tài
liệu P08.2. Không router/theme/client/dependency mới. Giữ source P08.1/P08.2 chưa
commit và `outputs/` ngoài phạm vi.

## Nghiệm thu cuối ngày 28/10/2026

- `node supabase/tests/run_live_pickup_handover.mjs --live`: PASS bằng JWT thật;
  shipper khác/manager bị từ chối, collect exact-full, marker hẹp, report,
  concurrent replay và new-key conflict; fixture của lượt chạy được cleanup.
- `node supabase/tests/run_live_pickup_handover.mjs --live --ui` với
  `GODEBUG=http2client=0`: **PASS, exit 0**. Flutter MH11 dùng Auth và RPC thật:
  mở task assigned → xác nhận thu đủ → đọc lại in_transit/marker false → xác
  nhận báo bàn giao → marker true và wording chờ cửa hàng nhận/kiểm tra.
  Kiểm tra API tiếp theo chỉ một report/event và một notification mỗi manager;
  retry đồng thời không đổi ACK, task/request/stock/COD giữ nguyên. Cleanup PASS.
- `flutter test --no-pub test/features/deliveries/return_pickup_repository_test.dart
  test/features/deliveries/return_pickup_production_test.dart
  test/features/deliveries/return_pickup_widget_test.dart --reporter expanded`:
  **45 PASS**.
- `flutter analyze --no-pub`: **No issues found**.
- `flutter test --no-pub --concurrency=1 --reporter expanded`: **465 PASS,
  3 opt-in live skipped**; live handover đã chạy riêng thành công ở lệnh trên.
- `git diff --check`: exit 0; chỉ cảnh báo line endings LF/CRLF.
- Kiểm tra cloud sau cleanup: fixture Auth users/category prefix LIVE-P082 = 0,
  disabled user triggers trên private pickup ledgers = 0, migration count = 21.
  Một lượt harness cũ dừng trước assignment còn fixture đã được đối chiếu đúng
  run UUID và dọn riêng; không xóa dữ liệu nghiệp vụ ngoài các lượt nghiệm thu.

Nghiệm thu live phát hiện lỗi dispatch Dart ở capability marker: extension và
provider tear-off qua static repository interface tự gọi extension thay vì
instance method. Đã cast tường minh sang reader interface và thêm test đi qua
provider production + interface extension với adapter HTTP. Review độc lập
không còn finding; lần chạy UI cuối đã xác minh bản sửa. Lỗi cuộn của harness
cũng được sửa bằng chờ layout/scroll hoàn tất và kiểm tra hit-test trước tap.

Đây là nghiệm thu widget MH11 kết nối Supabase thật, không phải bằng chứng đã
chạy trên điện thoại vật lý. Kế hoạch approval và dữ liệu order/catalog được
seed có nhãn fixture; collect/handover thực sự đi qua RPC production.
Phần shipper collect/fail/handover trong P08.2 đã có implementation production;
không coi đó là nghiệm thu toàn bộ chuỗi MH15 → manager receipt.

Manager `receive_customer_return` và approval UI MH15 của Sơn vẫn riêng; fixture
approved plan trong nghiệm thu không phải bằng chứng API approval đã có.
