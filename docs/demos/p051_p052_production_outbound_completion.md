# Nghiệm thu P04.2 và production P05.1 → P05.2

Cập nhật 26/10/2026. Tài liệu này thay thế kết luận fixture-only/live BLOCKED
trong các handoff P05 trước đây cho **giao đi thành công**. Failure, quyết định
giao lần hai, trả hàng và MH18 không được coi hoàn tất từ kết quả này.

## Quyết định và phạm vi

Người dùng đã chốt trong hội thoại: RPC nhận task/request UUID, xác nhận đã
giao đủ hàng và tiền thực thu; số tiền là lời xác nhận, không là nguồn tính
COD. Ledger completion riêng; event `delivery_completed`; thông báo khách sở
hữu đơn và toàn bộ manager hiện tại; dữ liệu liên kết chỉ UUID, không điện
thoại/địa chỉ. Đây là quyết định của người dùng, **không tuyên bố Bảo đã duyệt**.

P04.1 custody đã chốt: lần hai chỉ cùng shipper còn giữ đủ hàng, không xuất kho
lần nữa. P05 không tạo task2, không tăng attempt, không triển khai failure RPC.

## API thực đã deploy

```text
complete_outbound_delivery(
  p_task_id uuid,
  p_request_id uuid,
  p_received_all_items boolean,
  p_collected_amount_vnd bigint
) → jsonb
```

Chỉ `authenticated` có EXECUTE; server xác định `auth.uid()` qua private bridge
và role từ profiles, chỉ shipper hiện được gán được hoàn thành. Manager/khách/
shipper khác bị từ chối kể cả gọi trực tiếp. Không nhận shipper ID/order total
từ client. Anonymous/service-role không được grant EXECUTE RPC này.

Response chính xác:

| Trường | Kiểu/giá trị |
| --- | --- |
| task_id, order_id, event_id, request_id | UUID |
| operation | `complete` |
| task_status, order_status | `delivered` |
| attempt_number, delivery_attempt_count | integer 1 hoặc 2, bằng nhau |
| collected_amount_vnd | bigint, tổng COD server đã đối chiếu |
| completed_at | timestamptz server |

Preconditions: outbound in_transit, accepted_at/started_at đã ghi, chưa có
result cho task/order-attempt, order delivering với count khớp task attempt;
custody đúng shipper/task/attempt và dispatch proof khớp đầy đủ items/movements.
Proof bị sửa, thiếu movement hoặc sự cố damaged/lost sau start đều chặn.
`received_all_items` phải true. Task amount = order total = COD expected = số
tiền thực thu; COD phải uncollected sạch, đúng holder. Ví dụ 520.000 tiền hàng
+30.000 phí = 550.000; thiếu/thu một phần không chuyển trạng thái.

Transaction: khóa profile role, advisory request theo actor/request và advisory
order; khóa row **order → task → COD**; recheck assignment/state/proof dưới
khóa. Ghi một delivery_attempts success, task/order delivered, COD collected
đúng full server amount/by/at, event, notifications và hai private ledgers trong
cùng transaction. Không ghi received/handed_over, không nhập/xuất thêm tồn.
Một lỗi muộn phải rollback tất cả; không dùng nhiều request Flutter ghép tiền.

Replay cùng actor/request/payload trả ACK đã lưu sau khi recheck actor và task
assignment. Mismatch trả `IDEMPOTENCY_CONFLICT`. Request mới cho attempt đã kết
thúc bị `STATE_CONFLICT`; không trả thành công giả. Khóa order serialize với
outcome khác tuân cùng thứ tự khóa. Future failure RPC chưa được triển khai;
test contender failure được ghi rõ chỉ thuộc test.

| SQLSTATE | Marker/ý nghĩa |
| --- | --- |
| 42501 | AUTH_REQUIRED, PERMISSION_DENIED, NOT_FOUND_OR_FORBIDDEN |
| 22023 | INVALID_ARGUMENT: null UUID, false/null attestation, null/nonpositive amount |
| PT409 | STATE_CONFLICT, IDEMPOTENCY_CONFLICT, AMOUNT_MISMATCH |
| PT409 từ proof validator | CUSTODY_UNRESOLVED, ITEMS_MISMATCH/dispatch evidence conflict theo P04.1 |
| Lỗi vận chuyển/5xx/ACK không xác minh | Kết quả chưa xác định; giữ envelope/request ID, không suy ra thất bại commit |

Event dùng schema có sẵn, **không có cột event_type mới**: subject_type=
delivery_task, subject_id=task_id, from_state=in_transit, to_state=delivered,
reason=`delivery_completed`, actor/task/request/time server. Notification có
subject_type=delivery_task, subject_id=task UUID và event_id; title/body chung,
không chứa PII. Unique recipient/event chống lặp. Renderer/deep link MH17 vẫn
thuộc Bảo, phải xử lý theo role và recheck quyền; không chuyển khách/manager
vào route shipper chỉ vì có UUID. Chưa nghiệm thu giao diện MH17 trong phase này.

## Schema và quyền

CLI thực: `npx --yes supabase@2.122.0 migration new complete_outbound_delivery`
trả `20261026130645_complete_outbound_delivery.sql`. Bản tên thủ công ban đầu
đã được thay trước deploy. Migration thêm:

- `private.outbound_completion_requests`: PK(actor_id,request_id), operation,
  task/order, attestation, claimed amount, payload_hash, ACK, created_at.
- `private.outbound_completion_results`: PK(task_id), unique(order_id,attempt),
  unique event/request, actor, server amount/time và ACK.
- Hai ledger bật/force RLS, append-only; không client/service-role read/write.
- Internal writer `sports_store_outbound_completion_writer`: NOLOGIN,
  NOINHERIT, NOBYPASSRLS; policies/grants giới hạn cho transaction completion,
  không membership client. Security definer có search_path rỗng, identity,
  role/preconditions bắt buộc. Không nới general order/item/Auth/Storage reads.

## UI và cache

MH11 dùng repository/ViewModel/Riverpod và theme Nike chung. Chỉ outbound
current in_transit attempt1/2 có accepted/start timestamps và full amount mới
cho xác nhận. Dialog hiển thị COD backend không sửa được và yêu cầu hai checkbox:
khách nhận đủ hàng, đã thu đủ COD. Không mutation khi mở trang/hủy dialog.
Double tap có one-shot dialog guard, không pop luôn route MH11. Snapshot/session
đổi thì đóng/redact xác nhận cũ.

UUID request được tạo khi xác nhận hợp lệ; SDK auto retry tắt. Timeout/network/
backendUnavailable/malformed ACK giữ key. Retry sau ACK chỉ đọc lại; không tạo
write thứ hai. Refresh token cùng user giữ envelope; logout/account switch xóa
pending và bỏ response cũ. Key chỉ sống trong tiến trình, không lưu qua restart;
mở lại đọc trạng thái server trước khi thao tác. Ẩn route không tự gửi mutation.

Sau ACK phải đọc projection MH11 authoritative delivered, refresh MH10 giữ
filters và invalidate COD reads. Cache lỗi có retry đọc, không fake money/state.
Controller được page giữ qua loading/history để không tự coi refresh là rời
route; history chỉ hiển thị kết quả/retry đọc, không mở mutation. Cũng sửa vòng
refetch lặp của P04.2 khi request thật chậm, có regression widget test.

Gọi điện chỉ mở `tel:` composer bằng url_launcher, không tự gọi, không xin
CALL_PHONE. Chặn scheme/query/USSD; kiểm tra snapshot/session trước khi mở,
thông báo khi thiết bị không hỗ trợ. `url_launcher 6.3.3` vốn là transitive,
được khai báo direct dependency; không nâng cấp các package khác.

## Lệnh và kết quả nghiệm thu

- `powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/run_outbound_accept_start.ps1`:
  PASS trên PostgreSQL17.10 cô lập; **12 migrations, 14 SQL suites, 4 nhóm
  concurrency**. DB cuối `p011_p041_production_20261026202435_6d8ec1cb`, dữ liệu
  test rollback/cleanup, DB giữ để audit. Auth/Storage native là SQL stubs.
- `npx --yes supabase@2.122.0 db push --linked --dry-run`: chỉ một migration P05.
  `npx --yes supabase@2.122.0 db push --linked --yes`: migration trên đã deploy
  project `bqoyfytmrtvjwrpshuhh`. `migration list --linked`: **12 local=12 remote**.
- `npx --yes supabase@2.122.0 db query --linked --file supabase/tests/outbound_completion_production.sql`:
  PASS và ROLLBACK. Thêm 8 scoped cloud suites (internal_auth_identity,
  outbound_accept_start, delivery_read_security, delivery_task_list,
  delivery_task_detail, outbound_assignment, cod_collection_list, cod_receipt): PASS.
  Cloud SQL claims là set_config, được bổ sung bằng JWT thật bên dưới.
- `node supabase/tests/run_live_outbound_ui.mjs --live`: P04.2 PASS.
- `node supabase/tests/run_live_outbound_ui.mjs --live --complete`: **PASS real
  Auth/password JWT + Flutter widget + production repositories + cloud RPCs**:
  manager assign; wrong shipper/detail/accept denied; manual accept/start;
  full550.000 confirmation; authoritative MH11 delivered/MH10 Completed;
  COD held0→550.000; stock5→4/reserved1→0; count1/result1; replay không tạo thêm
  event/result; wrong-shipper completion denied; other shipper held0; exact
  customer+manager generic notifications. Test accounts/data đã cleanup.
- `flutter test --no-pub`: **358 PASS, 1 live test skipped** (opt-in live chạy
  riêng ở lệnh trên). `flutter analyze --no-pub`: No issues found.
- `dart format` tệp Dart liên quan và `git diff --check`: PASS.
- `flutter build web --dart-define-from-file=config/supabase.json`: PASS, build/web.
  Có cảnh báo font CupertinoIcons thiếu vốn ngoài phạm vi; build exit0.

Trong quá trình chạy đã sửa lỗi harness chọn thiết bị/scroll/button type/
fake-async teardown/COD provider family, và lỗi expectation notification3 cố
định trên cloud có thêm manager test. Test hiện so recipient với toàn bộ manager
hiện tại. Không sửa quyền hoặc xóa catalog để ép PASS. Các lượt lỗi/gián đoạn
đều cleanup đúng UUID test; kết quả PASS là các lượt chạy lại sau sửa.

Kiểm tra cloud sau cleanup: profiles=0, orders=0, notifications=0,
completion_requests/results=0, live test Auth users=0; products=3 giữ nguyên.
Native PG test server của workspace đã dừng sau nghiệm thu, không drop/reset DB.

Live harness dùng Auth Admin server-only để tạo tài khoản test auto-confirm
(không gửi mail), secret chỉ trong RAM của Node; không vào file/log/Flutter.
Flutter chỉ nhận tài khoản thử qua environment, dùng publishable key/JWT thật.
Cleanup đúng UUID sinh ngẫu nhiên trong transaction; chỉ tạm ngừng USER trigger
append-only của ledger để dọn fixture rồi bật lại trước commit; không tắt RLS/FK.
Không reset database. Không dùng service key làm caller mutation nghiệp vụ.

## Manifest và giới hạn

Mã/runtime mới: migration trên; delivery `data/models/outbound_completion_ack_dto.dart`,
`data/repositories/supabase_outbound_completion_repository.dart`,
`data/repositories/platform_delivery_phone_dialer.dart`,
`domain/models/outbound_completion_command.dart`, `outbound_completion_failure.dart`,
`domain/repositories/outbound_completion_repository.dart`, `delivery_phone_dialer.dart`,
`presentation/view_models/outbound_completion_providers.dart`,
`outbound_completion_view_model.dart`, `presentation/widgets/outbound_completion_action.dart`,
`delivery_call_action.dart`; tích hợp `presentation/pages/delivery_task_detail_page.dart`;
`pubspec.yaml`, `pubspec.lock`.

Kiểm thử mới/cập nhật: `supabase/tests/outbound_completion_production.sql`,
`outbound_completion_production_concurrency.mjs`, `run_outbound_completion_production.mjs`,
`run_delivery_read_fixture.mjs`, `internal_auth_identity.sql`, `run_live_outbound_ui.mjs`;
`test/live/live_outbound_ui_test.dart`; delivery tests `outbound_completion_production_test.dart`,
`outbound_completion_repository_test.dart`, `outbound_completion_action_test.dart`,
`delivery_call_action_test.dart`, `outbound_task_actions_page_test.dart`,
`delivery_task_detail_page_test.dart`; bốn docs contracts và handoff này.

P04.2/P05.1/P05.2 hoàn tất production theo phạm vi trên và đã xác minh real
network/JWT. Live UI là widget runner trên máy, **không phải điện thoại vật lý**;
chưa nghiệm thu native phone composer hay UI MH17. MH18 và các mutation P07/
returns không thuộc lượt này. Không commit/push Git trong lượt này.

Tham khảo API đã kiểm tra: [Auth Admin createUser](https://supabase.com/docs/reference/javascript/auth-admin-createuser),
[password login](https://supabase.com/docs/reference/javascript/auth-signinwithpassword),
[url_launcher](https://pub.dev/packages/url_launcher).
