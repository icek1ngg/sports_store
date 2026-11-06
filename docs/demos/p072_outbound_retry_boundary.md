# P07.2 — Manager retry, reassignment và custody

Audit ngày 26/10/2026: **live BLOCKED; phase chưa hoàn tất**. Đã kiểm tra
AGENTS.md, kế hoạch Minh Đức trong docs, screen_mapping/business_states/
api_contracts/database, chín migration và các tests assignment/fixtures liên
quan. Báo cáo gốc v3.0 chưa có; không tuyên bố đối chiếu toàn văn báo cáo.

## API hiện có và phần chưa có

`public.assign_delivery_task` P03.3 thực sự có trong migration, chỉ cho lần
đầu count=0 và đổi người trước thực nhận, CAS bằng expected task/shipper.
Đã có manager role check, request ledger/audit riêng, khóa order→tasks→COD;
không xuất kho hoặc tăng count. Endpoint từ chối mọi count>0, lịch sử attempt,
task terminal hoặc custody evidence. Không sửa/nới endpoint này trong P07.2.

Chưa có production `decide_outbound_retry`, custody transfer/receipt proof,
dispatch primitive Văn Đức, accept/start hoặc fail RPC. P04.1 demo và P07.1
dependency boundary không thay các dependency thật. Không nối demo vào MH09.

Hai interface mới chỉ là temporary SQL test-only, không public API:

```text
pg_temp.decide_outbound_retry_contract(order_id, request_id, decision)
pg_temp.reassign_outbound_task_contract(task_id, shipper_id, request_id)
```

`decision` draft nhận `retry` hoặc `return_to_store`. ID phải không null,
auth.uid phải có; input hợp lệ luôn lỗi `P0001/DEPENDENCY_NOT_READY`.
Không có table I/O, success replay, profile/assignment/state/custody lookup.
Signature chưa có expected IDs/version/custody proof nên **không dùng làm
contract finalized**; không thay API assignment hiện có bằng interface này.

## Hợp đồng mục tiêu bàn giao MH09

| Tình huống | Điều kiện và tác dụng mục tiêu | Điểm chưa thể tích hợp |
| --- | --- | --- |
| Cho giao lần hai | Manager; order awaiting_redelivery, count=1, đúng một kết quả failed lần 1; không task active/quyết định đối nghịch. Giữ task/attempt cũ, tạo task mới số 2. | Cách đóng băng quyết định, mốc order awaiting_pickup và assignment phải thống nhất Bảo; D3 proof custody chưa có. Không tăng count trước start. |
| Hoàn sớm | Manager sau failed lần 1; chưa có lần 2 đang đi. Order→awaiting_store_return; task cũ vẫn failed; holder không đổi. | Không đồng nghĩa cửa hàng đã nhận/kiểm tra; D5 cần xử lý task 2 đã tạo nhưng chưa start. |
| Cùng shipper giữ hàng | Có proof holder/items/dispatch hợp lệ. Không dispatch lại, không tự đặt accepted_at mới từ assignment. | Ai xác nhận tiếp tục custody và mốc accept của task mới chưa được chọn trong D3. |
| Đổi shipper sau failed | Ghi tách assignment và giao/nhận hàng thực tế; holder cũ vẫn là holder cho tới bàn giao đã xác nhận. | Chưa chốt chuyển trực tiếp hay qua cửa hàng, actor xác nhận/quantity/proof/mốc thu hồi quyền; không tự chọn một đường. |
| Đổi trước thực nhận lần đầu | Dùng API P03.3 với expected IDs, chưa custody/start/result; giữ count=0 và lịch sử audit. | Đã có implementation local; không mở quyền đổi sau custody. |
| Lần ba | Chặn ở mọi create/assign/start/decision, dù đổi manager/shipper/task/request; count thuộc order. | Existing assignment chặn count=2; chưa có các endpoint retry/start khác để nghiệm thu toàn luồng. |

Transaction mục tiêu: khóa request/profile theo contract chung, order→tasks
theo UUID→COD→inventory nếu cần; kiểm tra decision/custody và chỉ một manager
commit, lưu response an toàn cùng event/notification. Retry cùng payload/key
replay sau recheck quyền, key khác/payload đối nghịch phải bị chặn bằng trạng
thái/ledger trong khóa. Không ghép nhiều RPC client để mô phỏng transaction.

Dispatch history phải gắn order/operation bất biến, không chỉ event UUID mới;
lần hai dùng hàng đã dispatch, không giảm on_hand/reserved lần nữa. Không
restock khi manager chỉ chọn hoàn. Giữ attempt_number của task cũ và shipper
thực hiện kết quả; không viết lại lịch sử theo assignee mới. Assignment audit
không cấp quyền vào task mới hoặc chứng minh custody cho shipper cũ/mới.

## Dependency và quyết định còn mở

- Bảo + Minh Đức: D3 chọn đường bàn giao, actor xác nhận physical receipt và
  mốc cho phép start; D5 nhánh đổi quyết định khi task 2 chưa bắt đầu; MH09
  tích hợp transaction/CAS/decision replay, recipients D7.
- Văn Đức + Bảo: dispatch proof bất biến theo order, custody theo item và
  quantity, không xuất lần hai; inventory/cancel/receipt locks tương thích.
- Minh Đức + owners: ledger/version/custody schema S2/S4, exact payload/error/
  safe response; không tái dùng ledger assignment/COD receipt cho retry.
- P07.1 failure thật và P04.1 start/custody thật chưa có. Không coi seeded
  failure/count/dispatch trong tests là bằng chứng tích hợp production.

Đề bài hiện tại xác định hai lựa chọn manager và giới hạn hai lần; nó không
chọn một đường bàn giao cụ thể trong D3. Không có approval mới của teammates.
Không sửa màn Bảo/Văn Đức, router, dependencies, Dart, schema hoặc RLS.

## Manifest và kiểm tra

- `supabase/tests/fixtures/p072_retry_contract.sql.fixture`: hai interfaces.
- `supabase/tests/outbound_retry_dependencies.sql`: draft validation/auth,
  repeated/changed calls vẫn bị chặn và snapshots không đổi, BEGIN/ROLLBACK.
- `supabase/tests/outbound_assignment.sql`: regression **RPC thật hiện có**:
  seed count=2 có chủ đích (không chứng minh hai attempt thật), hai manager
  với shipper/request khác nhau gọi thẳng assign đều ATTEMPT_LIMIT; snapshot
  order/task/attempt/inventory/request ledger không đổi.
- `supabase/tests/run_delivery_read_fixture.mjs`: thêm suite/marker một lần.
- `supabase/tests/run_outbound_retry_dependencies.ps1`: database p011_ mới,
  chỉ runtime workspace; dừng server đã tự khởi động, không reset/drop.
- `supabase/tests/probe_local_fixture_ready.mjs`: chờ kết nối SQL thực và xác
  minh data_directory workspace, tránh nhầm pg_ctl status với sẵn sàng nhận query.
- Tài liệu này và bốn docs contract dùng chung được cập nhật nối tiếp.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/run_outbound_retry_dependencies.ps1
node --check supabase/tests/run_delivery_read_fixture.mjs
node --check supabase/tests/probe_local_fixture_ready.mjs
flutter analyze --no-pub
git diff --check
```

Không đổi Dart/dependencies nên không format/pub get hoặc thêm UI tests.
Acceptance còn thiếu: decision manager thành công, conflicting decisions,
custody transfer hợp lệ, start lần hai không dispatch lại và từ chối lần ba
qua toàn bộ API retry/start thật. Test interface bị chặn không thay acceptance.
Không migration/public API mới, không deploy cloud, không commit/push.

Kết quả thực chạy ngày 26/10/2026:

- Wrapper cuối exit 0, PostgreSQL 17.10, database mới
  `p011_p072_boundary_20261026080202_6f15e5b8`: chín migration hiện có được áp
  dụng trong database cô lập, **10 SQL suites PASS/ROLLBACK**, hai bộ concurrency
  assignment/COD receipt hồi quy PASS. Các race này không là race quyết định
  retry/hoàn sớm chưa có implementation.
- Hai manager gọi assignment với count=2 bị PT409/ATTEMPT_LIMIT và snapshot
  không đổi. Fixture P07.2 không seed dữ liệu; snapshots rỗng, không chứng minh
  quyền manager/custody/state hoặc không dispatch hai lần trên retry thật.
- Cleanup sạch; server do wrapper khởi động đã dừng (`server stopped`);
  database giữ nguyên, không reset/drop. Auth/Storage là SQL stubs, không JWT/
  PostgREST/Supabase cloud E2E.
- `node --check` cả runner và readiness probe: exit 0.
- `flutter analyze --no-pub`: exit 0, `No issues found!`.
- `git diff --check`: exit 0, cảnh báo LF/CRLF theo Git.

Trong kiểm tra, wrapper ban đầu gặp ECONNREFUSED do chỉ chờ pg_ctl status;
bản probe node -e trung gian gặp lỗi quoting PowerShell. Đã thay bằng file
probe riêng và chạy lại nguyên bộ thành công như trên. Review độc lập cuối
không còn finding quan trọng trong phạm vi dependency boundary.
