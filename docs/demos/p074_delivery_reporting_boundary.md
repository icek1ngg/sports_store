# P07.4 — Báo bàn giao cửa hàng và sự cố

Audit ngày 26/10/2026: **live BLOCKED; phase chưa hoàn tất**.
Đã đọc AGENTS.md, kế hoạch Minh Đức, bốn contract docs mới nhất, chín
migration và tests liên quan. Báo cáo gốc v3.0 chưa có để đối chiếu trực tiếp;
không tuyên bố đã đọc toàn văn báo cáo.

## Hiện trạng đã kiểm tra

- Chưa có `public.report_store_handover` hoặc `public.report_delivery_incident`.
- Enum DB là `delivery_incident_kind`: `damaged`, `lost`, `other`; từ damage/
  loss trong đề bài tương ứng hỏng/mất, không thêm hoặc đổi tên enum.
- Migration simplification đã bỏ bảng delivery_incidents. Incident nằm trong
  business_events với task_id, actor_id, request_id, reason, incident_kind,
  created_at. CHECK buộc subject_type=delivery_task, subject_id=task_id,
  actor/task/request/reason không null và reason không rỗng theo btrim.
- request_id của event unique **toàn bảng**, không phải ledger actor/request/
  operation/payload/result. Constraint không thể replay hoặc kiểm tra payload
  mismatch. Không dùng client UUID trực tiếp làm khóa global cho hai mutation
  khi chưa có contract namespace và ledger.
- Sau P01.1, policy business_events_read chỉ cho manager đọc raw events.
  Shipper không có raw incident/handover read; không nới RLS để đọc lại retry.
  ACK/replay sau này cần response/projection an toàn được duyệt.
- Chưa có custody/handover payload đầy đủ theo item. accepted_at/assignment
  không chứng minh ai đang giữ hàng. Event text đơn lẻ không thay custody proof.

## Contract mục tiêu và điểm phải phối hợp

| Hành động | Actor / state mục tiêu theo docs | Tác dụng được phép và điều còn mở |
| --- | --- | --- |
| Báo hoàn outbound O10 | Shipper hiện tại thực giữ hàng; task failed, order awaiting_store_return, bàn giao thực tế | Chỉ report event/giờ server, trạng thái giữ nguyên. Bảo cần receipt độc lập O11a rồi inspection O11b; D2/D5 và custody/item payload chưa có. |
| Báo bàn giao pickup P5 | Shipper hiện tại; task in_transit, request returning_to_store; có hàng bàn giao | Giữ task/request; Sơn thực nhận mới returned_to_store/under_inspection. D8 actual item/quantity và proof chưa chốt. |
| Báo bàn giao redelivery R6a | Shipper giữ hàng sau failed redelivery | Giữ trạng thái chờ manager; D9 chưa chọn mapping failed/redelivery_failed hoặc manager_action_required, nên không tự chốt allowed states. |
| Báo sự cố | Shipper hiện tại, kind hợp lệ, reason không chỉ whitespace, state hợp lệ và custody sau nhận | Ghi actor/task/type/reason/request/time/event + manager notification nguyên tử; không ghi delivery_attempts.failed, không giảm count/thu COD/compensation. D6 chưa chốt ma trận state theo kind và cách xử lý sự cố trước nhận. |

Report bàn giao không phải manager receipt/inspection: không set returned_to_store,
không cập nhật quantity sellable/damaged, on_hand/reserved hay inventory_movements,
không hoàn tiền/đóng return/thu COD. Người dùng đã yêu cầu rõ ranh giới này;
không cần approval lại cho quy tắc không restock và phân biệt incident/failure.

| Owner | Dependency hoặc quyết định chưa có |
| --- | --- |
| Bảo + Minh Đức | D2/D5 custody và hàng hoàn outbound; D6 ma trận incident states; manager recipient cụ thể của cảnh báo/handover, subject/deep link an toàn D7. “Manager” trong scope chưa chỉ định một/all/manager xử lý; không tự chọn tất cả. |
| Sơn + Minh Đức | D8 hàng/số lượng pickup, D9 redelivery failure/handover states và receipt trong MH15. Không dùng order_item_id tùy ý thay return snapshot. |
| Văn Đức + Bảo/Sơn | Dispatch/custody proof bất biến theo item; receipt/inspection/restock riêng có transaction, không coi report là xác nhận tồn. |
| Minh Đức + owners | S2 ledger, payload hash/exact payload, safe response/replay sau recheck assignment/role; event-type/payload mapping cho handover không giả incident; thời hạn keys, version nếu cần. |

Request tương lai phải serialize operation/actor/request trước business locks;
khóa order→return_request nếu có→tasks→custody theo contract chung. Recheck
current role/assignment/custody ngay cả replay, không trả PII sau thu hồi.
Cùng key/payload chỉ một event/notification; key khác payload bị từ chối;
rollback notification/ledger failure phải rollback cả report. Hai business
reports có thể hợp lệ ở hai lần khác nhau nên không tự unique(task_id) mãi mãi.
Signature/errors/return DTO và repeat-report policy còn phải chốt trước migration.

Quyết định P06.3 chỉ áp dụng notify shipper khi nhận COD, không chốt D7 cho
incident/handover. Không có stakeholder agreement mới được ghi nhận.

## Phần triển khai khi thiếu dependency

Hai temporary interfaces **test-only**, không public API:

```text
pg_temp.report_store_handover_contract(task_id, request_id)
pg_temp.report_delivery_incident_contract(task_id, request_id, incident_kind, reason)
```

Handover cố ý chưa có items/proof vì contract chưa chốt; interface luôn bị
chặn nên không thể gửi report thiếu hàng thành công. Không dùng chữ ký này
cho repository live. Incident dùng enum thật, input hợp lệ luôn
P0001/DEPENDENCY_NOT_READY; chỉ validation/auth.uid SQL stub, không claim role,
state, custody enforcement hoặc success idempotency. Không Supabase adapter/UI.

## Manifest và kiểm tra

- `supabase/tests/fixtures/p074_reporting_contract.sql.fixture`: hai interfaces.
- `supabase/tests/delivery_reporting_dependencies.sql`: null/auth/reason/type,
  repeated/changed calls fail-closed; snapshots không đổi, BEGIN/ROLLBACK.
- `supabase/tests/database_security.sql`: regression **schema/RLS thực**:
  privileged seed ba loại incident và một generic report incident_kind=null;
  actor/request/reason/subject constraints, duplicate request constraint đã có;
  shipper không đọc/ghi raw event, manager đọc được. Snapshot bảo đảm event-only
  seeds không đổi task/order/attempt/COD/return/tồn/notifications.
- `supabase/tests/run_delivery_read_fixture.mjs`: thêm đúng một marker/suite.
- `supabase/tests/run_delivery_reporting_dependencies.ps1`: wrapper database
  cô lập mới; dùng readiness probe SQL workspace có sẵn, dừng server tự mở.
- Tài liệu này và bốn contract docs dùng chung: cập nhật nối tiếp, giữ diff cũ.
  Các câu baseline về shipper đọc raw incident trong api_contracts/
  business_states/database đã được chú thích lại đúng policy P01.1 hiện tại.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/run_delivery_reporting_dependencies.ps1
node --check supabase/tests/run_delivery_read_fixture.mjs
flutter analyze --no-pub
git diff --check
```

Không đổi Dart/dependencies nên không có Dart cần format/pub get hoặc UI tests
mới. Không migration/public RPC/RLS/grant mới; không deploy/commit/push.

Acceptance còn thiếu: shipper report thật theo từng kind/state/custody, một
event và notification/response replay thực, payload conflict, concurrent calls
và rollback sau notification failure. Constraint/seed tests không thay các
tiêu chí này; không báo P07.4 hoàn tất từ fixture PASS.

Kết quả thực chạy ngày 26/10/2026:

- Wrapper cuối exit 0 trên PostgreSQL 17.10, database mới
  `p011_p074_boundary_20261026080847_dbb4e45c`: chín migration hiện có được áp
  dụng cô lập; **11 SQL suites PASS/ROLLBACK**, gồm schema/RLS regression mới
  và dependency reporting. Hai bộ concurrency assignment/COD receipt hồi quy
  PASS; không phải concurrency idempotent report RPC chưa có.
- Dependency snapshots không seed nghiệp vụ nên rỗng; riêng database_security
  có dữ liệu seeded thật và assertions schema/RLS/no-side-effect đã chạy.
  Privileged event seeds không chứng minh RPC authorization hoặc notification.
- Cleanup sạch, native server dừng (`server stopped`); database cô lập giữ
  nguyên, không reset/drop. Auth/Storage là SQL stubs, chưa cloud/JWT/PostgREST.
- Một lượt root ban đầu hết thời gian chờ readiness do các lượt kiểm tra agent
  chạy đồng thời trên runtime chung và dừng server. Đã kết thúc các lượt đó,
  chạy lại tuần tự toàn bộ wrapper thành công như trên; không sửa runtime API.
- `node --check supabase/tests/run_delivery_read_fixture.mjs`: exit 0.
- `flutter analyze --no-pub`: exit 0, `No issues found!`.
- `git diff --check`: exit 0; chỉ cảnh báo LF/CRLF của Git.
- Review độc lập cuối không còn finding quan trọng trong phạm vi bị chặn này.
