# P04.1 — Demo SQL cô lập, không phải backend live

Người dùng chọn **demo cô lập** ngày 24/10/2026. Demo mô phỏng các dependency
inventory/cancellation/custody đang thiếu để trình diễn và kiểm tra transaction.
Không kết nối app MH11, không tạo RPC public, không áp dụng migration hoặc
grants/RLS mới. Backend P04.1 thật vẫn bị chặn như api_contracts.md đã ghi.

## Chạy trên workspace Windows hiện tại

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/run_outbound_commands_demo.ps1
```

Script dùng PostgreSQL 17 native đã có trong thư mục ignored
`supabase/.temp/p011_pg_runtime` và data `supabase/.temp/p011_native_data`.
Nếu thiếu runtime/data, script dừng; không tải hoặc trỏ sang Supabase cloud.
Đây không phải dependency Flutter hoặc yêu cầu cài đặt cho production.
Runner xác minh host `127.0.0.1`, port `55439`, PG17 và data_directory chính xác
trước khi tạo database `p011_p041_demo_<timestamp>_<random>` mới. Không reset/drop
database có sẵn. Database test được giữ lại; dữ liệu demo/schema được dọn khi chạy xong.
Script dừng server nếu chính nó đã khởi động; nếu server có sẵn thì giữ nguyên.

Cũng có thể chạy khi native fixture đã sẵn sàng:

```powershell
node supabase/tests/run_delivery_read_fixture.mjs p011_p041_demo_unique_name --p041-demo
```

Tên database phải mới và có prefix `p011_`. Flag opt-in mới chạy demo thành công;
runner mặc định vẫn chỉ kiểm tra interface dependency fail-closed của P04.1.

## Phạm vi mô phỏng

Toàn bộ dữ liệu và lệnh demo nằm trong schema riêng `p041_demo`, có guard
fixture mode/database name. Không sửa bảng nghiệp vụ `public`. Các function
`SECURITY INVOKER` được gọi bằng test client đặc quyền trong database fixture;
actor UUID lấy qua Auth SQL stub và role lấy từ bảng **actors mô phỏng**.
Đây không phải kiểm thử JWT/RLS/quyền Supabase thật, không được expose cho client.

`p041_demo.command(operation, task_id, request_id)` chỉ có accept/start/cancel
mô phỏng. Không có endpoint complete/fail/retry tạo nhiệm vụ. Idempotency ledger,
dispatch proof, custody và inventory logic trong demo đều là thiết kế minh họa,
không phải schema đã được Văn Đức/Bảo/Sơn duyệt.

| Bước | Kết quả cần quan sát trong demo |
| --- | --- |
| Accept | Task assigned → accepted; ghi mốc nhận/custody và xuất đủ items trong cùng transaction; giảm on_hand/reserved; count không tăng. |
| Start | Yêu cầu accepted và custody/dispatch proof; task in_transit, order delivering; count tăng một; không xuất kho lại. |
| Retry | Cùng actor/request/payload trả kết quả cũ; payload/operation/target khác bị từ chối; key mới vẫn chịu state precondition. |
| Thiếu hàng | Tất cả cập nhật tồn/task/proof/ledger rollback; không có success giả. |
| Hủy thắng | Accept chờ khóa, sau commit cancellation phải bị từ chối; reservation được release, không dispatch. |
| Accept thắng | Cancellation chờ khóa, sau commit acceptance phải bị từ chối; task/custody/tồn giữ nhất quán. |
| Hai start | Chỉ một transaction bắt đầu; retry cùng key không tăng counter lần nữa. |

Lần hai chỉ là **giả định demo**: fixture seed một kết quả thất bại trước đó,
shipper vẫn giữ nguyên hàng và có dispatch/custody proof bất biến; accept task
hai sử dụng lại proof, không xuất tồn lần nữa. Không có API ghi kết quả trước
đó trong demo, không dùng assignment để suy ra custody. Đây không phải quyết
định D3 cho backend thật; chuyển shipper hoặc qua cửa hàng vẫn chưa chốt.
Accept/start không thêm bản ghi kết quả attempt; row kết quả lần một chỉ là
dữ liệu fixture được seed rõ ràng để minh họa lần hai.

## Đọc kết quả nghiệm thu demo

Runner in tên SQL suites, trace trạng thái/tồn/count từ test và kết quả race
trên hai kết nối PostgreSQL thật. Mọi assertion phải pass; exception làm lệnh
thoát khác 0, không được thay bằng thông báo thành công. Test kiểm tra khóa thực
bằng `pg_blocking_pids`, không chỉ gọi hai promise tuần tự.

PASS chỉ nghiệm thu **mô hình demo cô lập**. Các tiêu chí live còn thiếu:
primitive inventory Văn Đức, cancellation Bảo, schema/proof custody/version/
ledger được nhóm chốt, JWT/RLS thật và tích hợp MH11. Không dùng demo làm căn
cứ bật nút hoặc báo P04.1 production hoàn tất.

## Kết quả chạy nghiệm thu demo ngày 24/10/2026

Đã chạy chính lệnh PowerShell ở trên, exit code **0**, PostgreSQL **17.10**;
fixture database `p011_p041_demo_20261024213702_00ded97e`.

| Trace thực tế | Task | Order | Attempt count | Dispatch count |
| --- | --- | --- | --- | --- |
| accept | accepted | awaiting_pickup | 0 | 1 |
| start | in_transit | delivering | 1 | 1 |
| second_start (giả định demo cùng holder) | in_transit | delivering | 2 | 1 |

Bảy SQL suites PASS, gồm sáu bộ trước đó và outbound_commands_demo.sql.
P03.3 concurrency hồi quy PASS. Năm race demo trên hai kết nối thật PASS:
cancel thắng accept; accept thắng cancel; hai start cùng request replay;
hai accept khác request; hai start khác request. Có kiểm tra pg_blocking_pids
để xác nhận connection thứ hai thực sự chờ transaction lock.

Race cancel thắng: on_hand=10, reserved=0, dispatch=0, count=0. Race accept
thắng: on_hand=8, reserved=0, dispatch=1, count=0; start replay sau đó count=1
và không có attempt result. Late fault ở request ledger rollback cả dispatch,
custody, stock và task; không giữ success ledger khi transaction lỗi.

Review độc lập cuối không còn blocker. Đã dọn schema p041_demo (assert schema
không còn), rollback/dọn fixtures và nhận `server stopped`. Database test
được giữ, không drop/reset. `node --check` hai runner modules và
`git diff --check` PASS. Không đổi Dart/dependencies, không chạy lại Flutter UI
tests cho demo SQL; không dùng kết quả này để tuyên bố JWT/RLS/backend live.
