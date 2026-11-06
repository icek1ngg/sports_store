# P07.1 — Ranh giới ghi giao outbound thất bại

Ngày audit: 26/10/2026. **Live BLOCKED, phase chưa hoàn tất.**
Đã đọc AGENTS.md, kế hoạch Minh Đức, bốn contract docs và chín migration hiện
có. Báo cáo gốc v3.0 chưa có để đối chiếu trực tiếp; dùng quy tắc đã ghi trong
AGENTS.md và business_states.md, không tuyên bố đã đọc toàn văn báo cáo.

## Phạm vi được thực hiện

Chỉ interface SQL tạm `pg_temp.fail_outbound_delivery_contract` và dependency
tests, không production migration/RPC, adapter Flutter hoặc nút MH11 mới.
Interface nhận task UUID, request UUID, reason code và description tùy chọn.
Các mã draft là `unreachable`, `reschedule`, `bad_address`, `refusal`, `other`;
`other` bắt buộc mô tả không chỉ whitespace. Đây là tên kỹ thuật cho nhóm lý
do người dùng yêu cầu, **chưa phải enum/schema/RPC finalized**.
Không tự thêm giới hạn độ dài hoặc cách serialize code/description vào cột
`reason` text hiện tại. Interface không nhận shipper ID, số lần giao, giờ hoặc tiền.

Input hợp lệ luôn lỗi `P0001/DEPENDENCY_NOT_READY`; không có đường success,
idempotency replay thành công hay ghi dữ liệu. Kiểm tra auth chỉ nhận diện
auth.uid trong SQL stub; không đại diện cho authorization assignment/state thật.
Các SQLSTATE này chỉ thuộc fixture, chưa chốt error contract của RPC live.

## Contract mục tiêu và dependency

| Mốc | Tiền điều kiện và kết quả mục tiêu | Tình trạng |
| --- | --- | --- |
| Thất bại lần 1 (O6) | Shipper hiện tại; outbound in_transit, O=delivering; task.attempt_number=order.delivery_attempt_count=1; active attempt chưa result. T→failed, O→awaiting_redelivery. | Mapping có trong P00.1; chưa thực thi live. |
| Thất bại lần 2 (O9) | Cùng điều kiện, số lần=2; kết quả lần 1 phải là failed. T→failed, O→awaiting_store_return. | Chưa có custody/retry lần hai D3; không seed task số 2 để tuyên bố integration đạt. |
| Cả hai | Một failed delivery_attempts với actor, lý do, giờ server; completed_at/failure_reason trên task; count không tăng/reset; không thu COD, restock, tự tạo task mới hoặc manager receipt. | Unique task_id/(order_id,attempt_number) sẵn có chỉ bảo vệ trùng, chưa thay transaction. |
| Retry/kết quả đối nghịch | Cùng actor/request/payload trả kết quả cũ sau recheck quyền; mismatch bị từ chối; success/failure khóa cùng order→task→COD. | P05.1 chỉ p051_fixture, không public complete_outbound_delivery; chưa thể kiểm thử race production. |

Các điều kiện bổ sung cần thống nhất: custody/dispatch proof do Văn Đức và Bảo
cung cấp; liên kết timestamps/count/result không chỉ suy từ accepted_at được seed;
COD phải sạch uncollected, không được xóa một khoản đã thu để ép failure thành công.
Không gọi inventory qua network trong transaction.

| Owner | Cần bàn giao/chốt trước migration live |
| --- | --- |
| Văn Đức + Bảo/Minh Đức | P04.1 accept/start và proof thực nhận/xuất kho, D3 lần hai. |
| Bảo + Minh Đức | D7 recipient cụ thể của cảnh báo thất bại: manager nào, có customer hay không; event subject/deep link/nội dung và thời điểm. Không suy ra từ mock hoặc role manager chung. |
| Minh Đức + owners | Ledger/version S2/S4 cho fail và success; canonical payload reason/description/version, replay quyền, retention và khóa thống nhất; không tái dùng assignment/COD receipt ledger. |
| Bảo + Minh Đức | Mapping lỗi/response an toàn cuối, lưu code/description vào schema text hiện tại hay thêm cột; giới hạn mô tả nếu cần. |

Quyết định người dùng P06.3 chỉ notify shipper cho **COD receipt**, không chốt
D7 cho giao thất bại. Không có stakeholder approval mới trong P07.1.

## Kiểm thử và tệp

- `supabase/tests/fixtures/p071_failure_contract.sql.fixture`: interface test-only.
- `supabase/tests/outbound_failure_dependencies.sql`: validation, repeated calls,
  fail-closed và full-row snapshots không đổi; BEGIN/ROLLBACK.
- `supabase/tests/run_delivery_read_fixture.mjs`: nạp đúng một marker fixture
  vào transaction, thêm suite; giữ nguyên các suites/race trước.
- `supabase/tests/run_outbound_failure_dependencies.ps1`: tạo database mới có
  prefix p011_p071_boundary_, kiểm tra runtime PG17 trong workspace, dừng
  server nếu wrapper đã khởi động; không reset/drop database cũ.
- Tài liệu này và bốn contract docs: cập nhật nối tiếp, giữ diff các phase trước.

Acceptance **chưa đạt**: lần 1/lần 2 ghi thật, idempotency thành công, role/current
assignment/state enforcement, rollback sau partial write, absence of collected
COD trên failure thực và concurrency với success thật. Dependency PASS không
được dùng làm bằng chứng cho các tiêu chí đó. Không deploy Supabase/cloud.

Lệnh tái chạy:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/run_outbound_failure_dependencies.ps1
node --check supabase/tests/run_delivery_read_fixture.mjs
flutter analyze --no-pub
git diff --check
```

Không đổi Dart/dependencies nên không có Dart cần format/pub get hoặc test UI
mới. Không dùng kết quả 256 Flutter tests của P06.4 làm nghiệm thu RPC P07.1.
Kết quả ngày 26/10/2026:

- Wrapper SQL exit 0 trên PostgreSQL 17.10, database mới
  `p011_p071_boundary_20261026075619_c63d621b`: áp dụng chín migration hiện có,
  chín SQL suites PASS/ROLLBACK, gồm dependency P07.1 mới. Hai bộ concurrency
  assignment và COD receipt hồi quy PASS; **không phải fail-vs-success P07.1**.
- Snapshot suite mới không seed hàng nghiệp vụ nên các snapshots rỗng; test
  chứng minh interface không tạo dữ liệu/success, không kiểm thử chuyển trạng
  thái hay role/assignment thực. Source interface không có table I/O.
- Cleanup kiểm tra không còn fixture user/profile/order/task/COD/ledger/event/
  notification/Storage; wrapper đã dừng native server (`server stopped`).
  Database cô lập được giữ, không xóa/reset. Auth/Storage chỉ là SQL stubs,
  không Supabase Auth/PostgREST/cloud E2E.
- `node --check supabase/tests/run_delivery_read_fixture.mjs`: exit 0.
- `flutter analyze --no-pub`: exit 0, `No issues found!`.
- `git diff --check`: exit 0; chỉ cảnh báo Git LF/CRLF của working tree.

Không migration mới hoặc API runtime bị ảnh hưởng. Các diff phase trước
được giữ nguyên; không commit/push/deploy trong phase này.
