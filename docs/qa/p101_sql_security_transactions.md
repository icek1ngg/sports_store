# P10.1 — SQL security và transaction QA

Ngày 28/10/2026. Chỉ bổ sung kiểm thử, không runtime UI/API/migration/permissions.

## Lệnh và kết quả thực tế

```powershell
node --check supabase/tests/p101_delivery_cod_concurrency.mjs
node --check supabase/tests/run_delivery_read_fixture.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/run_p101_sql_qa.ps1
git diff --check
```

Tất cả exit **0**. Lượt nghiệm thu sau review:
`p011_p083_p101_20261028204829_10b389a1`, PostgreSQL **17.10**.
Runner áp dụng **22 migrations** vào database mới; **17 SQL suites PASS +
ROLLBACK**, **9 concurrency modules PASS**, cleanup **51 tables** khớp baseline
sau migration và tất cả trigger enablement giữ nguyên. Log ignored tại
`supabase/.temp/p101_qa.log`; tên DB mới có thể khác khi chạy lại.

Không chạy Flutter analyze/tests/build ở P10.1 vì không đổi Dart/pubspec;
không lấy kết quả Flutter từ PR #5 để coi là kết quả SQL mới.

## Phần bổ sung

- `p101_security_contracts.sql`: kiểm mỗi tên trong **28 RPC delivery/COD/
  return primitives đã tồn tại**, và mọi overload của chúng; thiếu tên là FAIL,
  anon/service_role execute hoặc thiếu authenticated execute là FAIL. Kiểm FORCE RLS và
  không client CRUD/TRUNCATE trên private ledgers; writer roles không login/
  superuser/bypassrls, phải NOINHERIT, không là member của role khác hoặc được
  anon/authenticated/service_role kế thừa. Chạy actual denied
  SELECT dispatch proof/UPDATE receipt ledger dưới role authenticated.
- `p101_delivery_cod_concurrency.mjs`: reserve là TEST seed, sau đó dùng RPC
  thật assign → accept → start → complete → confirm receipt. Chạy hai kết nối
  với claims + `SET LOCAL ROLE authenticated`, timeout và kiểm
  `pg_blocking_pids`; không suy cạnh tranh từ Promise.all đơn thuần.
- Completion chưa commit khiến receipt phải chờ. Commit → nhận đúng COD;
  rollback → receipt từ chối, task vẫn in_transit/order delivering/COD
  uncollected, không result/event/notification/receipt sót.
- Hai manager tranh receipt sau completion thật: đúng một receipt thắng.
  Cùng UUID request ở hai actor/operation không replay ACK của nhau; retry
  từng ledger trả ACK cũ, không thêm tiền/event/attempt. Payload partial bị
  rollback có thể thử lại cùng key với payload hợp lệ, không giữ key giả.
- Fixture merchandise **520.000 + phí 30.000 = 550.000 VND**: task/order/COD
  nhất quán; thu/nhận đúng 550.000, một dispatch/movement, một attempt result,
  một completion event và một receipt event. Completion gửi khách + hai
  manager fixture (3 notification); receipt chỉ shipper (1 notification).
- Runner `--p101` dùng lại suites production hiện hữu, thêm SQL redelivery
  trong BEGIN/ROLLBACK, chụp row counts mọi bảng auth/storage/public/private
  và trạng thái trigger trước/sau để phát hiện cleanup thiếu ledger mới.

## Traceability theo acceptance

Mỗi hàng dưới đây đã chạy trong wrapper và PASS:

| Yêu cầu | Test thực thi | Giới hạn diễn giải |
| --- | --- | --- |
| Role/RLS/Storage/private ledgers | database_security.sql, internal_auth_identity.sql, p101_security_contracts.sql | PostgreSQL roles/SQL policies thật; Auth/Storage services là stub. |
| History không mở task/order/items mới | delivery_read_security.sql, delivery_task_detail.sql, delivery_task_list.sql | Old shipper chỉ minimal history; đổi assignee cùng task gỡ task/items; ID không quyền bị từ chối. |
| Manager assignment, shipper nhận đúng task | outbound_assignment.sql + assignment concurrency | Duplicate create, CAS reassignment, wrong role/state, COD equality. |
| Custody/start/state/dispatch đúng một lần | outbound_accept_start.sql + accept/start concurrency | Replay/different key/rollback waiter; start mới tăng count, chưa ghi result. |
| Tối đa hai outbound attempts | outbound_retry_production.sql + retry concurrency | Task2 cùng holder; giữ history/custody, không dispatch lại; direct third retry/start bị chặn. |
| Completion nguyên tử với COD | outbound_completion_production.sql + completion concurrency + P10.1 module | 550.000, invalid/partial amount, failure injection rollback, no duplicate result/money/event. |
| Success/failure conflict | outbound_failure_production.sql + failure concurrency | Hai thứ tự của RPC fail/complete thật, một kết quả thắng; failure không thu COD. |
| Full manager-only receipt | cod_receipt.sql + receipt concurrency + P10.1 module | Shipper bị từ chối; partial/mismatch, concurrent manager, rollback/retry. |
| Outstanding độc lập return/refund | cod_collection_list.sql, cod_receipt.sql | Chỉ collected chưa received tính tiền đang giữ; không offset refund. |
| Handover khác store receipt/restock | delivery_reporting_production.sql + reporting concurrency, return_pickup_production.sql | Report không đổi receipt/tồn/COD/attempt; incident không giả failed delivery. |
| Pickup/redelivery đúng state, miễn COD | return_pickup_production.sql + pickup concurrency, redelivery_production.sql | Redelivery dùng fixture seed helpers có nhãn để gọi RPC production; không COD/attempt mới. |
| Cancel đối đầu accept | outbound_accept_start_concurrency.mjs | Khóa thực cả hai thứ tự; cancellation là trusted TEST UPDATE/trigger guard, không RPC hủy của Bảo. |
| Completion đối đầu reconciliation | p101_delivery_cod_concurrency.mjs | Chờ commit/rollback trên order lock thật; receipt không đọc COD chưa commit. |
| Idempotency/rollback/cleanup | Từng suite trên + final baseline snapshot | Không result/event/notification/tiền trùng; trigger cleanup không bị để tắt. |

## Cô lập và cleanup

- Wrapper chỉ loopback `127.0.0.1:55439`, native runtime/data dưới
  `supabase/.temp/p011_*`; runner kiểm PG17 và **data_directory chính xác**.
  Không nhận cloud URL/token. Chưa có runtime/data thì FAIL, không tải ngầm
  hoặc thay bằng shared project.
- Database mới có prefix `p011_p083_p101_*`. CREATE DATABASE lỗi nếu tên đã
  tồn tại; không RESET/DROP/reuse DB cũ. DB schema giữ lại để chẩn đoán; dữ
  liệu kiểm thử được rollback/xóa scoped UUID và so với baseline.
- Auth/Storage stubs chỉ được tạo trong DB empty có fixture-mode marker.
  Không gọi Supabase live, không đăng nhập tài khoản thật hoặc xóa dữ liệu
  project dùng chung. Service-role stub không dùng làm actor app trong assertions.
- Các concurrency tests cần seed committed để hai connection thấy nhau.
  Cleanup đặc quyền dùng `SET LOCAL session_replication_role='replica'` chỉ
  trong transaction của DB fixture, xóa UUID test được liệt kê; không cấp thêm
  grants/RLS cho client và không dùng replica mode trong nghiệp vụ/assertions.
- Chỉ dừng PG server nếu chính wrapper đã khởi động; server có sẵn giữ nguyên.
  Lượt ghi trên đã khởi động rồi dừng server thành công.
- Không bật `--p041-demo`/`--p051-fixture`. Suite dependency cũ chỉ kiểm
  interface fail-closed có nhãn; không dùng demo success thay production RPC.
  Không chạy runner redelivery diagnostic cũ vốn giữ data để điều tra.

## File manifest và trạng thái

Thêm:
`supabase/tests/p101_security_contracts.sql`,
`supabase/tests/p101_delivery_cod_concurrency.mjs`,
`supabase/tests/run_p101_sql_qa.ps1`, biên bản này.

Sửa: `supabase/tests/run_delivery_read_fixture.mjs` (flag + cleanup snapshot),
`supabase/tests/database_security.sql` (chỉ comment chỉ đường tới suite mới),
`docs/database.md` (liên kết QA). Không sửa schema/RPC/grants, router/dependencies
hoặc màn teammate. `outputs/` và artifact MH09 không thuộc thay đổi P10.1.

**Hoàn tất SQL/transaction QA P10.1 trong môi trường local cô lập** theo các
acceptance mô phỏng nêu trên. Không còn blocker để chạy các tests này trên máy
hiện tại. Chưa phải nghiệm thu Supabase cloud Auth/JWT/Realtime/Storage service,
hoặc full manager cancellation integration: repository chưa có RPC hủy của
Bảo, nên chỉ chứng minh boundary khóa/trigger và ghi rõ TEST mutation. Máy
mới thiếu PG17/runtime cần chuẩn bị dependency local trước khi chạy wrapper.

Không deploy migration và chưa commit/push ở lượt này. Không suy stakeholder
agreement mới từ kết quả tests.

Review độc lập đã đóng hai thiếu sót của audit ban đầu (service_role execute
và writer role inheritance/membership); reviewer xác nhận lại hai bản sửa,
không còn finding trong phạm vi tái kiểm tra đó. Toàn bộ wrapper đã chạy lại
sau sửa và PASS như mốc nêu trên.
