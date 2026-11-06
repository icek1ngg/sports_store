# P06.3 — Manager xác nhận nhận đủ COD

## Quyết định được người dùng chốt ngày 25/10/2026

Trong lượt P06.3, người dùng trả lời **“Chốt contract trên cho P06.3”** cho:

- Notification chỉ gửi shipper giữ khoản COD.
- Khi manager xác nhận nhận đủ, handed_over_at = received_at bằng giờ server.
- Ledger receipt riêng, không tái sử dụng ledger assignment.
- Khóa order → COD, mỗi order chỉ có một receipt thành công.

Đây là chấp thuận của người dùng cho phạm vi P06.3, không là xác nhận Bảo,
Sơn hoặc Văn Đức đã duyệt D7/S3/S2 chung. Không thay contract các write khác
đang blocked. Không cần inventory/custody primitive để nhận một khoản đã
collected hợp lệ, nhưng luồng tạo collected qua P05.1 live vẫn chưa có.

## API triển khai trong repository

`public.confirm_cod_received(p_order_id uuid, p_received_amount_vnd bigint,
p_request_id uuid)` trả JSON kết quả đã commit. Không nhận manager/shipper ID,
order total, refund, timestamp, notification recipient hoặc trạng thái từ client.

Số tiền là lời xác nhận của manager rằng đã thực nhận tiền mặt, không phải
nguồn chuẩn để sửa expected. Server đối chiếu đủ nguyên expected = collected;
server không có cơ chế kiểm đếm tiền vật lý ngoài lời xác nhận này. Không nhận
partial, pooled voucher hoặc offset refund. Không suy COD hết nghĩa vụ từ
trạng thái delivered/cancelled/returns/refunded của order/request.

Caller phải còn manager trong profiles do server quản lý, kể cả khi replay.
Shipper gọi RPC trực tiếp vẫn bị từ chối. Client không được cấp UPDATE COD
hoặc INSERT event/notification/ledger. Function write dùng role nội bộ bị giới
hạn và RLS, không thêm service role vào app hoặc nới policy authenticated.

Ledger actor/request + exact target/payload bảo đảm cùng request retry trả lại
kết quả đã commit, khác amount/order bị chặn. Request mới sau một receipt đã
thành công bị conflict thay vì tạo receipt/event/notification thứ hai. Hai
manager tranh chấp được serialize trên order/COD; chỉ một lần chuyển state.
Nếu transaction đầu rollback, waiter có thể thực hiện với trạng thái gốc.

COD phải collected sạch: full amount, collector/holder và collected_at hợp lệ,
chưa có received hoặc handed-over metadata. Không tự sửa dữ liệu cũ không
nhất quán để ép nghiệp vụ thành công. Không đổi collector, expected/collected
amount, order/task/return state hoặc giảm nghĩa vụ do refund.

Business event dùng subject_type=cod_collection, subject_id=order UUID,
from_state=collected, to_state=received. Không giả có cột event_type trong DB.
business_events.request_id là UUID event do server sinh, không dùng raw client
request ID toàn cục; mapping operation/client request → event nằm trong ledger
receipt. Notification subject cod_collection/order UUID mở `/cod?orderId=UUID`
qua guard hiện có; chỉ thông điệp tối thiểu, không bank/address/video/evidence.

## Validation và triển khai

Migration `supabase/migrations/20261025121908_confirm_cod_received.sql` được
tạo bằng `npx --yes supabase@2.122.0 migration new confirm_cod_received`.
Function SECURITY DEFINER thuộc role NOLOGIN/NOINHERIT/NOBYPASSRLS riêng
`sports_store_cod_receipt_writer`, search_path rỗng; chỉ authenticated có
EXECUTE ở client và phải qua kiểm tra manager từ profiles. RLS riêng của role
nội bộ, grants theo cột và lock-only profile/order không cấp quyền mutate cho
client. Private ledger force RLS/append-only; unique actor/request và order.
Không thêm version/global ledger, event_type hoặc bảng tài chính thứ hai.

Lỗi: 42501 AUTH_REQUIRED/PERMISSION_DENIED; 22023 INVALID_ARGUMENT;
PT409 STATE_CONFLICT/AMOUNT_MISMATCH/IDEMPOTENCY_CONFLICT/CORRUPT_COD_STATE.
Cast UUID/bigint sai trả lỗi PostgreSQL trước function. Missing/dirty COD,
collector/holder không nhất quán, collected_at thiếu/ở tương lai hoặc receipt
metadata đã có không được sửa tự động. Holder đổi role không xóa nghĩa vụ
tiền cũ, không bị dùng làm điều kiện tự xóa/offset COD.

## Tệp thay đổi trong P06.3

- Migration nêu trên: RPC, private ledger, writer role/policies/grants.
- `supabase/tests/cod_receipt.sql`: rollback fixture actual-role tests.
- `supabase/tests/cod_receipt_concurrency.mjs`: real multi-connection races.
- `supabase/tests/run_cod_receipt_tests.ps1`: tạo database local mới, không
  reset/drop hoặc dùng cloud credentials; server do wrapper mở được dừng.
- `supabase/tests/run_delivery_read_fixture.mjs`: tích hợp suite/race và kiểm
  tra cleanup receipt ledger/events/notifications.
- Tài liệu này, `docs/api_contracts.md`, `docs/database.md`,
  `docs/business_states.md`, `docs/screen_mapping.md`.

Không thay Dart/runtime UI, dependency/lockfile, router, theme, Storage hoặc
RLS/grants client hiện hữu. Không thực hiện phase UI manager tiếp theo.

## Kết quả ngày 25/10/2026

| Lệnh | Kết quả |
| --- | --- |
| `powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/run_cod_receipt_tests.ps1` | Exit 0; 9 migrations áp local; 8 SQL suites PASS; assignment và COD receipt concurrency PASS; cleanup PASS |
| `node --check supabase/tests/cod_receipt_concurrency.mjs` | Exit 0 |
| `node --check supabase/tests/run_delivery_read_fixture.mjs` | Exit 0 |
| `flutter analyze --no-pub` | No issues found |
| `flutter test --no-pub` | 225 tests PASS |
| `git diff --check` | Exit 0; chỉ cảnh báo LF→CRLF |

Run SQL cuối: `p011_p063_receipt_20261025192504_1e59e0c1`, PostgreSQL 17.10
workspace-local với SQL Auth/Storage stubs. Tám suite: database_security,
delivery_read_security, delivery_task_list, delivery_task_detail,
outbound_assignment, outbound_commands_dependencies, cod_collection_list,
cod_receipt. Allowed/denied RPC chạy authenticated/anon; privileged chỉ seed,
fault injection, assertion hậu kiểm và cleanup, không giả caller manager.

Kiểm tra gồm shipper/customer/anon denial, 550.000 VND, thiếu/sai tiền, COD
uncollected/corrupt, repeat/new-ID/mismatch, role downgrade trước replay,
refund không giảm tiền, read P06.1 sau receipt/outstanding=0, rollback khi
notification lỗi. Concurrency quan sát pg_blocking_pids cho hai manager,
cùng actor/key/payload replay, cùng key khác payload, và winner rollback ở
COMMIT để waiter thành công. Mỗi successful order chỉ một ledger/event/
notification; tiền không cộng lần hai. Fixtures rollback/cleanup xác nhận 0
users/profiles/orders/tasks/COD/assignment/receipt ledger/events/notifications/
Storage rows; server do wrapper khởi động đã dừng. Không chạy P04.1/P05.1 demo.

Đã đối chiếu [Supabase function security](https://supabase.com/docs/guides/database/functions)
và [PostgreSQL 17 locking](https://www.postgresql.org/docs/17/explicit-locking.html).
Review độc lập không còn blocker correctness/security sau sửa; chưa apply
migration cloud hoặc nghiệm thu Supabase Auth/PostgREST end-to-end.

**P06.3 hoàn tất triển khai và kiểm thử local** theo contract người dùng chốt.
Remaining integration: deploy migration theo workflow nhóm; Bảo nối dispatcher
notification subject cod_collection sang /cod?orderId và recheck quyền; phase
UI manager/repository write adapter chưa thuộc bước này. P05.1 collection live
vẫn chưa có, nên chưa nghiệm thu toàn luồng giao → thu → nhận tiền trên cloud.
