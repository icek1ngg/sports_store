# P10.3 — Bàn giao Delivery/COD/Maps

Mốc 29/10/2026, Minh Đức: MH10/MH11/MH12/MH18. Tài liệu này là chỉ mục trạng
thái hiện tại; các biên bản fixture-only cũ không phủ định RPC production được
triển khai sau đó. Không suy đồng thuận teammate từ quyết định trực tiếp của user.

## Khởi động và môi trường

Flutter/Dart theo pubspec: Dart `^3.13.2`, Riverpod 3.4.3, go_router 18.0.2,
supabase_flutter 2.18.0; giữ lockfile, không tự nâng dependency. Một client tại
core/supabase, router app/router, theme app/theme; MVVM feature-first.

```powershell
flutter pub get
flutter run -d chrome --dart-define-from-file=config/supabase.json
flutter build web --no-pub --dart-define-from-file=config/supabase.json
flutter build apk --debug --no-pub --dart-define-from-file=config/supabase.json
```

File cấu hình local cần hai giá trị client-safe:

```json
{"SUPABASE_URL":"https://<project-ref>.supabase.co","SUPABASE_PUBLISHABLE_KEY":"<publishable-key>"}
```

Đây là template, không chạy literal placeholder. Không thêm service_role,
sb_secret, password/JWT vào file/Dart/URL/log. Account manager/shipper cấp bởi
trusted administration; registration không được tự chọn role. Không có màn
Auth hoàn chỉnh được bổ sung bởi Minh Đức; shared bootstrap phải cung cấp
session thực. Build không có config vẫn compile được nhưng startup fail-closed.

Map đã chốt **OSM raster + Google Maps URL**, không API key. `MAP_USER_AGENT`
tùy chọn phải bắt đầu `sports_store/`, không CR/LF, default public app identity
đã có. Visible OSM attribution phải giữ; native bounded HTTP/file cache,
Web browser HTTP cache và Referer `strict-origin-when-cross-origin`. Không
prefetch/offline bulk tiles, GPS nền, store pin, route engine hoặc tính phí.
Google URL chỉ `api=1&destination=lat,lon`; Web `_self` sau async recheck,
native externalApplication, phone `tel:` mở dialer. Chi tiết license/cache và
platform: [P09.2](../demos/p092_reusable_maps_adapter.md),
[P09.4](../demos/p094_navigation_failures_access_revocation.md).

## Demo không phá dữ liệu

### A. Catalog SQL local, tự rollback

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/run_p101_sql_qa.ps1 -DemoCatalog
```

Guard chỉ PG17 loopback:55439, data_directory đúng dưới workspace `.temp`, DB
mới prefix `p011_p083_p101_*`; tên trùng phải lỗi. Không reset/drop/sharedDB.
Runtime PG17/Node `pg` phải có trong `supabase/.temp/p011_pg_runtime` và
`p011_native_data`; thiếu thì dừng, không tự chuyển cloud. Dùng cùng prerequisite
local đã mô tả [P10.1](../qa/p101_sql_security_transactions.md).

`p103_demo_catalog.sql` dùng UUID namespace `10300000-0000-4000-8000-*`:

| Vai trò/dữ liệu | Suffix | Tình huống |
| --- | --- | --- |
| Manager | 001 | Profile role manager; không password/login giả. |
| Shipper A/B | 002/003 | A xem 3 task; B có task riêng 054, A không đọc được. |
| Customers A/B | 004/005 | Đơn có customer owners riêng. |
| Outbound / pickup / redelivery | 051/052/053 | Saved Hanoi destination; outbound 550.000, hai kind kia 0. |
| COD collected / received | Orders 014/015 | B giữ collected550.000, A received550.000; held chỉ collected. |
| Error | Task054 / confirm receipt dưới shipper | Unauthorized ID không có row; shipper receipt bị 42501. |

**READ-ONLY FIXTURE:** trạng thái/đơn trực tiếp seed để demo projections, không
được dùng như proof custody/dispatch/return approval; video path fixture không
có Storage object. Không nhấn write RPC trên catalog và coi đó là operational
seed. SQL in DEMO TRACE/PASS rồi ROLLBACK, không giữ account/record cho app.
Đóng kết nối bất ngờ cũng rollback. Không cần DELETE thủ công; schema DB mới
giữ lại để chẩn đoán. Final snapshot phải chứng minh 51 bảng về baseline,
trigger enablement không đổi; wrapper dừng server chỉ nếu chính nó khởi động.

### B. Demo UI offline có nhãn

```powershell
flutter test --no-pub test/features/deliveries/integration
flutter test --no-pub test/features/deliveries/redelivery_widget_test.dart test/features/deliveries/return_pickup_widget_test.dart test/features/deliveries/delivery_task_map_page_test.dart
flutter run -d chrome -t test/core/maps/fixtures/p094_platform_probe.dart
```

Hai integration files dùng SDK/repository/ViewModel production với transport
fixture, không nối cloud. Redelivery dùng repository fixture có nhãn để giữ
authoritative reads pending; map probe chỉ public coordinate, không account.
Error cases loading/empty/timeout/network/denied/stale/launch/tiles/missingcoords
được trình diễn bằng tests, không chèn nút giả lỗi vào production screens.

### C. Demo live có scoped accounts và cleanup

Chỉ người vận hành có quyền CLI trên project cấu hình
`bqoyfytmrtvjwrpshuhh`; đọc scripts trước khi chạy, không đổi project tùy tiện.
CLI pinned 2.122.0 cần đăng nhập trực tiếp trên máy; không gửi token vào chat.

```powershell
node supabase/tests/run_live_outbound_ui.mjs --live --complete
node supabase/tests/run_live_outbound_ui.mjs --live --complete --cod
node supabase/tests/run_live_pickup_handover.mjs --live --ui --redelivery
node supabase/tests/run_live_pickup_handover.mjs --live --ui --redelivery --redelivery-failure
```

Runners tạo UUID/password ngẫu nhiên, fixture manager/shipper/customer, gọi
Auth thật/JWT và RPC; cleanup trong finally chỉ scoped IDs. Secret ở memory
cho Auth Admin, Flutter chỉ publishable+userJWT. Không debug-print argv/env.
Những runners này là **tự chạy rồi cleanup**, không seed tài khoản đăng nhập
bền cho demo thủ công. Không có “tài khoản demo chung/mật khẩu mặc định”. Nếu
process chết cưỡng bức giữa cleanup, không chạy reset hoặc xóa theo khoảng
thời gian: operator kiểm SQL tạm/log UUID còn giữ của chính run, dùng logic
cleanup trong script với đúng IDs. Runner hiện **không bảo đảm durable manifest
để resume sau kill**; nếu không khôi phục được IDs thì dừng và đối chiếu admin
audit, không đoán dữ liệu nào là fixture. Vì vậy nên dùng catalog rollback cho
demo bàn giao mặc định; crash-safe persistent live demo chưa được triển khai.

## Migration/RPC setup

Danh sách **22 migrations hiện có**, chạy tăng dần timestamp, không chỉnh file
đã deploy, không áp dụng fixture SQL như migration:

| Thứ tự | File trong supabase/migrations | Nội dung |
| --- | --- | --- |
| 1 | 20261006034251_sports_store_schema.sql | Schema nền |
| 2 | 20261006034259_sports_store_access.sql | Access/RLS nền |
| 3 | 20261006040019_simplify_sports_store.sql | Schema cuối nền |
| 4 | 20261023104903_secure_delivery_read_projections.sql | Task/item safe reads |
| 5 | 20261023153729_list_my_delivery_tasks.sql | MH10 query/counts/paging |
| 6 | 20261024010714_get_my_delivery_task.sql | MH11 authorized detail |
| 7 | 20261024070151_assign_outbound_delivery_task.sql | Manager assign |
| 8 | 20261025064829_list_cod_collections.sql | COD list/totals |
| 9 | 20261025121908_confirm_cod_received.sql | Full receipt |
| 10 | 20261026055651_accept_start_outbound_delivery.sql | Dispatch/custody/accept/start |
| 11 | 20261026062903_secure_internal_auth_identity_bridge.sql | Internal identity bridge |
| 12 | 20261026130645_complete_outbound_delivery.sql | Complete + COD |
| 13 | 20261027005254_checkout_placement.sql | Checkout reservation dependency |
| 14 | 20261027005305_hanoi_service_area.sql | Server service-area dependency |
| 15 | 20261027010030_checkout_exact_intent.sql | Checkout exact-intent dependency |
| 16 | 20261027060030_fail_outbound_delivery.sql | Failed attempt |
| 17 | 20261027062118_decide_outbound_retry.sql | Manager retry/custody/task2 |
| 18 | 20261027093919_report_delivery_handover_incidents.sql | Handover/incident reports |
| 19 | 20261027140241_delivery_reporting_context.sql | Authorized reporting context |
| 20 | 20261027142031_return_pickup_tasks.sql | Pickup assign/collect/fail |
| 21 | 20261028011128_return_pickup_store_handover.sql | Pickup handover |
| 22 | 20261028062908_p083_redelivery_production.sql | Receipt/inspection proof + free redelivery |

Local runner applies files into NEW DB and validates. Shared Supabase: trước
deploy luôn `npx --offline --yes supabase@2.122.0 migration list --linked`,
so với file inventory và remote project; dùng `db push --linked --dry-run`
để xem pending trước deploy được ủy quyền. Kiểm `--help` nếu CLI khác phiên bản.
Không reset/repair lịch sử để giấu drift; không chạy db push ở P10.3 vì không
có migration mới. Mốc 22 đã deploy theo biên bản P08.3 và live P10.2; chưa
query lịch sử cloud lại trong P10.3.

**RPC hiện hữu, không phải tên đề xuất:**

- Reads: `read_my_delivery_tasks`, `read_my_delivery_task_items`,
  `list_my_delivery_tasks`, `get_my_delivery_task`,
  `get_my_delivery_reporting_context`, `get_my_return_pickup_handover`,
  `list_cod_collections`.
- Outbound: `assign_delivery_task`, `accept_delivery_task`,
  `start_delivery_task`, `complete_outbound_delivery`, `fail_delivery_task`,
  `decide_outbound_retry`, `report_store_handover`, `report_delivery_incident`.
- Money: `confirm_cod_received`.
- Returns: `approve_return_pickup_plan`, `assign_return_pickup_task`,
  `collect_return_items`, `fail_return_pickup_task`, `report_return_pickup_handover`,
  `receive_customer_return`, `reject_return_after_inspection`,
  `assign_redelivery_task`, `accept_redelivery_task`, `start_redelivery_task`,
  `complete_redelivery`, `fail_redelivery_task`.

Chữ ký/payload/error/precondition chi tiết: [API contracts](../api_contracts.md)
và biên bản production được dẫn; không suy `fail_delivery_task` dùng được mọi
kind (pickup/redelivery có RPC riêng). `DeliveryMapReader.getMapTaskDetails`
là Dart interface tái dùng get_my_delivery_task, không RPC mới.
Inventory trên là 28 RPC thuộc delivery/COD/return primitives, không phải toàn
bộ public functions; checkout còn place_order/get_placement_result. Migration
16 replace complete_outbound_delivery, 20/22 mở rộng item projection; luôn áp
dụng toàn bộ thứ tự để không dùng nhầm definition cũ.
`receive_failed_delivery_return` và notification resolve APIs trong proposals
không tự trở thành RPC đã có chỉ vì xuất hiện trong plan.

## Audit trạng thái và owner

| Hạng mục | Implemented/integrated | Tested | Việc còn lại/owner |
| --- | --- | --- | --- |
| MH10/MH11 outbound + MH12 | Production repos/VM/UI/RPC | Local SQL + widgets + live success/COD | Failed1→task2→failed2→report mới có whole-flow fixture/SQL; chưa whole UI/JWT live. Minh Đức QA còn lại. |
| Pickup/free redelivery | Production RPC/proofs + shipper UI | Live success/failure + cleanup | MH15 UI binding thuộc Sơn, không claim screen đã nối. |
| MH18 | Task destination, map/call/copy/nav, fallback | Widget/provider, Web build; live reads gián tiếp | Android/Web OS launcher thật/recents chưa nghiệm thu; Minh Đức. 15s poll không realtime revoke. |
| Notes | Honest unavailable UI | Null/allowlist tests | Schema notes chưa có; phải chốt nguồn với orders/returns, không dùng bank/video/reason thay notes. |
| Outbound return receipt/restock | Report tách biệt receipt | Không tự restock được kiểm SQL | Manager operation/UI của Bảo/Văn Đức chưa đủ E2E; không tính thành feature shipper thiếu. |
| MH17 | Producer events/notifs + task destination guard | Events/rights/dedup SQL/live; fixture-link denied | Builder/session/repo/resolver wiring chưa bind, thuộc Bảo/Dung An; không sửa MH17 trong phase này. |
| MH16 map picker | Core coordinate/display/navigation seams | Adapter tests | Form picker + server placement thuộc Văn Đức, chưa claim đã dùng adapter. |
| P10.1/P10.2 | Tests + evidence | 17 SQL/9 concurrency, 1450 Flutter, 6 live widget runs | Chưa commit/push các thay đổi QA trong working tree. |

Owners theo AGENTS: Dung An auth/router/MH01/02/03/19; Bảo orders/MH07/08/09/17;
Văn Đức inventory/catalog/cart/checkout/MH04/05/06/16; Sơn returns/MH13/14/15/20;
Minh Đức deliveries/COD/core maps/MH10/11/12/18. Đây là phân công repository,
không phải biên bản từng người đã duyệt hoặc ký nhận handover.

Mock audit: fixtures trong test/**, SQL .fixture, probe map và preview tool là
có nhãn; application default không tự chuyển sang mock khi API lỗi. Role
builder thiếu thì unavailable, thiếu ảnh/Storage thì placeholder, missingcoords
chỉ text có quyền. Các comment/biên bản cũ “P07/P08 no live” là lịch sử;
supabase repositories hiện hữu và biên bản production mới là nguồn trạng thái.
Không xóa seams/test doubles vì grep thấy chữ unavailable.

## Acceptance NT và bằng chứng

Nguồn hiện có là plan và nhóm NT trong
[test spec §7.1](../technical_specification_mh07_mh08_mh09_mh17_tests.md).
Full report v3.0/exact từng câu NT chưa có trong repo để xác minh; **không gán
nhãn exact-NT PASS**. Bảng sau là traceability “as applicable” theo nhóm, cần
đối chiếu bản báo cáo gốc trước nghiệm thu toàn hệ thống:

| IDs yêu cầu | Bằng chứng phạm vi Minh Đức | Giới hạn |
| --- | --- | --- |
| NT02 | 520.000+30.000=550.000; SQL completion/assignment/COD, live P10.2 | Checkout Hà Nội/oversell/đặt đơn thuộc Văn Đức; không chứng minh full NT02 gốc. |
| NT08–NT11 | accept/start/result, 2 attempts, same custody, no double dispatch, full COD | Manager failed-return receipt/inspection/restock E2E còn dependency. |
| NT12, NT15–NT18 | Pickup actual full items, separate handover/receipt, free redelivery, denied/duplicate, COD không offset refund | Customer video/bank/refund evidence/submission window/UI MH13–15 thuộc Sơn. |
| NT24 | Events/notif recipients/dedup + UUID-only destination recheck | MH17 inbox/resolve production wiring thuộc Bảo; chỉ target guard fixture PASS. |
| NT25–NT26 | Ba kind saved destination/current authorization, fallback, no GPS tracking | NT25 đã được user đổi từ store pin sang task destination; Android launcher/instant revoke chưa complete. |

[P10.1 exact commands/results](../qa/p101_sql_security_transactions.md),
[P10.2 exact commands/results](../qa/p102_flutter_integration_tests.md).
28/10: full Flutter concurrency=1 **1450 PASS/4 skipped**, analyze sạch, Web
PASS; default concurrent run FAIL OOM được ghi riêng; **6 live network widget
runs PASS + cleanup**. Không nói số cũ là lượt chạy mới P10.3.

29/10 P10.3 đã chạy:

```powershell
node --check supabase/tests/run_delivery_read_fixture.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/run_p101_sql_qa.ps1 -DemoCatalog
git diff --check
```

**PASS** PG17.10/22 migrations/**18 SQL suites** + 9 concurrency modules,
DEMO TRACE, 51-table baseline/trigger cleanup. Lượt DB
`p011_p083_p101_20261029000553_0788f884`; log ignored `supabase/.temp/p103_demo.log`.
Không có Dart/pubspec đổi trong P10.3 nên không chạy lại Flutter build/tests
chỉ để nhân đôi kết quả; lệnh build/format/analyze/full tests đã bàn giao ở trên.

P10.3 hoàn thành artifacts/fixture/documentation/handover theo phạm vi, **không
nghĩa toàn bộ product/device/dependency đã nghiệm thu**. Không migration mới,
không deploy/permission changes, không commit/push hoặc gửi cho teammate ở
lượt này. `output/`, `outputs/`, artifact MH09 và changes QA trước được giữ riêng.

Audit độc lập xác nhận inventory/NT source boundaries; review không có blocker
cleanup. Đã bổ sung assertion exact role counts/task owner/kind/amount, quyền
shipper B/task054 và trạng thái COD; trace tiền tính từ rows, không literal.
Wrapper đã chạy lại PASS sau hardening này.
