# P07.5 — MH11 báo bàn giao và sự cố outbound

Phạm vi theo quyết định người dùng ở P07.4: **outbound trước**. Hai mutation
production `report_store_handover` / `report_delivery_incident` giữ nguyên chữ ký.
Không triển khai pickup/redelivery khi chưa có contract custody của Sơn.

## Giao diện và nguồn dữ liệu

MH11 dùng `DeliveryReportingViewModel` → `DeliveryReportingRepository` → shared
Supabase client. Không gọi Supabase từ widget, không tạo router/theme/client mới.
Hai thao tác dùng context server, không suy ra quyền bàn giao từ chữ `failed`
hoặc coi assignment là đã nhận hàng. Màn restricted vẫn có thể hiện báo cáo nếu
người dùng hiện là holder có chứng cứ custody hợp lệ.

- Bàn giao: xác nhận toàn bộ item/variant/số lượng từ snapshot custody; gửi chỉ
  `order_item_id`, `quantity`, task UUID và request UUID. Thông báo rõ **shipper
  báo bàn giao chưa phải chủ cửa hàng nhận, kiểm tra hoặc nhập lại tồn**.
- Sự cố: chọn `damaged`/`lost`/`other`, bắt buộc lý do cho mọi loại; cho biết
  chủ cửa hàng nhận thông báo. Không dùng dialog giao thất bại thông thường.
- Request UUID/payload giữ nguyên khi timeout hoặc ACK không chắc chắn; không
  tự coi thành công, không đổi sang request mới để né conflict. ACK hợp lệ mới
  mở bước đọc lại context/MH11/MH10. Lỗi đọc sau ACK chỉ thử lại phần đọc.
- Reports không đổi task/order/COD/attempt/stock; bàn giao đã báo được phản ánh
  bằng marker từ server. Chặn gửi trùng/xung đột, xóa dữ liệu khi đổi tài khoản.

## API đọc bổ sung, không mở quyền đọc bảng

Migration tạo bằng CLI 2.122.0:
`20261027140241_delivery_reporting_context.sql`.

`get_my_delivery_reporting_context(p_task_id uuid) → jsonb`, authenticated
shipper duy nhất; manager/customer/anon và task không thuộc assignment hiện tại
bị từ chối. Owner là role nội bộ P07.4 không LOGIN/SUPERUSER/BYPASSRLS;
`search_path=''`, chỉ authenticated có EXECUTE. Không thêm table grants/RLS
cho client; helper riêng không có client EXECUTE.

| Trường | Kiểu / ý nghĩa |
| --- | --- |
| `task_id`, `task_status` | UUID được yêu cầu, enum task đã đọc lại |
| `order_status` | Enum hoặc null nếu context không hợp lệ/cũ |
| `can_handover`, `can_incident` | Boolean sau kiểm tra P07.4 custody/state và COD holder |
| `handover_reported` | Có report server cho order/holder trong context hợp lệ |
| `handover_block_reason`, `incident_block_reason` | Null hoặc `STATE_CONFLICT` / `CUSTODY_UNRESOLVED` / `ITEMS_MISMATCH` |
| `items` | Chỉ khi có quyền bàn giao chưa báo; từng row `order_item_id`, `product_name`, `variant_label` nullable, `quantity` int32 dương |

Không trả order UUID, holder/customer ID, contact/address, giá, ngân hàng,
refund/evidence, Storage URL hoặc item của task khác. Task cũ có attempt mới hơn:
flags false, items rỗng, order_status null; dùng task mới nhất cho UI. Missing/
mismatched COD holder cũng fail closed, không hiện nút mà mutation chắc chắn từ chối.

Read giữ profile share, cùng advisory order lock với P04/P05/P07, rồi order →
tasks theo UUID → COD share. Dùng lại validator P07.4, chỉ chuyển các lỗi nghiệp
vụ đã biết thành flags; lỗi quyền/SQL không bị nuốt. Không ghi event/notification
hay trạng thái. RPC ghi vẫn kiểm tra lại tất cả điều kiện trong transaction.

## Kiểm chứng

SQL bổ sung vào `supabase/tests/delivery_reporting_production.sql`, dùng real
assignment/accept/start/failure/manager-decision RPC, fixture-seed chỉ dữ liệu
đầu vào và rollback cuối suite. Bao gồm exact whitelist/minimal items, accepted
incident-only, assigned chưa custody, lost chặn handover, post-report vẫn failed,
cancelled task2, old task1 khi task2 accepted/cancelled, missing/mismatched COD,
reassignment, manager/unknown ID/unauthenticated/unsupported-kind denial và ACL.

Đã chạy:

- `node supabase/tests/run_delivery_reporting_production.mjs p011_p075_context_20261027_d`:
  19 migrations + SQL PASS/ROLLBACK + reporting concurrency PASS.
- `node supabase/tests/run_delivery_read_fixture.mjs p011_p075_regression_20261027_final`:
  19 migrations, 14 SQL suites, 7 concurrency suites PASS, fixture cleanup sạch.
- `npx --offline --yes supabase@2.122.0 db push --linked --dry-run`:
  chỉ migration context mới; `db push --linked --yes`: đã áp dụng trên
  `bqoyfytmrtvjwrpshuhh`.
- `npx --offline --yes supabase@2.122.0 db query --linked --file supabase/tests/delivery_reporting_production.sql`:
  cloud PASS/ROLLBACK, gồm các assertions P07.5.
- `npx --offline --yes supabase@2.122.0 migration list --linked`:
  19 local = 19 remote.
- `npx --offline --yes supabase@2.122.0 db advisors --linked --type security --level error --fail-on error`:
  exit 0, no issues found ở mức error.
- `flutter test --no-pub test/features/deliveries/delivery_reporting_repository_test.dart test/features/deliveries/delivery_reporting_production_test.dart --reporter expanded`:
  **30 PASS**. Dùng production repository/VM/widgets với scripted adapters
  chỉ trong tests; không runtime demo fallback.
- `flutter test --no-pub --reporter expanded`: **420 PASS, 2 opt-in live skipped**.
- `flutter analyze --no-pub`: No issues found.
- `dart format` trên 10 Dart files trong manifest: PASS (1 file test được format
  lại ở lượt cuối). `git diff --check`: exit 0, chỉ cảnh báo LF/CRLF;
  `node --check supabase/tests/run_delivery_read_fixture.mjs` và
  `node --check supabase/tests/run_delivery_reporting_production.mjs`: PASS.

Independent review đã sửa các lỗi stale-task projection, missing COD eligibility,
same-user refresh reconciliation, dialog gate và stale-read-error race. Review
cuối không còn finding cần sửa. Tests bao phủ server flags/kinds, task2 cancelled,
full item confirmation, damaged/lost/other + reason, safe API errors, stable retry,
post-ACK read-only retry, late ACK/account switch, same-user refresh, gate và race.

Cloud audit sau suite: fixture Auth users/orders/reporting requests/handovers
prefix `07450000` đều bằng 0. Native PostgreSQL dùng
Auth/Storage SQL stubs; cloud SQL dùng claims trong transaction. Hai loại đó
không thay cho nghiệm thu ứng dụng bằng JWT thật trên thiết bị.
Native test server đã dừng; giữ database audit, không reset/drop.

## Files thay đổi

- `lib/features/deliveries/domain/models/delivery_reporting.dart`,
  `domain/repositories/delivery_reporting_repository.dart`.
- `lib/features/deliveries/data/models/delivery_reporting_dto.dart`,
  `data/repositories/supabase_delivery_reporting_repository.dart`.
- `lib/features/deliveries/presentation/view_models/delivery_reporting_providers.dart`,
  `delivery_reporting_view_model.dart`, `widgets/delivery_reporting_action.dart`,
  `pages/delivery_task_detail_page.dart`.
- `test/features/deliveries/delivery_reporting_repository_test.dart`,
  `delivery_reporting_production_test.dart`.
- Migration và SQL suite nêu trên; bốn shared contract docs và tài liệu này.

Không đổi dependencies/router/theme/shared Supabase client. Giữ nguyên
`outputs/` không liên quan. Migration đã deploy; trạng thái source được theo dõi
trong lịch sử Git của nhánh `duc`.

## Giới hạn

**Hoàn tất P07.5 cho nhánh outbound đã chốt**, source nối RPC production và API
context đã deploy. Chưa tuyên bố nghiệm thu UI/JWT thật trên thiết bị ở lượt này.

Pickup/redelivery vẫn chặn theo D8/D9, không tạo demo success để đi vòng. Manager
receipt/quality inspection/restock/compensation và giải quyết damaged/lost thuộc
contract riêng, không tự đóng bởi report. MH17 renderer do Bảo phụ trách chưa
nghiệm thu trong phase này. Không thay business state hoặc làm phase tiếp theo.
