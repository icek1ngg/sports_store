# MH09 — Source, dependency và LOC audit

Đếm **physical lines gồm comment/blank**, không lấy số nonblank của `Measure-Object -Line`.
Inventory01 lịch sử: [loc_inventory.json](artifacts/loc_inventory.json); current03A2: [verification](artifacts/03a2/verification.json).
Đường dẫn bảng rút gọn theo base ghi rõ, vẫn là relative paths tính từ project root.

## Production entry và read flow

`ManagerOrderDetailsPage(orderId, enablePolling=true, onOpenCod?, onOpenReturn?, onOpenChat?, onCallRecipient?)`.
Ba callback đầu nhận String UUID order/return/customer tương ứng; call nhận recipientPhone snapshot.
Theme → manager FeatureAccessGate → ForegroundRefresh → content/AsyncContent → sections/footer/dialog.
`orderDetailsFoundationProvider(orderId)` → `OrderDetailsFoundationViewModel` → nullable `OrderRepository`.
`SnapshotReadViewModel` sở hữu serialized refresh/retry/lifecycle; EpochCache sở hữu generation/resource epoch.
Không có detail VM riêng tên `ManagerOrderDetailsViewModel`; không tạo provider thay thế.

## Presentation dependency map

Base `lib/features/orders/presentation/`; `*` vượt limit hiện hành, giữ nguyên ở task01.

| Path | LOC/limit | API / trách nhiệm / dependency | Tests / risk |
| --- | ---: | --- | --- |
| `pages/manager_order_details_page.dart` |43/300|Public API/theme/manager gate;209 trước03A2|same6 params/defaults; current owner bên dưới|
| `pages/mh09/mh09_detail_content.dart` |275/300|ConsumerStateful read/session/cache/freshness/tickets/dialog/callback coordinator|same-frame/reparent/session/nav/late regressions|
| `pages/mh09/mh09_detail_body.dart` |82/180|5read components +shared lifecycle/timeline +OperationalActions, data-only|same aggregate/snapshots;40items reachable|
| `pages/mh09/mh09_page_layout.dart` |45/180|content-sized header/SafeArea/reserved body/footer35%scroll|no ref/business rules; không duplicate header/footer|
| `pages/mh09/mh09_legacy_detail_body.dart` |129/180|Mh09LegacyDetailBody: detail + original header, shared lifecycle/timeline|copy composition cũ; callback/data-only|
| `pages/mh09/mh09_legacy_contact_actions.dart` |81/180|Mh09LegacyContactActions: customerId/phone +2 callbacks|đúng snapshot IDs; unavailable nguyên bản|
| `pages/mh09/mh09_legacy_action_footer.dart` |176/180|Mh09LegacyActionFooter: details/action/predicate +2 flags|order commands và external disabled; gần limit|
| `view_models/order_providers.dart` |151/250|detail/list families, repository DI, receipt hook|foundation test; high: dùng chung MH07/08|
| `widgets/order_recipient_section.dart` |124/180|`OrderRecipientSection(order,buyer?,showPhone)`; snapshot|widgets/page; shared MH07, giữ nguyên|
| `widgets/order_items_section.dart` |113/180|`OrderItemsSection(items,title,showPrices)`; 64px placeholder|widgets/page; shared MH07|
| `widgets/order_payment_section.dart` |119/180|`OrderPaymentSection(order,codSummary?)`; integer VND|null/payment/widget tests; shared MH07|
| `widgets/order_lifecycle_sections.dart` |455/180*|`OrderLifecycleSections` + public Delivery/Cod/Returns sections; typed summaries/callbacks|page lifecycle test; high: 3 domain + layout/helpers|
| `widgets/order_timeline.dart` |358/180*|`OrderTimeline(entries,historyComplete,title)`; dedup/fallback/sort/labels|widgets/foundation; high: actual-event semantics, shared MH07|
| `widgets/order_action_dialog.dart` |204/180*|`OrderActionDialog(orderId,operation,isStillAllowed,submittedScope,sourceCache?)`|dialog/page; high: shared MH07/08, reason/cache listeners|
| `widgets/order_status_badge.dart` |68/180|`OrderStatusBadge(status)`; text/semantics|widget test; low, reuse|
| `widgets/order_notification_theme.dart` |254/180*|`OrderNotificationTheme(child)` + `data(base)`; fonts/tokens|shared all assigned screens; high, giữ nguyên|

Snapshot578 trước03A1: content78–215/scroll216–289/header290–329/contact330–380/footer381–528/helpers529–578.
03A1 từng giữ private consumer content;03A2 chuyển coordinator sang Mh09DetailContent +body/layout mới.
3 legacy files nguyên hash, không import/render trong active page; không tự delete transitional/untracked code.

## Domain / data map

Base `lib/features/orders/`; DTO parse ở `data/models/order_dto.dart`, không phải backend adapter.

| Path | LOC/limit | API / dependencies / risk |
| --- | ---: | --- |
| `domain/models/order_details.dart` |191/150*|`OrderDetails`: aggregate, immutable lists, item total/ID/COD relation checks, timeline dedup; DTO/foundation tests|
| `domain/models/order.dart` |181/150*|`Order`: UUID/status/snapshots/amount/timestamps/attemptCount; all screens share|
| `domain/models/order_capabilities.dart` |50/150|10 bool capabilities; UI không infer quyền từ status|
| `domain/models/order_item.dart` |96/150|snapshot product/variant/attributes/unitPrice/quantity/lineTotal; không image URL|
| `domain/models/buyer.dart` |11/150|`Buyer(id,fullName?)`; khác recipient|
| `domain/models/delivery_summary.dart` |145/150|`DeliverySummary`, `AttemptSummary`; nullable task/shipper/times, count/failure; gần limit|
| `domain/models/cod_summary.dart` |108/150|`CodSummary`: expected/collected/received full amounts, times/actors|
| `domain/models/return_summary.dart` |49/150|`ReturnSummary`: status/reason/times/eligibility; không bank/refund evidence|
| `domain/models/order_timeline_entry.dart` |171/150*|typed source/entity/actor/state/server instant; không duplicate model|
| `domain/models/order_status.dart` |480/150*|status re-exports/labels; legacy outside visual scope|
| `domain/repositories/order_repository.dart` |68/150|getOrderDetails + confirm/reject/cancel/getOperationResult; PendingOrderCommandStore; chưa adapter thật|
| `domain/repositories/order_repository_contract.dart` |1/150|re-export duy nhất; không tạo contract song song|
| `data/models/order_dto.dart` |722/150*|DTO↔domain, enum/wire validation; mapping không tạo transport|

## Shared infrastructure / Preview

| Path | LOC/limit | API / dependency / risk |
| --- | ---: | --- |
| `lib/core/state/snapshot_read_view_model.dart` |183/250|`SnapshotReadViewModel<T>`; refresh10s/retry policy/current-token acceptance; readonly|
| `lib/core/state/epoch_cache.dart` |120/250|`EpochCache` read/begin/accept/invalidate/blockSession; readonly|
| `lib/core/state/read_snapshot.dart` |19/150|`ReadSnapshot<T>.isFresh`: data + !loading + !stale + no failure|
| `lib/core/state/foundation_providers.dart` |16/250|session unresolved default + epoch cache dispose; CIN01 dependency|
| `lib/shared/widgets/feature_access_gate.dart` |63/180|roles + session keyed subtree; privacy checks không thay RLS|
| `lib/shared/widgets/foreground_refresh.dart` |87/180|3s foreground/current route, resume; timer dispose|
| `lib/shared/widgets/async_content.dart` |402/180*|loading/error/stale/expired; shared outside scope|
| `lib/core/utils/display_formatters.dart` |221/150*|formatVnd/Hanoi/status labels; reuse không duplicate|
| `lib/app/router/app_router.dart` |26/300|`appRouterProvider`, route `/` duy nhất; MH09 route target chưa wire|
| `tool/ui_preview/main.dart` |17/250|debug entry → Mh08PreviewApp; giữ nguyên|
| `tool/ui_preview/mh08_preview_app.dart` |44/250|stable ProviderScope trên Navigator; session/repository overrides|
| `tool/ui_preview/mh08_preview_surface.dart` |121/250|`_openOrder(id)` push existing page; pop mounted/scope/cache guard, query refresh|
| `tool/ui_preview/mh08_manager_repository.dart` |181/250|Preview getOrderDetails qua fixture riêng; mutations unavailable|
| `tool/ui_preview/preview_app.dart` |308/250*|legacy UiPreviewApp direct MH09 entry; không thay active harness|

## Tests và violations ngoài MH09

| File | LOC/limit | Vai trò |
| --- | ---: | --- |
| `test/features/orders/presentation/pages/manager_order_details_page_test.dart` |62/400|trước440;2 cases snapshot/layout,7 cases gốc chia vào read_states/actions|
| `test/features/orders/presentation/widgets/order_action_dialog_test.dart` |214/400|reason/session/cache invalidation|
| `test/features/orders/presentation/widgets/order_widgets_test.dart` |300/400|snapshot/semantics/timeline/320px|
| `test/features/orders/presentation/view_models/order_foundation_test.dart` |377/400|generation/receipt/read ordering; gần limit|
| `test/ui_preview/mh08_preview_lifecycle_test.dart` |292/400|6 cases, exact UUID→back canonical refresh|
| `test/ui_preview/mh08_preview_query_test.dart` |142/400|3 query/search/navigation cases|

Broad dependency inventory còn legacy MH07 page1310/card515/test741, order_card351, feed436,
preview fixture709 và visual_layout_test654 vượt gate. Đây không phải quyền refactor hoặc exception được duyệt.
Inventory flags chỉ phân loại, không claim toàn project LOC PASS; owned docs/utilities task01 phải PASS riêng.

## Điểm cần bảo toàn / xử lý sau review

- Giữ nguyên models/DTO/providers/formatters và shared sections; UI mới chỉ compose/render dữ liệu hiện có.
- 03A2 tái hiện cả inactive còn mounted; _owns active/generation/route-active short circuit trước interaction ref read.
- `acceptHistoricalReceipt` đọc scope trước `ref.mounted`; risk shared late callback, chưa có reproducer disposal.
- Shared provider không đổi; sourceCache03A2 explicit captured cache; scope/cache/fresh/current capability recheck giữ authority.
- Confirm/reject hiện dựa canonical `isFresh` + capability, không suy từ status; server precondition vẫn chưa tích hợp.
- No production router/real Auth/repository; Preview test PASS không chứng minh RLS hoặc Supabase connectivity.
- Model chưa chứng minh DeliverySummary không latestAttempt hoặc delivery timeline task thuộc order; server/adapter phải validate links.

## Test extraction / evidence03A1

Base `test/features/orders/presentation/pages/mh09/`: read_states107/actions119/callback_navigation100/session_navigation125 LOC.
Support host/repository/session93 và fixtures103≤150; root entry62. Không thay assertions9 ca gốc.
Thêm6 ca:4 callback IDs trong1case; cancel reason/capability2cases; source disposal/session expiry/late read3cases.
Token comparison toàn8 class bodies giữ nguyên ngoài renames/optional Key và guard đã ghi rõ:
[presentation_preservation](artifacts/03a1/presentation_preservation.json); [test_preservation](artifacts/03a1/test_preservation.json).
LOC/hashes/links/diff ở [verification03A1](artifacts/03a1/verification.json); legacy shared violations ở bảng trên vẫn outside scope.

## Integration03A2 / current tests

7 approved widgets readonly đều active; shared lifecycle/timeline/formatters nguyên trạng, không provider/cache/domain mới.
Existing tests LOC entry62/actions124/read107/callback100/session125; helper93/fixtures103 nguyên hash.
6 new files trong pages/mh09/: access281/action_integration230/component_integration235/navigation_owner197/owner_lifecycle172/preview_navigation_contract89 LOC.
25 new runtime cases;15 existing/81 assertions tương đương sau finder migrations, [test_preservation](artifacts/03a2/test_preservation.json).
138 focused PASS;full391 PASS/2 FAIL: [INTEGRATION_03A2](INTEGRATION_03A2.md) ghi exact protected finder blocker.
Legacy3 files vẫn129/81/176,unused; shared LOC violations ngoài scope giữ nguyên. Task BLOCKED tại full-suite gate.
