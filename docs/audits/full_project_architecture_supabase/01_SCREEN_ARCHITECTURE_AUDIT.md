# Audit kiến trúc toàn bộ màn hình

Ngày audit: 26/10/2026, Asia/Saigon. Phạm vi: current working source, bao gồm dirty/untracked files. Đây là báo cáo và kế hoạch; không sửa Flutter, test, router, theme, cấu hình hoặc database.

## Cách đọc kết quả

- **VERIFIED**: đã thực hiện kiểm tra trong lượt audit này, có log.
- **SOURCE-EVIDENCED**: truy vết được implementation/contract trực tiếp trong source hiện tại; chưa đồng nghĩa chạy production.
- **INFERRED**: đánh giá rủi ro hoặc hệ quả dựa trên source, có nêu giới hạn.
- **NOT VERIFIED**: chưa có bằng chứng đủ để nghiệm thu runtime.

Không đánh giá bằng LOC, không yêu cầu provider cho mọi màn hoặc file riêng cho mọi widget. UI đã được user duyệt của MH07/MH08/MH09/MH17 là baseline cần giữ. Các tài liệu cũ còn ghi MH17 “NOT USER APPROVED” không ghi đè xác nhận mới của user.

## A. Architecture overview

Stack thực tế khớp thỏa thuận: Flutter, Riverpod 3.4.3, go_router 18.0.2, supabase_flutter 2.18.0. Domain của Orders/Notifications không phụ thuộc widget hoặc SDK; data layer có DTO và repository interfaces ở domain; production repository implementations chưa có.

Luồng UI hiện có:

~~~text
main → Supabase.initialize → ProviderScope → SportsStoreApp
                                           → AppTheme.light
                                           → appRouterProvider → "/" → trang khung

Preview entrypoints → ProviderScope overrides (scope + fixture repositories)
                    → MH07 / MH08 / MH09 / MH17

Page/Screen → foundation providers → repository interface → [production adapter thiếu]
           → page-owned coordinator (feed/query/actions/lifecycle)
           → widgets nhận data/callback
~~~

Nguồn: [main.dart](../../../lib/main.dart), [SportsStoreApp](../../../lib/app/sports_store_app.dart), [router](../../../lib/app/router/app_router.dart), [foundation](../../../lib/core/state/foundation_providers.dart), [OrderRepository](../../../lib/features/orders/domain/repositories/order_repository.dart).

**Không có business screen nào được router production đăng ký.** Chỉ route “/” là Registered. Không có Spring Boot/REST business client hoặc local business database được tìm thấy trong workspace; xem báo cáo 02.

## B. Screen compliance matrix

Có **4 màn nghiệp vụ thực sự được implement**, ứng với MH07, MH08, MH09, MH17. Có thêm **2 bề mặt kỹ thuật**: trang khung và startup failure. Tổng cộng 6 bề mặt cấp trang nếu tính cả kỹ thuật; không gọi chúng là 6 màn MH. Một detail bottom sheet thuộc MH07 và các Preview wrappers không tăng screen count.

| Screen ID | Screen name | Role | Source path / symbol | Router status | Widgets structure | State ownership | Provider integration | ThemeData | Data source | UI baseline | Recommendation |
|---|---|---|---|---|---|---|---|---|---|---|---|
| MH07 | My Orders | Customer | lib/features/orders/presentation/pages/customer_orders_page.dart:37 — CustomerOrdersPage | Not registered; được Preview mount | Partial: card/feed/sections đã tách; query/feed acceptance còn inline | Mixed: provider/cache canonical; local aggregate cursor, search và modal UI | Existing; không cần thêm provider hình thức | Partial: shared scope, còn token/style cục bộ | Mock trong Preview; production adapter thiếu | User approved | Small refactor tùy chọn cho feed/query; giữ layout |
| MH08 | Manager Order List | Manager | lib/features/orders/presentation/pages/manager_orders_page.dart:29 — ManagerOrdersPage | Not registered; được Preview mount | OK: Mh08PageLayout, ListControls, OrderCard và components | Mixed có ranh giới: foundation canonical; Query/FeedCoordinator page-owned; scroll local | Existing | Partial: shared scope + một số style theo component | Mock trong Preview; production adapter thiếu | User approved | Keep |
| MH09 | Manager Order Details | Manager | lib/features/orders/presentation/pages/manager_order_details_page.dart:9 — ManagerOrderDetailsPage; pages/mh09/mh09_detail_content.dart:21 | Not registered; Preview push bằng business ID | OK: Layout, DetailBody, Header, Identity, Recipient/Items/Payment, Footer | Provider cho read; local route ticket/dialog-open; callbacks cho navigation | Existing; coordinator riêng chưa cần | Partial: shared scope + style giữ approved UI | Mock trong Preview; production adapter thiếu | User approved | Keep |
| MH17 | Notifications | Customer/Manager/Shipper | lib/features/notifications/presentation/screens/notifications_screen.dart:35 — NotificationsScreen; pages/notifications_page.dart:5 alias | Not registered; có Preview entrypoint riêng | OK: Header/Content/Filters/Feed/Tile/ContextModal | Provider/cache canonical; Read/Feed/SessionBridge/Actions theo lifetime Screen; UI context tại Screen | Existing; compatibility exports cùng identity | Shared qua AppTheme/StorefrontTheme; badge override có mục đích | Mock trong generic/acceptance Preview; production adapter/resolver thiếu | User approved | Keep cấu trúc; F03/F05/F07 vẫn pending |
| Không có MH | Base project placeholder | Shared, không hiển thị dữ liệu riêng | lib/app/router/app_router.dart:16 — _BaseProjectPage | Registered: “/” | OK cho placeholder | Local UI state không có | Unnecessary | Shared AppTheme.light | Local text | Unknown | Keep trong audit; thay thế bằng routing tích hợp sau duyệt |
| Không có MH | Startup failure fallback | Shared | lib/main.dart:26 — StartupFailureApp | Not registered; runApp trực tiếp khi startup exception | OK cho error fallback | Không có business state | Unnecessary | Hardcoded/minimal MaterialApp, chưa dùng shared theme | Local text | Unknown | Keep; chuẩn hóa visual chỉ khi có yêu cầu |

Quy ước ThemeData “Partial” không có nghĩa thiết kế sai: các màn dùng cùng visual scope, nhưng vẫn có style override/constant riêng. Không có bằng chứng cần redesign hoặc theme thứ hai.

### Các bề mặt phụ và Preview đã kiểm tra

| Surface | Source | Đường chạy thực tế | Kết luận |
|---|---|---|---|
| Chi tiết đơn của khách | customer_orders_page.dart:947 — _CustomerOrderDetailsSheet; _CustomerOrderDetailsContent/_CustomerOrderDetailsBody | _openDetails → showModalBottomSheet; cache bị ràng buộc captured session | Modal thuộc MH07, không phải MH09 hoặc màn MH mới |
| Action dialog | orders/presentation/widgets/order_action_dialog.dart:17 | MH07/MH08/MH09 mở bằng showDialog | Dialog validation, chưa gửi mutation; không tính màn |
| Context thông báo | notifications/presentation/widgets/mh17/notification_context_modal.dart:16 | NotificationContextHandle; modal có lifecycle độc lập sau Screen disposal | Modal thuộc MH17; không tính màn |
| Preview mặc định | tool/ui_preview/main.dart:13; mh08_preview_app.dart; mh08_preview_surface.dart:135 | Mh08PreviewApp, MH07/MH08; mở MH09 qua Mh09PreviewRoute/orderId | Preview only; không có MH17 trong menu này |
| Generic Preview | tool/ui_preview/preview_app.dart:29 — UiPreviewApp; _buildBody | Menu MH07/MH08/MH09/MH17, fixture DI | Preview only; tái sử dụng đúng bốn entrypoints trong lib |
| Acceptance Preview MH17 | tool/ui_preview/mh17_acceptance_main.dart:11 | runApp(UiPreviewApp), debug-only | Preview only; không phải production entrypoint |
| Preview MH07 cũ | tool/ui_preview/mh07_preview_app.dart | Harness riêng, vẫn có source; không được tool/ui_preview/main.dart chọn | Preview only; không đếm lặp MH07 |
| Mh08/Mh09 page layouts, legacy detail bodies | lib/features/orders/presentation/widgets/mh08/; pages/mh09/ và widgets/mh09/ | Composition/helper widgets; legacy helpers vẫn có import/compatibility references | Không coi là screens/provider authorities mới |

### Những màn chỉ tồn tại trong specification

Đã quét toàn bộ Dart trong lib và tool. Các feature auth/catalog/cart/checkout/deliveries/cod/returns/chat/inventory chưa có Dart implementation; thư mục/placeholder không phải feature hoàn chỉnh.

| ID | Chức năng đặc tả | Role | Tình trạng source Flutter |
|---|---|---|---|
| MH01 | Login | Shared | Không có Screen/Page/Auth ViewModel |
| MH02 | Registration | Customer | Không có Screen/Page |
| MH03 | Product management | Manager | Không có Screen/Page |
| MH04 | Product list/search | Customer | Không có Screen/Page |
| MH05 | Product details/variants | Customer | Không có Screen/Page |
| MH06 | Cart | Customer | Không có Screen/Page |
| MH10 | Shipper tasks | Shipper | Không có Screen/Page |
| MH11 | Delivery task details | Shipper | Không có Screen/Page |
| MH12 | COD reconciliation | Manager/Shipper | Không có Screen/Page |
| MH13 | Create return | Customer | Không có Screen/Page |
| MH14 | Return tracking | Customer | Không có Screen/Page |
| MH15 | Return management | Manager | Không có Screen/Page |
| MH16 | Checkout/location selection | Customer | Không có Screen/Page |
| MH18 | Store map | Shipper | Không có Screen/Page |
| MH19 | Conversation list | Customer/Manager | Không có Screen/Page |
| MH20 | Conversation details | Customer/Manager | Không có Screen/Page |

HTML mocks trong docs/ui_mocks và ảnh nghiệm thu là reference/evidence; không phải Flutter screen implementation. “Thiếu 16 màn” là khoảng trống coverage so với đặc tả, không phải lý do refactor bốn màn đã có hoặc tự triển khai ngoài nhiệm vụ.

## C. Đánh giá trách nhiệm, state và lifecycle

### Screens và Widgets

- **KEEP — SOURCE-EVIDENCED:** Không có Supabase/HTTP/database query trong build của các business screens. Provider watch/listen hoặc preflight đọc canonical cache là UI wiring, không phải API call trực tiếp.
- **MH07:** domain query chuẩn hóa search/status; Screen debounce và chọn filter. Các hàm _consumeCanonical/_consumeNext quản lý aggregate nhiều cursor, không ghi order và không giả làm backend authority. Header/chips/detail body là private widgets có trách nhiệm thực, không bắt buộc tách mỗi widget thành file.
- **MH08:** Mh08QueryCoordinator giữ query/debounce; Mh08FeedCoordinator giữ accepted aggregate, cursor history, denial/reset và metadata. watchMh08Reads nối Riverpod vào coordinator. Page giữ scroll, setState, refresh và dialog context.
- **MH09:** Mh09DetailContent sở hữu ticket/generation/route state và dialog-open latch; _authorized/_current kiểm scope, cache identity và read freshness trước action/link. Đây là lifecycle/UI orchestration phù hợp, không cần chuyển BuildContext/ModalRoute vào provider.
- **MH17:** NotificationsScreen chỉ wiring, preflight context, subscriptions/modal/poll eligibility; NotificationPageActions phối hợp read/open; VM giữ acknowledgement/typed target validation; ReadCoordinator/FeedCoordinator giữ một accepted feed/filter/cursor authority. Không đề nghị refactor lại cấu trúc đã nghiệm thu.
- **Widgets:** OrderFeed, AsyncContent và detail sections tái sử dụng; Mh07/Mh08 cards khác approved layout nên không ép hợp nhất. Widget xử lý format label/status/visibility là presentation logic. Mh09OperationalActions nhận capabilities nhưng cố ý disabled, không tự phát sinh quyền nghiệp vụ.
- **Redundant wiring nhỏ:** MH07 truyền custom itemBuilder cùng legacy callbacks vào OrderFeed; custom builder được ưu tiên nên không tạo double action. Có thể bỏ tham số dư trong small cleanup, không coi là lỗi runtime.

### Providers, cache và dependency direction

| Owner | Trách nhiệm thực | Lifecycle / invalidation | Đánh giá |
|---|---|---|---|
| featureSessionScopeProvider | Input trusted Auth scope, hiện unresolved | Phải đổi generation theo session/role; adapter Auth còn thiếu | Client fail-closed tốt; integration blocker |
| epochCacheProvider / EpochCache | Accepted per-resource aggregate; namespace theo full SessionScope | dispose/clear, blockSession, epoch/request/query tokens, prefix invalidation | KEEP; không dùng receipt làm current data |
| SnapshotReadViewModel | Serial read/retry, stale retention, reject obsolete responses | ref.mounted + lifecycle + cache token; timeout 10s, backoff hữu hạn; clear private data khi auth/deny | KEEP |
| orderListFoundationProvider(query), orderDetailsFoundationProvider(id) | Canonical query/detail reads | autoDispose family, framework auto retry tắt vì VM đã sở hữu retry | KEEP |
| Notification page/count foundations | Canonical page và exact unread count là hai resource riêng | autoDispose; recipient/filter/negative-count/cursor validation | KEEP; không tính unread từ trang đang load |
| NotificationInteractionViewModel | Per-ID markRead single-flight, canonical ack, typed target decision | Scope/cache/lifecycle guards; state reset/dispose; invalidation riêng | KEEP; open chưa single-flight (F05) |
| NotificationPageSessionBridge, ReadCoordinator, Actions | Namespace lease, provenance, accepted feed/action orchestration | Screen owns dispose; modal revocation/handoff có test | KEEP; không thêm provider wrappers |
| Local search/scroll/dialog/route state | UI lifetime | controllers/timers/subscriptions được hủy | Giữ ở UI; không chuyển context/ref vào provider |

Nguồn chính: core/state/{epoch_cache,snapshot_read_view_model,foundation_providers,session_scope}.dart; notifications/presentation/providers/; orders/presentation/view_models/order_providers.dart.

**Không phát hiện duplicate provider/cache authority do alias.** notifications/presentation/view_models/*.dart và view_models/mh17/*.dart chỉ re-export canonical providers; NotificationsPage là typedef NotificationsScreen; OrderNotificationTheme delegate StorefrontTheme. _rows ở MH07/MH08 là view aggregate nhiều cursor, không phải một repository cache cạnh tranh. Cache riêng của customer detail modal có mục đích captured-session privacy; không hợp nhất máy móc với root cache.

**Giới hạn:** local guards chỉ có hiệu lực thực khi Auth phát đúng scope/generation. Chúng không chứng minh server authorization, tức thời phát hiện silent mutation không có signal, memory zeroization hoặc production router/session đã tích hợp.

## D. ThemeData

Nguồn duy nhất cho storefront hiện tại là app/theme/storefront_theme.dart; AppTheme và OrderNotificationTheme là facade/compatibility, không phải ba theme systems độc lập.

| Thành phần | Bằng chứng hiện tại | Kết luận |
|---|---|---|
| Global theme | app_theme.dart:14 — AppTheme.light, Material 3, seed blue | App shell cơ bản; chưa đồng nhất global storefront defaults |
| ColorScheme/TextTheme | storefront_theme.dart:31 — data(base), Inter và BarlowCondensed | Shared cho bốn màn qua visual scope |
| AppBar/Card/Buttons/Input | cùng data(base): AppBarTheme, CardThemeData, Filled/Outlined/TextButtonTheme, InputDecorationTheme | Đã có; không tạo theme thứ hai |
| Chip/Divider/Dialog | cùng shared ThemeData | Đã có |
| Fonts/icons | pubspec.yaml assets/fonts; font licenses đăng ký tại StorefrontTheme; Material Icons | Có cơ sở dùng chung |
| Spacing/radius | Các value 16/20/32/999 và local sizes lặp ở components | Chưa có token layer tổng quát; không bắt buộc ThemeExtension |
| Local style | mh07_order_card.dart:7–9 trùng ink/cloud/muted; customer_orders_page.dart:_mh07AppBar/_CustomerListHeader; mh08/mh09 widget overrides | Partial centralization, vẫn bảo toàn approved appearance |
| MH17 badge | notifications_header.dart:_HeaderBadge override error→onSurface | Override cục bộ có mục đích; không phải duplicate theme |

Không có cơ sở đề nghị đổi palette/font/layout. Nếu gom constants, chỉ thay tham chiếu khi giá trị/render không đổi và chạy parity/a11y tests; chưa tự nâng StorefrontTheme lên global vì có thể ảnh hưởng dialog và các module chưa tích hợp.

## E. Finding register — kiến trúc

### ARC-01 — Không có business routing/role guards production

- **Severity:** Blocker. **Classification:** INTEGRATION WORK. **Evidence:** app/router/app_router.dart:5–16, appRouterProvider chỉ có GoRoute “/”; sports_store_app.dart:19 dùng router này.
- **Current behavior:** main chỉ tới placeholder; bốn màn truy cập qua Preview. Không có role-prefixed routes, Auth redirect hoặc notification target routing production.
- **Why it matters:** UI readiness không tạo luồng app sử dụng được; backend adapter riêng cũng chưa đủ.
- **Proposed solution:** nối router trung tâm vào trusted Auth scope; đăng ký route đã có theo role, business ID parameters và callbacks; target chưa implement hiển thị unavailable.
- **Affected:** MH07/08/09/17 và các links catalog/returns/COD/chat. **Risk:** Cao khi wiring sai scope/deep link; giữ UI nguyên.
- **Prerequisites:** CIN-01/Auth owner, route/target contracts và read adapters. **Confidence:** SOURCE-EVIDENCED; không phải router runtime PASS.

### ARC-02 — Query/feed acceptance của MH07 khó tái kiểm thử độc lập và dễ lệch MH08

- **Severity:** Minor. **Classification:** SMALL REFACTOR, tùy chọn. **Evidence:** customer_orders_page.dart:_setQuery (439), _resetExtraCursors (474), _consumeCanonical (509), _consumeNext (562); so với Mh08FeedCoordinator.consumeCanonical/consumeNext và Mh08QueryCoordinator.
- **Current behavior:** MH07 giữ query generation, private-denial latch, aggregate/cursor dedup trong State; MH08 đã đưa cùng nhóm trách nhiệm vào pure coordinators. Không phát hiện hai business authorities hoặc lỗi acceptance trong nhóm test đã chạy.
- **Why it matters:** sửa invalid-cursor/privacy pagination về sau dễ chỉ cập nhật một bản; thuật toán MH07 cần widget host để test.
- **Proposed solution:** đưa feed/query state thuần của MH07 vào coordinator riêng theo pattern đã có; chỉ chia sẻ primitive khi chứng minh rules giống nhau. Giữ UI controllers, Navigator, ref/listeners và modal scope ở Page.
- **Affected:** MH07; MH08 là reference, không bắt buộc sửa. **Risk:** Trung bình do freshness/denial/modal interactions.
- **Prerequisites:** bảo toàn characterization tests; user duyệt kế hoạch. **Confidence:** SOURCE-EVIDENCED về duplication, INFERRED về drift tương lai.

### THM-01 — Một số style/token dùng chung vẫn khai báo cục bộ

- **Severity:** Minor. **Classification:** SMALL REFACTOR, tùy chọn. **Evidence:** mh07_order_card.dart:7–9 trùng StorefrontTheme constants; customer_orders_page.dart:_mh07AppBar/_CustomerListHeader; storefront_theme.dart:data; app_theme.dart:light.
- **Current behavior:** four-screen scoped theme thống nhất, local styles vẫn override có chủ đích; global shell dùng defaults khác.
- **Why it matters:** thay token trung tâm có thể không đi tới local constants; không phải bằng chứng visual defect.
- **Proposed solution:** alias literal trùng sang shared constants hoặc Theme.of khi equivalent; giữ explicit approved typography khi ThemeData không tương đương. Không tạo theme/token framework mới.
- **Affected:** chủ yếu MH07; phạm vi mở rộng chỉ sau rà soát parity. **Risk:** Trung bình về pixel/accessibility, nhỏ về logic.
- **Prerequisites:** approved UI làm baseline, parity test an toàn không ghi đè ảnh cũ. **Confidence:** SOURCE-EVIDENCED.

### MH17-F03 — Role × target matrix chưa đủ bằng chứng nghiệm thu

- **Severity:** Major (verification gap, chưa khẳng định permission bug). **Classification:** BLOCKED / NEEDS DECISION về tiêu chí nghiệm thu.
- **Evidence:** providers/notification_interaction_view_model.dart:356 — _isValidDecision allowlist role/mode/screen và manager delivery-task→order exception; notification_interaction_view_model_test.dart có một số positive/negative cases nhưng chưa đủ toàn matrix; docs/features/mh17/SOURCE_AUDIT.md:F03.
- **Current behavior:** có typed validation/fail-closed; adapter resolver/production routes còn thiếu. **Why it matters:** không thể coi mọi đích COD/task/return/conversation đã được kiểm chứng theo role.
- **Proposed solution:** table-driven allow/deny fixtures đối chiếu contracts; kiểm manager task→order và stale assignment; sau đó test resolver/backend/router thật.
- **Affected:** MH17 và MH07/09/11/12/14/15/20 theo mapping. **Risk:** Cao nếu thay mapping; test-only phase thấp.
- **Prerequisites:** resolver/target owner contracts; không thêm quyền. **Status:** PENDING, không đóng trong audit.

### MH17-F05 — Rapid opens có thể phát nhiều navigation callbacks

- **Severity:** Major (interaction regression risk). **Classification:** BLOCKED / NEEDS DECISION rồi SMALL REFACTOR có mục tiêu.
- **Evidence:** providers/notification_interaction_view_model.dart:69 — _readRequests chỉ dedup markRead; openNotification:200–271; notification_page_actions.dart:74 — open không serialize navigation; mh17_gesture_characterization_test.dart:44–54 hiện assert 1 read, 3 resolver calls, 3 navigation callbacks.
- **Current behavior:** read/open độc lập được bảo toàn; rapid taps và pending read-control hit có thể đi tiếp outer open. **Why it matters:** production callback có thể push nhiều route; chưa chứng minh ba production routes vì router thật chưa có.
- **Proposed solution:** chốt single-flight/cooldown/lifetime policy tại một interaction/navigation owner; giữ read failure không chặn valid open, không chuyển BuildContext sang provider; cập nhật đúng characterization khi policy được duyệt.
- **Affected:** MH17 và các đích mở. **Risk:** Cao về gesture/return-route/pending-read behavior.
- **Prerequisites:** quyết định interaction policy và production navigation contract. **Confidence:** callback multiplicity được source/test-evidenced và có trong nhóm tests mới; production stack impact INFERRED. **Status:** PENDING.

### MH17-F07 — Preview inbox fixtures chưa canonical theo producer contract

- **Severity:** Minor. **Classification:** SMALL REFACTOR/tooling fidelity.
- **Evidence:** tool/ui_preview/preview_app.dart:239–252 — _PreviewInbox._buildItems đổi row ID nhưng reuse event/recipient/subject từ fixtureNotificationJson; test/fixtures/order_notification_fixtures.dart:169–181.
- **Current behavior:** nhiều fake rows cùng event/recipient; notification_only giữ order subject ID thay vì identity theo proposed producer semantics. Không phải dữ liệu production.
- **Why it matters:** preview không thể chứng minh recipient/event dedup hoặc canonical target semantics; không bác bỏ UI acceptance.
- **Proposed solution:** fixture producer riêng cho mỗi event, đúng recipient/type/subject semantics; vẫn DEMO và cùng repository contract. Không xóa fixture/test/evidence cũ.
- **Affected:** MH17 Preview; không đổi UI production. **Risk:** Trung bình với fixture-based expectations.
- **Prerequisites:** CIN-09 canonical fixture agreement. **Status:** PENDING.

## F. Verification và giới hạn

**VERIFIED mới trong lượt audit:**

- Flutter analyzer: PASS, “No issues found”, exit 0 — [log](verification/flutter_analyze_verified.log).
- **763 existing tests PASS**, exit 0 — [log](verification/focused_tests_verified.log). Nhóm: core, shared, Orders, Notifications data/view_models/widgets/pages, notifications_structure_actions_test và ui_preview.
- Không chạy test/visual_refinement; không chạy notifications_visual_parity_test hoặc notifications_final_acceptance_test vì chứa optional capture code. Không bật capture defines; không ghi đè ảnh nghiệm thu.
- Invocation dùng Dart executable chạy flutter_tools.snapshot của SDK hiện có, tương đương flutter analyze/test; --no-pub, không đổi dependency. Wrapper ban đầu chờ SDK lock; sandbox direct attempt báo không truy cập SDK lockfile; đã dừng và chạy lại thành công với quyền SDK cache qua auto-review. Lần test arguments qua batch đầu bị “command line too long”, không được tính là test fail của ứng dụng.

763 là số của nhóm được chọn, **không phải rerun nguyên checkpoint 441 MH17** và không phải toàn bộ suite. Kết quả cũ 441 PASS chỉ là reference baseline. Không build/install Android, không live Auth, không production router, không backend workflow tests trong lượt này.

Lệnh tương đương để tái lập trên SDK hiện có (không cần pub get):

~~~powershell
flutter analyze --no-pub
flutter test --no-pub --reporter expanded test/core test/shared test/features/orders test/features/notifications/data test/features/notifications/presentation/view_models test/features/notifications/presentation/widgets test/features/notifications/presentation/pages test/features/notifications/presentation/screens/notifications_structure_actions_test.dart test/ui_preview
~~~

Các lệnh Flutter có thể ghi build/tool cache; source/config không được sửa. Runtime probe dùng script hiện có với config client sẵn, kết quả và giới hạn nằm ở báo cáo 02.

Đánh giá tổng hợp: **3 màn KEEP cấu trúc (MH08/MH09/MH17), 1 màn SMALL REFACTOR tùy chọn (MH07), 0 màn cần STRUCTURAL/MAJOR rewrite** theo bằng chứng hiện có. MH17 giữ cấu trúc nhưng F03/F05/F07 vẫn phải theo dõi riêng. Toàn bộ 4 màn còn integration blockers; không dùng phân loại kiến trúc để tuyên bố production-ready.

Review độc lập: GPT-5.6 Sol/Medium, source-only; đã loại bỏ đề nghị ban đầu chỉ dựa vào naming/folder vì không phù hợp tiêu chí của user. GPT-5.6 Luna/Max không khả dụng, coordinator tự khảo sát thay vì tuyên bố đã dùng worker đó.

Kế hoạch chi tiết và kiểm thử cần bảo toàn: [03_REFACTOR_PLAN.md](03_REFACTOR_PLAN.md). Trạng thái Supabase: [02_SUPABASE_INTEGRATION_AUDIT.md](02_SUPABASE_INTEGRATION_AUDIT.md).
