# MH08 — Danh sách đơn hàng của quản lý

Ngày cập nhật:19/10/2026 (Asia/Saigon). **MH08 đã được người dùng chốt**, yêu cầu commit/push milestone MH08.
Trạng thái và kết quả hiện tại: [HANDOFF](HANDOFF.md), [ANDROID_ACCEPTANCE](ANDROID_ACCEPTANCE.md).
Approval: **MH08 — USER APPROVED,19/10/2026**. Chưa bắt đầu MH09.
Phạm vi Git và kiểm tra snapshot19/10: [GIT_RELEASE](GIT_RELEASE.md).

## Mục tiêu và ownership

Hoàn thiện visual theo HTML, bảo toàn Riverpod/read contracts Phase 2.
Bảo sở hữu MH08 trong feature `orders`; màn dùng chung order model/repository.
Preview/manager fixtures đã nối03B, visual tinh chỉnh04B2;04B3 chỉ verification, production sources giữ nguyên.
Được phép lưu/push MH08 lên Git theo yêu cầu19/10; không tự sửa/chuyển MH09/MH17/backend.
MH07 đã APPROVED theo chỉ dẫn người dùng hiện tại; báo cáo MH07 cũ ghi chưa duyệt là lịch sử.

## Đọc tối thiểu cho session tiếp theo

1. `AGENTS.md` ở project root.
2. [HANDOFF](HANDOFF.md), [ENGINEERING_RULES](ENGINEERING_RULES.md).
3. [UI_SPEC](UI_SPEC.md) hoặc [BEHAVIOR_CONTRACT](BEHAVIOR_CONTRACT.md) theo task.
4. Chỉ source/test cần sửa; không nạp lại toàn bộ Phase 1/2.

## Tài liệu nguồn

- [HTML MH08](../../ui_mocks/MH08_Manager_Order_List.html): visual reference, không phải business API.
- [Technical Specification v1.2](../../technical_specification_mh07_mh08_mh09_mh17.md): §7, §12.3–12.5, §13.1, §17.
- [Data/API](../../technical_specification_mh07_mh08_mh09_mh17_data_api.md): OP-O02/O04/O05.
- [Acceptance tests](../../technical_specification_mh07_mh08_mh09_mh17_tests.md): T08 và TX.
- [Screen mapping](../../screen_mapping.md), [Business states](../../business_states.md), [API contracts](../../api_contracts.md).
- [MH07 review lịch sử](../../ui_review_mh07.md): lifecycle fixes cần bảo vệ.
- [TEST_PLAN](TEST_PLAN.md), [MANUAL_REVIEW](MANUAL_REVIEW.md): kiểm chứng và approval.

## File map hiện có (đường dẫn từ project root)

| File | Trách nhiệm / LOC audit |
| --- | --- |
| `lib/features/orders/presentation/pages/manager_orders_page.dart` | Access/lifecycle/composition/dialog/navigation; **288**, trước768 |
| `lib/features/orders/presentation/view_models/order_providers.dart` | Shared read providers, **151**; giữ identity |
| `lib/features/orders/presentation/widgets/order_feed.dart` | Shared async/feed/paging/actions, **436** |
| `lib/features/orders/presentation/widgets/order_card.dart` | Shared generic card/projection, **351** |
| `lib/features/orders/presentation/widgets/order_action_dialog.dart` | Shared validation + unavailable, **204** |
| `lib/features/orders/presentation/widgets/order_notification_theme.dart` | Shared theme/fonts/header, **254** |
| `tool/ui_preview/main.dart` | Entrypoint thật, **17**; import shell chung `mh08_preview_app.dart`, default MH07 |
| `tool/ui_preview/mh07_preview_app.dart` | Stable scope/harness MH07, **163** |
| `tool/ui_preview/mh07_preview_data.dart` | Shared demo repository, **709** |
| `tool/ui_preview/preview_app.dart` | Harness đa màn, **308**; chưa được main import |
| `test/features/orders/presentation/pages/manager_orders_page_test.dart` | Render/loading/responsive, **122**, trước480; split namespace `pages/mh08/` |
| `test/visual_refinement/preview_app_test.dart` | Existing multi-screen preview tests, **123** |
| `test/visual_refinement/visual_layout_test.dart` | Shared responsive regressions, **654** |
| `tool/ui_preview/render_mh08_reference.cjs` | Renderer mới, cùng cách Chromium/Playwright như MH07 |
| `docs/features/mh08/artifacts/` | HTML screenshots, manifest, source hash baseline |

## Dependency boundaries

- Reuse `OrderSummary`, `OrderPage`, `OrderQuery`, capabilities, formatters và read providers.
- Không sửa DTO/schema/repository contracts, Auth/router production, SQL hoặc module khác.
- Ưu tiên `OrderFeed.itemBuilder` để chọn card MH08; giữ default render MH07 nguyên trạng.
- Dùng lại `OrderNotificationTheme`; style riêng chỉ trong component MH08.
- Confirm/reject hiện chỉ validation và báo unavailable; chưa có mutation integration.
- Navigation là callback UUID; Preview có thể dùng MH09 hiện hữu, không chỉnh UI MH09.

## Kế hoạch triển khai có thể kiểm chứng

| Task | Allowed files / deliverable | Acceptance / verification |
| --- | --- | --- |
| MH08-01 | Feature docs + reference renderer/artifacts | Audit, LOC, HTML 390×844; dừng duyệt kế hoạch |
| MH08-02 | `widgets/mh08/`, component tests mới; page/test cũ readonly | Component độc lập, LOC ≤180, focused tests; chưa đổi VM |
| MH08-03A | Page refactor + component integration + tách page tests | Page ≤300, controller ≤250/test≤400; giữ API/providers/guards |
| MH08-03B | Preview integration + manager fixtures/navigation | Cùng entrypoint, stable scope; paging/search/navigation đúng contract |
| MH08-04 | MH08 tests/artifacts/docs, visual corrections MH08 | Responsive + interaction + final checks; user review; dừng |

Mỗi task cập nhật HANDOFF.03A đã duyệt;03B thực hiện trong lượt này;04 cần người dùng cho phép.

## Trình tự tách trách nhiệm dự kiến

1. Tạo component và test độc lập, chưa wire vào page trong MH08-02.
2. MH08-03A tách query/search và pagination khỏi page theo trách nhiệm; chạy regression mỗi lượt.
3. Giữ read provider families hiện tại; controller mới chỉ điều phối state MH08, không tạo repository khác.
4. Page chỉ scope/layout/listener/dialog orchestration; widget không tự đánh giá quyền bằng status.
5. Truyền predicate/freshness/callback xuống card khi dùng `itemBuilder`; hook này bỏ qua default actions của feed.
6. MH08-03B mới nối Preview bằng lựa chọn MH08, giữ default MH07 và ProviderScope trên Navigator.
7. MH08-03B tạo fixture manager riêng, không sửa semantics/dữ liệu customer MH07.

### Preview dataset MH08-03B

- Pending có/không capability; preparing (đã xác nhận); delivering; failed delivery từ typed warning.
- Tên khách/sản phẩm/variant tiếng Việt dài; đầy đủ snapshot/domain hợp lệ, UUID thật.
- Ít nhất2 pages có opaque cursor; counts lấy toàn bộ demo dataset theo semantics server.
- Scenarios data/loading/empty/error/stale/expired, thêm unauthorized và session-unavailable riêng.
- Dán nhãn demo; manager confirm/reject tiếp tục unavailable, không tái dùng customer mutation giả.
- Giữ `MH07_HIDE_CONTROLS`, default MH07 và ProviderScope/Navigator lifecycle hiện hữu.

## LOC gate và working tree

LOC là số dòng vật lý, kể cả dòng trống/comment. Page288≤300, main test122≤400, controller238/57≤250.
**MH08-03A owned-file gate PASS**; bảng chi tiết mọi file mới/sửa ở HANDOFF.
Các shared legacy vượt ngưỡng ngoài scope được giữ nguyên, không phải exception được duyệt để sửa.
Nếu cần sửa shared legacy, phải tách an toàn trong scope hoặc xin quyết định trước khi vượt gate.
Không kéo refactor MH07/MH09/MH17 vào MH08 để giảm LOC.

Working tree trước audit đã dirty/untracked, gồm cả MH08 page/test và HTML nguồn.
[Source baseline](artifacts/source_baseline.json) ghi SHA-256 của120 file có sẵn; renderer mới được loại rõ lý do, hash renderer/HTML ghi riêng trong render manifest.
Không dùng Git HEAD làm baseline duy nhất vì MH07 approved có thể nằm trong thay đổi chưa commit.

## Component namespace MH08-02

Base: `lib/features/orders/presentation/widgets/mh08/` (10 components03A đã tích hợp, source task02 giữ nguyên).
`mh08_{header,search_section,kpi_strip,status_chips}.dart` phụ trách controls.
`mh08_{buyer_section,item_preview,payment_section,operational_notice}.dart` render projections.
`mh08_{order_card,card_actions}.dart` composition và callback-only actions.
Tests: `test/features/orders/presentation/widgets/mh08/`, 4 nhóm test + shared test support.
API và LOC từng file: [HANDOFF](HANDOFF.md). Không tạo provider/repository hoặc sửa shared widgets.
Search parent phải echo `value` ngay; debounce/query vẫn do page/controller sở hữu ở task03A.

## Dependency map và checkpoint03A

Page → `pages/mh08/mh08_read_subscriptions.dart` (86) → shared `orderListFoundationProvider(OrderQuery)` → repository hiện hữu.
`view_models/mh08/mh08_feed_coordinator.dart` (238) giữ canonical/rows/cursors/privacy; `mh08_query_coordinator.dart` (57) giữ editing/timer.
Hai coordinator là object local của page, không notifier/provider/cache mới hay nguồn order authority thứ hai.
`OrderFeed.itemBuilder` → `Mh08OrderCard` → buyer/item/payment/typed notice/callback actions.
Widgets mới: `mh08_page_layout.dart` (47), `mh08_list_controls.dart` (64): scaffold/controls composition.
Action guard relookup summary + session/epoch/freshness; dialog capture sourceCache/scope, guard mounted/active trước WidgetRef.
Checkpoint A55 PASS → B55 PASS (legacy UI) → C70 PASS (integrated) → D246 PASS/analyze sạch.
Page/test vốn untracked;134 file có sẵn ngoài hai file được phép sửa giữ nguyên hash so với Checkpoint A.
03B bổ sung Preview/manager fixtures/navigation return-refresh bên dưới. Không tự bắt đầu04 hoặc đổi approval UI.

## Preview03B — ownership và cách dùng

`main.dart` → `mh08_preview_app.dart` → một ProviderScope ổn định → `mh08_preview_surface.dart` → MaterialApp/Navigator.
Mặc định MH07; menu **Chọn màn hình** chuyển MH07/MH08, menu **Chọn trạng thái** chọn scenario.
`mh08_preview_environment.dart` sở hữu screen/scenario/session generation duy nhất; không cần Supabase/login.
Customer reads/actions delegate nguyên `mh07_preview_data.dart`; hai harness cũ và fixture MH07 giữ nguyên.
Manager records/snapshot/projections/timeline riêng ở `mh08_manager_{data,record,projections,timeline}.dart`; repository riêng chỉ dùng trong Preview.
`mh08_manager_cursor.dart` giữ codec/normalization theo query/session; không đưa fixture logic vào production.
10 orders, page size3, opaque cursor theo query/session; search UUID/account, không product/recipient; counts bỏ status filter.
Scenarios: data/loading800ms/empty/error/stale/expired/unauthorized/session unavailable.
Nút **DEMO: lỗi trang tiếp theo** refresh head rồi làm một cursor request lỗi để thử retry.
Confirm/reject chỉ dialog validation + unavailable; không mutate fixture hoặc báo success.
MH08 callback mở MH09 hiện hữu bằng UUID; pop recheck mounted/session/epoch rồi refresh đúng canonical query.
Search/status giữ nguyên, extra pages reset theo coordinator production; không invalidate family hàng loạt khi pop.
Tests mới ở `test/ui_preview/mh08_*`; kết quả và lệnh Android trong [MANUAL_REVIEW](MANUAL_REVIEW.md).
Checkpoint03B:19 focused/265 full tests PASS, Analyze/format/diff/owned LOC PASS;145 protected files giữ nguyên hash.
Android Pixel5/API35 runtime smoke PASS; fidelity/TalkBack/full responsive dành04, UI vẫn NOT YET APPROVED.
