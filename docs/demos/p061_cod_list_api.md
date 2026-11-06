# P06.1 — COD list read API

Phạm vi: read API MH12 cho shipper/manager, typed repository và SQL/repository
tests. Không thêm màn MH12, xác nhận nhận tiền, completion RPC hoặc fixture
fallback vào production. P04.1/P05.1 live còn thiếu không ngăn triển khai API
đọc COD hiện có; không tự tạo khoản collected để bù dependency đó.

## Contract

`list_cod_collections(p_shipper_id uuid default null, p_order_id uuid default null,
p_statuses cod_status[] default null, p_limit integer default 20,
p_cursor text default null)` trả JSON một trang và aggregate trong cùng snapshot.

Shipper chỉ được scope `cod_collections.shipper_id = auth.uid()`; filter shipper
khác bị từ chối, không được dùng order ID/deep link để mở scope. Manager được
xem global hoặc kết hợp shipper/order/status. Vai trò lấy từ profile server;
customer không gọi endpoint này. Policy đọc COD customer đã có từ baseline
được giữ nguyên, không coi việc từ chối RPC là thu hẹp Data API của customer.

Items gồm COD amounts/status, collector/receiver IDs và timestamps hiện có.
`order_code` là UUID đơn hiện có; `order_code_source=order_uuid` nói rõ đây là
mã tham chiếu, chưa phải mã đơn ngắn của Bảo. Không join orders/returns/profiles
để mở rộng dữ liệu, không trả contact, bank, video hoặc evidence.

`counts` gồm all/uncollected/collected/received trên toàn scope shipper/order,
trước lọc status. `filtered_total` sau lọc status nhưng trước cursor/limit.
`outstanding_vnd` cộng collected_amount_vnd chỉ khi status=collected, trước
lọc status/pagination. Vì schema cấm nhận một phần, uncollected/received góp 0.
Không trừ refund hoặc phụ thuộc order/return status.

Sort `(created_at, order_id)` giảm dần; keyset cursor gắn user/role/filter,
không chứa PII và không là token quyền truy cập. Mỗi lần gọi kiểm tra lại quyền.
Không đóng băng dữ liệu giữa các trang; refresh từ đầu khi có cập nhật.
Read không nhận request_id, không ghi trạng thái/event và retry là lần đọc mới.

## Chạy local SQL

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/run_cod_list_fixture.ps1
```

Wrapper cần native PostgreSQL 17 và data directory test đã có dưới
`supabase/.temp/p011_pg_runtime` và `supabase/.temp/p011_native_data` (ignored).
Nó tạo database mới `p011_p061_cod_*`, áp migrations thật, dùng Auth/Storage SQL
stubs và chạy suites rollback; không reset/drop database, không dùng key cloud.
Server do wrapper khởi động sẽ được dừng sau kiểm thử. Đây là kiểm tra migration/
RLS trên PostgreSQL, chưa là xác minh Supabase Auth/PostgREST cloud end-to-end.

## Migration và giới hạn

Migration `supabase/migrations/20261025064829_list_cod_collections.sql` được
tạo bằng `npx --yes supabase migration new list_cod_collections` với CLI
2.122.0. Function STABLE/SECURITY INVOKER, search_path rỗng, EXECUTE chỉ cấp
authenticated; RLS/grants trên bảng hiện có giữ nguyên, không thêm definer
hoặc nới quyền đọc. Không cần index mới: full aggregates materialize tập scope
trước sort; giữ shipper_id/PK indexes đã có, không thêm order index chưa đo.

`p_statuses=null` là tất cả; mảng SQL rỗng, nhiều chiều hoặc chứa null bị
22023 INVALID_ARGUMENT. Dart query rỗng chuẩn hóa thành null; enum unknown/
UUID sai bị PostgreSQL từ chối ở bước cast (22P02). Cursor malformed/khác
user/role/filter và limit ngoài 1..100 bị 22023. Thiếu auth hoặc role/scope sai
bị 42501; anon không có EXECUTE. Các lỗi không được đổi thành danh sách rỗng
hoặc dữ liệu fixture. Chỉ query hợp lệ không có row trong scope mới trả empty.

Triển khai đọc trong repository hoàn tất local; chưa apply migration lên cloud
hoặc kiểm tra PostgREST/Auth thật. App cần migration này trước dùng adapter
mới; nếu RPC thiếu thì báo lỗi thật. Dữ liệu collected live còn phụ thuộc API
P05.1 chưa có; không phải blocker để đọc khoản hiện có, nhưng chưa nghiệm thu
được luồng giao thành công → COD live. Mã đơn ngắn riêng vẫn chờ contract Bảo;
UUID reference được đánh dấu rõ. Customer projection S3 là quyết định riêng
chưa xử lý, không ghi nhận stakeholder đã duyệt. Không triển khai UI hoặc receipt.

## Tệp thay đổi trong P06.1

- Migration trên; `supabase/tests/cod_collection_list.sql`,
  `supabase/tests/run_cod_list_fixture.ps1`, cập nhật danh sách suite trong
  `supabase/tests/run_delivery_read_fixture.mjs`.
- `lib/features/cod/domain/models/cod_collection.dart`,
  `cod_collection_query.dart`, `cod_collection_page.dart`,
  `lib/features/cod/domain/repositories/cod_repository.dart`.
- `lib/features/cod/data/models/cod_collection_dto.dart`,
  `cod_collection_page_dto.dart`,
  `lib/features/cod/data/repositories/supabase_cod_repository.dart`.
- `test/features/cod/cod_collection_page_test.dart`, `cod_repository_test.dart`,
  `cod_provider_test.dart`; cập nhật HTTP fixture COD trong
  `test/app/router/operational_navigation_test.dart` theo API mới, không sửa router.
- Hướng dẫn này, `docs/api_contracts.md`, `docs/database.md`,
  `docs/business_states.md`, `docs/screen_mapping.md`.

Tham chiếu API đã đối chiếu: [Supabase database functions](https://supabase.com/docs/guides/database/functions),
[Dart RPC](https://supabase.com/docs/reference/dart/rpc). SDK khóa hiện có
supabase_flutter 2.18.0; không đổi dependencies/lockfile.

## Validation ngày 25/10/2026

| Lệnh | Kết quả |
| --- | --- |
| `npx --yes supabase --version` | 2.122.0 |
| `npx --yes supabase migration new list_cod_collections` | Tạo tệp migration nêu trên; không apply cloud |
| `powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/run_cod_list_fixture.ps1` | Exit 0; 8 migrations áp local; 7 SQL suites PASS, assignment concurrency 2 connections PASS, cleanup PASS |
| `flutter test --no-pub test/features/cod` | 21 tests PASS |
| `flutter test --no-pub` | 205 tests PASS |
| `flutter analyze --no-pub` | No issues found |
| `dart format --output=none --set-exit-if-changed lib/features/cod test/features/cod test/app/router/operational_navigation_test.dart` | 14 files, 0 changed, exit 0 |
| `node --check supabase/tests/run_delivery_read_fixture.mjs` | Exit 0 |
| `git diff --check` | Exit 0; chỉ cảnh báo chuẩn hóa LF→CRLF |

Run SQL cuối: `p011_p061_cod_20261025135358_fe19d19d` trên PostgreSQL 17.10.
SQL suites: database_security, delivery_read_security, delivery_task_list,
delivery_task_detail, outbound_assignment, outbound_commands_dependencies,
cod_collection_list. Các test COD đọc/RPC chính dùng role authenticated thật,
anon/customer bị từ chối; chỉ seed/refund/đổi role test dùng privileged context.
Toàn bộ business data rollback và concurrency fixtures dọn sạch; native server
do wrapper mở đã dừng. Không chạy P04.1/P05.1 demo opt-in trong run này.

P06.1 **hoàn tất phần triển khai và kiểm thử local**. Chưa nghiệm thu deployment/
Auth/PostgREST cloud hoặc luồng tạo collected qua P05.1; cần áp migration theo
workflow nhóm trước dùng adapter trên backend chung. Không ghi nhận xác nhận
của Bảo/Sơn/Văn Đức chỉ từ các fixture hoặc quyết định triển khai read này.
