# MH09 — Component architecture và bounded tasks

**MH09-01/02A/02B/03A1/03A2 được duyệt;03B Preview đã kiểm chứng, UI chưa approved.**
Component map phía dưới là kế hoạch gốc; wiring hiện tại ở checkpoint03A2, Preview ở [PREVIEW_03B](PREVIEW_03B.md).
Reuse models/formatters/theme/providers; không rename/move shared files để đạt LOC.

## Quyết định kiến trúc

- Namespace visual mới `lib/features/orders/presentation/widgets/mh09/`; callback/data-only, không Riverpod trong section.
- Page giữ public constructor và provider family identity; state/cache/read authority vẫn foundation hiện hữu.
- Styling MH09 nhận shared theme rồi dùng local text/spacing; không sửa OrderNotificationTheme/AppTheme.
- Shared recipient/items/payment đang dùng MH07: tạo MH09-specific render bằng **cùng domain objects**, giữ shared nguyên trạng.
- Delivery/COD/Returns dùng public shared `OrderDeliverySection`, `OrderCodLifecycleSection`, `OrderReturnsSection` ban đầu.
- Timeline dùng `OrderTimeline` nguyên trạng để giữ normalize/dedup/fallback; không copy thuật toán sang formatter khác.
- Không tạo component riêng cho label/divider/icon đơn giản; private helpers cùng responsibility nếu đủ LOC.
- Chưa tạo wrapper timeline/lifecycle chỉ forward props; body composition là đủ.
- Warnings lấy current authorized delivery reason/attempt; không invent warning DTO hoặc đọc summary MH08 làm authority.

## Component map — estimates, không phải LOC đã đo

Base path `lib/features/orders/presentation/widgets/mh09/`; target LOC ≤180/file, plan trước mốc144.
Tất cả component tests mới trong `test/features/orders/presentation/widgets/mh09/` và ≤400/file.

| File / class | Responsibility, input / callback API | LOC aim | Tests / dependencies / risk |
| --- | --- | ---: | --- |
| `mh09_header.dart` / Mh09Header |center title/back/refresh; `canPop,isRefreshing,onBack?,onRefresh?`; implement PreferredSizeWidget nếu cần|60–90|header semantics/back/refresh disabled; Material/theme; low|
| `mh09_order_identity.dart` / Mh09OrderIdentity |full UUID/status/server placedAt/attempt count; `Order order`; không action/menu chưa hỗ trợ|80–110|UUID dài/unknown status/Hanoi; badge/formatters; medium vì identity cao hơn mock|
| `mh09_recipient_section.dart` / Mh09RecipientSection |buyer khác snapshot recipient, number/address/contact; `Order,Buyer?`, `VoidCallback? onCall,onChat`|130–165|null buyer/long text/callback unavailable/48px; shared models; medium|
| `mh09_items_section.dart` / Mh09ItemsSection |all items snapshot + count +64px placeholder; `List<OrderItem>`; no catalog calls|130–170|0/1/40items/long name/quantity/prices; formatVnd; medium|
| `mh09_payment_section.dart` / Mh09PaymentSection |subtotal/fee/total/method + COD unavailable/current label; `Order,CodSummary?`|120–160|no discount/full VND/null distinct/large text; formatters; medium financial semantics|
| `mh09_action_footer.dart` / Mh09ActionFooter |reject→confirm/exceptional cancel; per-operation `OrderCapabilities` AND fresh/scope/not-busy/callback, không canAct đơn lẻ|120–160|hidden/disabled/48px/wrap/order, callback only; owner rechecks; high eligibility|
| `mh09_operational_actions.dart` / Mh09OperationalActions |supported external capability labels + disabled reason; `OrderCapabilities`; không callback mutation|100–140|assign/reassign/retry/early/receive disabled; no local mutation; medium|
| `mh09_details_body.dart` / Mh09DetailsBody |RefreshIndicator/scroll/gap16; compose new sections + existing lifecycle/timeline; `OrderDetails,onRefresh`, guarded optional callbacks|140–175|last row reachable, nullable projections, independent lifecycle; high composition|

Không tạo `Mh09OperationalNotice` riêng khi data source chỉ có reason đã được Delivery section render.
Không thêm order warning property hoặc refund field để đáp ứng component giả định.
Nếu một component gần144LOC, tách private row có trách nhiệm (ví dụ item row) trước khi vượt180;
chỉ tạo file riêng khi đủ responsibility/test surface, không artificial split hoặc Dart part.

## Page / dialog ownership dự kiến ở03A

Page `manager_order_details_page.dart` ≤300 (aim220–270): gate/theme/polling, provider read, async state,
Scaffold/header/body/footer composition, callbacks và dialog launch. Không controller mới nếu chưa cần local state.
Nếu cần mounted/active owner, dùng ConsumerStatefulWidget content riêng MH09; giữ provider identities/API public.
Điều này chỉ được triển khai ở03A, task02 không wire page hoặc dialog.

Dialog launcher nếu cần: `pages/mh09/mh09_action_dialog_launcher.dart`, utility≤150, aim80–120.
Input context + orderId/operation + submittedScope/sourceCache + safe current-capability predicate.
Predicate kiểm tra **owner mounted/active trước ref.read**, rồi scope/cache/freshness/current operation capability.
Trước showDialog recheck capability; dialog submit dùng lại guarded predicate, không capture snapshot bool vĩnh viễn.
Owner dispose/route teardown phải khiến predicate trả false; không đọc deactivated WidgetRef.
Không tự thêm provider/cache hoặc reparent ProviderScope dưới modal; listener/controller do dialog hiện hữu dispose.
Không sửa shared OrderActionDialog204/receipt provider151 trong visual task; risk shared receipt disposal ghi dependency.
Nếu chứng minh phải sửa shared code để an toàn: dừng nhánh đó, trình reproducer + đề xuất scoped guard trước;
không tự kéo MH07/MH08 hoặc shared formatter/timeline refactor vào MH09.

## Canonical action boundary

Visual visibility từ capability; enabled từ owner fresh/authorized + callback tồn tại.
Owner relookup current detail, không tin item/status/capability capture lúc build hoặc source HTML.
`canAct=false` khi refresh/stale/failure/session denied; không disable read-only scroll khi network failure còn quyền.
Dialog validation/unavailable hiện tại giữ nguyên; không sender/request key/optimistic state/success toast mới.
External actions vẫn disabled dù capability=true; links readonly cần callback owner đã được ký/guard.

## Roadmap chi tiết / acceptance

| Task | Work / dependencies | Verification / stop |
| --- | --- | --- |
| 01 audit approved |docs+renderer+inventory/hash; đọc spec và current sources|39 focused lịch sử; plan đã user approve|
| 02A approved |header/identity/recipient/items cô lập|63 historical PASS; user approved; readonly|
| 02B hiện tại |payment/footer/operational sections; chưa body integration|107 focused PASS; no integration; STOP|
| 03A1 hoàn tất |page209 +3 legacy sections; test entry62 + responsibility suites|9 cases/49 assertions gốc giữ nguyên;6 mới;122 focused/368 full PASS; STOP|
| 03A2 BLOCKED |wire7 components/body +active/ticket owner; shared lifecycle/timeline giữ nguyên|138 focused PASS;full391PASS/2protected stale-finder FAIL; STOP|
| 03B Preview |extend current Mh08PreviewApp/Surface, MH09-specific fixtures only nếu thiếu; không thay MH07/MH08 UI|exact UUID, repeated open/pop/query/head refresh, stable scope, expiry while loading/modal; STOP|
| 04A visual |fresh Flutter same390×844/DPR1, long/empty/missing/error scenes, responsive matrix|geometry + screenshot manifest, separate intentional business deltas; STOP|
| 04B refinement |only measured defects; split04B1/B2 nếu nhiều defect; Android runtime/manual|full regression/LOC/analyze, device/insets/IME/TalkBack evidence; user review; STOP|

Task02 nên chia02A (header/identity/recipient/items) và02B (payment/footer/operational) nếu dự kiến>60k context.
Mỗi nhánh có checkpoint; không tự chạy task tiếp theo vì task trước PASS.
03B không sửa behavior/fixtures/render của approved MH07/MH08; dùng extension điểm navigation hiện hữu.
Body có thể tạo trong03A thay vì02 vì trách nhiệm chủ yếu composition; tránh widget forward-only dư thừa.

## Test split dự kiến03A

Giữ test gốc làm entry nhỏ hoặc chia file theo read_states/actions/session_layout, không duplicate full fixtures.
Support fixture riêng≤400, cùng models/repository contract; không sửa test assertions để hợp mock mới.
New file names gợi ý `mh09_read_states_test.dart`, `mh09_actions_test.dart`, `mh09_session_navigation_test.dart`.
Không chuyển/tách shared tests hoặc MH07 tests để giảm LOC MH09.
Foundation test377 gần80%: thêm case MH09 tại test mới, không inflate file shared.

## Definition of Done của visual roadmap

Page≤300/components≤180/helper≤150/test≤400; all changed files format + analyze + relevant tests.
Read/business/session/navigation contracts giữ nguyên; HTML deviations được giải thích bằng authority.
Fresh screenshots/Android verification chỉ PASS khi chạy thật; user quyết approval, không agent tự duyệt.
Backend/owner contract blockers vẫn được ghi rõ; visual approval không đồng nghĩa feature full-runtime complete.

## MH09-02A — actual public APIs và integration requirements

Tất cả ở `lib/features/orders/presentation/widgets/mh09/`, chưa import từ production page hoặc Preview.

| Component | Constructor inputs (ngoài `Key? key`) | Parent ownership |
| --- | --- | --- |
| `Mh09Header` |`required bool canPop, bool isRefreshing=false, VoidCallback? onBack, VoidCallback? onRefresh`|Navigator/canPop, refresh provider, SafeArea và chiều cao host|
| `Mh09OrderIdentity` |`required Order order`|canonical current snapshot; không derive action capability|
| `Mh09RecipientSection` |`required Order order, Buyer? buyer, VoidCallback? onCall, VoidCallback? onChat, bool contactEnabled=true`|manager/session gate, bind phone/customerId, unavailable callback, destination recheck|
| `Mh09ItemsSection` |`required List<OrderItem> items`|canonical detail.items + main scroll; component freeze list và giữ nguyên item instances|

Header content-sized min64, không implement fixed PreferredSizeWidget; parent không ép height64 khi text scale cao.
Header tự padding20 ngang; các section khác nhận constraints đã có20 outer gutter từ future body.
Cards có16 inner padding/radius32, components không có scrollable nội bộ; page sở hữu khoảng cách16.
Identity full UUID wrap + status badge bên dưới, tooltip/semantics full ID; date dùng Hanoi formatter.
Call cần phone có dữ liệu + parent callback/flag; Chat không phụ thuộc optional Buyer/recipient phone.
Recipient missing-contact branch chỉ defensive: valid Order hiện yêu cầu phone/address nonblank;
test-only legacy stub kiểm tra branch này, không đổi model hoặc tạo demo/provider fallback trong production.
Items dùng snapshot unitPriceVnd/lineTotalVnd, shared formatter; count dòng, không tính order totals.
Recipient gần gate180: contact controls là responsibility có thể tách nếu future task cần thêm behavior;
02A giữ cùng card để API đơn giản, không thêm file tiny helper hoặc tăng scope shared widgets.
Checkpoint/test/LOC actual cuối task ở [HANDOFF](HANDOFF.md) và [verification02A](artifacts/02a/verification.json).
02A verified: Header80/Identity65/Recipient177/Items131LOC; test files124/95/306/155 +support78.
42 new component tests +21 existing regression PASS; analyzer/format/owned LOC/protected hashes PASS.
Independent review P2 duplicate contact semantics đã sửa: single semantics authority + guarded semantic tap;
enabled/disabled/exact label dispatch tests PASS, reviewer recheck không còn finding P1/P2.

## MH09-02B — actual APIs / financial and action boundaries

| Component / source file | Inputs ngoài Key? key | LOC |
| --- | --- | ---: |
| Mh09PaymentSection / `mh09_payment_section.dart` |required Order order; CodSummary? codSummary|133|
| Mh09ActionFooter / `mh09_action_footer.dart` |OrderCapabilities capabilities=none(); bool isActionStateFresh=false; bool canActInCurrentScope=false; bool isBusy=false; ValueChanged<OrderOperation>? onAction|179|
| Mh09OperationalActions / `mh09_operational_actions.dart` |OrderCapabilities capabilities=none(); String? unavailableReason|100|

Payment reads exact subtotalVnd/deliveryFeeVnd/totalCodVnd; no UI arithmetic/discount/default monetary projection.
COD overview method/status only; full collection/receipt/actor/history remains OrderCodLifecycleSection, không duplicate.
Parent cung cấp order và COD từ cùng accepted OrderDetails; aggregate validator đã kiểm orderId/expectedAmount relation.
Valid Order hiện enforce fee30000 và total sum; tests không tạo malformed model để giả một fee hợp lệ khác.
Footer visibility AND enable luôn dùng capability riêng canReject/canConfirm/canCancelExceptional; không nhận OrderStatus.
Fresh/scope/busy chỉ additional gates; defaults disable cả khi capability=true nếu parent chưa xác nhận scope/freshness.
Reject→Confirm balanced ở390, stack khi hẹp/large-text/landscape; exceptional managerCancel block riêng; SafeArea do page sở hữu.
Callback chỉ forward đúng enum; parent phải relookup capability/session/epoch khi mở/submit dialog, không tin captured bool như server authorization.
Ops API cố ý không có callback/availability=true: cả5 capability đều chưa có accepted owner integration ở task này.
False cap bị ẩn, all-false shrink; true cap hiển thị disabled + reason giao hàng/kho hoặc unavailableReason do parent cung cấp.
Không nhận COD/refund/return approval mutation và không tự tạo task/custody/receipt. Future wiring cần task/owner contract riêng.
Footer179 gần gate180: nếu cần thêm presentation ở task sau, exceptional-action block là extraction boundary có ý nghĩa;
không thêm logic vào file hoặc refactor shared/page/02A để né LOC. Helpers test02B64≤150.
Checkpoint B12/C17/D15 +existing63 =107 final PASS; reviewer độc lập không P1/P2; full suite/Android NOT RUN.
Chi tiết test/format/analyze/hash ở [evidence02B](artifacts/02b/verification.json) và HANDOFF.

## MH09-03A1 — extraction lịch sử đã duyệt

Page hiện209/300: giữ ManagerOrderDetailsPage + private ConsumerWidget content, gate/read/refresh/dialog.
API giữ `required String orderId`, `bool enablePolling=true`,4 `ValueChanged<String>?` callbacks, optional Key.
Provider identities/SessionScope/EpochCache/ReadSnapshot/shared lifecycle và timeline không đổi; không snapshot/cache thứ hai.
Ba sections data/callback-only trong `lib/features/orders/presentation/pages/mh09/`, đều optional Key:

| Class / file | API chính | LOC |
| --- | --- | ---: |
| Mh09LegacyDetailBody / mh09_legacy_detail_body.dart |required details, onShowAction, isStillAllowed, onRefresh;4 optional callbacks như page|129/180|
| Mh09LegacyContactActions / mh09_legacy_contact_actions.dart |required String customerId, recipientPhone; optional onOpenChat/onCallRecipient|81/180|
| Mh09LegacyActionFooter / mh09_legacy_action_footer.dart |required OrderDetails details, void Function(OrderOperation) onShowAction, bool Function(OrderOperation) isStillAllowed; orderCommandsOnly=false, externalActionsOnly=false|176/180|

Tên Legacy phân biệt rõ layout cũ với7 visual widgets02A/02B chưa được wire. Không parallel design/state/provider.
Body nhận OrderDetails hiện tại; onRefresh Future<void> Function();4 callbacks ValueChanged<String>? như page.
Footer giữ confirm→reject→cancel cũ; commands ở page SafeArea/35% scroll, external actions trong body vẫn disabled.
03A2 thay composition trực tiếp bằng components đã duyệt; chỉ giữ legacy responsibilities còn cần, tránh wrapper forward-only.
Footer176 gần limit: không thêm logic/design mới vào đó;03A2 thay bằng Mh09ActionFooter179 readonly thay vì inflate legacy.
Guard trong page callback dùng context.mounted trước đọc WidgetRef, sau crash reproducer; sourceCache vẫn default null.
Không chứng minh inactive/deactivated cùng frame;03A2 cần active-owner/route lifecycle probe riêng trước wiring dialog.
Test split2 entry +4 read +3 actions; thêm callback/cancel3 +session/disposal3. Helpers93/103≤150, tests≤125/400.
9 test bodies/49 assertions +8 class bodies được so tokens với baseline (ngoại lệ rename/Key/guard ghi rõ).
Evidence/plan trước edit và red→green: [REFACTOR_03A1](REFACTOR_03A1.md); next chỉ **MH09-03A2 khi được giao**.

## MH09-03A2 — integrated architecture, full-regression gate BLOCKED

Page43 public API/theme/manager gate; Mh09DetailContent275 consumer state coordinator duy nhất, không cache canonical snapshot.
Mh09DetailBody82:Identity→Recipient/contact→Items→Payment→shared Delivery/COD/Returns→Timeline→OperationalActions.
Mh09PageLayout45:SafeArea/header content-size/body Expanded/footer35% scroll; boundary layout riêng tránh owner chạm300LOC.
Header/ActionFooter do owner compose;7 visual widgets nguyên hash. Legacy129/81/176 tồn tại nhưng inactive, chưa cleanup.
Owner active/generation revoke ở deactivate/dispose/orderId change; activate không revive old tickets; route captured lúc active.
Guard active/ticket/route-active→manager scope equality→same readable cache→fresh canonical orderId→current operation capability.
Dialog captures sourceOrderId/submittedScope/sourceCache/ticket; launcher check routecurrent, predicate không dùng isCurrent.
UI busy chặn reentrant open; legitimate modal submit vẫn validation/unavailable, không mutation/receipt/success.
Navigation bind current customerId/phone/orderId/returnId; _forward rechecks aggregate+routecurrent; nullable callbacks dispatch an toàn.
Toolbar/pull/poll/retry qua một refresh path, ignore already-loading trước notifier.refresh để tránh duplicate UI reads.
15 existing cases tương đương sau finder migrations;25 new runtime cases;138 focused PASS, owner/session/late/null probes PASS.
Full391PASS/2FAIL do protected Preview legacy UUID/BackButton finders; existing Preview flow qua actual header PASS.
Follow-up nhỏ nhất tại [INTEGRATION_03A2](INTEGRATION_03A2.md): quyền đổi3finders trong2testfiles trước full-green/03B.
Không sửa components177/179/shared để làm test cũ xanh; không thêm hidden text/duplicate back button. **STOP03A2 BLOCKED**.

## 03B — kiến trúc debug hiện tại

Đoạn BLOCKED phía trên là lịch sử trước03A2F (393full PASS).03B mới421full/181focused PASS.
Không đổi production; main/App/ProviderScope/Navigator giữ nguyên; route wrapper chỉ thêm DEMO selector.
Fixture world theo exactUUID, project summary/detail cùng aggregate; reset trước existing canonical head refresh khi pop.
Data scenes không đổi scope/cache; auth scenes revoke world trước generation; denied scope giữ nguyên sauBack tới explicit recovery.
Revision+scope guards chặn late list/detail; controlled loading release không tạo gate sau reset/dispose.
Map files/LOC/test/runtime và giới hạn ở [PREVIEW_03B](PREVIEW_03B.md). STOP03B; tiếp theo04A khi được giao.
