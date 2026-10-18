# MH08 — Behavior contract

MH08-03A/03B, 15/10/2026. Mapping PAGE lịch sử bên dưới chuyển sang ownership mới ghi cuối tài liệu; contracts giữ nguyên.
Không tài liệu nào ở đây cho phép triển khai Phase 3/backend.

## Traceability

- **S7**: [Technical Specification v1.2 §7](../../technical_specification_mh07_mh08_mh09_mh17.md#7-đặc-tả-kỹ-thuật-mh08).
- **S12**: cùng đặc tả §12.3–12.5: freshness, routes, canonical reads/historical receipts.
- **API**: [Data/API](../../technical_specification_mh07_mh08_mh09_mh17_data_api.md), OP-O02/O04/O05.
- **PAGE**: `lib/features/orders/presentation/pages/manager_orders_page.dart`, các method ghi bên dưới.
- **READ**: `lib/features/orders/presentation/view_models/order_providers.dart`.
- **DIALOG**: `lib/features/orders/presentation/widgets/order_action_dialog.dart`.

S7/API mô tả contract mục tiêu; PAGE/READ/DIALOG mới là bằng chứng implementation local hiện có.
Không coi test fixture hoặc revision tài liệu là bằng chứng backend hoạt động.

## Quyền và isolation

| Quy tắc | Nguồn / implementation |
| --- | --- |
| Chỉ manager xem MH08 | PAGE `ManagerOrdersPage` → `FeatureAccessGate(roles: {'manager'})` |
| Read cần session private hợp lệ + epoch readable | PAGE `_canRead`, shared `SessionScope`/epoch cache |
| Role guard UI không thay authorization backend | S7, API OP-O02; read repository mặc định null, chưa tích hợp production |
| Session đổi phải che/clear private rows và paging | PAGE `_resetForSession`, `_clearPrivateData`, `_queryGeneration` |
| Response cũ không được phục hồi cache/row của query mới | PAGE `_consumeCanonical`, `_consumeNext`: generation/cursor checks |
| Unauthenticated/forbidden không giữ private snapshot | PAGE `effectiveSnapshot`, `_isPrivateDataFailure` |

## Search/filter/counts

- Contract S7/API OP-O02: server search full UUID hoặc tên tài khoản `profiles.full_name`.
- `recipientName` là snapshot người nhận; có thể display fallback có nhãn, không thay semantics search.
- PAGE `_onSearchChanged`: debounce350ms, tối đa200 Unicode scalars; query trim/empty→null qua `OrderQuery`.
- PAGE `_clearSearch`, `_onStatusSelected`, `_setQuery`: reset cursor/extra pages và giữ filter còn lại.
- UI hiện single-status selection hoặc tất cả; hiển thị đủ10 enum; không thêm status Returns.
- Domain `OrderQuery`: default limit20, hợp lệ1–100; status dedup/sort; opaque cursor tối đa2048 chars.
- `OrderPage.totalCount/statusCounts/asOf` là authority; không đếm loaded rows thành KPI.
- API counts theo search/other filters, bỏ riêng status filter; counts và rows cùng snapshot `as_of`.
- KPI pending=`pendingConfirmation`, shipping=`delivering`; chưa có Returns aggregate contract nên bỏ KPI đó.
- Counts đang hiển thị từ canonical page cũ trong lúc refresh: không được coi là fresh; action vẫn khóa.
- Cần test riêng count/asOf khi stale và khi đổi query; chưa claim backend counts đã được xác minh.
- Harness legacy `preview_app.dart` vẫn có manager demo cũ; main03B dùng fixture riêng: exact UUID/account name, không product/recipient.

## Pagination và refresh

- PAGE `_baseQuery.copyWith(cursor: null)` là canonical head; provider families vẫn giữ nguyên identity.
- `_consumeNext`: merge/dedup UUID; page sau không ghi đè counts canonical.
- `_maybeLoadMore`: khi còn dưới360 logical px; nút load/retry giữ cùng semantics.
- `_requestLoadMore`: chỉ khi canRead + canonicalFresh, chống request cursor trùng và load đồng thời.
- `invalidCursor` → bỏ extra cursors và refresh head; next-page error giữ rows cùng session.
- Query/session đổi → generation mới, bỏ nextCursor/history/processed pages; không append late response.
- Refresh head thành công thay rows/counters và reset extra pages; refresh lỗi giữ snapshot stale cùng session.
- Foreground refresh dùng shared `ForegroundRefresh`; `enablePolling` là API page hiện hữu cần giữ.

## Lifecycle và thao tác

| Hành vi | Contract / tình trạng hiện có |
| --- | --- |
| Confirm | S7/API OP-O04: pending → preparing; server không reserve/assign lần nữa |
| Reject | S7/API OP-O05: pending → rejected; reason trimmed nonblank; release reservation một lần |
| Capability | PAGE `_isActionAllowed`: manager/readable + canonical fresh + pending + canConfirm/canReject |
| Recheck | PAGE `_showActionDialog` lookup summary hiện tại; DIALOG check submittedScope/cache/invalidation/predicate lúc submit |
| Local submit hiện nay | DIALOG `_submit`: validate, rồi forbidden/stateChanged/externalDependencyUnavailable; **không dispatch mutation** |
| Lỗi reason | Không gửi khi blank; giữ reason nếu lỗi cùng session; session đổi thì clear reason |
| Idempotency/race | S7/API server contract, chưa tích hợp; không giả success hoặc thêm mutation trong MH08 UI task |
| Auto-confirm | Server event ≥1h; UI không tạo device timer/đổi state tự động |
| Historical receipt | S12.5: không overwrite canonical order/capability/counts từ receipt lịch sử |

Không triển khai giao lại, COD, Returns hoặc kho trong card. Order/delivery/COD/return là lifecycle riêng.
Warnings, assignment, shipper và failure attempts chỉ đọc authorized typed projection; null là thiếu dữ liệu.
Không suy luận incident hoặc “lần1/2” từ tổng tiền, task mới, hay COD status.

## Async và navigation

- Initial loading: shared skeleton/progress; không gán số0 thay count chưa biết.
- Empty toàn bộ khác empty search/filter; PAGE `_emptyMessage` đã phân biệt.
- Initial error có retry; refresh error có stale notice và khóa thao tác xung đột.
- Session unavailable/expired/unauthorized phải che private UI; không render demo thay production failure.
- MH08→MH09 qua `onOpenOrder(String uuid)`; thiếu callback thì detail disabled, ghi rõ unavailable.
- Route contract S12.4: `/manager/orders` → `/manager/orders/:orderId`; production router ngoài scope.
- S7 yêu cầu refresh list + counts khi quay về từ MH09; PAGE callback hiện là `void`, chưa có return-refresh wiring được kiểm chứng.
- Return-refresh wiring dành MH08-03B qua Preview callback/Navigator completion;03A chưa triển khai, giữ signature page.
- Hiện `tool/ui_preview/main.dart` import harness MH07; multi-screen harness chưa phải runtime entrypoint.
- Preview phải giữ ProviderScope trên MaterialApp/Navigator, không key theo scenario; guard mounted sau await.

## External dependencies và giới hạn

API read/mutation, trusted Auth/roles, server counts/clock, authoritative warnings, MH09 router integration còn phụ thuộc Phase3/owner khác.
Preview chỉ DI demo theo domain contract và phải ghi rõ demo; manager action tiếp tục unavailable.
Không thêm call shipper, bank/evidence, Returns KPI hoặc bottom tab khi thiếu contract/callback.
Mọi gap ở đây là việc cần kiểm chứng/giới hạn tích hợp, không phải yêu cầu tự mở rộng scope.

## Mapping implementation03A

- PAGE giữ `onOpenOrder(String uuid)`/`enablePolling`, manager gate và shared theme.
- `Mh08FeedCoordinator` sở hữu state/methods canonical/privacy/generation/paging từng ở PAGE; `Mh08QueryCoordinator` giữ editing350ms/Unicode200/clear/status.
- `watchMh08Reads` chỉ wire shared provider families/listeners/post-frame acceptance/retry; không thêm cache/provider/repository.
- Query/session reset vẫn clear head/rows/cursors; session đổi hủy pending debounce để timer phiên cũ không apply query muộn.
- `_canRead` short-circuit mounted+active trước WidgetRef; dialog capture sourceCache/scope trước await và relookup current summary/capability/freshness khi submit.
- Counts/asOf authority vẫn canonical; next page chỉ merge UUID. Expired/forbidden che rows/counters, stale không cấp capability.
- Navigation recheck readability/current summary và UUID thật; không callback thì disabled. Preview/router/return-refresh chưa sửa.
-70 focused +246 full regression PASS; backend vẫn unavailable, không dispatch mutation hoặc claim Android runtime verification.
