# P07.4 — Báo bàn giao cửa hàng và sự cố outbound

Ngày 27/10/2026. **Backend outbound đã hoàn tất và deploy** project
`bqoyfytmrtvjwrpshuhh`. Phạm vi người dùng chốt: **outbound trước**. Pickup/redelivery
phải bị từ chối rõ đến khi có contract custody/quantity của Sơn; không coi
timestamps hoặc assignment là proof nhận hàng. Không sửa UI/flows của teammate.
Mốc này thay những blocker P04/P07.1/P07.2 đã lỗi thời trong boundary P07.4,
không tuyên bố owner khác đã duyệt.

## State và tác dụng được chốt

| Report | Actor / tiền điều kiện | Tác dụng |
| --- | --- | --- |
| Bàn giao toàn bộ | Shipper hiện được gán và holder thật; order awaiting_store_return; task failed hoặc task2 cancelled do hoàn sớm | Ghi report/item snapshot/giờ server/event, thông báo chủ cửa hàng. Không đổi task/order/custody thành manager receipt |
| Sự cố | Cùng current assignee/holder sau nhận hàng; accepted/in_transit/failed hoặc task2 cancelled chờ hoàn | Ghi actor/task/type/reason/request/time/event và thông báo chủ cửa hàng; không ghi ordinary failed attempt |

Task2 cancelled khi còn assigned chưa có custody riêng không được coi là đã
thực nhận lần hai; server phải xác minh holder/dispatch/custody task1 vẫn còn
nguyên. Task2 đã accepted giữ receipt riêng và phải khớp holder/proof.

Mã sự cố theo enum thật: damaged/lost/other. Reason không chỉ whitespace.
Hỏng nhưng còn đủ số lượng có thể báo bàn giao; có report mất hàng thì không
thể xác nhận bàn giao toàn bộ cho đến khi có hợp đồng xử lý của manager.
Không tính bồi thường, restock, receipt/inspection hoặc tự kết thúc order.

Bàn giao chỉ một report/order trong đợt hoàn outbound; key khác sau report
đầu trả conflict. Incident cho phép nhiều report khác nhau; cùng actor/key/
payload chỉ tạo một lần, đổi payload/operation/target bị từ chối. Report bàn
giao không đóng quyền báo sự cố: nếu holder/state còn hợp lệ thì incident
sau report vẫn được ghi. Manager nhận/kiểm tra thật là thao tác riêng.

## API

- `report_store_handover(p_task_id uuid,p_request_id uuid,p_items jsonb) → jsonb`.
  Items là array không rỗng, mỗi object đúng hai field order_item_id UUID và
  quantity integer dương trong miền int32; không duplicate/extra keys.
  Array theo thứ tự order_item_id UUID tăng dần; phải khớp đầy đủ số lượng
  snapshot server. Không gửi giá, trạng thái chất lượng hoặc receipt manager.
- `report_delivery_incident(p_task_id uuid,p_request_id uuid,
  p_incident_kind delivery_incident_kind,p_reason text) → jsonb`.
  Kind dùng enum damaged/lost/other, reason trim whitespace và bắt buộc nonblank.
  Không nhận actor/time/amount/count/status client.

ACK an toàn gồm task_id/order_id, operation chính xác tên RPC, request_id,
event_id, reported_at, task_status/order_status hiện lúc report. Không trả
snapshot product/recipient/bank/refund; ACK không phải state transition.

| SQLSTATE / marker | Điều kiện |
| --- | --- |
| 42501 / AUTH_REQUIRED | Thiếu identity |
| 42501 / PERMISSION_DENIED | Profile không còn shipper |
| 42501 / NOT_FOUND_OR_FORBIDDEN | Task khác assignee hoặc không tồn tại, không lộ khác biệt |
| 22023 / INVALID_ARGUMENT | Thiếu ID/reason/kind hoặc items sai shape/extra/duplicate/order/integer |
| PT409 / UNSUPPORTED_TASK_KIND | Pickup/redelivery chưa có contract |
| PT409 / STATE_CONFLICT | Task/order không trong state report hoặc handover đã có |
| PT409 / CUSTODY_UNRESOLVED | Proof/holder thiếu hoặc full handover sau lost |
| PT409 / ITEMS_MISMATCH | Items/quantity khác snapshot/dispatch proof |
| PT409 / IDEMPOTENCY_CONFLICT | Cùng actor/key khác target/payload/operation |

Input enum/UUID không cast được bị PostgreSQL/PostgREST từ chối trước RPC;
không có fallback success. Không tự giới hạn reason theo một policy mới.

## Schema, quyền và transaction

CLI-created migration `20261027093919_report_delivery_handover_incidents.sql`
thêm private.outbound_reporting_requests PK actor/key với exact canonical
payload/hash/ACK, và private.outbound_handover_reports PK order. Incident nằm
trong business_events hiện có; không dựng lại bảng delivery_incidents đã bỏ.
Ledgers force RLS/append-only, client không SELECT/INSERT/UPDATE/DELETE.

Hai public wrappers SECURITY DEFINER owner là internal NOLOGIN/NOINHERIT/
NOBYPASSRLS reporting writer, search_path rỗng, EXECUTE chỉ authenticated.
Helper private SECURITY INVOKER, client không EXECUTE. Identity dùng bridge
đã có, không grant schema Auth. Chỉ đọc đúng columns cần proof, khóa rows bằng
UPDATE(id/order_id) lock-only với WITH CHECK(false); không UPDATE nghiệp vụ.

Shared actor/request advisory → profile recheck → order advisory/row → tất cả
outbound tasks theo UUID → COD. Cùng thứ tự business locks với completion/
failure/retry/start. Trước replay kiểm tra current profile/assignment và
holder từ original dispatch/custody; replay trả ACK cũ, không tạo event mới.
Đổi key cho cùng handover bị unique order/state conflict; incident nhiều key
được ghi riêng. Hai actor cùng client UUID độc lập vì event token do server sinh.

Historical proof helper đối chiếu dispatch/items/inventory movements bất biến
như P04, nhưng bỏ điều kiện chặn mọi damaged/lost để nhận thêm incident reports.
Full handover kiểm tra lost riêng. Không sửa helper P04: damaged/lost commit
trước completion tiếp tục khiến completion bị chặn; completion thắng trước
thì incident mới bị từ chối vì delivered. Other report không tự khóa vận chuyển.

Task failed1 sau manager tạo/hủy task2 không được dùng để bỏ qua context task2;
report dùng task2 cancelled đang chờ hoàn và giữ đúng proof holder gốc. Task2
assigned-cancel không tự có receipt2; accepted-cancel đối chiếu receipt2 đã giữ.

Event handover: reason=store_handover_reported, incident_kind NULL; event
incident: reason mô tả và incident_kind enum. Cả hai from_state/to_state NULL,
subject delivery_task, UUID task, actor/time server; business_events.request_id
= server event UUID. Notification title/body chung cho profiles role manager
(chủ cửa hàng), không khách/shipper hoặc mô tả sự cố/PII. Event, notification,
report/ledger cùng transaction; bất kỳ lỗi muộn đều rollback toàn bộ.

## Kiểm thử và deploy

- `node supabase/tests/run_delivery_reporting_production.mjs`:
  PASS SQL/ROLLBACK và race thật; native PG17.10,
  DB `p011_p074_production_1793108953667`.
- `node supabase/tests/run_delivery_read_fixture.mjs p011_p074_regression_20261027_final`:
  **18 migrations, 14 SQL suites PASS/ROLLBACK, 7 nhóm concurrency PASS**.
  Bao gồm role/UUID/kind/state/custody, full/partial/duplicate/fake items,
  assigned và accepted task2 cancelled, multiple incidents sau damaged/handover,
  lost chặn full claim ở task đang đủ state hoàn, exact retry/mismatch/cross-op,
  hai actor cùng UUID, event/manager-only notification, late-fault rollback và
  full-row order/task/COD/stock/results/return_items snapshots không đổi.
  Concurrency hai connection: handover/incident replay, key khác conflict,
  incident-first/completion-first chỉ kết quả hợp lệ thắng. Dữ liệu mở đầu là
  fixture; assign/accept/start/fail/manager-return/report đều gọi RPC thật.
- `npx --offline --yes supabase@2.122.0 db push --linked --dry-run --skip-vault`:
  chỉ pending migration P07.4.
- `npx --offline --yes supabase@2.122.0 db push --linked --yes --skip-vault`:
  **PASS**, migration đã áp dụng project cấu hình.
- `npx --offline --yes supabase@2.122.0 db query --linked --file supabase/tests/delivery_reporting_production.sql`:
  **PASS/ROLLBACK** cloud.
- Cùng lệnh query với `outbound_completion_production.sql`: **PASS/ROLLBACK**.
- `npx --offline --yes supabase@2.122.0 migration list --linked`:
  **18 local=18 remote**.
- `flutter analyze --no-pub`: No issues found.
- `flutter test --no-pub --reporter expanded`: **390 PASS, 2 opt-in live skipped**.
- `node --check` reporting runner/concurrency/shared runner, `git diff --check`:
  PASS, chỉ Git LF/CRLF warnings. Không Dart/dependency mới để format/pub get.
- `npx --offline --yes supabase@2.122.0 db advisors --linked --type security --level error --fail-on error`:
  exit0, No issues found. Các warnings public authenticated SECURITY DEFINER
  vẫn phải được review theo role/ACL/RLS, không có nghĩa caller được bypass
  quyền: [advisory](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

Các lỗi test ban đầu (syntax/UUID, seed order chưa preparing, sai claims,
temp ACL, snapshot timing và FK cleanup order) đã sửa rồi chạy lại full suite.
Không nới RLS/grant client để ép PASS. Reviewer phát hiện kỳ vọng notification
customer bị nhầm owner; sửa thành store manager trước deploy. Agent review
chạm quota trước final review, coordinator hoàn thiện và rà soát còn lại;
không tuyên bố có final independent approval. CLI migration-list chạy song
song advisors bị kẹt login role; dừng đúng process và chạy tuần tự đạt.

Cloud cleanup xác minh Auth/orders fixture0745=0, reporting requests=0,
handover reports=0; ba products có sẵn giữ nguyên. Native final runner cleanup
sạch, server đã dừng sau nghiệm thu; giữ DB audit, không reset/drop.

## Manifest và giới hạn

Mới: migration trên; tests delivery_reporting_production.sql,
delivery_reporting_production_concurrency.mjs, run_delivery_reporting_production.mjs;
tài liệu này. Shared regression runner thay fixture boundary P07.4 bằng
production suite/race; bốn contract docs cập nhật nối tiếp. Không đổi runtime
Flutter/router/theme/client/dependencies, không RPC receipt/inspection mới.

**Hoàn tất backend outbound P07.4 và deploy, không coi toàn bộ ba kinds đã
hoàn tất.** Pickup/redelivery live vẫn bị chặn D8/D9/custody của Sơn. UI báo
bàn giao/sự cố chưa nối ở lượt backend này; MH17 renderer của Bảo chưa nghiệm
thu. Cloud SQL dùng claims trong transaction, chưa app/JWT thật/điện thoại.

Hai integration boundary cần tiếp tục phối hợp: manager resolution sau damaged/
lost (P04/P05/P07.2 hiện fail-closed, không tự sửa report để đi tiếp), và nguồn
item snapshot có quyền cho UI handover vì failed-task projection đang restricted.
Không mở general order/item reads cho shipper hoặc trả PII trong ACK để đi vòng.
Manager receipt/inspection/restock/compensation hoàn toàn riêng. Chưa commit/push;
giữ nguyên các thay đổi phase trước và outputs không liên quan.
