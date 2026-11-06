# P07.2 — Manager chọn giao lần hai hoặc hoàn sớm

Ngày 27/10/2026. **Backend P07.2 hoàn tất và đã deploy** project
`bqoyfytmrtvjwrpshuhh`. Chỉ backend cho MH09; không sửa giao diện của Bảo,
không bật dialog thất bại P07.3 hoặc bàn giao/sự cố P07.4.
Tài liệu này thay các blocker accept/start/fail đã lỗi thời trong bản boundary
P07.2 sau khi nghiệm thu implementation bên dưới; giữ nguyên tài liệu lịch sử.

## Contract đã được người dùng chốt

Manager là chủ cửa hàng. Chỉ cùng shipper đang giữ đầy đủ hàng được tiếp tục
lần hai; không hỗ trợ chuyển người sau nhận hàng. Phân công task2 không phải
physical receipt: shipper phải dùng accept để xác nhận tiếp tục custody trước
start. Manager có thể chuyển sang hoàn sớm khi task2 chưa start, kể cả task2
đã accepted. Sau start không đổi quyết định. Thông báo quyết định chỉ gửi
shipper đang giữ hàng. Đây là quyết định của người dùng, không tuyên bố Bảo
hoặc Văn Đức đã duyệt riêng.

| Hành động | Tiền điều kiện | Chuyển trạng thái và tác dụng |
| --- | --- | --- |
| Chọn retry | Order awaiting_redelivery, count1, đúng task/result1 failed, custody/dispatch/COD sạch, chưa task2 | Tạo task2 assigned cùng holder, attempt2; order awaiting_pickup; chưa accepted/start, count giữ1 |
| Shipper xác nhận tiếp tục giữ hàng | Task2 assigned, same holder, proof cũ đầy đủ | Existing accept_delivery_task ghi custody task2/accepted; không xuất kho lần hai |
| Bắt đầu lần hai | Task2 accepted, proof đúng, count1 | Existing start_delivery_task chuyển in_transit/delivering, count2 đúng một lần; chưa ghi result2 |
| Hoàn sớm trực tiếp | Sau failed1, chưa task2 | Order awaiting_store_return; task1 failed/custody/result giữ nguyên |
| Chuyển retry sang hoàn | Expected task2 khớp, assigned hoặc accepted, chưa start | Task2 cancelled; giữ accepted_at/custody nếu có, không ghi result2; order awaiting_store_return |
| Sau start2 hoặc count2 | Đã bắt đầu lần hai | Từ chối retry/đổi quyết định/lần ba, kể cả gọi API trực tiếp hoặc đổi key/manager |

Không thu hoặc sửa COD, không dispatch/restock, không xóa attempt1, không
coi cửa hàng đã nhận/kiểm tra hàng. Receipt/inspection của Bảo/Văn Đức vẫn riêng.
Đổi người trước nhận lần đầu tiếp tục dùng API P03.3; P07.2 không nới API đó.

CAS gồm expected failed task và expected retry task: NULL retry task xác nhận
chưa có task2; UUID task2 chỉ dùng để chủ động chuyển quyết định trước start.
Nhờ vậy hai manager chọn đối nghịch từ cùng snapshot không tự ghi đè nhau.

## RPC bàn giao MH09

`decide_outbound_retry(p_order_id uuid,p_request_id uuid,p_decision text,
p_expected_failed_task_id uuid,p_expected_retry_task_id uuid DEFAULT NULL) → jsonb`.
Decision `retry` hoặc `return_to_store`, chuẩn hóa whitespace hai đầu.
Không nhận shipper, amount, count, timestamp hoặc trạng thái client.

ACK gồm task_id/failed_task_id/retry_task_id/order_id, operation
`decide_outbound_retry`, decision, task_status/order_status,
attempt_number/delivery_attempt_count, holder_id, accepted_at/started_at,
event_id/request_id. Retry_task_id NULL nếu hoàn trực tiếp. ACK chỉ là kết quả
quyết định; MH09 cần đọc lại order/tasks để hiển thị trạng thái mới nhất.

| SQLSTATE / marker | Điều kiện |
| --- | --- |
| `42501 / AUTH_REQUIRED` | Thiếu identity |
| `42501 / PERMISSION_DENIED` | Profile không là manager |
| `P0002 / ORDER_NOT_FOUND` | Order không tồn tại sau kiểm tra manager |
| `22023 / INVALID_ARGUMENT` | Thiếu ID/code sai, retry kèm expected retry task |
| `PT409 / IDEMPOTENCY_CONFLICT` | Cùng actor/key khác decision/target/expected IDs |
| `PT409 / STATE_CONFLICT` | CAS/task/order không còn đúng snapshot; đã chốt hoàn hoặc đã có quyết định đối nghịch |
| `PT409 / ATTEMPT_LIMIT` | Count đã2 hoặc lịch sử result không đúng một failed lần1 |
| `PT409 / COD_CONFLICT` | COD/task/order amount hoặc collector/trạng thái không sạch |
| `PT409 / CUSTODY_UNRESOLVED` | Holder/dispatch/items/receipt/incident không đủ chứng cứ |

Replay recheck profile manager và khóa order/tasks/COD trước trả ACK cũ. Sau
khi task2 đã bắt đầu/kết thúc, request retry cũ vẫn replay ACK đã commit;
request mới không thể tạo lần3. Request IDs thuộc ledger operation này, không
tái dùng key assignment/COD receipt. Hai manager/key khác cùng snapshot được
serialize; loser không được tự đổi quyết định winner. Chuyển retry→return
bắt buộc lấy đúng retry UUID sau lần đọc mới.

## Transaction, custody và quyền

Migration CLI `20261027062118_decide_outbound_retry.sql` thêm
private.outbound_retry_requests (PK actor/request, exact payload và ACK) và
private.outbound_retry_decisions (unique order/decision_number). Tối đa hai
decision: lựa chọn đầu và chuyển retry→return. Append-only/force RLS, không
client grants; role NOLOGIN/NOINHERIT/NOBYPASSRLS, EXECUTE chỉ authenticated,
search_path rỗng và identity bridge. Không cấp schema Auth cho role mới.

Khóa profile/request → shared order advisory → order row → outbound tasks
theo UUID → COD. Decision ledger bất biến được đọc dưới order lock; không
UPDATE ledger chỉ để khóa. Tất cả task/event/notification/decision/request
writes atomic; lỗi notification rollback cả task2/quyết định.

Task2 lấy snapshot recipient/destination và full COD từ order server, holder
từ task1 + custody + immutable dispatch proof. Giữ nguyên task1/failed result/
stock/COD; task2 assigned chưa có custody. Existing accept/start P04 xác minh
cùng holder, tạo receipt task2 khi shipper chủ động accept và tăng count tại
start. Không tạo endpoint chuyển người sau nhận hàng.

Khi hoàn sau task2 accepted, ghi decision trước rồi guard custody kiểm tra
decision/actor/task2/holder/assignment không đổi/start NULL/cancel reason
`manager_return_to_store`. Chỉ ngoại lệ đó được hủy accepted task2. Không GUC
client, không disable trigger/RLS/FK. Task1 accepted vẫn không được hủy; mọi
đổi assignee/assigned_by/assigned_at sau custody vẫn bị chặn.

Role mới chỉ được đọc và khóa các bảng tiền/tồn cần kiểm tra; không UPDATE
amount/counter/stock. P07.2 bổ sung EXECUTE helper role nội bộ cho failure
writer để shared snapshot/RLS plan trong cùng phiên accept/start/fail hoạt
động, không cấp quyền client. Không sửa body RPC P03/P04/P05/P07.1.

Events có reason `outbound_retry_selected` hoặc `outbound_return_selected`,
subject order UUID, server UUID event token tách client key. Notification
subject task UUID, body chung, duy nhất holder shipper; không customer/manager
inbox và không PII. MH17 renderer vẫn thuộc Bảo.

## Kiểm thử và deploy

- `node supabase/tests/run_outbound_retry_production.mjs`: PASS SQL và
  concurrency sau sửa, native PostgreSQL17.10, DB
  `p011_p072_production_1793092800019`.
- `node supabase/tests/run_delivery_read_fixture.mjs p011_p072_regression_20261027_final3`:
  **17 migrations, 14 SQL suites PASS/ROLLBACK, 6 nhóm concurrency PASS**.
  Whole chain dùng RPC thật assign→accept→start→fail1→retry→accept2→start2→fail2;
  chỉ reservation/order ban đầu là fixture. Count1→2, chỉ một dispatch và COD
  luôn uncollected; không seed sẵn failure/task2 để tuyên bố loop đạt.
  Có early return trực tiếp, hủy assigned/accepted task2, giữ custody/history,
  manager-only/role switch denial, stale CAS/idempotency mismatch/replay kể cả
  sau result2, strict lần3, late notification rollback, ACL/force RLS/private
  ledger privacy và hai manager quyết định đối nghịch. Race accepted cancel vs
  start cả hai thứ tự dùng hai connection thật, không competitor giả.
- `flutter analyze --no-pub`: No issues found.
- `flutter test --no-pub --reporter compact`: **358 PASS, 2 opt-in live skipped**.
- `node --check` new standalone/concurrency/shared runner và `git diff --check`:
  PASS. Không đổi Dart/dependency P07.2, không cần format Dart mới/pub get.
- `npx --offline --yes supabase@2.122.0 db push --linked --dry-run --skip-vault`:
  chỉ migration P07.2 pending.
- `npx --offline --yes supabase@2.122.0 db push --linked --yes --skip-vault`:
  **PASS**, migration P07.2 đã áp dụng.
- `npx --offline --yes supabase@2.122.0 db query --linked --file supabase/tests/outbound_retry_production.sql`:
  **PASS/ROLLBACK** trên cloud, chạy lại sau tăng test role-denial vẫn PASS.
- Cùng lệnh db query với `outbound_failure_production.sql` và
  `outbound_completion_production.sql`: **PASS/ROLLBACK** hồi quy cloud.
- `npx --offline --yes supabase@2.122.0 migration list --linked`:
  **17 local=17 remote**.
- `npx --offline --yes supabase@2.122.0 db advisors --linked --type security --level warn --fail-on error`:
  exit0 trước/sau deploy, không ERROR. WARN authenticated SECURITY DEFINER
  12→13 là RPC gọi có chủ đích, kiểm soát bằng role/RLS/identity/assignment;
  [giải thích advisory](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

Hai lệnh cloud regression chạy song song ban đầu kẹt khởi tạo login role;
đã dừng đúng các process đó và chạy tuần tự, đều PASS. Các lượt lỗi local
ban đầu gồm PG crash recovery chưa ready, thiếu privilege helper/column,
fixture đọc ledger với role client, SQL assertion/snapshot và cleanup FK sai
thứ tự; đã sửa và chạy lại toàn bộ. Không mở quyền client để làm tests pass.
Các DB local thất bại giữ để audit; fixture thành công rollback/cleanup.

Cloud cleanup xác minh fixture Auth/orders prefix0725=0, retry request/decision
ledgers=0, ba products cũ giữ nguyên. Native final runner cleanup sạch; server
đã dừng sau nghiệm thu, không reset/drop DB.

## Manifest và giới hạn

Mới: migration trên; `supabase/tests/outbound_retry_production.sql`,
`outbound_retry_production_concurrency.mjs`, `run_outbound_retry_production.mjs`;
tài liệu này. Cập nhật shared runner thay retry dependency boundary bằng
production suite/race và bốn contract docs. Giữ nguyên P06/P07.1 chưa commit,
upstream checkout sources và outputs không liên quan.

Independent reviewer đã phát hiện guard regression và thiếu ràng buộc event
notification, được sửa trước tests. Agents chạm usage limit trước final
review; coordinator trực tiếp hoàn thiện/rà soát và chạy các checks trên,
không tuyên bố có final independent approval.

**Backend P07.2 hoàn tất trong phạm vi đã chốt và đã deploy.** MH09 UI chưa
nối/nghiệm thu; không có app/JWT thật hoặc điện thoại physical trong lượt
này. Cloud SQL dùng claims có kiểm soát trong transaction; concurrency native.
Không làm P07.3/P07.4 hoặc manager receipt/inspection/restock. Chưa commit/push.
