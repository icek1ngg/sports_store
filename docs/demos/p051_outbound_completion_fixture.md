# P05.1 — Completion contract fixture, chưa có RPC live

Ngày 25/10/2026, repository chưa có `public.complete_outbound_delivery`,
accept/start live hoặc custody/dispatch proof tích hợp. Event type/recipient D7,
idempotency/version S2/S4 và failure outcome workflow còn phải phối hợp owner.
Theo stop rule P05.1, chỉ bổ sung interface/fixture SQL cô lập để kiểm tra logic;
không thêm migration, quyền client, UI P05.2 hoặc API production.

## Chạy fixture

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/run_outbound_completion_fixture.ps1
```

Wrapper dùng PG17 native/data đã có trong `supabase/.temp/`; thiếu runtime thì
dừng. Không tải credentials hoặc dùng database cloud. Runner kiểm tra host
127.0.0.1:55439, PG17 và data_directory trong workspace; tạo database p011_ mới,
không drop/reset database có sẵn. Wrapper dừng server nếu chính nó khởi động.

Nếu native fixture đang chạy, dùng tên database mới:

```powershell
node supabase/tests/run_delivery_read_fixture.mjs p011_p051_unique_name --p051-fixture
```

Flag opt-in mới tải completion fixture; runner mặc định không cài schema này.
SQL suite cài schema trong BEGIN/ROLLBACK. Concurrency suite cài riêng schema
để hai connection nhìn thấy dữ liệu, rồi dọn đúng schema `p051_fixture` vừa tạo.
Database cô lập được giữ lại. Không chạy file `.sql.fixture` trên cloud/shared DB.

## Interface minh họa, không phải RPC finalized

`p051_fixture.complete_outbound_delivery(task_id,request_id,received_all_items,
collected_amount_vnd)` dùng UUID/boolean/bigint. Amount đầu vào là **số tiền thực
nhận do shipper khai**, không phải expected amount hoặc total đáng tin cậy.
Fixture tính expected từ generated server subtotal+fee, so sánh task amount và
COD expected, rồi yêu cầu claimed amount bằng toàn bộ expected. Không có tham
số actor/shipper hoặc order total để client ghi đè. Collector lấy từ auth.uid
SQL stub và actors mô phỏng. Không có Supabase adapter hoặc public RPC tương ứng.

Mẫu fixture: 520.000 tiền hàng + 30.000 phí giao = **550.000 VND**. Thiếu/null,
thu thiếu hoặc thu dư đều không được biến thành collected. Nhận toàn bộ hàng
phải true. Order/task phải delivering/in_transit, đúng current shipper, lần đã
start khớp order count, có accepted/start timestamp và custody/proof fixture.
COD phải uncollected sạch; không sửa nghĩa vụ đã collected/received để hợp thức hóa.

Lệnh mô phỏng khóa actor/request rồi order→task→COD, lưu exact payload và safe
response cùng transaction. Ghi một success attempt, delivered task/order,
collected COD, một event và notifications theo cấu hình fixture; không tăng
attempt count, xuất kho, hoặc đối soát received. Retry cùng key/payload replay
sau recheck quyền; payload khác hoặc kết quả khác đã chiếm attempt phải từ chối.

## Những giả định chỉ có trong test

- `p051_fixture.actors` là role map test, không phải profiles/RLS/JWT thật.
- Custody và dispatch proof được privileged fixture seed; không chứng minh
  primitive Văn Đức đã tồn tại hoặc hàng đã được nhận qua P04.1 thật.
- Recipient customer+manager được test seed riêng theo order. Đây là cấu hình
  giả định test, **không phải D7 đã được Bảo duyệt**. Không có recipient config
  thì fixture từ chối, không tự gửi tới mọi manager hoặc một ID hardcode live.
- Event/notification/ledger schema chỉ thuộc `p051_fixture`, không là schema
  dùng chung hoặc event enum đã được nhóm chốt. Không có dữ liệu địa chỉ/bank/
  evidence trong notification fixture.
- Race success/failure dùng helper `pg_temp.claim_failed_result_for_test` chỉ
  chiếm result slot và đổi task thành failed. Nó cố ý không mô phỏng đầy đủ
  order lifecycle/event/notification thất bại; không phải failure RPC hoặc
  implementation phase tiếp theo. Order có thể còn delivering trong fixture
  này để tránh tự đoán failure contract. Chỉ dùng để chứng minh loại trừ kết quả.

## Coverage và tiêu chí live còn thiếu

Fixture kiểm tra role/state/amount/proof, exact replay/payload mismatch, late
fault rollback và concurrency bằng hai kết nối PostgreSQL thật. Chờ khóa phải
được xác nhận bằng pg_blocking_pids, không giả bằng hai callback tuần tự.
PASS chỉ áp dụng cho mô hình fixture; không nghiệm thu Supabase/JWT/RLS thật.

P05.1 live vẫn BLOCKED bởi P04.1, custody/version/ledger chung và D7; cần owner
bàn giao rồi mới tạo migration bằng CLI và chạy lại allowed/denied/concurrency
trên API thật. Không bật MH11 complete-success hoặc làm P05.2 trong phase này.

## Bàn giao và kiểm chứng ngày 25/10/2026

Các tệp riêng P05.1:

- `supabase/tests/fixtures/p051_completion.sql.fixture`
- `supabase/tests/outbound_completion.sql`
- `supabase/tests/outbound_completion_concurrency.mjs`
- `supabase/tests/run_outbound_completion_fixture.ps1`
- `supabase/tests/run_delivery_read_fixture.mjs` (thêm opt-in P05.1)
- `docs/demos/p051_outbound_completion_fixture.md`
- Mục P05.1 trong `docs/api_contracts.md`, `docs/database.md`,
  `docs/business_states.md`, `docs/screen_mapping.md`.

Tổng 10 tệp trong phạm vi phase; giữ nguyên diff P03.3/P04.1/P04.2 chưa commit,
không đụng `outputs/`. Không migration/API production/RLS/Dart/UI/dependency mới.

Lệnh và kết quả thực tế:

- `powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/run_outbound_completion_fixture.ps1`:
  exit **0**, PostgreSQL **17.10**, database mới
  `p011_p051_fixture_20261025083334_18e269f1`. Bảy migrations hiện có được apply
  chỉ vào fixture; bảy SQL suites PASS/ROLLBACK, gồm outbound_completion.sql.
- P03.3 assignment concurrency hồi quy PASS. Năm P05.1 lock races PASS:
  same-key replay; different-key duplicate; complete thắng failed-result claim;
  failed-result claim thắng complete; same-key khác claimed amount. Mỗi contender
  được xác minh thật sự chờ bằng pg_blocking_pids.
- Trace từ dữ liệu đã ghi: task/order delivered, total/collected=550000,
  attempts=1, events=1, notifications=2 theo recipient config test. Failure
  contender thắng thì COD vẫn uncollected/0, không event/notification success.
- `node --check supabase/tests/run_delivery_read_fixture.mjs`: PASS.
- `node --check supabase/tests/outbound_completion_concurrency.mjs`: PASS.
- `flutter analyze --no-pub`: No issues found.
- `git diff --check`: PASS (chỉ warning LF/CRLF).

Suite kiểm tra full/missing/partial/excess amount, received-all false/null,
auth/role/shipper/state/kind, sai counter/proof, task-only/COD-only amount
mismatch, metadata COD uncollected bị bẩn, timestamp server đồng nhất,
exact replay/payload conflict/replay sau role hoặc assignment bị thu hồi,
thiếu/không hợp lệ recipient config, notification fault rollback toàn bộ
và retry cùng request sau rollback. Không bỏ assertion hoặc biến lỗi thành success.

Schema p051_fixture được dọn và assert không còn; public fixture rows được
rollback/dọn sạch; wrapper nhận `server stopped`. Database test giữ lại, không
reset/drop. Không chạy lại Flutter UI tests vì không đổi Dart/UI; 164 tests
P04.2 trước đó không được tính thành P05.1 RPC acceptance. Không có file Dart
thay đổi cần format, không pub get hoặc deploy cloud.

Worker Luna audit/fixture và reviewer Sol độc lập; các finding về delivered_at,
role/custody/recipient locks, amount mismatch độc lập và dirty COD/replay tests
đã sửa trước run cuối. Pending: accept/start/dispatch proof và cancellation
integration của Văn Đức/Bảo; D7 event type/recipients/deep links; S2/S4 common
ledger/version và phối hợp failure outcome. Không nhận stakeholder approval
mới từ test fixture. P05.1 **chưa hoàn thành live**.

Kiểm chứng source cuối sau bổ sung attempt 2 và mismatch counter: chạy lại cùng
lệnh wrapper, exit0, database p011_p051_fixture_20261025083528_d90b91eb; vẫn đủ
7 SQL suites và 5 completion races PASS, schema fixture dọn/public sạch/server
stopped. Positive attempt 2 giữ failed result lần một, count=2 không tăng;
mismatch task attempt/order count không ghi outcome, money hoặc request.
Review độc lập cuối không còn finding trong scope fixture. P05.1 live vẫn
BLOCKED, chưa có public RPC; các tệp vẫn chưa commit/push.
