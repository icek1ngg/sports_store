# MH09-03A1 — Safe extraction checkpoint

Task03A1 only: extract without redesign. MH09 UI NOT YET APPROVED; seven02A/02B widgets remain readonly/unwired.
Pre-edit branch `feature/orders-notifications-phase2`; baseline2281 files/1600 dirty entries, working versions not HEAD.
Page578 physical LOC; page test440; existing9 page tests freshly PASS at CheckpointA.
Artifacts riêng [baseline](artifacts/03a1/baseline.json), original source/test snapshots và checkpoint logs trong03a1/.

## Pre-edit responsibility map / extraction proposal

| Existing responsibility | Owner after extraction | Invariant |
| --- | --- | --- |
| Public constructor/role gate/theme/polling |existing ManagerOrderDetailsPage|same6 parameters/types/defaults; manager gate; no new route/provider|
| Provider subscription/loading/error/stale/Scaffold/AppBar/footer reserve |existing content in same page|same orderDetailsFoundationProvider/read state; no local snapshot/cache|
| Refresh and current capability/session/cache gates |existing page|serialized loader authority unchanged; operation-specific current capability|
| Dialog launch/submittedScope/ref closure |existing page|same OrderActionDialog, default sourceCache=null; lifetime observed separately|
| Existing scroll/identity/shared recipient/items/payment/lifecycle/timeline composition |new pages/mh09/mh09_legacy_detail_body.dart, UI≤180|copy same order/spacing/labels/RefreshIndicator/widgets, no visual02A/02B imports|
| Existing contact card/callback/unavailable helper |new pages/mh09/mh09_legacy_contact_actions.dart, UI≤180|same customerId/phone callbacks; no navigate/dial/provider|
| Existing order/external footer/unavailable buttons |new pages/mh09/mh09_legacy_action_footer.dart, UI≤180|same capabilities/predicates/wrap/order/disabled explanations|

All new UI files receive immutable data/ordinary callbacks; never WidgetRef. No controller/session/cache introduced.
Original confirm→reject order remains in03A1 (02B reject→confirm is for03A2 only).
Page retains SafeArea, max footer height35%, refresh affordance and all external callback IDs.
Body keeps shared OrderLifecycleSections +OrderTimeline with original incomplete/empty/null semantics.
Each meaningful extraction is tested before the next; no giant source patch or renamed provider identities.

## Original test integrity / proposed split

| Original meaningful case (unique name) | Destination | Critical assertions |
| --- | --- | --- |
| renders manager snapshot and all independent unavailable states |legacy entry test|buyer/item/payment/null3lifecycles, actual timeline/incomplete notice|
| wraps long content at 320 width with 2x text |legacy entry test|320/360/412/640 layouts, no exception|
| keeps delivery, COD and return lifecycles separate |mh09_read_states_test|delivered/failed/collected/active return independent, not cancelled|
| shows loading then safe error without placeholder details |mh09_read_states_test|spinner→network error, no private placeholder|
| fails closed for customer even when the order belongs to them |mh09_read_states_test|deny UI,0 repository calls|
| refresh failure retains read-only detail then denial clears it |mh09_read_states_test|freshness disables action, stale retention, forbidden clears private data|
| validates reject reason and reports unavailable dependency |mh09_actions_test|blank reason blocked, valid reason unavailable, no fake success|
| keeps external actions disabled and callback destinations safe |mh09_actions_test|5 external actions disabled +missing target explanations|
| dialog checks refreshed capability before continuing |mh09_actions_test|new capability revokes submit, state-changed message,2 reads|

Public helper renames only; test bodies/assertions/chronology stay equivalent. No duplicate registration.
Support split by responsibility: page/repository/session host≤150; detail/projection fixture data≤150.
Names above are preserved verbatim; machine case inventory/preservation evidence added during CheckpointB.

## Dialog lifetime inspection plan

Page currently owns WidgetRef/capability predicate; root Navigator owns dialog route and may outlive page subtree.
OrderActionDialog owns reason/controller and subscribes to submitted scope/cache; it calls page predicate at build/submit.
Structural extraction keeps this ownership, no scope reparenting/sourceCache change.
Probe source page disposal/session loss separately, record real stack/result. No shared dialog/provider changes.
If a scoped page guard can safely prevent a reproduced disposed-ref access, document precise change; otherwise stop affected branch.
Full guarded dialog-owner design remains03A2; do not silently suppress exceptions or weaken tests.

## Kết quả03A1 / cấu trúc sau extraction

Page578→209/300; chỉ giữ public API +consumer content/subscription/gates/Scaffold/refresh/dialog.
`pages/mh09/`: legacy_detail_body129/180, legacy_contact_actions81/180, legacy_action_footer176/180.
Tên public có prefix Mh09Legacy để phân biệt rõ7 visual components đã duyệt nhưng chưa wire.
Thêm optional Key cho3 widget public để tuân analyzer; không đổi defaults/render hoặc state ownership.
Không part files, WidgetRef/provider trong presentation, controller/cache/snapshot mới hoặc shared refactor.
Header/identity/shared recipient/items/payment/independent lifecycle/timeline giữ nguyên; order/footer/disabled reasons nguyên bản.
Đối chiếu8 class bodies tự động PASS; normalize đúng3 tên class, optional Key và guard duy nhất dưới đây.
[presentation_preservation](artifacts/03a1/presentation_preservation.json) ghi ngoại lệ và destination từng class.

## Bảo toàn tests / regression bổ sung

Entry440→62/400,2 cases; read_states107/400,4 cases;actions119/400,3 cases;support93/150,fixtures103/150.
9 tên test gốc không đổi;49 expect assertions đúng1 bản, body tokens giữ nguyên ngoài helper rename/trailing commas/format.
[test_preservation](artifacts/03a1/test_preservation.json) có mapping gốc và inventory6 cases mới/32 assertions.
callback_navigation100/400:4 exact destination IDs;exceptional cancel required reason/unavailable;capability absent hidden.
session_navigation125/400:source-page unmount khi modal còn;expiry lúc modal mở;late response sau expiry.
Expiry tests giữ cùng ProviderContainer, chỉ repump đầy đủ overrides vào ProviderScope hiện hữu; không đổi protected providers.
Test harness từng sai override-count/expiry-label đã sửa theo API/SessionExpiredState hiện hữu, không nới assertions bảo mật.

## Dialog disposal — tái hiện thực tế và sửa cục bộ

1. Mở page manager có canConfirm=true, mở root dialog; submit đang enabled.
2. ValueNotifier gỡ riêng page subtree, giữ MaterialApp/root Navigator/ProviderScope; xác nhận dialog vẫn tồn tại.
3. Tap submit sau pump/unmount → StateError: Using ref when widget is about to or has been unmounted is unsafe.
4. Stack ConsumerStatefulElement.read → page _isStillAllowed → captured closure → dialog _submit.
5. [Red root stack](artifacts/03a1/dialog_disposal_red_stack.log) ghi nguyên lỗi; test không suppress exception.
6. Page callback thêm `context.mounted && _isStillAllowed(ref, operation)` trước ref access.
7. Cùng reproducer PASS: stateChanged, submit disabled,1 read,no exception; shared dialog/cache/sourceCache không đổi.

Root Navigator sở hữu modal; page ConsumerElement sở hữu ref, vì vậy callback có thể sống lâu hơn owner.
Guard không lưu business snapshot, không đổi freshness/capability/session check hoặc fake unavailable thành success.
Mounted chỉ chứng minh sau unmount; chưa chứng minh inactive/deactivated cùng frame.03A2 cần probe active-owner/route transition.
Session expiry modal/reason/private nodes và late response đều PASS; không kết luận đã xử lý mọi navigation lifecycle.

## Checkpoint / validation mới thực thi

A9 PASS;B9 PASS randomized20261019;C1contact/C2footer/C3body từng9 PASS;D15 page PASS cùng seed.
E focused122 PASS:15 page+86 visual components+12 shared widget/dialog+9 MH08 Preview lifecycle/query.
Final full suite368 PASS; analyzer no issues; final format11 files/0changed; LOC/links/diff/protected hashes PASS.
2273 protected files nguyên SHA-256 theo baseline working tree03A1, không dựa HEAD;7 visual components vẫn unwired.
Independent reviewer Sol Medium không P1/P2; worker Luna Max xử lý bounded test split/callback cases.
Utilities test_preservation60/presentation_preservation48/verify≤150 LOC; fixtures gốc so tokens PASS; [verification](artifacts/03a1/verification.json).
Log analyzer lần đầu3 infos thiếu public Key đã sửa; logs đỏ/trung gian giữ để trace, final logs xanh mới là kết quả cuối.
Không blockers cho03A1. Backend/owner integrations/shared receipt risk vẫn ngoài scope; MH09 UI NOT YET APPROVED.
Không Android/fresh same-viewport MH09 comparison; full suite fixture visual tests không thay thế review04A.
Next chỉ03A2 khi được giao: wire7 widgets, giữ shared lifecycle/timeline/read graph, kiểm tra active-owner trước dialog integration.
**MH09-03A1 — PAGE REFACTORED & TESTS SPLIT, READY FOR COMPONENT INTEGRATION. STOP.**
