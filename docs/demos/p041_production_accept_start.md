# P04.1 — Production accept/start outbound

Ngày 26/10/2026 người dùng yêu cầu triển khai hai RPC production và chốt:

1. Triển khai primitive xuất kho + custody cùng transaction với hai RPC.
2. Lần giao thứ hai chỉ hỗ trợ cùng shipper còn giữ đủ hàng; chặn đổi người
   sau nhận. Không coi assignment là physical receipt.

Đây là quyết định người dùng, không tuyên bố Bảo/Văn Đức đã review hoặc đồng
thuận. Các mục BLOCKED P04.1 trước đây trong docs là lịch sử; tài liệu này ghi
implementation mới, không biến demo p041_demo thành backend production.

## Phạm vi

Hai function public, cùng chữ ký:

```sql
accept_delivery_task(p_task_id uuid, p_request_id uuid) returns jsonb
start_delivery_task(p_task_id uuid, p_request_id uuid) returns jsonb
```

Caller phải có profiles.role=shipper và đang được phân công task outbound.
Identity từ auth.uid, không nhận actor/shipper/order/items/amount/status/timestamp
từ client. Task UUID ngoài quyền và không tồn tại cùng lỗi quyền, không oracle.
Các task return_pickup/redelivery không được đi qua hai RPC outbound này.

Accept lần đầu: order awaiting_pickup/count=0, task assigned/attempt=1, chưa
accepted/start/result. Server đọc order_items, kiểm tra bằng chứng reserve/
release **của chính order** và số lượng biến thể, khóa inventory rồi giảm
on_hand và reserved một lần. Ghi immutable dispatch proof/snapshot, custody
receipt và accepted_at cùng transaction; order/count không đổi.

Start: task accepted, proof dispatch/custody còn nguyên và đúng holder; số
task=count+1 trong 1..2. Ghi in_transit, order delivering, started_at server và
tăng count một lần. Không dispatch lại; không INSERT delivery_attempts.

Lần hai: chỉ khi có failed result lần một đúng order/task/shipper, count=1 và
task mới số 2 được tạo hợp lệ; cùng holder, full original item proof/movements
khớp. Accept ghi custody receipt task mới, không giảm tồn lần hai; start tăng
count lên 2. Không tự tạo task mới hay sửa failed task/attempt cũ.
API manager retry P07.2 vẫn chưa có, nên acceptance lần hai dùng seed được
gắn nhãn rõ, không tuyên bố đã tích hợp MH09 retry/failure production.

## Reservation, custody và retry

`product_variants.reserved` là tổng, không đủ chứng minh đơn đang giữ hàng.
Primitive đối chiếu inventory_movements của order với order_items và từ chối
thiếu reserve evidence, biến thể thừa/thiếu, released/dirty/deducted rows;
không âm thầm tạo reservation hoặc mượn reservation của đơn khác.
Checkout/Văn Đức phải ghi reserve movement và aggregate stock trong cùng
transaction tương thích. Không backfill proof cho dữ liệu accepted cũ.

Các bảng private mới, không phải API/table đọc client:

- outbound_dispatches: một proof theo order, initial task/holder/event/snapshot.
- outbound_custody_acceptances: một receipt bất biến theo task, gắn proof và holder.
- outbound_command_requests: actor+request, operation/target và response an toàn.

Cùng actor/request/operation/target replay đúng response cũ sau recheck role/
current assignment. Dùng key cho operation/task khác bị từ chối. New key sau
accepted/start không tái chạy transition. Response replay là command receipt,
không current-state snapshot; UI phải gọi get_my_delivery_task để đọc lại.
Server event UUID riêng tránh collision global business_events.request_id.

Khóa profile/request → order → outbound tasks theo UUID → COD → order_items
theo variant/id → variants theo UUID. Không network call trong transaction. Role được
khóa/kiểm tra từ profiles; dedicated writer NOLOGIN/NOINHERIT/NOBYPASSRLS với
search_path rỗng, grants/RLS nội bộ tối thiểu. Client chỉ EXECUTE hai RPC,
không tăng quyền ghi orders/tasks/inventory/private ledger.

Có guard DB ngăn hủy order sau dispatch/custody. Không bổ sung RPC hủy đơn
của Bảo: concurrency test cập nhật order bằng trusted test session chỉ nghiệm
thu guard/row-lock boundary, không giả lập hủy/release stock hoàn chỉnh.
Bảo cần cùng order-first locking cho cancellation sau này.

Không ghi kết quả success/failure, không thu/nhận COD, không báo bàn giao/
incident, không thay router/theme/client/UI. Chỉ business events accept/start;
notification recipients D7 chưa chốt nên phase này không phát notification.

## Manifest / kiểm tra

Migration được tạo bằng CLI thật:

```powershell
npx --yes supabase@2.122.0 migration new accept_start_outbound_delivery
```

Tệp: `supabase/migrations/20261026055651_accept_start_outbound_delivery.sql`.
Không sửa migration teammates đã có, không đặt tên timestamp giả.

- `supabase/tests/outbound_accept_start.sql`: actual roles, state/reservation/
  proof/retry/rollback/second attempt/access-control assertions; BEGIN/ROLLBACK.
- `supabase/tests/outbound_accept_start_concurrency.mjs`: nhiều kết nối thật,
  xác minh pg_blocking_pids; duplicate/replay/new keys, rollback waiter,
  accept-vs-order-cancel guard và accept-vs-actual-assignment cả hai hướng.
- `supabase/tests/run_delivery_read_fixture.mjs`: thêm actual suite/race và
  kiểm tra cleanup các ledger mới; vẫn áp dụng mọi migration vào DB mới.
- `supabase/tests/outbound_commands_dependencies.sql`: giữ temporary interface
  cũ fail-closed, cập nhật assertion rằng public RPC mới có thật và được test riêng.
- `supabase/tests/run_outbound_accept_start.ps1`: runtime PG17 workspace,
  database p011_ mới; không reset/drop DB cũ, dừng server do script mở.
- Tài liệu này và bốn docs hợp đồng: bổ sung nối tiếp, giữ diff các phase trước.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/run_outbound_accept_start.ps1
node --check supabase/tests/outbound_accept_start_concurrency.mjs
node --check supabase/tests/run_delivery_read_fixture.mjs
flutter analyze --no-pub
git diff --check
```

Hướng dẫn kỹ thuật được đối chiếu với tài liệu Supabase chính thức:
[Database functions](https://supabase.com/docs/guides/database/functions),
[RLS](https://supabase.com/docs/guides/database/postgres/row-level-security),
[CLI migration new](https://supabase.com/docs/reference/cli/supabase-migration-new).

## Live và giới hạn tích hợp

“Production implementation trong repository” khác “đã deploy/kiểm thử cloud”.
Local PG17 dùng Auth/Storage SQL stubs, không phải Supabase JWT/PostgREST test.
Ở audit đầu chưa linked/login; sau đó người dùng xác nhận deploy project đang
cấu hình và tự đăng nhập CLI. Kết quả deploy/cloud được ghi ở mục dưới.

P04.2 production action wiring vẫn chưa được thay trong scope hai RPC này;
MH11 còn read-only. Các guide P04.2/P05/P07 fixture trước đây chưa tự trở thành
integration production khi hai RPC này có mặt. P07.2 manager retry, Bảo cancel,
checkout reservation producer và D7 notifications vẫn cần tích hợp riêng.

## Fix tương thích hosted Auth và manifest bổ sung

Migration `20261026062903_secure_internal_auth_identity_bridge.sql` được tạo
bằng CLI thật để xử lý lỗi cloud đã phát hiện: postgres không thể cấp schema
auth USAGE cho dedicated roles trên Supabase managed. Không grant role
authenticated cho writer và không mở RLS để né lỗi. Dùng helper private
`delivery_request_user_id()` STABLE SECURITY DEFINER, owner postgres,
search_path rỗng, body duy nhất `select auth.uid()`, chỉ EXECUTE cho bốn
internal roles. Đây không là quyền đọc bảng Auth. Chỉ function/policy của bốn
roles đó đổi sang helper; client/Storage policy, table grants và memberships
không thay đổi. Đã cấp private schema USAGE cho internal reader để gọi helper.

Căn cứ: [Supabase managed Auth schema permissions](https://supabase.com/kb/troubleshooting/permission-errors-when-granting-custom-roles-access-to-the-auth-schema).

Tệp bổ sung trong cùng thay đổi:

- `supabase/tests/internal_auth_identity.sql`: mô phỏng thiếu auth schema
  USAGE, kiểm tra owner/ACL/helper và direct client denial; BEGIN/ROLLBACK.
- `supabase/tests/check_outbound_rpc_access.mjs`: HTTP live với configured
  publishable/anon key, từ chối service keys, không in key/token. Kiểm tra cả
  hai RPC đã xuất hiện trên PostgREST và từ chối caller không đăng nhập.
- `supabase/tests/delivery_task_detail.sql`: trước khi kiểm tra cancellation
  masking, xác nhận guard từ chối hủy task legacy đã nhận rồi reset READ fixture
  về preaccept bằng privileged setup. Không giả đây là runtime reversal.
  Membership test đếm distinct member: hosted PG17 có hai grantor cho cùng
  postgres member, không đồng nghĩa cấp role cho hai người dùng.

## Kết quả cuối ngày 26/10/2026

- Native wrapper: 11 migrations, **13 SQL suites PASS/ROLLBACK**, ba nhóm
  concurrency PASS. Gồm replay/new-key, rollback waiter, order-cancel guard
  hai hướng và assignment/custody race. Không claim Bảo đã có cancel RPC.
- SQL acceptance thật kiểm tra first/second accept/start, no-second-dispatch,
  wrong actor/kind/state, dirty/missing reservation/COD, revoked replay,
  malformed legacy history và known damage/loss. Fault injection rollback
  task/order/stock/proof/event/ledger. Native server dừng, dữ liệu test dọn sạch.
- `node --check` runner/concurrency/HTTP probe: exit 0.
- `flutter analyze --no-pub`: exit 0, `No issues found!`.
- `git diff --check`: exit 0; cảnh báo LF/CRLF của Git. Không đổi Dart,
  pubspec/lockfile nên không thêm Dart tests/format/pub get trong phần RPC này.

Lệnh cloud đã thực chạy sau khi người dùng duyệt project và đăng nhập riêng:

```powershell
npx --yes supabase@2.122.0 link --project-ref bqoyfytmrtvjwrpshuhh
npx --yes supabase@2.122.0 migration list --linked --output json
npx --yes supabase@2.122.0 db push --linked --dry-run
npx --yes supabase@2.122.0 db push --linked --yes
npx --yes supabase@2.122.0 db query --linked --file supabase/tests/internal_auth_identity.sql --output json
npx --yes supabase@2.122.0 db query --linked --file supabase/tests/outbound_accept_start.sql --output json
node supabase/tests/check_outbound_rpc_access.mjs
```

Project `bqoyfytmrtvjwrpshuhh` (sports_store): trước deploy chỉ ba baseline
migrations, không target functions/private tables/profile/order. Đã push bảy
migration pending đã kiểm thử (read/assignment/COD/accept-start), rồi migration
bridge sửa hosted Auth. Lịch sử **11 local = 11 remote**. Không reset DB hoặc
xóa catalog hiện có. Profile/order sau tests vẫn 0, private proof/request rows
và fixture Auth users vẫn 0; mọi cloud SQL fixture đều rollback.

**8 cloud SQL suites PASS:** internal_auth_identity, outbound_accept_start,
delivery_read_security, delivery_task_list, delivery_task_detail,
outbound_assignment, cod_collection_list, cod_receipt. Đây là real Auth schema/
RLS/roles trên cloud nhưng claims được test set_config, không login GoTrue
positive-user end-to-end. PostgREST thực trả HTTP401/42501 cho cả hai RPC khi
không có session; không PGRST202 missing function. Chưa làm positive JWT/UI E2E.

Các lỗi trong quá trình kiểm thử đã được xử lý/ghi rõ:

- Hosted Auth USAGE bị từ chối: đã sửa bằng migration bridge, cloud suites PASS.
- Native tests phát hiện tên bảng inventory_balances legacy và UUID typo trong
  test; đã sửa sang product_variants và UUID đúng, không thay backend để nới test.
- Statement timestamp trong multi-statement tests cũ hơn accepted_at: chuyển
  clock_timestamp sau locks, không lấy giờ client.
- Baseline database_security không phù hợp chạy nguyên file trên cloud có ba
  catalog products sẵn (expected1, got4); transaction rollback. Không xóa catalog
  để ép test PASS. Suite này PASS trên isolated native DB; cloud scoped suites
  ở trên đã PASS. Đây không phải lỗi RPC accept/start còn mở.

Hai RPC và primitive **đã triển khai và kiểm thử cloud** theo phạm vi P04.1.
Không đồng nghĩa hoàn thiện mọi phase hoặc nối MH11 UI; P04.2 adapter/ViewModel
production vẫn cần triển khai riêng. Không commit/push Git trong lượt này.
