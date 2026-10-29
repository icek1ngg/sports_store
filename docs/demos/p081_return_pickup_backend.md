# P08.1 — Backend thu hồi hàng tại khách

## Quyết định người dùng và ranh giới tích hợp

Ngày 27/10/2026 người dùng chốt D8 trong phạm vi này:

- Chỉ tạo/phân công pickup từ request đã `awaiting_return_pickup`, với kế hoạch
  `return_items` được manager duyệt. Không duyệt request/hoàn tiền ở API giao nhận.
- Thu **đủ đúng toàn bộ** item/số lượng kế hoạch; thiếu, thừa, sai hoặc một phần
  bị từ chối, không ghi custody một phần. Hàng ngoài kế hoạch phải được Sơn xử lý
  ở bước duyệt trước, không dùng toàn bộ order_items thay cho hàng thực tế.
- `collect_return_items` ghi thực nhận tại khách, gộp accepted/start:
  task `assigned → in_transit`, request `→ returning_to_store`; không store receipt.
- Thất bại chỉ trước nhận; task `→ failed`, request giữ `awaiting_return_pickup`,
  thông báo chủ cửa hàng; manager được tạo task mới, không trần hai lần outbound.
- Chỉ đổi shipper trước nhận. Không chuyển custody sau nhận.

Đây là quyết định trực tiếp của người dùng, không tuyên bố Sơn/Bảo/Văn Đức đã
review hoặc triển khai API. Tại lúc bắt đầu phase, `lib/features/returns` chưa có
runtime source và repository chưa có RPC duyệt return-plan hay
`receive_customer_return`. Những tên này không được trình bày là endpoint có sẵn.

## Bảng chuyển trạng thái

| Hành động | Actor, tiền điều kiện | Transition / side effects | Không thực hiện |
| --- | --- | --- | --- |
| Tạo/phân công pickup | Manager server role; request/order cùng đơn đã delivered; kế hoạch đã duyệt, không custody/task return active xung đột | Task assigned, attempt_number=1, amount=0; snapshot điểm khách và item kế hoạch | Không approval/refund, không nhận hàng |
| Đổi shipper | Manager, expected task/shipper đúng, task chưa nhận | Assignment mới, snapshot giữ nguyên; đọc lại quyền mỗi fetch | Không custody transfer |
| Thực nhận tại khách | Current assigned shipper; task/request/order khớp; input đủ đúng snapshot kế hoạch | accepted_at=started_at server; task in_transit, request returning_to_store; immutable custody/event | Không delivery_attempts/count outbound, stock/COD/refund/inspection |
| Lấy thất bại | Current shipper, assigned chưa custody; reason hợp lệ | Task failed, server completed_at/reason, request còn awaiting_return_pickup; event/manager notification | Không phát sinh custody hoặc giới hạn hai lần |
| Shipper báo bàn giao | API riêng cần custody pickup contract | Chỉ report; không phải store receipt | Không triển khai bởi P08.1 |
| Chủ cửa hàng nhận/kiểm tra | API `receive_customer_return` thuộc Sơn, chưa có | Phải phối hợp khóa/custody trong transaction server riêng | P08.1 không đổi task returned_to_store/request under_inspection |

## Kết quả triển khai và kiểm chứng

Đã triển khai ba RPC, kiểm chứng local và **deploy cloud thành công sau khi bật
VPN ngày 28/10/2026**; chưa nghiệm thu ứng dụng bằng JWT thật. Live ordering → approved return plan vẫn cần upstream
MH15 của Sơn; test fixtures chỉ cung cấp đầu vào đã duyệt, không runtime fallback.

Kiểm chứng cuối ngày 28/10/2026:

| Lệnh | Kết quả |
| --- | --- |
| `node supabase/tests/run_return_pickup_production.mjs p011_p081_final_20261028_c` | PASS: 20 migrations, production SQL PASS/ROLLBACK và race assignment/plan insert, idempotent assignment, CAS reassignment, collect/fail |
| `node supabase/tests/run_delivery_read_fixture.mjs p011_p081_regression_20261028_verified` | PASS: 20 migrations, 15 SQL suites, 8 concurrency groups; fixture cleanup sạch, không còn năm ledgers pickup |
| `flutter analyze --no-pub` | No issues found; chạy ở lượt implementation cùng source Dart không đổi |
| `flutter test --no-pub --reporter expanded` | 420 PASS, 2 opt-in live skipped; cùng source Dart không đổi |
| `node --check supabase/tests/run_return_pickup_production.mjs` và cùng lệnh cho `return_pickup_production_concurrency.mjs`, `run_delivery_read_fixture.mjs` | PASS |
| `git diff --check` | exit 0; chỉ cảnh báo LF/CRLF của shared files |
| `npx --offline --yes supabase@2.122.0 db push --linked --dry-run` | Kẹt `Initialising login role`; đã dừng đúng process của lệnh này, chưa apply migration |
| Cùng dry-run với `--dns-resolver https` / HTTP2 tắt cho CLI | Vẫn kẹt login role; không tiếp tục lặp hoặc reset cloud |
| `npx --offline --yes supabase@2.122.0 projects list` với `GODEBUG=http2client=0` | Đọc được linked project `bqoyfytmrtvjwrpshuhh`, ACTIVE_HEALTHY |
| `db query --linked --file supabase/.temp/p081_cloud_probe.sql` với cùng transport | Vẫn kẹt login role; probe chỉ SELECT version, không migration |

Probe TCP riêng: pooler resolve được nhưng port 5432 và 6543 timeout; direct DB
hostname trả ENOTFOUND trên mạng hiện tại. Management API HTTPS đọc project được,
nhưng chưa đủ để xác nhận đường SQL/deploy hoạt động. Không ghi cloud migration
history bằng tay hoặc tuyên bố deploy thành công. Lịch sử đã xác minh trước lượt
nghẽn mạng là 19 remote; migration P08.1 thứ 20 còn local.

SQL tests bao gồm metadata duyệt thiếu/sai/future, permission, exact-full/foreign/
duplicate/zero/partial/excess, task/request/order, retry sau downstream collect,
payload mismatch, CAS latest-failed, hơn hai pickup thất bại, owner-only notification,
reassignment denial, no stock/COD/refund/inspection changes. Ca lỗi event sau khi
cập nhật task/request/item chứng minh rollback không còn custody/ledger/event.
Task legacy thiếu snapshot bị từ chối write, không adopt kế hoạch ngầm.

Review độc lập đã sửa item-plan drift sau failed và race INSERT–assignment.
Plan-field UPDATE/INSERT/DELETE được khóa khi đã có snapshot/custody, không phụ
thuộc task còn active. Guard khóa parent request trước kiểm tra; future upstream
plan writers phải lấy order → request → items trước ghi, retry cùng request khi
40P01/40001. Không tự triển khai reapproval/versioning trong phase này. Review
cuối không còn finding trong guard. Native PG được dừng sau kiểm chứng; giữ DB
audit, không reset/drop.

## Contract API triển khai trong migration P08.1

### Cập nhật deploy sau VPN — 28/10/2026

Các lỗi kết nối trong bảng kiểm chứng phía trên là lịch sử trước khi bật VPN.
Đã chạy tuần tự CLI 2.122.0 với `GODEBUG=http2client=0`:

- `migration list --linked`: trước deploy chỉ thiếu migration P08.1.
- `db push --linked --dry-run`: đúng một migration
  `20261027142031_return_pickup_tasks.sql`, không seed/role file ngoài phạm vi.
- `db push --linked --yes`: SUCCESS trên `bqoyfytmrtvjwrpshuhh`.
- `db query --linked --file supabase/tests/return_pickup_production.sql`:
  **PASS**, suite rollback toàn bộ dữ liệu kiểm thử.
- `migration list --linked`: **20 local = 20 remote**.
- `db advisors --linked --type security --level error --fail-on error`:
  exit 0, No issues found ở mức error.
- Cloud cleanup query: fixture users/orders/request ledgers/item snapshots/
  custody prefix `08150000` đều bằng 0.

Backend P08.1 đã deploy; không còn blocker mạng của lượt trước. SQL cloud dùng
claims trong transaction, không thay cho UI/JWT thật. Approval/manager receipt
của Sơn vẫn là tích hợp riêng chưa triển khai. Pickup handover reporting đã được
bổ sung sau P08.1 theo yêu cầu người dùng; xem
[RPC và nghiệm thu handover](p082_pickup_handover_acceptance.md).

`20261027142031_return_pickup_tasks.sql` được tạo bằng CLI 2.122.0. Trạng thái
kiểm thử/deploy ghi ở phần kết quả cuối, không suy từ sự có mặt của file.

| RPC | Input, role | Output |
| --- | --- | --- |
| `assign_return_pickup_task` | `p_return_request_id uuid`, `p_shipper_id uuid`, `p_request_id uuid`, `p_expected_task_id uuid DEFAULT NULL`, `p_expected_shipper_id uuid DEFAULT NULL`; manager | task/request/order/shipper UUIDs, operation, action assigned/reassigned/noop, task_status, return_status, attempt_number=1, amount_to_collect_vnd=0, assigned_at, event_id nullable nếu noop, request_id |
| `collect_return_items` | `p_task_id uuid`, `p_request_id uuid`, `p_items jsonb`; current shipper | task/request/order UUIDs, operation, task_status in_transit, return_status returning_to_store, accepted_at=started_at=occurred_at server, event_id, request_id |
| `fail_return_pickup_task` | `p_task_id uuid`, `p_request_id uuid`, `p_reason_code text`, `p_description text DEFAULT NULL`; current shipper | task/request/order UUIDs, operation, task_status failed, return_status awaiting_return_pickup, reason_code/description chuẩn hóa, failed_at=occurred_at server, event_id, request_id |

`p_items` là array không rỗng, sắp tăng theo UUID `return_item_id`; mỗi object
chỉ có `return_item_id` UUID và `quantity` integer dương. Không duplicate/field
ngoài contract hoặc fractional quantity. So với snapshot server phải exact-full;
client không gửi actor/status/destination/order total/COD/refund.
Quantity trong API này giới hạn int32 dương; kế hoạch vượt giới hạn bị từ chối
trước tạo task, không tạo kế hoạch mà RPC collect không thể thực hiện.

Lý do thất bại: unreachable/reschedule/bad_address/refusal/other; other bắt buộc
mô tả không chỉ whitespace. Mô tả được chuẩn hóa trước so payload và lưu.

CAS phân công: lần đầu chưa có task dùng expected NULL; đổi người dùng đúng
task active/shipper hiện tại. Sau lấy thất bại, tạo task mới phải nêu đúng task
failed gần nhất/shipper của task đó. Không dùng task cũ hơn để bỏ qua quyết định
mới. Mỗi task pickup vẫn có attempt_number=1; đây không phải số lần thu hồi.

Đọc MH11 tiếp tục dùng chữ ký `get_my_delivery_task` và
`read_my_delivery_task_items` hiện có; không cho shipper đọc return request
nguyên dòng, bank/video/refund/Storage. Task do P08.1 tạo dùng snapshot task
riêng; lịch sử failed không mở contact/items hay task mới.

Ledger actor/request dùng chung ba operation, lưu payload chuẩn hóa/hash và ACK;
same key/same payload sau kiểm tra lại actor/target trả ACK trước, không chạy lại
side effects. Đổi operation/target/payload bị conflict; không catch duplicate SQL
rồi báo success. Mỗi event có UUID server riêng, không dùng client key unique
toàn cục của business_events. Khi timeout/40P01/40001, caller retry có giới hạn
với đúng request UUID/payload; không tự thay UUID.

Khóa request advisory → cùng order advisory P04/P05/P07 → order → return request
→ tasks theo UUID → return_items theo UUID; profile được khóa và đọc lại role.
Snapshot/ledger append-only không cần FOR SHARE/UPDATE để tránh cấp quyền ghi
chỉ phục vụ đọc. Transaction chứa task/request/items/custody/event/notification
và ACK; lỗi bất kỳ rollback tất cả. Không giữ khóa qua network/Storage.

Lỗi public: `42501 AUTH_REQUIRED/PERMISSION_DENIED/NOT_FOUND_OR_FORBIDDEN`,
`22023 INVALID_ARGUMENT`, `PT409 APPROVAL_UNRESOLVED/STATE_CONFLICT/STALE_ASSIGNMENT/
ITEMS_MISMATCH/CUSTODY_UNRESOLVED/INVALID_SHIPPER/TASK_CONFLICT/IDEMPOTENCY_CONFLICT`.
Không phản chiếu SQL chi tiết hay PII vào UI/log. Client role checks không thay
authorization server; role lấy từ profiles, không user_metadata.

Schema private mới: `return_pickup_requests` (idempotency),
`return_pickup_task_items` (snapshot), `return_pickup_custody` (thực nhận),
`return_pickup_assignment_audits`, `return_pickup_failure_results`. RLS bật và
FORCE, append-only, client không có table privileges. Role writer chỉ có các cột
cần thiết cho ba RPC; read role chỉ thêm cột snapshot/custody cần projection.
Không thêm enum, không cấp shipper general read orders/return_requests/items.

Legacy pickup tạo trước P08.1 chưa có snapshot tiếp tục nhánh read projection
cũ với quyền task hiện tại, để không phá contract đọc đã có. Đây không phải
fallback của mutation: không có snapshot production/custody hợp lệ thì từ chối
write. Không backfill hoặc đoán kế hoạch đã duyệt cho dữ liệu cũ.

## Manifest

- Migration `supabase/migrations/20261027142031_return_pickup_tasks.sql`.
- SQL suite `supabase/tests/return_pickup_production.sql` và runner
  `run_return_pickup_production.mjs`, race suite
  `return_pickup_production_concurrency.mjs`.
- Shared regression runner `supabase/tests/run_delivery_read_fixture.mjs` thêm
  suite/race pickup và kiểm tra không còn năm private ledgers sau cleanup.
- Bốn tài liệu business/API/database/screen mapping cùng tài liệu bàn giao này.

Không đổi Dart runtime/UI, router/theme/client hoặc dependencies; không có Dart
file thay đổi để format, không cần pub get. `outputs/` không liên quan giữ nguyên.
Chưa commit/push các thay đổi P08.1 ở lượt này.

## Bàn giao cho Sơn, Bảo và Văn Đức

| Owner | Input/bằng chứng giao nhận cần dùng | Ranh giới chưa được triển khai ở P08.1 |
| --- | --- | --- |
| Sơn / MH15 approval | Request cùng order/customer, trạng thái awaiting_return_pickup, decision metadata manager và kế hoạch thực tế đã duyệt; tên hàng/số lượng không suy từ toàn đơn | API duyệt kế hoạch và UI MH15 chưa có trong repository; không ghi bank/video vào task snapshot |
| Sơn / manager receipt | Phải đọc custody theo đúng task/request/order/holder và item đã thực nhận; khóa order → request → tasks → items cùng giao dịch | `receive_customer_return` chưa có; báo bàn giao khác receipt; không update receipt bằng nhiều Flutter requests |
| Văn Đức / inventory | Pickup chưa làm hàng bán được; chỉ lượng được manager kiểm tra đạt mới có thể đi qua contract nhập tồn riêng | Không inventory movement/reservation/dispatch/restock khi collect/fail |
| Bảo / order/COD/notification | Order delivered và COD còn phải nộp giữ nguyên; notification thất bại là event task chỉ gửi store owner, mở link đọc lại quyền | Không xóa/offset COD vì return; renderer MH17 vẫn owner Bảo |

Không tự tạo API duyệt/nhận hàng của Sơn hoặc tuyên bố phối hợp đã hoàn thành.
Mọi fixture plan/approval đều có nhãn kiểm thử và rollback/cleanup, không được
đưa vào app như nguồn dữ liệu thay thế Supabase.
