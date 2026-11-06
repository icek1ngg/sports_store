# Audit Supabase và đường đi dữ liệu thực tế

Ngày audit: 26/10/2026, Asia/Saigon. Chỉ đọc source/config an toàn và chạy probe GET không đọc bản ghi. Không đăng nhập/tạo tài khoản, không SQL test, migration, thay RLS, upload, mutation hoặc thao tác production data.

## A. Kết luận kết nối

**Supabase có cấu hình thật, có khởi tạo SDK và client provider dùng chung. Probe runtime mới xác minh endpoint Auth/PostgREST nhận publishable key. Chưa có business repository production nối tới client, chưa có dữ liệu nghiệp vụ thật đi vào bốn màn.**

| Lớp đánh giá | Trạng thái | Bằng chứng và giới hạn |
|---|---|---|
| Supabase endpoint/client key | VERIFIED CONNECTED, chỉ phạm vi endpoint probe | GET Auth settings HTTP 200; Data API probe limit=0 HTTP 404/PGRST205 mong đợi; log mới và script hiện tại |
| App SDK initialization/DI | CONFIGURED ONLY ở cấp app runtime | main.dart có Supabase.initialize và shared client; analyzer PASS. Không launch main trên thiết bị trong audit |
| Auth đăng nhập/đăng ký/profile/session bridge | NOT CONNECTED ở feature layer | Không có Auth repository/VM/screen hay bridge đến featureSessionScopeProvider |
| Orders/Notifications production data | NOT CONNECTED | Providers mặc định null, không adapter trong lib |
| Bốn màn trong Preview | MOCK ONLY | Fixture/in-memory repositories qua explicit overrides; không initialize Supabase |
| PostgreSQL deployed schema/RLS/RPC/Storage | NOT VERIFIED hiện tại | Có migrations/policies source và tài liệu nghiệm thu cũ; probe không kiểm tra deployment/business rows |
| Flutter → backend REST/Spring Boot | Không có bằng chứng trong workspace | Không business HTTP client/base URL, Spring controller/service, pom.xml hoặc server project; backend ngoài workspace nếu có là UNKNOWN |
| Realtime nghiệp vụ | NOT CONNECTED | Không subscription/channel/stream SDK trong app; polling UI là cơ chế khác |

Không gọi toàn dự án “Supabase integration PASS”. HTTP 200 Auth settings không chứng minh login; HTTP 404/PGRST205 chỉ chứng minh probe đến PostgREST với key được chấp nhận, không chứng minh bảng orders tồn tại hoặc SELECT dữ liệu thật thành công.

### Runtime evidence mới

Script hiện có [tool/check_supabase_connection.dart](../../../tool/check_supabase_connection.dart): GET /auth/v1/settings; GET /rest/v1/__connection_probe__?select=*&limit=0. Script xác nhận cả HTTP status lẫn payload code, không in body/key/PII. Không tạo session hoặc đọc hàng.

Log: [supabase_readonly_probe_verified.log](verification/supabase_readonly_probe_verified.log).

~~~text
OK /auth/v1/settings (HTTP 200)
OK /rest/v1/__connection_probe__?select=*&limit=0 (HTTP 404)
PROBE_EXIT=0
~~~

Lần chạy sandbox trước đó gặp SocketException và hạn chế process/SDK cache; không coi lần đó là endpoint down. Đã chạy lại script nguyên vẹn qua auto-review cho phép network GET, exit 0. Không bổ sung credential hoặc đổi config.

## B. Dependencies và configuration

| Mục | SOURCE-EVIDENCED | Đánh giá |
|---|---|---|
| Dependencies | pubspec.yaml/pubspec.lock: supabase_flutter 2.18.0, supabase 2.16.2, gotrue 2.27.2, postgrest 2.9.1, storage_client 2.8.1, realtime_client 2.13.0 | Dependency không tự chứng minh feature integration |
| Initialization | lib/main.dart:8–23, WidgetsFlutterBinding → SupabaseConfig.validate → await Supabase.initialize(url, publishableKey) → ProviderScope | Thứ tự đúng; không fake fallback nếu init thất bại |
| Client | lib/core/supabase/supabase_providers.dart:5, trả Supabase.instance.client | Một shared client; chưa được production repository consumer sử dụng |
| Compile-time config | lib/core/config/supabase_config.dart:11–16, String.fromEnvironment cho hai define | Không có dotenv loader; file JSON chỉ đi vào app khi truyền --dart-define-from-file |
| Config file | config/supabase.json có HTTPS URL và publishable key; README hướng dẫn cách truyền define | Không in giá trị trong báo cáo; đây là client-safe key, không phải server secret |
| Validation | SupabaseConfig.validate: HTTPS, nonempty/no surrounding whitespace; chặn secret/service_role format và chỉ nhận publishable/legacy anon JWT role | Không thay backend auth/RLS; validator không chứng minh quyền của user |
| SDK version check | Đã đọc local cache supabase_flutter-2.18.0, src/supabase.dart:87–111 và flutter_go_true_client_options.dart:30–37 | publishableKey là tham số đúng của installed version; không đề nghị đổi sang API cũ |
| SDK session persistence | SDK mặc định persistSession=true; SharedPreferencesLocalStorage khi không override, session recovery có sẵn | CONFIGURED SDK capability; chưa có login/logout/session restoration app test; không phải PendingOrderCommandStore |
| Failure handling | main.dart chỉ log runtimeType; startup fallback hiển thị message an toàn | Không lộ cấu hình/session qua source logging path này |
| Android | android/app/src/main/AndroidManifest.xml:2 có INTERNET | Không thiếu network permission |
| Flavors/environments | Một config chung; README cho phép config/*.local.json; .gitignore bỏ local/env | Chưa thấy phân tách dev/staging/prod hoặc flavor wiring. supabase/config.toml là local CLI config, không tự chọn endpoint app |
| Release packaging | android/app/build.gradle.kts còn com.example và debug signing cho release | Chưa thể gọi production release-ready; việc release/signing cần task riêng, không thay trong audit |
| Backend/client HTTP | http là transitive package; dart:io HttpClient chỉ dùng trong probe | Không có REST business adapter. Không suy có Spring Boot chỉ từ dependency HTTP |

Không phát hiện service-role/secret credential được dùng trong Flutter/config đã khảo sát. Đây là kiểm tra source có phạm vi, không phải chứng nhận quét toàn bộ Git history hoặc artifacts build. Không có API key/token/password được chép vào báo cáo hoặc logs mới.

Theo [Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys), publishable/anon thuộc client, còn secret/service-role không được đưa vào app. Installed SDK và [Flutter initializing](https://supabase.com/docs/reference/dart/initializing) là cơ sở kiểm tra chữ ký initialization.

## C. Architecture path

**Lựa chọn kiến trúc có bằng chứng:** Flutter → Supabase trực tiếp ở infrastructure; feature-first repository boundary đã chuẩn bị cho mô hình đó. Đường đang render dữ liệu là Flutter → Mock Repository trong Preview. Đây chưa phải mixed production REST/Supabase integration.

Không tìm thấy app local database (SQLite/Drift/Isar/Hive) hoặc persistent business repository. EpochCache và Preview lists là memory state/cache; SharedPreferences của SDK phục vụ session, không phải nguồn dữ liệu Orders.

Không đề xuất đổi từ REST sang Supabase: không có REST business implementation để chuyển. Nếu nhóm cung cấp backend nằm ngoài workspace, cần audit riêng source/base URL/Auth/DB connection của backend đó trước khi gọi VIA BACKEND hoặc xác nhận nó dùng Supabase/PostgreSQL.

## D. Trace data flow theo chức năng

Các đường dẫn dưới đây tính từ project root; method/symbol chỉ lấy từ source hiện tại. “Thiếu” không phải một implementation giả định.

| Chức năng | UI → state owner | Contract → data source | Thực tế |
|---|---|---|---|
| Auth/login/register | Không có màn/VM; main chỉ initialize SDK | core/state/foundation_providers.dart:8 → SessionScope.unresolved; không có signIn/signUp/signOut/Auth repository | Chưa implement feature; SDK capability không phải auth flow |
| User profile/role | Không có profile UI/adapter | Migration profiles + private.current_app_role; không có Flutter query profiles | Schema-only; trusted role bridge thiếu |
| Catalog/product/variants | MH03/04/05 không có source | Không Dart repository; SQL products/product_variants/categories có nền tảng | Không thể đánh giá real search/filter/catalog UI; chưa có feature |
| Cart/checkout/order creation | MH06/16 không có source | SQL cart_items/orders/order_items; chưa có placement/reservation RPC/client repository | Không có end-to-end placing order |
| My Orders read | CustomerOrdersPage/_CustomerOrdersBody → orderListFoundationProvider(query) → OrderListFoundationViewModel.configureLoader | OrderRepository.getCustomerOrders(query) → orderRepositoryProvider=null; DTO OrderListResponseDto chưa có runtime producer | Production fail-closed; tool/mh07_preview_data.dart:PreviewOrderRepository.getCustomerOrders trả memory fixtures |
| Customer order detail | _openDetails → _CustomerOrderDetailsSheet/Content → orderDetailsFoundationProvider(orderId) | OrderRepository.getOrderDetails → null adapter; DTO OrderDetailsDto | Preview cùng contract; modal scoped cache không thay nguồn dữ liệu |
| Manager Orders read/search/filter | ManagerOrdersPage → Mh08QueryCoordinator/Mh08FeedCoordinator + watchMh08Reads → orderListFoundationProvider | OrderRepository.getManagerOrders(query) → null adapter | tool/mh08_manager_repository.dart:Mh08ManagerRepository.getManagerOrders lọc/paginate memory records; đây là demo, không phải DB search |
| Manager details | ManagerOrderDetailsPage → Mh09DetailContent → orderDetailsFoundationProvider | OrderRepository.getOrderDetails → null adapter | Preview có Mh09PreviewRoute và mh09_preview_details.dart fixtures; chưa real summaries/timeline/capabilities |
| Confirm/reject/cancel | Page preflight → OrderActionDialog._submit | Dialog không gọi repository; confirm/reject/cancelCustomer/cancelManager chỉ có interface; PendingOrderCommandStore chỉ có save/list/remove interface | Chưa gửi mutation, trả externalDependencyUnavailable. acceptHistoricalReceipt là validation hook, không command sender |
| Delivery/shipper | MH10/11/18 không có UI; MH09 có Mh09OperationalActions disabled | Domain DeliverySummary/TaskState được render từ OrderDetails fixture; không DeliveryRepository/API | Không có assignment/pickup/attempt/GPS/map integration; không suy màn tồn tại từ summary |
| COD | MH12 không có UI; MH09 payment/CodSummary và optional onOpenCod | Domain summary + cod_collections schema, không reconciliation adapter/RPC | Không thu/nhận tiền thật; không fake received status |
| Return/refund | MH13/14/15 không có UI; MH07/09 callbacks/ReturnSummary | return_requests/return_items schema; không ReturnsRepository/Storage/refund RPC | Links không callback bị unavailable; summaries chỉ fixture |
| Notifications page | NotificationsScreen → NotificationPageReadCoordinator/FeedCoordinator → notificationPageFoundationProvider | NotificationPageFoundationViewModel.configureLoader → NotificationRepository.getPage(query); provider=null | Generic Preview dùng _PreviewInbox.getPage, mutable memory list; không Supabase query |
| Unread count | header/UnreadBadge → unreadCountFoundationProvider → UnreadCountFoundationViewModel | NotificationRepository.getUnreadCount → null | Exact-count contract riêng, Preview đếm memory, không count DB |
| Mark read | tile → NotificationPageActions.markRead/open → NotificationInteractionViewModel.markRead | NotificationRepository.markRead(id); provider=null; NotificationDto/notificationReadSignal là mapper/payload builder | _PreviewInbox.markRead cập nhật memory read_at; production không PATCH |
| Open notification | NotificationPageActions.open → NotificationInteractionViewModel.openNotification/_isValidDecision | NotificationTargetResolver.resolve(id); notificationTargetResolverProvider=null; onNavigate optional | Chưa có current-target server check/router callback production. notification_only mở local context, không dereference target |
| Chat/support | MH19/20 chưa có UI; optional onOpenChat ở MH09 | conversations/messages schema; chưa ChatRepository/Auth/Realtime client | Không có chat read/send thật; giữ đúng một conversation/customer là constraint source |
| Storage/images/video/evidence | Không upload/download/image network widget integration trong feature | Schema có private buckets/policies; không client.storage/createSignedUrl/upload methods | Assets hiện tại chủ yếu fonts; product snapshot label/placeholder không phải ảnh Storage thật |

### Evidence entrypoints quan trọng

- [Order providers](../../../lib/features/orders/presentation/view_models/order_providers.dart):19 null DI; configureLoader của list/detail; detail ownership check; acceptHistoricalReceipt không làm mutation transport.
- [Order contract](../../../lib/features/orders/domain/repositories/order_repository.dart):12–42, có interface read/commands/pending store, chưa concrete implementation trong lib.
- [Notification providers](../../../lib/features/notifications/presentation/providers/notification_providers.dart):13 null DI; :47/:84 foundation VMs.
- [Notification interaction](../../../lib/features/notifications/presentation/providers/notification_interaction_view_model.dart):20 resolver=null; :90 markRead; :200 openNotification; :356 typed validation.
- [Order dialog](../../../lib/features/orders/presentation/widgets/order_action_dialog.dart):96–111 trả dependency unavailable, không success giả.
- [Generic Preview](../../../tool/ui_preview/preview_app.dart):54 overrides, :239 _PreviewInbox fixture builder.

**Coverage dữ liệu thật:** 0/4 business screens có đường production adapter hoàn chỉnh trong lib. Cả 4 có fixture path trong ít nhất một Preview. Đây là số màn được khảo sát, không phải phần trăm của toàn bộ đặc tả hoặc mức hoàn thành backend.

## E. Supabase services và schema

### Source migrations đang có

Đã đọc cả ba theo thứ tự:

1. supabase/migrations/20261006034251_sports_store_schema.sql — enums, 25 initial tables, constraints/indexes, customer profile trigger, RLS enable và revoke baseline.
2. supabase/migrations/20261006034259_sports_store_access.sql — grants, row policies, role helper, read-time triggers, private Storage.
3. supabase/migrations/20261006040019_simplify_sports_store.sql — gộp về **18 tables**, stock trên variants, cart customer key, refund/evidence trên return_requests, chat read markers.

Final source tables: profiles, categories, products, product_variants, cart_items, orders, order_items, return_requests, inventory_movements, delivery_tasks, delivery_attempts, cod_collections, return_items, business_events, notifications, conversations, messages, store_settings.

Không nhầm inventory_balances/carts/refunds/refund_accounts/return_evidence/delivery_incidents/conversation_reads của migration đầu là final tables: migration thứ ba đã bỏ/gộp chúng.

Migration simplify chỉ cho nền trống, giữ locks/emptiness guards và DROP RESTRICT; **không chạy lại lên database có dữ liệu**. Audit không tạo/applied migration nào.

| Service | Source status | Runtime status trong audit |
|---|---|---|
| Auth | SDK initialized; private.handle_new_user hardcode customer; profiles.role server-managed | Auth settings reachability VERIFIED; login/register/logout/profile fetch NOT VERIFIED/feature chưa có |
| PostgreSQL | Bảng/enums/FK/check/index/versioned schema có thật trong migrations | Business rows/query/deployment current NOT VERIFIED |
| CRUD | SQL cấp một số catalog/cart/chat/read-marker writes; giao dịch nghiệp vụ bị chặn direct client write | Không business CRUD adapter trong lib |
| RLS | SOURCE-EVIDENCED: bật ở schema migration, role/ownership policies + grants ở access/simplify; xem SEC-01/02 | Không chạy allowed/denied theo authenticated role; không tuyên deployed RLS safe |
| Storage | Bốn bucket đều private: product-images, return-videos, inspection-evidence, refund-evidence; scoped policies | Upload/download/signed URLs/current deployed policies NOT VERIFIED |
| Realtime | supabase/config.toml [realtime] enabled cho local service; SDK dependency tồn tại | Không Dart subscription, không migration publication cho app; business Realtime NOT CONNECTED |
| Session | SDK có persistence/recovery/auto-refresh capability; feature scope generation/lease/epoch thiết kế sẵn | Chưa có Auth event bridge, role refresh/revocation, persisted-session app test |
| Roles | SQL helper đọc profiles, không dùng user_metadata.role; user-provided full_name chỉ là profile data | Manager/shipper provisioning và route enforcement hiện tại chưa kiểm chứng |
| Errors | DTO strict parsing, AppFailure, fail-closed null adapters, retry timeout/lifecycle có tests | Supabase exceptions→AppFailure/envelope error mapping production chưa có |
| Pagination/filtering | OrderQuery normalized, NotificationQuery, cursor acceptance/stale logic, DTO counts có tests | Chưa server ordering/cursor/query/count implementation; mock pagination không chứng minh SQL performance |
| Environment | Một shared JSON client config và optional local config | Staging/production isolation, auth redirects/deep links và release credentials chưa verified |
| Automatic confirmation | Không cron.schedule/pg_cron job/business function trong migrations | NOT CONNECTED; UI ForegroundRefresh không phải server job |
| Edge Functions | Không implementation source trong supabase/functions | Không có bằng chứng deployed Functions; ngoài workspace UNKNOWN |

### Điều đang tốt và phải giữ

- RLS helper private.current_app_role có fixed search_path và execute grants giới hạn; profile creation không cho chọn manager/shipper.
- Writes vào stock/order/delivery/COD/returns state không được cấp thẳng cho authenticated; không “sửa lỗi quyền” bằng service-role trong app.
- Notification read_at chỉ có column UPDATE grant, trigger giữ first-read server timestamp; chat marker trigger giữ mốc user khác.
- Storage evidence không public; shipper không được đọc bank/refund table thông qua policies hiện có.
- UUID/int VND/server timestamp conventions được biểu diễn trong SQL và DTO/domain; đơn, task, COD, return có states riêng.
- Unique constraints cho recipient/event, sender/client-message, order placement request và active return có nền tảng, nhưng chưa thay idempotent workflow/replay protocol.

### Historical evidence không phải xác minh mới

docs/database.md ghi ngày 06/10/2026 đã applied ba migrations, 18/18 RLS, 4 private buckets và 83 SQL assertions PASS/ROLLBACK. Đây là lịch sử tài liệu; lượt này không có authenticated DB metadata/raw run log mới đủ để xác nhận trạng thái cloud hiện tại. Không gọi 83 SQL checks là một phần của 763 Dart tests.

supabase/tests/database_security.sql có BEGIN, fixture writes, role impersonation và ROLLBACK. Dù rollback, nó vẫn tạo dữ liệu trong transaction nên **không chạy** theo audit read-only. Có source allow/deny tests không có nghĩa chúng vừa PASS.

Theo [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), quyền bảng và row policies cần được xét cùng nhau. Filter userId trong Flutter không thay RLS. [Auth state events](https://supabase.com/docs/reference/dart/auth-onauthstatechange) là integration point cần quản lý subscription/errors/disposal khi owner Auth triển khai.

## F. Finding register — integration/security

### INT-01 — Auth/session input chưa nối server identity

- **Severity:** Blocker. **Classification:** INTEGRATION WORK.
- **Evidence:** core/state/foundation_providers.dart:8–10 trả unresolved; core/state/session_scope.dart:SessionScope; lib/main.dart chỉ initialize SDK; auth feature không có Dart.
- **Current behavior:** private gates giữ unresolved/loading, không có authenticated role hoặc generation thay đổi từ SDK.
- **Why it matters:** repository thật và router thật vẫn không render dữ liệu hợp lệ; session isolation local chưa có event nguồn.
- **Proposed solution:** AuthRepository/Auth ViewModel/bridge từ session và server profiles.role; phát generation khi account/role/logout/expiry; fail-closed trong thời gian unresolved; không authorize từ editable metadata.
- **Affected:** bốn màn hiện có, toàn bộ protected routes tương lai. **Risk:** Cao về leak tài khoản/late responses.
- **Prerequisites:** CIN-01 và Auth/router owners, tài khoản QA được provision riêng. **Confidence:** SOURCE-EVIDENCED.

### INT-02 — Thiếu production repositories và target resolver

- **Severity:** Blocker. **Classification:** INTEGRATION WORK.
- **Evidence:** order_providers.dart:19; notifications/presentation/providers/notification_providers.dart:13; notification_interaction_view_model.dart:20; contracts có interface nhưng lib không có concrete implementation.
- **Current behavior:** khi có scope hợp lệ, loaders trả externalDependencyUnavailable thay vì dữ liệu; resolver null trả unavailable. Preview overrides chỉ là fixtures.
- **Why it matters:** chưa có business read/write request thật; SDK dependency không làm data integration.
- **Proposed solution:** adapters tại feature data/repositories, inject shared client, strict DTO/error mapping; current-recipient/current-target authorization ở backend; bind providers một lần ở app composition.
- **Affected:** MH07/08/09/17. **Risk:** Cao về shape/query/privacy.
- **Prerequisites:** INT-01, INT-03 và deployed read contracts. **Confidence:** SOURCE-EVIDENCED.

### INT-03 — DTO aggregate/RPC contracts chưa có runtime producer

- **Severity:** Blocker. **Classification:** INTEGRATION WORK + BLOCKED / NEEDS DECISION cho external contracts.
- **Evidence:** orders/data/models/order_dto.dart:423 OrderDetailsDto, :481 OrderListResponseDto, :554 OrderMutationReceiptDto, :588 OperationResultDto; ba migrations chỉ có private role/trigger functions; docs/technical_specification_mh07_mh08_mh09_mh17_data_api.md ghi RPC PROPOSED.
- **Current behavior:** DTO đòi capabilities/timeline/history_complete/as_of/status_counts và summary projections không tồn tại dưới dạng raw table response.
- **Why it matters:** thêm select('orders') không đáp ứng contract, client không nên tự tính financial/custody authority hoặc mở rộng raw-task RLS cho khách để ghép đủ data.
- **Proposed solution:** xác nhận owned revision1.2 + external CIN acceptance, backend read projection/envelope + cursor/count consistency, error discriminants và quyền per-role; adapter map đúng shape.
- **Affected:** MH07/08/09; target/read metadata MH17. **Risk:** Cao về privacy và state authority.
- **Prerequisites:** backend và Delivery/COD/Returns/Inventory owners; không mặc định proposed RPC đã deployed. **Confidence:** SOURCE-EVIDENCED.

### INT-04 — Mutation/recovery và transactional business workflows chưa implement

- **Severity:** Blocker. **Classification:** INTEGRATION WORK.
- **Evidence:** order_action_dialog.dart:96–111 chỉ validation/unavailable; PendingOrderCommandStore interface chưa impl; migrations không có app RPC/cron; schema.sql:189 orders, :388 cod_collections; simplify.sql:195–254 refund bundle.
- **Current behavior:** confirm/reject/cancel chưa gửi; placement/reserve/dispatch/restock/COD/refund/auto-confirm/event fan-out chưa executable trong source. CHECK/FK không bảo đảm đầy đủ liên-bảng: COD expected tự so với amount nhưng chưa so total order; refund chỉ positive/bundle, chưa full merchandise+fee; tọa độ chỉ bounds địa lý, chưa Hà Nội; attempt counter chưa có transactional cập nhật.
- **Why it matters:** chưa chứng minh overselling prevention, cancel-confirm race, attempts cap theo order, obligation COD độc lập returns, deadline/video/refund và idempotent replay.
- **Proposed solution:** server transactions/RPC theo contracts, protected durable pending store + command VM, same request/payload retry và lookup unknown outcome, server job một giờ; không chuỗi Flutter requests thay transaction.
- **Affected:** MH07/08/09 và các feature chưa implement MH06/10/11/12/13/14/15/16; notification producers.
- **Risk:** Cao nhất về stock/tiền/concurrency. **Prerequisites:** INT-01/03, business owner contracts, staging workflow/RLS tests.
- **Confidence:** SOURCE-EVIDENCED về phần thiếu; không gọi đây là regression của UI hoặc khai thác thực tế vì direct writes đang bị chặn.

### INT-05 — External feature handoffs/notification producers chưa có implementation

- **Severity:** Major. **Classification:** INTEGRATION WORK + BLOCKED / NEEDS DECISION.
- **Evidence:** MH07/09 optional callbacks và Mh09OperationalActions disabled; feature dirs không Dart; docs/Cross_Module_Integration_Contracts.md:CIN-02–09 ghi external offers/missing acceptance; không producer function trong migrations.
- **Current behavior:** summary render từ fixture, links/custody/COD/returns/chat chưa nối; bảng notifications có schema/dedup nhưng không server fan-out theo business event.
- **Why it matters:** read adapters riêng không tạo ordering→delivery→COD hoặc per-recipient notifications end-to-end.
- **Proposed solution:** owner agreement bằng concrete request/result/errors/role/preconditions/idempotency; tích hợp ordering→delivery→COD trước, rồi cancellation/failure/returns/chat. Các màn chưa có là feature delivery tasks riêng, không UI refactor.
- **Affected:** bốn màn có handoffs và 16 màn đặc tả. **Risk:** Cao về cross-module states/fan-out.
- **Prerequisites:** acceptance của từng owner và dữ liệu staging, không tự sáng tác business policy. **Confidence:** SOURCE-EVIDENCED source/document distinction.

### SEC-01 — Phạm vi đọc của shipper chưa phân biệt assignment còn hiệu lực và lịch sử

- **Severity:** Major. **Classification:** BLOCKED / NEEDS DECISION, rồi INTEGRATION WORK.
- **Evidence:** access.sql:90–104 tasks_read/order_items_read/attempts_read; :118–124 return_items_read; simplify.sql:351–365 business_events_read: so assigned_shipper_id và role nhưng không có predicate trạng thái/current custody; database_security.sql:674–718 chủ yếu kiểm assigned vs other shipper.
- **Current behavior:** theo policy source, một task terminal/cancelled vẫn giữ assigned_shipper_id có thể tiếp tục cấp quyền đọc task và một số dữ liệu liên quan. Cập nhật assignee trên cùng row sẽ bỏ quyền cũ; rủi ro ở historical rows vẫn giữ assignee, không phải mọi reassignment đều leak.
- **Why it matters:** AGENTS yêu cầu current assignment/necessary information; policy chưa biểu diễn rõ lúc nào snapshot/PII phải thu hồi. Chưa chứng minh live disclosure; quyền đọc lịch sử/COD có thể có mục đích nghiệp vụ khác và phải tách riêng.
- **Proposed solution:** Delivery owner chốt lifecycle predicate và trường cần thiết; dùng policy/projection hẹp, test old/terminal/current assignee; giữ quyền COD của shipper theo nghĩa vụ lịch sử độc lập task/return.
- **Affected:** MH10/11/18 tương lai, related order/return projections và MH17 target resolver. **Risk:** Cao nếu thu hồi nhầm quyền COD hoặc làm mất thông tin nhiệm vụ đang thực hiện.
- **Prerequisites:** current-assignment/history policy, staging allowed/denied tests, migration review. **Confidence:** SOURCE-EVIDENCED predicate; lifecycle business interpretation INFERRED/NEEDS DECISION.

### SEC-02 — Customer read grant bao gồm các cột tồn kho nội bộ

- **Severity:** Minor. **Classification:** BLOCKED / NEEDS DECISION về data minimization.
- **Evidence:** access.sql:17 table-level SELECT cho authenticated; :40–43 variants_read cho customer active variants; simplify.sql:140–161 thêm on_hand/reserved/damaged/available_quantity.
- **Current behavior:** nếu deployment đúng source, customer được phép đọc toàn row active variant, gồm reserved/damaged/on_hand, không chỉ available_quantity. RLS là row-level, không tự ẩn cột.
- **Why it matters:** catalog consumer contract tối thiểu chưa chốt; thêm stock columns đã mở rộng dữ liệu đọc. Báo cáo nghiệp vụ chưa quy định đây là secret nên không gọi là confirmed confidentiality breach.
- **Proposed solution:** chốt fields customer cần; nếu chỉ availability thì expose projection/column privileges phù hợp, manager/server giữ fields nội bộ. Không chỉ ẩn fields ở widget.
- **Affected:** MH03/04/05 tương lai, Inventory contract. **Risk:** Trung bình về query compatibility/catalog.
- **Prerequisites:** Catalog/Inventory owner acceptance và allowed-column/denied-column SQL tests; chưa tự đổi grants. **Confidence:** SOURCE-EVIDENCED grant, necessity quyết định bởi nhóm.

## G. Cần gì để hoạt động production/end-to-end

1. Chốt environment đích và kiểm migration history/schema/RLS metadata đọc-only bởi backend owner; không suy current cloud từ log cũ/probe.
2. Auth/profile/role/session generation bridge và protected router; giữ local privacy guards hiện có.
3. Implement authorized read projections/RPC contracts và adapters; raw notification page/count/read có thể tích hợp riêng trước full event producers, nhưng cần Auth/recipient checks.
4. Implement protected command persistence, transaction workflows, idempotency receipts/lookup và server automatic confirmation.
5. Tích hợp Delivery/Inventory/COD projections/actions; rồi failure/cancellation/returns/refund; producers thông báo trong cùng transaction.
6. Storage clients với private paths/signed URLs, retry/errors/session isolation; Chat contract chung MH19/20 rồi Realtime authorized nếu scope yêu cầu.
7. Chạy staging smoke/allow-deny/concurrency/replay/end-to-end tests; chỉ sau bằng chứng mới phân loại từng feature VERIFIED CONNECTED.

Chi tiết file/task/Definition of Done: [03_REFACTOR_PLAN.md](03_REFACTOR_PLAN.md). Không task nào ở đây được tự triển khai trong lượt audit.
