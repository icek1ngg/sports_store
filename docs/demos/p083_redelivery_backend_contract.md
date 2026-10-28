# P08.3 — Backend giao lại miễn phí: contract và fixture cô lập

**Lịch sử trước khi người dùng giao bổ sung primitive:** phần fixture-only dưới
đây giữ làm bằng chứng mốc cũ. Backend hiện tại đã có production migration và
RPC receipt/inspection/redelivery theo user approval tiếp theo; xem
[implementation và nghiệm thu mới](p083_production_redelivery.md). Runner
contract fixture pin baseline 21 migrations, không đo trạng thái production mới.

## Trạng thái và căn cứ

Ngày 28/10/2026 người dùng chốt D9: thất bại dùng task và return request
`manager_action_required`; thành công từ task `in_transit` và request
`awaiting_redelivery` sang task `delivered`, request `rejected_after_inspection`
và `closed_at`. Người dùng yêu cầu **giữ chặn khi thiếu proof**, chỉ xây
interface/fixture có nhãn khi dependency Sơn chưa có. Đây là quyết định người
dùng, không phải bằng chứng Sơn đã duyệt/tích hợp contract.

**P08.3 chưa hoàn tất production/live.** Không thêm migration, public RPC,
grants/RLS, Flutter runtime hoặc màn P08.4. File SQL fixture chỉ chạy trong
database native PG17 cô lập, transaction rollback, không được deploy Supabase.
Fixture không thay thế implementation, kiểm thử RLS/Auth hoặc concurrency thật.

Đã đọc `AGENTS.md`, `docs/minh_duc_implementation_plan.md`, bốn shared contract
docs, schema/access migrations và các migration giao nhận hiện có. Kiểm tra
độc lập xác nhận:

- `lib/features/returns` chỉ có `.gitkeep`; chưa có API manager receipt,
  inspection hoặc kết luận từ chối sau kiểm tra của Sơn.
- Schema nền có `inspection_started_at`, `inspected_at`, `inspected_by`,
  `closed_at`, `quantity_collected`, `sellable_quantity`, `damaged_quantity`.
  Các cột/status không chứng minh receipt hay inspection transaction đã chạy.
- P08.1/P08.2 có immutable pickup plan/custody và shipper handover report;
  report không phải manager receipt/inspection/release để giao lại.
  Pickup sau report vẫn in_transit và giữ active-return slot; Sơn phải hoàn tất
  receipt hợp lệ trước khi tạo task redelivery, không hủy task pickup để lách
  unique index hoặc tự suy manager đã nhận hàng.
- Các accept/start/fail/complete outbound và collect/fail pickup hiện hữu không
  hỗ trợ redelivery. Projection redelivery vẫn `unavailable_redelivery_plan`,
  items rỗng. Không lấy toàn bộ `order_items` làm hàng giao lại.

Kiểm tra catalog cloud read-only ngày 28/10/2026 trên project đang cấu hình:
không có function public/private khớp tên redelivery, inspect-return hoặc
receive-return. Không ghi dữ liệu, không seed fixture và không chạy DDL cloud
trong P08.3. Kết luận dependency thiếu dựa cả trên source/migration và kiểm tra
này; không coi tên API đề xuất trong docs là API tồn tại.

## Interface tích hợp đề xuất — chưa phải RPC hiện có

Các tên sau là **proposed**, chỉ được chuyển thành migration khi dependency
receipt/inspection/plan/custody có contract và writer thật. Không có endpoint
production để client hoặc MH15 gọi trong thay đổi này.

| Operation đề xuất | Input client | Caller và server precondition | Output tối thiểu và kết quả |
| --- | --- | --- | --- |
| `assign_redelivery_task` | `return_request_id uuid`, `shipper_id uuid`, `request_id uuid` | Manager hiện tại; cùng order/customer/request; order delivered; kết luận từ chối sau inspection hợp lệ; receipt/inspection release + item plan bất biến; không task return active hoặc custody chưa giải quyết | Task UUID/order/request, kind redelivery, assigned shipper, assigned status, amount 0, attempt_number 1, server time/event/request UUID; không COD mới |
| `complete_redelivery` | `task_id uuid`, `request_id uuid`, `received_all_items boolean` | Current assigned shipper; task in_transit, R awaiting_redelivery, đủ custody exact plan và start proof; received_all_items=true | T delivered/completed_at, R rejected_after_inspection/closed_at cùng transaction; outcome event/request UUID; không ghi delivery_attempts, tiền hoặc inventory |
| `fail_redelivery_task` | `task_id uuid`, `request_id uuid`, `reason_code text`, `description text?` | Cùng quyền/custody/state như complete; lý do unreachable/reschedule/bad_address/refusal/other, other cần mô tả | T/R manager_action_required, reason/server time/event/request UUID; completed_at và closed_at vẫn null, custody giữ nguyên; chờ chủ cửa hàng |

Không nhận order total, tiền hoặc shipper identity từ client cho các outcome.
Assign được phép nhận shipper mục tiêu nhưng phải kiểm tra profile role server.
Hàng/quantity/destination phải lấy từ proof/snapshot server, không nhận payload
tùy ý từ client để sửa task hoặc dữ liệu return/refund.

Accept/start vật lý cho redelivery cần contract custody riêng: assignment không
chứng minh shipper đã nhận; accepted_at rồi started_at/in_transit chỉ sau thực
nhận đủ kế hoạch. Không mở rộng accept/start outbound bằng suy đoán. Fixture
có bước vận chuyển có nhãn để kiểm thử outcome, không phải API accept/start.

### Interface Sơn phải cung cấp

Một immutable release proof cần liên kết cùng order/request, pickup receipt và
inspection event UUID; manager actor, thời gian server; outcome rejected sau
inspection, version và item plan hàng thực tế trả lại. Mỗi item có UUID nguồn
return item, tên/variant snapshot và quantity dương đã được manager nhận/cho
phép giao lại. Không suy từ quality counters hoặc đọc evidence/bank cho shipper.
Proof ghi trong transaction receipt/inspection của owner, không thể do shipper
hoặc manager client tự khai JSON thay cho nghiệp vụ server.

Wrapper Sơn phải khóa order → return request → tasks UUID → items UUID, ghi
kết luận/plan và chuyển request sang awaiting_redelivery trong cùng transaction
với việc cho phép tạo task. Cách lưu proof/version và điểm gọi internal routine
còn cần Sơn chốt. Fixture dùng bản ghi giả lập có nhãn; không cấp writer này
cho authenticated và không đưa fixture vào migrations/app.

### Tính nguyên tử, retry và lỗi dự kiến

Các write phải khóa namespace actor/request, rồi order advisory chung với
delivery/COD → order → return request → tasks UUID → items UUID; kiểm tra lại
role/assignment/relationship/proof trước replay. Unique active-return index
hiện bao gồm manager_action_required: failure không tự giải phóng slot để tạo
task mới. Không tự quyết định manager retry, chuyển custody hoặc đóng task cũ.

Ledger riêng unique actor/request lưu operation/target/normalized payload và
ACK server. Same key/same payload trả ACK cũ sau reauthorization; khác payload,
target hoặc operation từ chối. Key mới vẫn phải qua state/unique checks. Complete
và fail khóa cùng aggregate để chỉ một outcome thắng. Event/notification cùng
transaction; lỗi muộn rollback cả task/request/ledger/event. Không retry như
operation mới sau timeout; đọc lại hoặc replay đúng key/payload đã gửi.

Lỗi dự kiến: AUTH_REQUIRED, PERMISSION_DENIED, NOT_FOUND_OR_FORBIDDEN,
INVALID_ARGUMENT, INVALID_SHIPPER, STATE_CONFLICT, ITEMS_MISMATCH,
CUSTODY_UNRESOLVED, DEPENDENCY_NOT_READY, IDEMPOTENCY_CONFLICT. Wire SQLSTATE,
ACK schema chính xác và notification recipients/event taxonomy vẫn phải chốt
trước implementation production. Không trình bày các marker này là API đã có.

## Transition được chốt và giới hạn

| Bước | Precondition | Transition/side effect | Còn chặn |
| --- | --- | --- | --- |
| Tạo/phân công | Manager, rejected-inspection proof, actual plan, store custody | Task assigned, kind redelivery, amount 0, attempt 1 | Sơn receipt/inspection/release proof và wrapper chưa có |
| Thực nhận/start | Assigned shipper nhận đủ actual plan | Accepted → in_transit; không xuất tồn hoặc outbound count | Custody/accept/start primitive redelivery chưa có |
| Thành công | T in_transit, R awaiting_redelivery, đủ hàng=true | Delivered + rejected_after_inspection/closed_at nguyên tử | Production writer phụ thuộc proof/custody trên |
| Thất bại | Cùng active transport và reason hợp lệ | T/R manager_action_required, giữ custody/open | Manager resolution/receipt/retry sau thất bại chưa chốt |

Order vẫn delivered; COD obligation cũ giữ nguyên ngay cả đang collected chưa
received. Amount task luôn 0, không COD row mới, outbound count/attempts giữ
nguyên. Không áp trần hai lần outbound lên redelivery; cũng không tự tạo lần
giao lại tiếp theo. Hàng không tự thành sellable, không restock/refund.

## Files và kiểm chứng

- `supabase/tests/fixtures/p083_redelivery.sql.fixture`: interface giả lập cô
  lập, không public RPC hoặc migration.
- `supabase/tests/redelivery_contract_fixture.sql`: kiểm thử hợp đồng bằng
  fixture receipt/inspection/plan có nhãn; cuối transaction rollback.
- `supabase/tests/run_redelivery_contract_fixture.mjs`: chỉ loopback native PG17
  với data_directory workspace, database mới prefix p011_p083_; không reset/drop
  database hoặc kết nối cloud; kiểm tra không thêm public function sau rollback.
- Bốn shared docs cập nhật D9 và tình trạng blocked; giữ nguyên thay đổi P08.1/
  P08.2 chưa commit. Không sửa router/theme/client/dependencies hoặc `outputs/`.

## Kiểm chứng ngày 28/10/2026

Điều kiện chạy: native PostgreSQL 17 trong runtime ignored
`supabase/.temp/p011_pg_runtime`, data_directory `supabase/.temp/p011_native_data`,
loopback 127.0.0.1:55439 đã sẵn sàng (`node supabase/tests/probe_local_fixture_ready.mjs`).
Runner từ chối server hoặc database name khác phạm vi này, không tải runtime
hoặc sử dụng credential cloud. Database test mới được giữ lại, các fixture
table/function/business rows được rollback; không drop/reset database.

| Lệnh | Kết quả thực chạy |
| --- | --- |
| `node --check supabase/tests/run_redelivery_contract_fixture.mjs` | PASS |
| `node supabase/tests/run_redelivery_contract_fixture.mjs production_db` | Exit 1 như mong đợi: tên DB sai prefix bị từ chối trước connect |
| `node supabase/tests/run_redelivery_contract_fixture.mjs p011_p083_worker_item` | Worker: PASS, 21 migrations, suite ROLLBACK |
| `node supabase/tests/run_redelivery_contract_fixture.mjs p011_p083_final_codfull_20261028` | Coordinator chạy độc lập sau sửa review: PASS, 21 migrations, suite ROLLBACK, public API/business counts không đổi, không còn p083_fixture schema |
| `flutter analyze --no-pub` | No issues found |
| `git diff --check` | Exit 0, chỉ cảnh báo LF/CRLF của working tree có sẵn |

Suite gồm proof thiếu/sai số lượng/khác request, actor/state/relationship không
hợp lệ, tạo task miễn phí, exact custody, full completion, failure còn mở,
reason validation, replay/mismatch/opposite outcome và lỗi muộn rollback.
Fixture COD cũ là **collected đủ 210.000 VND, chưa received**; snapshot tiền,
collector/timestamp/status và toàn bộ COD row (`to_jsonb`) giữ nguyên sau success/failure, không chỉ kiểm tra
uncollected=0. Đây là dữ liệu fixture, không phải giao hàng outbound thật.
Environment guard cũng được kiểm bằng savepoint tắt fixture_mode: bị từ chối.
Public proposed RPC names phải vắng mặt ngay sau áp dụng migrations và sau test.

Review độc lập đã yêu cầu bổ sung order delivered/customer relationship,
reason allowlist/Other description, COD collected và kiểm tra đúng proposed RPC
names; các sửa này nằm trong lần chạy cuối. Không đổi Dart/dependencies nên
không có Dart file P08.3 để format hoặc widget flow mới để kiểm thử.
Review lại độc lập đã xác nhận không còn finding P08.3. Native test server do
coordinator khởi động đã được dừng sau kiểm tra; không để fixture service chạy nền.

**Chưa deploy, chưa live và chưa đạt acceptance production P08.3.** Tiếp tục
cần Sơn cung cấp receipt/inspection/release plan và custody primitive được chốt;
notification/wire ACK/manager resolution còn ở trạng thái proposed. Không coi
fixture PASS là kiểm thử RLS/Auth/concurrency hoặc nghiệm thu RPC production.
