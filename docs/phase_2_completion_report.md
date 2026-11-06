# Báo cáo hoàn tất Phase 2 — Flutter Presentation

Ngày 10/10/2026. Baseline Technical Specification revision 1.2; Phase 1 commit `8e982ac`, 92 tests. Continuation từ source có sẵn, không triển khai lại dự án.

## 1. Quyết định

**PHASE 2 COMPLETE WITH EXTERNAL LIMITATIONS.** Presentation MH07/MH08/MH09/MH17 và unit/widget tests đạt quality gates local. Auth/router/backend production còn unavailable/disabled; đây không phải acceptance cho RLS, transactions hay end-to-end workflows.

Đầu lượt: nhánh `feature/orders-notifications-phase2`, HEAD `4d22a8d` — `wip: implement phase 2 presentation and tests`, tracked working tree/index sạch, 11 file untracked. Chạy lại trước sửa: Notifications **50 PASS/1 FAIL**, full suite **154 PASS/1 FAIL**, cùng lỗi polling pagination. Các số 132/5 và 21/4 trong báo cáo lịch sử đã lỗi thời.

## 2. IMPLEMENTED AND TESTED

| Phần | Presentation hoàn thiện | Đối chiếu revision 1.2 |
|---|---|---|
| MH07 | Customer gate, server search debounce/filter 10 trạng thái/count, cursor pagination, detail/tracking modal, recipient/items/payment/timeline, cancel dialog, return intents, async/stale states, giữ query khi quay lại | Main §6/12; Data/API §4/6/7.2.1 |
| MH08 | Manager gate, buyer search/status filters/server counts, cards/warnings, confirm/reject dialogs/reason validation, callback MH09 hoặc unavailable, pagination/refresh/stale | Main §7/12; Data/API §4/6/7.2.1 |
| MH09 | Buyer/recipient snapshots, items/subtotal/fee/COD total, timeline, bốn lifecycle riêng, manager dialogs, external actions disabled/unavailable, safe callbacks | Main §8/12; Data/API §3–4; CIN-03/04/05/06 |
| MH17 | All/unread, whole-inbox server badge, paging/dedup, foreground head polling, canonical mark-read acknowledgement, typed target resolution, read/navigation độc lập, notification-only modal, session/denial isolation | Main §9/12.5; Data/API §11–12; DR-03/04 |
| Shared | FeatureAccessGate, ForegroundRefresh, thông báo tiếng Việt, current capability recheck, responsive/text scaling | Main §12.2–12.5 |

Reuse Riverpod DI, SessionScope, EpochCache, SnapshotReadViewModel, retry policy, repository contracts, Phase 1 models/DTOs/widgets, AsyncContent và AppTheme. Không đổi contracts Phase 1, pubspec/lockfile, central router, Supabase client, theme hoặc migrations. Repositories/session mặc định fail closed; fakes chỉ trong tests. Orders dialogs không gửi mutation hoặc báo success giả khi transport/protected store chưa có.

## 3. Bugs fixed

- Poll từ cursor page từng tạo lại head provider: initial read cộng explicit refresh thành request dư/timeout timer dư. Giữ head provider được watch khi duyệt nhiều trang; mỗi poll chỉ một head request, busy query không queue poll khác.
- `invalid_cursor` tại MH07/MH08/MH17 reset/refetch canonical head, không retry mãi cursor cũ. ID merge/cursor history ngăn duplicate và cycle.
- Next-page Orders denial xóa rows/counts/actions/cursors, hiển thị đúng session unavailable/expired thay vì accepted empty. Giữ private failure qua query changes; post-frame/head response trước denial không rehydrate. Chỉ explicit authoritative refresh phục hồi.
- MH17 list hoặc count denial ẩn cả inbox/badge/actions, dừng polling, invalidate transient interactions, che modal đang mở và chặn late navigation. Chỉ phục hồi sau explicit refresh xác nhận cả head/count fresh cùng scope/cache/query.
- Interaction notifier rebuild cùng phiên có thể nhận callback cũ. Lifecycle/cache identity guards ngăn obsolete acknowledgement/resolver ghi vào lifecycle mới; tiếp tục dùng SessionScope/EpochCache.
- Refresh trả cùng immutable OrderPage instance không khóa pagination/actions vĩnh viễn.
- MH07 return creation kiểm tra fresh snapshot, current scope/ownership/capability lúc render và trước callback.
- Sửa test async/fixture: hoàn tất pending responses, kiểm tra disposal thực tế, scroll lazy footer, chọn modal button và invalidate đúng captured modal cache. Không bỏ timer assertions, suppress analyzer hay chạy polling pumpAndSettle vô hạn.

Unread badge: count từ server trên toàn inbox, không đếm một trang/filter. Null không thành 0; badge ẩn khi null hoặc 0, giữ exact count trong semantics và dùng 99+ chỉ để hiển thị. Main §9 không yêu cầu badge chữ 0; giữ shared UnreadBadge semantics đã PASS Phase 1. Mark-read không optimistic decrement/remove: đợi canonical acknowledgement rồi invalidate/refetch; unread filter bỏ row sau reload. Failure cho explicit retry.

## 4. Files modified trong continuation

Không tạo lại các file đã tồn tại; các file untracked bên dưới có trước continuation.

| File | Thay đổi |
|---|---|
| `lib/features/notifications/presentation/pages/notifications_page.dart` | Head retention, cursor, denial/recovery, modal/navigation |
| `lib/features/notifications/presentation/view_models/notification_interaction_view_model.dart` | Lifecycle/cache guards |
| `lib/features/orders/presentation/pages/customer_orders_page.dart` | Private failure, cursor, identical refresh, fresh return capability |
| `lib/features/orders/presentation/pages/manager_orders_page.dart` | Private failure, cursor, identical refresh |
| `test/features/notifications/presentation/pages/notifications_page_test.dart` | Poll/paging/filter/count/denial/ack/dispose regressions |
| `test/features/notifications/presentation/pages/notifications_session_test.dart` | Expiry during poll, denial khi modal đang mở |
| `test/features/notifications/presentation/view_models/notification_interaction_view_model_test.dart` | Retry, denied target, obsolete resolver/ack |
| `test/features/orders/presentation/pages/customer_orders_page_test.dart` | Denial/late head/cursor/identical refresh/stale return + fixture fixes |
| `test/features/orders/presentation/pages/manager_orders_page_test.dart` | Denial/cursor/identical refresh + fixture fixes |
| `test/features/orders/presentation/pages/manager_order_details_page_test.dart` | Format, giữ nguyên behavior/assertions |
| `docs/phase_2_completion_report.md` | Báo cáo kiểm chứng hiện tại |

## 5. Tests và verification thực tế

Thêm **23 regression tests** so với đầu continuation: **15 Notifications + 8 Orders**. Full suite **178 PASS/0 FAIL**, gồm **92 baseline + 86 Phase 2 tests**. Không sửa/xóa tests Phase 1.

Coverage mới: multi-page head refresh/new notifications/new cursor chain/dedup; busy poll; count toàn inbox 55/56 và 41/40 dù chỉ vài rows; pending filter response; invalid cursor; disposal/expiry during poll; mark-read retry/unread-filter removal; denied/unavailable target; late resolver sau expiry/dispose/rebuild; late ack sau invalidation; list/count denial và modal privacy; Orders next-page denial/pre-denial head/identical refresh/stale return. Existing tests tiếp tục cover cross-user isolation, search/10 filters, loading/empty/error/stale, dialogs/current capability, long text và responsive. MH07/MH08 test 320/360/412px/landscape; MH09/MH17 long text/320px/text scale 2.

| Lệnh/check cuối ngày 10/10/2026 | Kết quả |
|---|---|
| `dart format` trên 21 Dart files Phase 2, tracked + untracked | **PASS**, lần cuối 0 changed |
| `flutter analyze --no-pub` | **PASS**, No issues found |
| `flutter test --no-pub test/features/notifications --reporter expanded` | **PASS**, 66 tests |
| `flutter test --no-pub test/features/orders/presentation/pages test/features/orders/presentation/widgets/order_action_dialog_test.dart --reporter expanded` | **PASS**, 41 tests |
| `flutter test --no-pub --reporter expanded` | **PASS**, 178 tests, 0 failures |
| `git diff --check` | **PASS** |
| `git diff --no-index --check -- NUL <file>` cho từng untracked file | **PASS**, 11 files, không whitespace errors |
| `flutter pub get` | Không chạy lại: dependencies không đổi; PASS thuộc baseline Phase 1 |
| Supabase/backend/device/performance/pixel integration | **NOT RUN / NOT VERIFIED**, dependency/evidence thiếu |

Tests dispose widget và advance fake time xác nhận không có periodic request mới; complete pending fake transports sau disposal/expiry để chứng minh callback bị bỏ. Không còn pending-timer assertion failures. Không khẳng định production network transport cancel được khi adapter chưa có.

Review độc lập đã rà bốn màn/shared widgets và rereview các fixes; không còn finding P0/P1 cụ thể. Tracked diff và untracked source được review trong scope Phase 2.

## 6. Remaining issues và dependencies

- **BLOCKER/MAJOR trong Phase 2 local:** không còn failure/analyzer issue đã biết.
- **MINOR — Git:** kết quả chưa có checkpoint mới; 11 files còn untracked. Commit hiện tại chưa chứa toàn bộ bàn giao.
- **BLOCKED BY EXTERNAL DEPENDENCY:** CIN-01 Auth owner Dung An/shared infrastructure: trusted role/session epochs, central guards/routes, protected pending-command storage.
- **BLOCKED BY EXTERNAL DEPENDENCY:** Orders production read aggregates/RPC mutations/receipts/job/producers/adapters chưa triển khai hoặc verified trong Phase 2.
- **BLOCKED BY EXTERNAL DEPENDENCY:** CIN-02 Checkout/Inventory; CIN-03/04 custody/stock bridges; CIN-05 Delivery/COD owner Minh Đức; CIN-06/08 Returns owner Sơn và approved cutoff; CIN-09 producers/authorized target routes Checkout/Delivery/COD/Returns/Chat cần acceptance + runtime evidence. Các action/routes liên quan giữ disabled/unavailable.
- **IMPLEMENTED BUT NOT VERIFIED về visual fidelity:** không pixel-compare MH07/MH08/MH09 vì ảnh references thiếu trong repository. MH17 vẫn Proposed Design Main §9.1, không gọi là mockup nhóm đã duyệt.
- **NOT IMPLEMENTED ngoài scope:** SQL/RPC/migrations, production adapters/Auth, receipt persistence, auto-confirm job, producers, Delivery/COD/Returns/Chat workflows, push/SMS/email/mark-all. Không triển khai Phase 3.

## 7. Git working tree

Nhánh vẫn `feature/orders-notifications-phase2`, HEAD vẫn `4d22a8d`. Index không staged changes; **5 tracked modified + 11 untracked**. Không commit/push trong continuation theo yêu cầu hiện tại.

Tracked modified:

- `docs/phase_2_completion_report.md`
- `lib/features/notifications/presentation/pages/notifications_page.dart`
- `test/features/notifications/presentation/pages/notifications_page_test.dart`
- `test/features/notifications/presentation/pages/notifications_session_test.dart`
- `test/features/orders/presentation/pages/customer_orders_page_test.dart`

Chưa vào version control:

- `lib/features/notifications/presentation/view_models/notification_interaction_view_model.dart`
- `lib/features/orders/presentation/pages/customer_orders_page.dart`
- `lib/features/orders/presentation/pages/manager_order_details_page.dart`
- `lib/features/orders/presentation/pages/manager_orders_page.dart`
- `lib/shared/widgets/feature_access_gate.dart`
- `lib/shared/widgets/foreground_refresh.dart`
- `test/features/notifications/presentation/view_models/notification_interaction_view_model_test.dart`
- `test/features/orders/presentation/pages/manager_order_details_page_test.dart`
- `test/features/orders/presentation/pages/manager_orders_page_test.dart`
- `test/shared/widgets/feature_access_gate_test.dart`
- `test/shared/widgets/foreground_refresh_test.dart`

## 8. Next phase readiness

Presentation sẵn sàng bàn giao qua existing DI và typed callbacks. Tiếp theo: user quyết định commit đúng files Phase 2; phối hợp Auth/router owners; xác minh backend contracts/RPC thực sự tồn tại trước adapters; chạy real authorization/mutation/receipt/external-target integration tests. Giữ disabled các dependency thiếu runtime evidence. NFR freshness <=5s cần đo môi trường thật, không suy từ fake-clock tests.
