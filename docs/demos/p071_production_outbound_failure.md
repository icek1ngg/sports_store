# P07.1 — Ghi kết quả giao outbound thất bại

Ngày: 27/10/2026. **Backend P07.1 hoàn tất và đã deploy** project
`bqoyfytmrtvjwrpshuhh`; SQL cloud PASS/ROLLBACK. Phạm vi chỉ backend outbound; không bật dialog MH11
(P07.3), không tạo lần giao hai/hoàn sớm (P07.2), không báo bàn giao/sự cố
(P07.4). Tài liệu này thay các blocker P04/P05 đã lỗi thời trong
`p071_outbound_failure_boundary.md`; không xóa lịch sử kiểm thử fixture.

## Nghiệp vụ và quyền

Người dùng làm rõ manager là chủ cửa hàng duy nhất. Thông báo thất bại gửi
chủ cửa hàng qua profile có role `manager`, không gửi khách. Không thêm
constraint singleton profile hoặc tự thay đổi tài khoản của đồng đội.
Không tuyên bố Bảo/Văn Đức đã duyệt trong hội thoại.

| Lần giao | Tiền điều kiện server | Kết quả nguyên tử |
| --- | --- | --- |
| 1 | Shipper hiện tại; outbound `in_transit`; order `delivering`; count=attempt=1; chưa result; custody/dispatch hợp lệ; COD sạch `uncollected` | Một result `failed`, task `failed`/giờ kết thúc; order `awaiting_redelivery`; chờ manager quyết định |
| 2 | Cùng điều kiện, count=attempt=2; lần 1 đã thất bại; cùng shipper còn giữ hàng | Một result `failed`, task `failed`/giờ kết thúc; order `awaiting_store_return` |

Không tăng/reset bộ đếm, không thu/xóa COD, không dispatch/restock,
không tạo task mới hoặc ghi manager receipt/inspection. Dữ liệu retry lần hai
trong SQL tests là fixture có nhãn; không chứng minh P07.2 đã production.
`return_pickup` và `redelivery` bị từ chối, không suy đoán D8/D9.

## Contract

RPC đã triển khai `fail_delivery_task(p_task_id uuid,p_request_id uuid,
p_reason_code text,p_description text DEFAULT NULL) → jsonb`.
Chỉ nhận task/key/lý do; không nhận actor, tiền, count, trạng thái hay giờ client.

Reason code: `unreachable`, `reschedule`, `bad_address`, `refusal`, `other`.
`other` cần mô tả không chỉ whitespace. Nội dung mô tả không đi vào notification.
Server giữ mã và mô tả riêng; chuỗi reason cũ vẫn phục vụ schema/read tương thích.

Mã và mô tả được trim whitespace hai đầu; mô tả trống thành NULL. Fingerprint
và đối chiếu từng trường dùng cùng giá trị chuẩn hóa. Legacy
`delivery_attempts.reason`/`delivery_tasks.failure_reason` = code hoặc
`code: description`; không dùng chuỗi legacy để phân tích ngược code.

ACK gồm task_id/order_id, operation=`fail`, task_status=`failed`, order_status,
attempt_number/delivery_attempt_count, failure_reason_code/description,
failed_at/event_id/request_id. ACK là kết quả command, không thay snapshot đọc
có kiểm tra quyền; adapter/UI P07.3 sau này cần refetch authoritative.

| SQLSTATE / marker | Ý nghĩa |
| --- | --- |
| `42501 / AUTH_REQUIRED` | Không có identity |
| `42501 / PERMISSION_DENIED` | Profile không còn role shipper |
| `42501 / NOT_FOUND_OR_FORBIDDEN` | Task không thuộc current shipper/outbound, không lộ sự tồn tại ID khác |
| `22023 / INVALID_ARGUMENT` | Thiếu UUID, code sai hoặc other không có mô tả |
| `PT409 / IDEMPOTENCY_CONFLICT` | Cùng actor/key khác target/payload hoặc dùng lại key giữa fail/complete |
| `PT409 / STATE_CONFLICT` | Không còn in_transit/delivering, count sai hoặc đã có result |
| `PT409 / AMOUNT_MISMATCH` | Task/order không khớp server COD |
| `PT409 / COD_CONFLICT` | COD không sạch uncollected/không thuộc shipper/expected không khớp |
| `PT409 / ATTEMPT_LIMIT` | Lần2 không có kết quả thất bại lần1 đúng người giữ hàng |
| `PT409 / CUSTODY_UNRESOLVED` | Không có custody/holder/dispatch proof hợp lệ |

Proof validator P04 có thể trả thêm lỗi proof/inventory hiện có; không đổi
thành success hoặc sửa tồn để vượt kiểm tra.

## Transaction, khóa và idempotency

Role lấy từ profiles server, không user_metadata. Request lock theo actor/key
dùng cùng namespace completion; sau đó advisory order và row locks
order → task → COD. Recheck current assignee dưới khóa trước replay. Cùng
actor/key/payload chuẩn hóa trả nguyên ACK; mất quyền thì không replay. Key
khác sau kết quả trả conflict. Thiếu state/custody/COD không ghi ledger success.

Failure dùng hai private ledgers append-only/force RLS: requests PK actor/key,
results PK task và unique order/attempt, actor/key, event. Client không được
đọc/ghi. Server sinh event UUID riêng (business_events.request_id=event_id);
client key chỉ lưu trong ledger, tránh unique event toàn cục làm hai actor
trùng client UUID bị xung đột.

Migration giữ nguyên function completion P05, ngoài một guard đọc failure
ledger sau authorization/khóa và trước xử lý result: cùng key đổi outcome
luôn IDEMPOTENCY_CONFLICT. Policy đọc chéo hai ledger chỉ cho internal writer
và đúng actor. Không tạo public helper hoặc dùng trigger postgres để bypass RLS.
Các key khác nhau vẫn cạnh tranh result và chỉ một transaction thắng.

Failure writer NOLOGIN/NOINHERIT/NOBYPASSRLS, EXECUTE RPC chỉ authenticated,
search_path rỗng, identity bridge nội bộ. COD chỉ có UPDATE(order_id) để khóa;
WITH CHECK(false) chặn UPDATE thật. Không thêm client quyền order/items/return/
bank/refund/Storage. Không có writes stock hoặc tiền.

## Đồng bộ migration checkout từ cloud

Kiểm tra `migration list --linked` ngày 27/10/2026 cho thấy cloud có ba
migration chưa có trong local hoặc cây migration của `origin/duc`/`origin/main`
vừa fetch:

| Version | Tên cloud |
| --- | --- |
| `20261027005254` | `checkout_placement` |
| `20261027005305` | `hanoi_service_area` |
| `20261027010030` | `checkout_exact_intent` |

Đã khôi phục nguyên SQL trong `supabase_migrations.schema_migrations.statements`
về đúng version/tên file. Không sửa nghiệp vụ checkout, repair/reset lịch sử
hoặc giả tạo migration rỗng. MD5 nguồn (bỏ newline cuối file) local=cloud:
`e749b529b9c2c7ab8a1d03497e0b391a`,
`6d4897fbd7ef2f625fc82b4aff32611d`,
`116d993470569dd6e50a96ab616d960d`, theo thứ tự bảng trên.
Đây là phục hồi source dependency đã deploy, không tuyên bố triển khai hoặc
nghiệm thu lại checkout. Chuỗi hợp nhất cần kiểm thử trước deploy P07.1.
Các kiểm thử native không được gọi là nghiệm thu Auth/PostgREST/cloud thật.

## Kiểm thử và deploy

- `node supabase/tests/run_outbound_failure_production.mjs`: PASS trên native
  PG17.10, DB `p011_p071_production_1793081322725`; sau đó đã mở rộng test và
  chạy lại toàn bộ regression bên dưới. Runner chỉ nhận workspace PG17 native,
  tạo DB mới prefix p011_, không reset/drop DB cũ.
- `node supabase/tests/run_delivery_read_fixture.mjs p011_p071_regression_20261027_final4`:
  **PASS**, 16 migrations, 14 SQL suites PASS/ROLLBACK và 5 nhóm concurrency.
  Bao gồm ACL/owner/search_path/force RLS/no client ledger grants, first/second
  failure, standard reason không cần mô tả, other whitespace, current actor/
  role/state/custody/COD/amount rejection, rollback sau late notification fault,
  replay/mismatch, cross-operation key, fail/complete thật cả hai thứ tự với
  key giống/khác, hai shipper trùng client UUID độc lập. Fixture task2 được
  seed rõ ràng, chưa phải manager retry production.
- `npx --offline --yes supabase@2.122.0 db push --linked --dry-run --skip-vault`:
  chỉ pending migration P07.1; không đẩy lại ba migration checkout.
- `npx --offline --yes supabase@2.122.0 db push --linked --yes --skip-vault`:
  **PASS**, áp dụng `20261027060030_fail_outbound_delivery.sql`.
- `npx --offline --yes supabase@2.122.0 db query --linked --file supabase/tests/outbound_failure_production.sql`:
  **PASS/ROLLBACK** trên cloud.
- `npx --offline --yes supabase@2.122.0 db query --linked --file supabase/tests/outbound_completion_production.sql`:
  **PASS/ROLLBACK**, hồi quy completion sau thêm guard.
- `npx --offline --yes supabase@2.122.0 migration list --linked`:
  **16 local=16 remote**.
- `flutter analyze --no-pub`: **No issues found**.
- `flutter test --no-pub`: **358 PASS, 2 opt-in live tests skipped**.
- `node --check` ba runner/module JS liên quan và `git diff --check`: PASS.
  Không đổi Dart/dependency trong P07.1, không có Dart mới cần format/pub get.

Lượt regression đầu gặp fixture store_settings insert trùng seed Hanoi của
checkout; sửa test thành UPSERT trong transaction rollback, không sửa seed
đồng đội. Lượt tiếp gặp fixture cũ cố khẳng định public fail RPC không tồn tại;
runner đã thay suite dependency cũ bằng suite production, giữ file lịch sử.
Lượt final4 là kết quả sau các sửa trên. Không dùng kết quả lỗi làm PASS.

Cloud cleanup: Auth/order fixture prefixes P071/P051 = 0,
failure requests/results = 0, 3 products có sẵn giữ nguyên. Native fixture
cleanup không còn users/profiles/orders/tasks/COD/ledgers/Storage test.
Native server dừng sau nghiệm thu, các DB audit được giữ lại.

Advisors trước/sau deploy không có ERROR; INFO checkout private table RLS/no
policy có sẵn được giữ nguyên. WARN authenticated SECURITY DEFINER tăng11→12
do RPC mới được gọi có chủ đích; quyền được giới hạn bằng internal role/RLS/
identity/assignment tests, không revoke RPC cần dùng hoặc mở quyền bảng để
làm mất cảnh báo. Tham khảo [advisory SECURITY DEFINER](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)
và [RLS no policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

## Manifest và giới hạn

Mới: migration P07.1; `supabase/tests/outbound_failure_production.sql`,
`outbound_failure_production_concurrency.mjs`, `run_outbound_failure_production.mjs`;
tài liệu này. Cập nhật runner regression, fixture database_security và bốn
contract docs. Khôi phục ba migration checkout nguyên nguồn như mục trên.
Các thay đổi P06 chưa commit và thư mục outputs được bảo toàn.

Backend P07.1 đã hoàn tất theo acceptance SQL và deploy; chưa nghiệm thu
real Auth/JWT qua app hoặc điện thoại trong lượt này. SQL cloud dùng claims
có kiểm soát trong transaction test; concurrency chạy hai connection native.
Nối repository/ViewModel/dialog là P07.3, chưa thực hiện. P07.2/P07.4 và MH17
renderer của Bảo vẫn độc lập. Không commit/push trong lượt P07.1.
