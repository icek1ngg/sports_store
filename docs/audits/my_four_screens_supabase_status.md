# Supabase read/write — MH07, MH08, MH09, MH17

Ngày kiểm tra: 27/10/2026, Asia/Saigon. Baseline là current working source. **Auth đã dừng; chưa nghiệm thu.** Lượt này chỉ triển khai Notifications data adapter, opt-in DI và tests; không sửa UI, theme, router, Auth, Orders contracts, migrations/RLS hoặc business mutations.

## Kết quả theo operation

“MISSING CONTRACT” ở Orders nghĩa là thiếu backend runtime contract/projection/RPC thực có; repository interface và owned specification revision1.2 đã tồn tại. Không suy proposed RPC đã deployed.

| Screen | Operation | Repository | Supabase source/RPC | Code status | Runtime verified | Blocker |
|---|---|---|---|---|---|---|
| MH07 | Customer list, status filter, search, pagination | OrderRepository.getCustomerOrders | Proposed get_customer_orders; orders/items raw không đủ aggregate | MOCK ONLY trong Preview; MISSING CONTRACT runtime | Không | Production adapter + authorized aggregate/search/cursor/count/capabilities; Auth/role |
| MH07 | Detail, timeline và thông tin liên quan | OrderRepository.getOrderDetails | Proposed get_order_details | MOCK ONLY; MISSING CONTRACT runtime | Không | Customer-safe timeline/delivery/COD/return projections, backend endpoint |
| MH07 | Customer cancel | OrderRepository.cancelCustomer | Proposed cancel_customer_order | MISSING CONTRACT runtime; dialog chỉ validate/unavailable | Không | Transaction RPC thực có, stable request/receipt/recovery và protected pending store |
| MH08 | Manager list, search/filter/pagination | OrderRepository.getManagerOrders | Proposed get_manager_orders | MOCK ONLY; MISSING CONTRACT runtime | Không | Authorized server aggregate và Auth manager |
| MH08 | Server status counters, failed-delivery warnings | Cùng getManagerOrders/OrderPage | Cùng aggregate, server snapshot as_of/counts/warnings | MOCK ONLY; MISSING CONTRACT runtime | Không | Không tính counters từ page hoặc tự suy warnings ở client |
| MH08 | Confirm | OrderRepository.confirm | Proposed confirm_order | MISSING CONTRACT runtime | Không | Owner-approved transaction RPC deployed + receipt/idempotency/recovery |
| MH08 | Reject | OrderRepository.reject | Proposed reject_order | MISSING CONTRACT runtime | Không | RPC như trên, reason/preconditions và stock release server |
| MH09 | Detail theo ID: buyer/recipient, items/payment, delivery/COD/return summary, timeline/capabilities | OrderRepository.getOrderDetails | Proposed get_order_details | MOCK ONLY; MISSING CONTRACT runtime | Không | Full DTO aggregate và current permissions; external summary contracts |
| MH09 | Confirm / reject / exceptional manager cancel | confirm / reject / cancelManager | Proposed confirm_order / reject_order / cancel_manager_order | MISSING CONTRACT runtime | Không | RPC thực có; custody/stock/receipt/recovery; dialog chưa gửi command |
| MH09 | Phân công/giao lại/hoàn/kiểm nhận và links COD/returns/chat | External callbacks, operational actions hiện disabled | Delivery/Inventory/COD/Returns owner APIs chưa cung cấp | MISSING CONTRACT | Không | Không có operation/callback backend hợp lệ để bật; không tự thêm nghiệp vụ |
| MH17 | Notification list All/Unread, pagination | SupabaseNotificationRepository.getPage | GET notifications, OP-N01 | CODE IMPLEMENTED BUT NOT RUNTIME VERIFIED; opt-in | Không | Auth/role do nhóm cung cấp, approved composition + QA session/schema/RLS verification |
| MH17 | Exact unread count toàn inbox | SupabaseNotificationRepository.getUnreadCount | HEAD notifications, count=exact, OP-N02 | CODE IMPLEMENTED BUT NOT RUNTIME VERIFIED; opt-in | Không | Như trên; không thay missing/error count bằng 0 |
| MH17 | Current target resolution | NotificationTargetResolver.resolve; binding hiện null | OP-N04 authorized target reads còn thiếu | MISSING CONTRACT; BLOCKED BY AUTH/ROLE | Không | Target owners cung cấp current authorized reads, manager task→order mapping, route callback |
| MH17 | Mark read | SupabaseNotificationRepository.markRead | GET own row → PATCH read_at → SELECT canonical row, OP-N03 | CODE IMPLEMENTED BUT NOT RUNTIME VERIFIED; opt-in | Không | Verify deployed read-time trigger/grants/RLS; approved QA/staging trước write thử |

Supabase client/config đã tồn tại (**CONFIGURED ONLY** ở mức app). Không operation nào trong bảng được gắn CONNECTED & RUNTIME VERIFIED. Preview tiếp tục dùng fixture cũ.

## Adapter đã triển khai và đường đi dữ liệu

- Tạo [supabase_notification_repository.dart](../../lib/features/notifications/data/repositories/supabase_notification_repository.dart), implement đúng NotificationRepository hiện có, dùng shared SupabaseClient và callback đọc SessionScope từ subsystem ngoài. Không import/reuse Auth feature đang dừng.
- Thêm supabaseNotificationRepositoryProvider tại [notification_providers.dart](../../lib/features/notifications/presentation/providers/notification_providers.dart). **Canonical notificationRepositoryProvider vẫn null mặc định.** Team chỉ opt-in binding sau khi cung cấp Auth/role được nghiệm thu; không tự sửa main hoặc kích hoạt nhánh Auth dở.
- Không tạo OrderRepository giả hoặc resolver giả trả thành công; Orders repository và target resolver giữ unavailable/null.

~~~text
MH17 Screen → canonical page/count foundations hoặc InteractionViewModel
            → notificationRepositoryProvider
            → [opt-in tại composition do nhóm cung cấp]
            → SupabaseNotificationRepository → shared SDK → notifications

MH07/08/09 → existing foundation providers / action dialog
            → OrderRepository interface / null binding
            → [thiếu production aggregate + transactional RPC]
~~~

N01 dùng explicit 9 columns, own recipient + RLS, read_at IS NULL khi Unread, sort created_at DESC/id DESC, limit+1; cursor Base64URL đúng sáu fields theo §11, bound user/filter/limit và strict timestamp/UUID. Không đưa raw cursor vào filter. page.asOf/unreadCount giữ null, không tạo server snapshot giả.

N02 là exact count riêng cho toàn inbox chưa đọc, không theo page/filter đang hiển thị. List/count không phải atomic snapshot.

N03 GET đúng own row trước: đã đọc thì trả canonical row, không PATCH lặp. Nếu chưa đọc, chỉ gửi read_at bằng created_at UTC đã đọc từ server như non-null signal theo OP-N03; không dùng client clock hoặc timestamp tự tạo. private.stamp_read_time trong migration phải thay signal bằng clock_timestamp()/giữ first read. Chỉ full selected server ACK hợp lệ mới được trả về; zero rows, wrong owner/ID, null read_at hoặc immutable fields thay đổi đều bị từ chối. Mất ACK thì lần gọi lại GET trạng thái canonical, không giả thành công.

Mỗi operation pin exact SDK session/token và full supplied SessionScope/generation, kiểm lại sau await. Same-user new token, account switch, logout, expiry và disposed provider đều reject late result. Không có cache/provider authority mới. Đây là request guards; không phải triển khai Auth hoặc thay server authorization.

Source contracts đã đối chiếu: [Data/API OP-N01–03 và §11](../technical_specification_mh07_mh08_mh09_mh17_data_api.md), schema notifications và notifications_read/update + stamp_read_time trong ba migrations hiện có. Chưa xác minh chúng deployed; chưa chạy SQL/migration.

## Đọc/ghi thật và mức kiểm chứng

| Mức | Kết quả mới |
|---|---|
| A — Repository unit/SDK tests | PASS; SupabaseClient thật qua HTTP MockClient, không phải cloud |
| B — Provider integration tests | PASS; canonical foundations/interaction → concrete adapter, count refresh, account change, disposal, opt-in isolation |
| C — Real Supabase business read | NOT VERIFIED, không chạy: không có approved QA session |
| D — Real Supabase write | NOT VERIFIED, không chạy: không có approved staging/test record |
| E — End-to-end production Auth/Router | NOT VERIFIED; ngoài phạm vi, Auth chưa nghiệm thu và entrypoint còn lỗi |

**Không có thao tác nghiệp vụ nào thực sự đọc hoặc ghi Supabase trong lượt này.** Probe endpoint của audit trước không phải authenticated business read/write proof.

**823 focused tests PASS** (763 existing + 60 mới). Tests mới kiểm cursor/tie boundary, count zero/error, canonical ACK, repeated/concurrent reads, lost ACK recovery, account/same-user SDK/generation changes, expiry, foreign/malformed rows, connection/pool errors, disposal và opt-in DI. Mock mô phỏng response không chứng minh trigger/RLS trên server đã PASS.

- Analyzer Notifications: **PASS, no issues**.
- Analyzer Notifications data tests: **PASS, no issues**.
- flutter analyze toàn dự án: **FAIL**, 58 diagnostics thuộc main/Auth đang dở; hiện main.dart có ref.watch() thiếu đối số và child dạng record; tests/features/auth tham chiếu implementation không còn tồn tại. Không sửa vì user đã cấm tiếp tục Auth/main integration.
- Format changed files và diff whitespace check: PASS. Không chạy Auth tests, visual capture writers, build Android hoặc sửa assertions cũ.

Evidence: [823 tests](my_four_screens_supabase_verification/focused_tests_reviewed.log), [feature analyzer](my_four_screens_supabase_verification/analyze_notifications_reviewed.log), [test analyzer](my_four_screens_supabase_verification/analyze_repository_tests_reviewed.log), [full analyzer FAIL](my_four_screens_supabase_verification/analyze_full_reviewed.log), [workspace guard](my_four_screens_supabase_verification/source_guard_final.json).

## Auth đang dở — giữ nguyên, không nghiệm thu

Những file đã tạo/sửa trong lượt I1 trước khi có lệnh STOP:

- lib/features/auth/domain/models/auth_session.dart
- lib/features/auth/domain/repositories/auth_repository.dart
- lib/features/auth/data/repositories/supabase_auth_repository.dart
- lib/features/auth/presentation/view_models/auth_session_view_model.dart
- lib/features/auth/presentation/widgets/auth_session_bootstrap.dart
- test/features/auth/{auth_test_support,auth_session_view_model_test,supabase_auth_repository_test,auth_session_bootstrap_test}.dart
- lib/main.dart; lib/core/state/foundation_providers.dart; pubspec.yaml; pubspec.lock; docs/api_contracts.md; docs/features/auth/I1_AUTH_SESSION_HANDOFF.md và evidence I1.

Ngay đầu phạm vi mới, năm implementation files trong lib/features/auth ở trên đã không tồn tại; tests/tài liệu/wiring I1 còn dở. Lượt này không xóa, restore, rollback hoặc tiếp tục chỉnh chúng. Kết quả I1 cũ không được xem là baseline đã nghiệm thu.

Hash còn phát hiện main.dart thay đổi trong lúc làm task, ngoài các patch của lượt này. Chỉ báo trạng thái hiện tại, không suy đoán người thay đổi hoặc ghi đè. Phần source hiện có do task này sửa chỉ là Notifications DI; tạo thêm adapter và ba test/support files.

## Nhóm cần cung cấp để hoàn tất

1. Auth owner cung cấp accepted current SessionScope/generation + SDK session, xử lý entrypoint/tests Auth dở và chịu trách nhiệm production composition; không dùng nhánh I1 dở làm bằng chứng.
2. Backend owner xác nhận deployed notifications columns/grants/own-recipient RLS/read-time trigger. Cấp QA session qua kênh an toàn và environment đã phê duyệt để làm read smoke. Write smoke cần staging/test record và user phê duyệt riêng.
3. Orders backend cung cấp actual deployed get_customer_orders/get_manager_orders/get_order_details với đúng aggregate DTO/count/cursor/sanitization; và confirm_order/reject_order/cancel_customer_order/cancel_manager_order/get_order_operation_result transactions, receipt/idempotency/recovery. Tên hiện tại là proposed; không được gọi như endpoint đã tồn tại.
4. Owner shared infrastructure cung cấp protected pending command store; các owner Delivery/COD/Returns/Inventory cung cấp accepted summaries/preconditions. Không client UPDATE status/stock/money.
5. Target owners cung cấp authorized target reads và callbacks cho OP-N04. F03/F05/F07 MH17 vẫn pending; task này không đóng chúng.

Đã dừng đúng phạm vi bốn màn. Không tự triển khai Auth, router, UI refactor hoặc database changes.
