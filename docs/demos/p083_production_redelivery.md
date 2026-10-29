# P08.3/P08.4 — Receipt, inspection release và giao lại miễn phí production

## Quyết định và phạm vi

Người dùng ngày 28/10/2026 giao bổ sung primitive backend còn thiếu và hoàn
thiện phần Minh Đức. User chốt manager nhận đủ pickup sau handover →
under_inspection; kết luận từ chối có lý do, giao lại toàn bộ hàng thực nhận;
shipper thực nhận và start riêng; D9 failure T/R manager_action_required giữ
custody/open, success mới đóng rejected_after_inspection. Không tự restock,
refund, COD mới hoặc outbound attempt. Không tuyên bố Sơn đã tích hợp MH15.

Migration `20261028062908_p083_redelivery_production.sql` tạo bằng CLI 2.122.0,
đã deploy project đang cấu hình ngày 28/10/2026 sau kiểm tra lịch sử 21 remote
và dry-run đúng một migration. Source fixture P08.3 ban đầu vẫn giữ như lịch sử,
runner fixture pin baseline 21 migrations; không phải backend hiện tại.

## API hiện có trong migration mới

Mọi UUID/quantity do server đối chiếu, caller từ auth bridge + profiles.role.
Client không thể tự khai shipper identity, giá, COD hoặc kết quả inspection
thay cho operation manager. Mọi write có request_id UUID bắt buộc.

| RPC | Input | Quyền/precondition và transaction |
| --- | --- | --- |
| `approve_return_pickup_plan` | p_return_request_id uuid, p_request_id uuid, p_items jsonb | Manager; pending_review, order delivered, exact kế hoạch return_items hiện hữu; chuyển awaiting_return_pickup, ghi decided_by/time và event. Không tạo hàng giả hoặc duyệt refund. |
| `receive_customer_return` | p_task_id uuid, p_request_id uuid, p_items jsonb | Manager; pickup in_transit, returning_to_store, full immutable custody + handover report hợp lệ; exact-full items; T returned_to_store/completed_at, R under_inspection/inspection_started_at; immutable receipt. |
| `reject_return_after_inspection` | p_return_request_id uuid, p_request_id uuid, p_reason text | Manager; under_inspection và receipt proof; reason bắt buộc; kiểm tra full quantities, chưa restock/quality disposition; snapshot toàn bộ actual received items thành release plan, R awaiting_redelivery, inspected_by/at và event; chưa closed_at. |
| `assign_redelivery_task` | p_return_request_id uuid, p_shipper_id uuid, p_request_id uuid | Manager; immutable receipt/inspection/release proof đầy đủ, order delivered, request awaiting_redelivery, không active return task/custody trái ngược; tạo assigned, amount 0/attempt 1, snapshot riêng và notification shipper. |
| `accept_redelivery_task` | p_task_id uuid, p_request_id uuid, p_items jsonb | Current shipper, assigned; exact-full immutable task plan; accepted_at, physical custody và event; chưa start. |
| `start_redelivery_task` | p_task_id uuid, p_request_id uuid | Current shipper, accepted và custody khớp; started_at/in_transit, immutable start proof; không dispatch/increment outbound. |
| `complete_redelivery` | p_task_id uuid, p_request_id uuid, p_received_all_items boolean | Current shipper, in_transit/R awaiting_redelivery, custody/start proof và received_all_items=true; atomic delivered/completed_at + rejected_after_inspection/closed_at, outcome/event/notification/ACK. |
| `fail_redelivery_task` | p_task_id uuid, p_request_id uuid, p_reason_code text, p_description text? | Cùng quyền/state/custody; unreachable/reschedule/bad_address/refusal/other, other cần mô tả; T/R manager_action_required, timestamps kết thúc null; custody giữ nguyên, outcome/event/notification; không tự tạo task mới. |

Items payload là array sorted UUID `{return_item_id,quantity}` dương exact-full,
không partial, trùng ID, item ngoài task/request hoặc extra private fields.

### ACK shipper và đọc dữ liệu

Common keys: task_id/order_id/return_request_id/operation/task_status/return_status/
event_id/request_id/occurred_at. Accept thêm kind=redelivery, amount_to_collect_vnd=0,
accepted_at và started_at=null. Start thêm kind/amount=0, accepted_at/started_at.
Complete thêm completed_at/closed_at. Fail thêm reason_code/description/failed_at/
custody_open=true. DTO kiểm exact keys/ID/timestamp/state, không biến malformed
ACK thành thành công. UI đọc lại MH11/MH10 sau ACK, không optimistic mutation.

Projection hiện hữu chỉ thêm redelivery có immutable private task plan:
item_source=return_plan, items trả UUID/name/variant/attributes/quantity actual;
quantity_collected phản ánh lượng manager đã nhận trong plan, không phải thu
COD. Legacy redelivery không proof vẫn unavailable_redelivery_plan/items rỗng.
History/restricted vẫn che recipient/item; không general orders/returns reads,
bank/videos/evidence hoặc Storage URL cho shipper.

### Quyền, khóa, idempotency

Reuse restricted writer NOLOGIN/NOINHERIT/NOBYPASSRLS; SECURITY DEFINER cần thiết
cho atomic aggregate, search_path rỗng, EXECUTE chỉ authenticated và role được
kiểm tra trong RPC. Tất cả proof tables private FORCE RLS, append-only, không
client SELECT/INSERT/UPDATE/DELETE. Reader chỉ đọc snapshot cho task được gán
hiện tại và state hợp lệ. Không mở quyền base-table cho shipper.

Ledger unique actor/request chung tám operation; normalized payload/hash và
ACK bất biến. Same key/payload replay sau reauthorization, khác target/payload/
operation → IDEMPOTENCY_CONFLICT. Key mới vẫn qua state/proof/unique checks.
Khóa request advisory → shared order advisory → order → request → tasks/items;
completion và failure cùng namespace order nên chỉ một kết quả thắng.
Không khóa FOR UPDATE append-only proof; order/request lock và advisory bảo vệ
giao dịch. Lỗi muộn rollback cả trạng thái/event/notification/ledger.

Lỗi wire: 42501 AUTH_REQUIRED/PERMISSION_DENIED/NOT_FOUND_OR_FORBIDDEN;
22023 INVALID_ARGUMENT/ITEMS_MISMATCH; PT409 STATE_CONFLICT, ITEMS_MISMATCH,
CUSTODY_UNRESOLVED, IDEMPOTENCY_CONFLICT và các proof/shipper markers kiểm theo
migration. Repository đưa lỗi typed an toàn, không in raw backend message/PII.

Notifications: assignment chỉ target shipper; outcomes current managers/store
owner và customer đơn, dedupe event/recipient. Nội dung chung, subject UUID task;
không bank/contact/inspection reason trong inbox/URL. Receipt/rejection event
được lưu riêng; không coi report shipper là manager receipt.

## Giao diện và giới hạn

MH11 dùng redelivery repository/VM/widget riêng trong feature: accept đủ hàng,
start, complete full-goods hoặc failure reason dialog; request ID giữ nguyên
sau timeout, chống tap kép và xung đột outcome; đổi tài khoản không giữ PII.
Không COD/two-attempt warnings, không shipper tự retry scheduling/restock.
Manager receipt/inspection/assignment primitives sẵn cho MH15; không thiết kế
lại UI teammate. Manager resolution sau redelivery failure là bước riêng,
không được giả hoàn tất hoặc tự đóng active task.

## Kiểm chứng

- `node supabase/tests/run_redelivery_production.mjs p011_p083_prod_o`: PASS,
  22 migrations; production RPC chain, wrong role/state/partial, exact receipts,
  success/failure/replay/mismatch/opposite outcome và late-fault rollback.
  ACL tám RPC + SET ROLE anon/authenticated denial PASS. Toàn COD row, inventory,
  outbound attempts giữ nguyên. SQL suite rollback; isolated race DB được giữ
  để chẩn đoán, không phải cloud data.
- Multi-connection suite cùng runner: completion/failure serialization + replay
  PASS. Không suy concurrency từ một transaction.
- `node supabase/tests/run_delivery_read_fixture.mjs p011_completion_regression_final`:
  PASS toàn bộ SQL/concurrency cũ với 22 migrations, cleanup sạch.
- `flutter test --no-pub --concurrency=1 --reporter expanded`: 486 PASS,
  4 live opt-in skipped; `flutter analyze --no-pub`: No issues found.
- Independent review không có deploy blocker sau bổ sung ACL/role tests.
- CLI `migration list --linked`, `db push --linked --dry-run` và
  `db push --linked --yes`: đúng một migration mới, deploy SUCCESS.

## Nghiệm thu live cuối

- `node supabase/tests/run_live_pickup_handover.mjs --live --redelivery`: PASS,
  real JWT manager approval/receipt/inspection/assign và shipper accept/start/
  free completion; wrong shipper/role denied, toàn COD 550.000 VND cũ giữ nguyên.
- `node supabase/tests/run_live_pickup_handover.mjs --live --redelivery --ui`:
  PASS, MH11 pickup collect/handover → manager primitive thật → MH18 authorized
  saved destination/read recheck → MH11 accept/start/success thực, readback server.
- `node supabase/tests/run_live_pickup_handover.mjs --live --redelivery
  --redelivery-failure --ui`: PASS, chọn Other + mô tả → manager_action_required
  trên task/request, giữ custody/open/COD/stock, một receipt/inspection/outcome,
  notification đúng owner/customer. Toàn fixture/Auth của các lượt đã cleanup.
- CLI `db advisors --linked --type security --level error --fail-on error`:
  exit 0, No issues found tại mức ERROR; không khẳng định không có WARN/INFO.
- `flutter build web --no-pub`: PASS. Build có warning font CupertinoIcons thiếu
  (không có usage trong source mới); artifact vẫn tạo thành công, không thêm
  dependency ngoài scope để che warning.
- MH18 tile HTTPS kiểm tra HTTP 200; widget tests tile outage/address fallback,
  directions adapter, session/reassignment và permission reads PASS. Platform
  launcher dùng url_launcher thật; không claim đã mở dialer/Google Maps trên
  điện thoại vật lý hoặc chạy iOS (workspace chưa có target iOS).

Live nghiệm thu đã phát hiện và sửa mapper metadata cho current redelivery
(pickup giữ strict), disposal gate và chuyển stage accept → start → outcome.
Lượt failure đầu có transient network ở read-only map recheck; harness retry đọc
tối đa ba lần chỉ với network failure. Không automatic retry write bằng key mới.
Các lượt cuối PASS và cleanup; không bỏ assertions hoặc fake result để đạt.

Backend/frontend của nhánh được user chốt đã production và nghiệm thu. UI MH15
Sơn, refund/restock hay manager resolution mới sau redelivery failure không được
tự suy là hoàn tất. Không claim điện thoại vật lý hoặc toàn bộ 20 màn đã chạy.
