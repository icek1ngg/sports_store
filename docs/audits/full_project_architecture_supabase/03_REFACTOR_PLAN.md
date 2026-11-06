# Kế hoạch refactor và tích hợp — chờ review

Ngày: 26/10/2026. **PLAN ONLY. Không triển khai code, cấu hình, database hoặc dependency trong audit.**

Baseline: working source đang dirty/untracked; UI MH07/MH08/MH09/MH17 đã được user duyệt. Không lấy HEAD thay baseline, không redesign, không LOC gates, không thêm provider/widget/layer không có trách nhiệm.

Findings và evidence: [01_SCREEN_ARCHITECTURE_AUDIT.md](01_SCREEN_ARCHITECTURE_AUDIT.md), [02_SUPABASE_INTEGRATION_AUDIT.md](02_SUPABASE_INTEGRATION_AUDIT.md).

## A. Quyết định giữ kiến trúc

- Giữ Flutter + feature-first MVVM + Riverpod + go_router + shared Supabase client.
- Giữ domain contracts/DTO/state enums hiện có; không tạo Order/Conversation/SessionScope bản khác cho từng màn.
- Giữ MH08 coordinators, MH09 page-owned route/dialog guards, MH17 Screen/Widgets/Providers/Actions/SessionBridge và canonical provider identities.
- Không chuyển Navigator/BuildContext/WidgetRef/ModalRoute hoặc widget controllers vào provider.
- Không hợp nhất cache modal có mục đích session isolation chỉ vì nó khác root cache.
- Không ép mỗi screen có provider mới. Không di chuyển MH17 chỉ để khớp tên thư mục.
- Không đổi sang REST hoặc di chuyển toàn bộ sang direct Supabase: current infrastructure đã direct; backend ngoài workspace nếu có cần source/contract trước.

## B. Thứ tự triển khai đề xuất

Hai track độc lập, mỗi thay đổi cần được user duyệt scope riêng. Tích hợp backend không được ngụy trang thành UI refactor.

| Thứ tự | Task | Lý do | Rủi ro | Có đổi approved design? |
|---|---|---|---|---|
| 1 | R0 — baseline/characterization và F03 matrix | Test-only, làm rõ behavior trước đổi logic | Thấp | Không |
| 2 | R1 — F07 canonical Preview fixtures | Giảm sai lệch demo/producer contract, độc lập production | Thấp–trung bình | Không |
| 3 | R2 — MH07 query/feed coordinator, tùy chọn | Cải thiện testability, tránh drift so MH08 | Trung bình | Không |
| 4 | R3 — alias theme tokens trùng, tùy chọn | Loại duplicate literal có semantic chung | Trung bình về visual | Không |
| Sau quyết định | R4 — F05 navigation policy | Thay đổi interaction thật, cần contract và route-stack tests | Cao | Giữ visual, thay behavior đã duyệt riêng |
| Song song ở planning | I0 → I1 → I2 → I3 | Contracts/env → Auth → read adapters → router production | Cao về integration | Không redesign |
| Sau nền read/Auth | I4 → I5 → I6 | Command protocol + placement → delivery/COD → cancellation/failure/returns; notifications producers xuyên suốt | Cao nhất stock/tiền | Business integrations riêng |
| Theo module scope | I7 → I8 | Storage/chat/Realtime theo quyền; staging/release verification | Cao về privacy | Giữ UI hiện có |

Không bắt buộc làm R1–R3 trước Auth/backend reads: chúng là các cải thiện hẹp, không phải điều kiện hình thức để kết nối Supabase.

## C. Refactor tasks theo feature

### R0 — Characterization và MH17-F03 role/target matrix

1. **Scope / priority:** P1, test-only trước khi thay target mapping; F03 chưa được đóng.
2. **Files hiện tại:** notification_interaction_view_model.dart tại notifications/presentation/providers; notification_page_actions.dart; notification_target.dart; test/features/notifications/presentation/view_models/notification_interaction_view_model_test.dart; test/features/notifications/presentation/pages/mh17/*; screens/notifications_structure_actions_test.dart.
3. **Files tạo/chỉnh:** đề xuất test/features/notifications/presentation/view_models/mh17/notification_target_role_matrix_test.dart; bổ sung test support nếu có trách nhiệm mới. Không đổi production mapping nếu không phát hiện sai so accepted contract.
4. **Widgets:** tái sử dụng Screen/Tile/ContextModal hiện có; không tách widget.
5. **Providers:** giữ notificationInteractionViewModelProvider, notificationTargetResolverProvider và identity qua legacy exports; không thêm authority.
6. **State ownership:** VM xác minh typed decision; resolver/backend là authority về quyền hiện tại; Screen/router sở hữu điều hướng/context.
7. **ThemeData:** không thay.
8. **Navigation/import compatibility:** test cả canonical và compatibility imports; full allow/deny role×target×mode×screen, UUID/subject mismatch, manager task→order exception, unknown subject, expired scope, changed assignment, stale/denied target. Không tự đăng ký màn chưa có.
9. **Tests bảo toàn:** toàn bộ MH17 read/open độc lập, denial/two-fresh repair, read provenance, epoch/cache replacement, session/modal lifetime, gesture characterization hiện hành. Chưa đổi expected F05.
10. **DoD:** matrix chốt theo contracts, expected positive/negative có giải thích; fixtures không chứa dữ liệu người thật; focused suite/analyzer PASS; F03 chỉ được nghiệm thu đến client matrix, backend/route permission test vẫn cần I8.

### R1 — MH17-F07 canonical Preview fixtures

1. **Scope / priority:** P2, tooling-only sau khi owner xác nhận CIN-09 fixture semantics.
2. **Files hiện tại:** tool/ui_preview/preview_app.dart:_PreviewInbox._buildItems; test/fixtures/order_notification_fixtures.dart:fixtureNotificationJson; test/features/notifications/presentation/view_models/mh17/notification_action_fakes.dart làm reference đúng notification_only identity.
3. **Files tạo/chỉnh:** tạo tool/ui_preview/mh17_preview_fixtures.dart nếu cần fixture factory có trách nhiệm riêng; sửa Preview để dùng factory. Test fixture canonicality ở test/ui_preview/mh17_preview_fixtures_test.dart đề xuất. Không xóa/overwrite fixture hoặc ảnh cũ.
4. **Widgets:** giữ nguyên tất cả; không sửa visual text/layout ngoài dữ liệu fixture bắt buộc đúng contract.
5. **Providers:** dùng _PreviewInbox qua provider override hiện có; không dùng fixture làm default production repository.
6. **State ownership:** repository DEMO giữ memory state; mỗi event/recipient hợp lệ và subject/type đúng contract, vẫn tách canonical server authority.
7. **ThemeData:** không thay.
8. **Navigation/import compatibility:** giữ UiPreviewApp và debug entrypoints; thông báo notification_only không dereference entity. Nếu cần ảnh demo mới, ghi vào thư mục evidence mới sau khi được giao, không vào evidence cũ.
9. **Tests bảo toàn:** preview switching, page filters/count/read/open; event/recipient uniqueness; notification_only semantics; hết fixture không thành backend success.
10. **DoD:** F07 có canonical fixture proof, DEMO label không mất; unit/widget/analyzer PASS; không tuyên backend producer/production navigation đã hoạt động.

### R2 — MH07 feed/query coordinator, cải thiện có chọn lọc

1. **Scope / priority:** P2, SMALL REFACTOR tùy chọn cho ARC-02; không phát hiện runtime defect cần emergency rewrite.
2. **Files hiện tại:** lib/features/orders/presentation/pages/customer_orders_page.dart, view_models/order_providers.dart; MH08 coordinators/read subscriptions làm reference; OrderFeed/Mh07OrderCard/shared sections giữ nguyên.
3. **Files tạo/chỉnh:** đề xuất orders/presentation/view_models/mh07/mh07_feed_coordinator.dart và mh07_query_coordinator.dart; chỉ tạo pages/mh07/mh07_read_subscriptions.dart nếu listener wiring có trách nhiệm đủ rõ. Chỉnh CustomerOrdersPage để delegate pure state; không chỉnh shared contracts/router.
4. **Widgets:** header/chips/detail private widgets có thể ở cùng file; chỉ di chuyển CustomerOrderDetailsSheet khi giúp review độc lập session owner. Không có nhiệm vụ tách widget theo kích thước.
5. **Providers:** tái sử dụng orderListFoundationProvider/query và orderDetailsFoundationProvider/id; không thêm cache/repository; không tạo provider wrapper cho page-owned coordinator.
6. **State ownership:** foundation/EpochCache giữ canonical reads; FeedCoordinator giữ aggregate cursor/freshness/private-denial state; QueryCoordinator giữ query validation/debounce policy phù hợp; Page giữ controllers, scroll triggers, ref/watch/listen, setState, dialogs/context. Preserve captured modal cache và cross-session fail-closed.
7. **ThemeData:** không thay trong R2 để dễ phát hiện regression.
8. **Navigation/import compatibility:** giữ CustomerOrdersPage constructor, optional callbacks, showPreviewNavigation, enablePolling, widget keys/semantics. _openDetails vẫn UI; không đổi route count hoặc luồng return.
9. **Tests bảo toàn:** customer_orders_page_test.dart; order_foundation_test.dart; epoch_cache_test.dart; FeatureAccessGate/ForegroundRefresh; order_action_dialog_test.dart; MH07 Preview smoke và privacy cases. Thêm pure tests có ý nghĩa cho head replaces tail, invalid cursor head refresh, cursor loop/dedup, late old query/session, private denial và fresh recovery.
10. **DoD:** không duplicate authority; scoped cache/lifecycle unchanged; behavior/layout parity tại narrow width/large text/keyboard; focused tests + analyze PASS. Chỉ cân nhắc shared pagination primitive sau khi thấy MH07/MH08 contracts thật sự giống nhau, không ép chung toàn feature.

### R3 — Theme token aliases không đổi thiết kế

1. **Scope / priority:** P3, tùy chọn cho THM-01; chỉ constants/style trùng semantic và giá trị.
2. **Files hiện tại:** lib/app/theme/{app_theme,storefront_theme}.dart; orders/presentation/widgets/{order_notification_theme,mh07_order_card}.dart; customer_orders_page.dart:_mh07AppBar/_CustomerListHeader; MH08/MH09 overrides chỉ là đối tượng rà soát.
3. **Files tạo/chỉnh:** ưu tiên sửa tham chiếu trong files hiện có. Không tạo theme thứ hai hoặc ThemeExtension/spacing framework nếu chưa có reuse thực.
4. **Widgets:** giữ component APIs, key, semantic/hit target và responsive layout.
5. **Providers:** không liên quan, không tạo provider theme.
6. **State ownership:** không đổi.
7. **ThemeData:** alias mh07Ink/cloud/muted về StorefrontTheme khi equivalent; dùng ColorScheme/TextTheme khi kết quả không đổi. Giữ typography override đã duyệt khi token chung không khớp. Không đổi global AppTheme.light trong cùng task.
8. **Navigation/import compatibility:** giữ OrderNotificationTheme facade và AppTheme.notificationsScope/data; tránh vòng import từ app/theme sang feature.
9. **Tests bảo toàn:** MH07/08/09 widgets, notification widgets/structure/semantics, narrow/large text/keyboard; visual parity dùng artifact directory mới nếu được giao.
10. **DoD:** no visual redesign/pixel drift ngoài dung sai đã duyệt; cùng font licenses; focused tests/analyzer PASS; không dùng “hardcoded còn tồn tại” làm lý do gom mọi style.

### R4 — MH17-F05 single-flight/open policy, chỉ sau quyết định

1. **Scope / priority:** P1 khi triển khai navigation thật; đây là behavioral remediation cần duyệt policy, không phải refactor hình thức.
2. **Files hiện tại:** notification_interaction_view_model.dart:openNotification; notification_page_actions.dart:open/_navigate; notifications_screen.dart; notification_tile.dart; mh17_gesture_characterization_test.dart.
3. **Files tạo/chỉnh:** sửa một interaction/navigation owner phù hợp sau khi chốt lifetime. Đề xuất test notification_navigation_single_flight_test.dart và router stack test; không tạo latch ở cả VM, Actions, Screen và router cùng lúc.
4. **Widgets:** giữ look, labels, hit targets; xem rõ pending read-control tap tới outer tile. Nếu cần đổi gesture behavior, ghi acceptance riêng.
5. **Providers:** reuse VM/Actions hiện có. Gate phải scoped theo session/generation và notification/target theo policy; không giữ context trong provider.
6. **State ownership:** canonical ack vẫn VM; read và open vẫn độc lập. Open gate chỉ điều phối active navigation, release theo route lifetime/policy đã chốt; reject late responses khi dispose/account/filter/cache thay đổi.
7. **ThemeData:** không thay.
8. **Navigation/import compatibility:** giữ typed NotificationTargetDecision và callback API nếu đủ; nếu cần port route completion phải cập nhật một nơi và giữ adapters legacy. Cần route-stack proof, không chỉ đếm callback.
9. **Tests bảo toàn:** markRead per-ID dedup; read failure vẫn cho authorized open; already-read vẫn resolver; resolver denied không push; rapid taps một route theo policy; pop→reopen; targets khác; logout/role change/dispose giữa resolve/navigation; ContextModal độc lập; unavailable messaging. Chỉ đổi expectation 3 opens của characterization khi policy được user duyệt.
10. **DoD:** không duplicate route theo policy; read/open independence và privacy không regression; kiểm thử qua Navigator/go_router thực; F05 closure có bằng chứng riêng. Audit này không đóng F05.

## D. Integration plan riêng

Mọi path ở phần này là **đề xuất tương lai**, không tuyên file đã có. Giữ migrations hiện có nguyên lịch sử; nếu cần schema/grant/RPC mới phải tạo bằng Supabase CLI thực tế trong task triển khai, không tự đặt filename hoặc applied claim.

### I0 — Contract/environment/security decisions trước production writes

- **Priority / findings:** P0; INT-03/04/05, SEC-01/02.
- **Scope:** backend owner xác nhận direct Supabase là đường nhóm sử dụng, environment đích và schema history hiện tại; nếu có backend ngoài workspace, cung cấp source và contract trước đánh giá.
- **Files affected sau duyệt:** docs/api_contracts.md, database.md, business_states.md, screen_mapping.md và Cross_Module_Integration_Contracts.md; config environment chỉ sửa trong task cấu hình riêng. Audit không sửa các file đó.
- **Contracts cần chốt:** owned Orders/Notifications revision1.2 khác external CIN offers; request/result/error/cursor/count/target/permission/idempotency cụ thể; store address/Hà Nội geometry; return cutoff edge; custody/discrepancy/history access; canonical producer facts và notification payload privacy.
- **Security:** chốt “currently assigned” vs historical task/PII; giữ COD obligation visibility riêng; chốt customer variant fields; không dùng user_metadata role, service-role mobile, raw customer task/event access để bù thiếu projection.
- **Required checks:** read-only deployed schema/grants/policy metadata có redacted evidence; source-to-schema diff do backend owner; staging role fixtures và plan cho migration có dữ liệu.
- **DoD:** mỗi contract có owner, trạng thái accepted/proposed, actual endpoint/migration hay missing rõ ràng; chưa có accepted contract thì không invent RPC hoặc unlock action.

### I1 — Auth/profile/session bridge

- **Priority / finding:** P0, INT-01.
- **Current files:** main.dart, core/config/supabase_config.dart, core/supabase/supabase_providers.dart, core/state/{foundation_providers,session_scope}.dart và FeatureAccessGate.
- **Proposed files:** features/auth/domain/repositories/auth_repository.dart; data/repositories/supabase_auth_repository.dart; presentation/view_models/auth_session_view_model.dart. Reuse SessionScope; không thêm session authority thứ hai.
- **Responsibilities:** một Auth event subscription với error/dispose handling; server profiles.role resolution; unresolved fail-closed; currentSession restore/refresh/signOut; generation khi account/token authority/role thay đổi theo agreed contract; trusted manager/shipper provisioning ngoài customer registration.
- **UI scope:** MH01/02 chưa có; implement trong feature task riêng khi được giao, không giả vờ đã có login.
- **Tests:** session restore, logout trong modal/pending read, A→B, A→same-A-new-generation, role unresolved/revoked, invalid/expired token, profile unavailable, stream error/dispose.
- **DoD:** actual Auth flow + authoritative role tạo existing SessionScope đúng; local privacy regressions PASS và staging sign-in proof riêng. Test fixture credentials không commit/log.

### I2 — Read adapters, bắt đầu Notifications raw read rồi Orders projections

- **Priority / findings:** P0, INT-02/03.
- **Current files:** repository interfaces, DTOs, foundation providers hiện có.
- **Proposed files:** features/notifications/data/repositories/supabase_notification_repository.dart; supabase_notification_target_resolver.dart theo agreed server contract; features/orders/data/repositories/supabase_order_repository.dart. Chỉ thêm datasource abstraction nếu có tái sử dụng/transport responsibility thực.
- **Backend:** raw notifications có row/grants sẵn trong source; page sorting/cursor/count/PATCH ack cần implement adapter thực. Orders cần authorized aggregate producers/envelope; không map raw orders như OrderDetailsDto; không tự tính capabilities/financial authority ở Screen.
- **DI/state:** shared supabaseClientProvider inject vào adapters; replace null composition binding có chủ đích; giữ same provider identities và cache lifecycle. Error thật không fallback fixtures.
- **Tests:** adapter mapping cho envelope success/error, timeout/auth/permission/malformed fields, recipient mismatch, stable order pagination/count/as_of, no double fetch do DI, ack monotonic và exact unread count; expected role-allowed/denied responses.
- **DoD:** ít nhất one authenticated business read từ staging cho từng adapter; logs không PII/key; source/mock phân biệt rõ; schema version và actual response khớp DTO. Chưa kết luận mutations working.

### I3 — Central protected router và handoff callbacks

- **Priority / finding:** P0, ARC-01.
- **Current files:** app/router/app_router.dart, sports_store_app.dart, page constructors/callbacks; notification_target.dart.
- **Files affected:** central router và nếu cần một router session refresh adapter trong app/router; giữ pages API trừ necessity có review. Cập nhật screen_mapping.md cùng change.
- **Navigation:** role-prefixed routes của bốn màn theo existing specification; order ID parameter; shared /notifications guards; login path theo Auth owner. Catalog/returns/COD/chat/task chưa implement phải unavailable, không route sang fake page hoặc hardcode user ID.
- **State/theme:** route scope nằm trên Navigator để modal guard dùng đúng provider container; dùng existing shared visual scope, không redesign global theme.
- **Tests:** unauth/unresolved/wrong-role deep link, auth refresh redirect, business ID validation, manager order→back giữ feed, notification current permission check, logout khi dialog/modal mở, same-user new generation, denied target không lộ cached PII.
- **DoD:** main entrypoint truy cập bốn màn bằng data adapters và đúng role; debug Preview vẫn tách biệt; route matrix automated PASS; không xem preview Navigator push là production router proof.

### I4 — Command VM/persistence và ordering/inventory server transactions

- **Priority / finding:** P0, INT-04; độc lập R2 UI refactor.
- **Current files:** OrderRepository, PendingOrderCommandStore, StableOrderCommand, receipt/result DTOs, order_action_dialog.dart và acceptHistoricalReceipt.
- **Proposed files:** orders/presentation/view_models/order_action_view_model.dart; protected pending store trong shared/Auth infrastructure theo CIN-01; server workflow migrations mới bằng CLI trong task riêng.
- **Contract:** persist stable request/payload trước first send; same-key retry/relaunch; unknown outcome lookup; changed payload conflict; receipt là historical result, invalidate/refetch current, không overwrite canonical cache.
- **Core ordering:** Checkout/Inventory owner implement atomic full-cart reservation + snapshots + Hà Nội server validation + fee30k, no stock reserve on cart add; không client-supplied prices/totals/time.
- **Auto-confirm:** server task một giờ, order row lock/precondition phối hợp cancel/confirm; không tự assign shipper, không device timer.
- **Tests:** concurrent last-stock buyers, all-or-nothing reserve, duplicate request/payload conflict, cancel-confirm race, timeout/restart lookup, pending store account isolation, receipt replay không rollback state, denied roles; không fake success khi storage/network unavailable.
- **DoD:** transaction/idempotency/recovery proof staging, allowed/denied backend tests và client command-state tests PASS; UI chỉ dispatch/reflect result.

### I5 — Delivery → COD integration trước returns

- **Priority / findings:** P0, INT-04/05 và SEC-01.
- **Files affected:** Deliveries/COD/Inventory owned repositories/models/views khi được giao; OrderDetails projection/adapters, Mh09OperationalActions callback integration, docs/CIN contracts; CLI-generated migrations cho actual operations.
- **Contract:** current assignee/custody, initial pickup/dispatch ledger, tối đa hai outbound attempts trên order kể cả đổi task/shipper; không áp attempt cap đó cho return pickups; successful delivery và full COD thu cùng transaction.
- **Permissions:** current necessary task projection; manager-only full money receipt; COD history vẫn của collecting shipper dù task/return đổi. Không reconcile partial hoặc offset refund.
- **Tests:** reassign/revoke old task visibility, old assignee late action denied, attempt #3 denied sau task change, pickup ledger replay once, COD expected bằng order full total, receipt partial denied, return không xóa COD obligation.
- **DoD:** placement→delivery→collected→store-received chạy end-to-end staging với đúng role; nút operational chỉ mở khi owner API có proof. Các MH10/11/12/18 chưa có phải được giao implementation riêng.

### I6 — Cancellation, failed delivery, returns/refund và event producers

- **Priority / findings:** P1 sau I4/I5, INT-04/05.
- **Files affected:** Orders/Returns/Inventory/Delivery backend workflows và repository adapters; notification producer server helpers theo accepted CIN-09; không tạo producer fan-out trên Screen.
- **Contract:** failed goods chỉ sellable sau manager receive/inspect; không tự restock lost/damaged; return ≤7 ngày tại submission, đúng reasons/video/one active; goods actually received; inspection không đồng nghĩa refund approval; full merchandise+original fee, manager transfer evidence; rejected return free redelivery không COD; failed redelivery chờ manager.
- **Notifications:** producer business change + canonical event + recipient manifest/dedup trong transaction; replay không tạo new event/recipients; text không chứa bank/evidence/PII ngoài quyền; target check quyền lúc mở.
- **Tests:** return boundary/server clock/video missing, two active requests race, missing-item actual goods, refund full total/role/evidence, COD remains collected/owed independent return, free redelivery failure pending, transactional event rollback/replay/recipient changes.
- **DoD:** accepted state transitions + staging tests, manager/customer-only bank/evidence and no shipper access; client cannot unlock bằng local clock/status assumption. UI mới chỉ khi feature task được giao.

### I7 — Storage và Chat/Realtime theo scope

- **Priority:** P2 theo feature readiness; không thêm push/GPS hoặc media chat.
- **Files affected:** feature-owned data adapters mới cho Storage/Chat; shared client hiện có; chat contracts chung MH19/MH20; policies/migrations chỉ nếu review thật sự cần.
- **Storage:** private buckets đúng paths; authenticated upload và authorized read/signed URL; server return submission kiểm video tồn tại/liên kết; evidence ownership, upload failures/orphan handling theo accepted policy; không đổi bucket public để tiện demo.
- **Chat:** một conversation/customer, text only customer↔manager, sender session, stable client message ID, unread marker server, shipper denied. Chốt activity timestamp và visible-message read semantics.
- **Realtime:** subscriptions chỉ khi đã cần và được authorize; dispose/recreate trên session switch, không để old account event publish. Không gọi 3-second polling hiện tại là Supabase Realtime.
- **Tests:** Storage role allow/deny, unrelated path/object access, evidence URL expiry, logout during upload; chat idempotent concurrent open/send, participant denies, subscription stop/reconnect/account switch.
- **DoD:** source + authenticated runtime proof riêng mỗi service; no private public URLs; same shared ChatRepository cho hai owner.

### I8 — End-to-end và production readiness evidence

- **Priority:** P0 gate trước release, không thực hiện trong audit.
- **Files affected:** staging/integration tests mới tại integration_test và supabase/tests; cấu hình môi trường/release task riêng; docs/QA evidence directory mới.
- **Checks:** migrate history/schema/policy metadata khớp deployed target; allowed/denied mỗi role; stale JWT/role refresh; offline/timeouts/retry/partial failure; concurrency/idempotency; full main router flows; environment selection và Android release package/signing/network.
- **Smoke progression:** endpoint probe hiện tại → Auth/session/profile → authorized page/count/detail read → private Storage → commands/lookup/server job → ordering/delivery/COD → failure/returns/refund/events → chat/Realtime nếu đã implement.
- **Production writes:** chỉ dùng staging fixtures trong test workflow; mọi live production write/SQL fixture/migration test cần user phê duyệt riêng.
- **DoD:** từng feature có status SOURCE-EVIDENCED/CONFIGURED ONLY/VERIFIED CONNECTED rõ ràng, runtime request/role/schema version evidence không PII/credentials; không nâng toàn dự án PASS vì một endpoint GET hoặc fixture tests.

## E. Regression strategy và acceptance chung

Fresh baseline của audit: analyzer PASS và **763 safe existing tests PASS**. Logs trong verification; không coi đó là full suite hoặc rerun nguyên checkpoint MH17 441. Trước mỗi change dùng working source thời điểm đó và các approved UI artifacts, không HEAD.

| Risk | Tests phải ưu tiên |
|---|---|
| Session/privacy | A→B; same-user new generation; logout/expiry khi dialog/modal/read/open đang pending; cache identity replacement/blocked cache; late response không publish |
| Pagination/cache | head refresh replaces tails; query/filter generation; cursor loop/invalid/malformed; deny clears private data; same owner stale display chỉ theo provenance; count authority riêng |
| Navigation/interaction | no unauthorized target, full role matrix, route stack rapid tap, read/open independence, modal survives opener disposal nhưng revoke khi session mất |
| Theme/layout | approved visual parity, narrow widths, large text, keyboard insets, semantics/hit targets; ghi evidence mới vào directory mới |
| Money/stock/workflow | atomic reservation, race/duplicate/idempotency, two outbound attempts toàn order, no automatic sellable restock, COD obligation independent return, full refund/fee |
| Backend permissions | authenticated customer/manager/shipper/anon allowed và denied; current/historical assignments; customer stock columns theo contract; private bank/video/evidence; no spoofed metadata role |

Sau khi thay Dart/pubspec trong task được duyệt: dart format changed files, flutter analyze, relevant tests, flutter pub get chỉ khi dependency đổi và preserve lockfile. Không cài package chỉ vì plan gợi ý.

Không cần broad test reruns lặp lại nếu không có thay đổi/failure mới. Không chạy legacy capture/evidence writers đè ảnh cũ; nếu visual evidence cần thiết, tạo output directory mới có provenance.

## F. Quyết định cần user/team xác nhận

| Quyết định | Owner cần tham gia | Không có quyết định thì |
|---|---|---|
| Có ưu tiên R2/R3 tùy chọn hay giữ hiện tại để làm integration trước | User + Bảo | Giữ approved UI/source hiện tại |
| F05: single-flight theo notification/target/page và release lúc nào; pending read hit có được open | User + Notifications/router owner | Giữ behavior characterization hiện tại, F05 pending |
| F03 accepted target matrix và server resolver contract | Notifications + Auth/router + target owners | Không gọi mọi target permissions PASS |
| F07 canonical event/recipient/notification_only fixtures | Notifications + producer owners | Preview vẫn chỉ là UI demo, F07 pending |
| Environment direct Supabase và actual deployed contracts; backend ngoài workspace nếu có | Team/backend owner | Chỉ endpoint probe được VERIFIED |
| Auth/profile/role stream, routes và protected pending storage | Dung An + shared/router owner | Protected production runtime chưa khả dụng |
| Current task/history access và allowed customer stock fields | Minh Đức + Catalog/Inventory owners | SEC-01/02 giữ NEEDS DECISION; không tự thu hồi/mở rộng RLS |
| Checkout geometry/store location, custody/inspection, COD/return cutoff/producer contracts còn pending | Các owner theo CIN-02–09 | Không invent policy hoặc enable mutations |
| Bản business report v3.0/NT01–NT30 đầy đủ để trace acceptance | Team | Không tuyên full NT01–NT30 PASS từ partial docs/tests |

Khi duyệt, chọn task cụ thể với scope/files/DoD ở trên. Báo cáo này không phải ủy quyền triển khai tất cả tasks.

**PRM393 — FULL ARCHITECTURE & SUPABASE AUDIT COMPLETE — PLAN READY FOR REVIEW**
