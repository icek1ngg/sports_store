# MH09 — Test coverage và verification plan

Evidence01/02/03A1/03A2 là lịch sử;03A2F giải quyết finder compatibility,03B mới full421 PASS.
**PASS chỉ cho lần thực thi có evidence**, không gán PASS cho toàn test catalog.
04A mới:15layout cases PASS,181existing tests PASS,6newtests PASS/2a11yFAIL;[VISUAL_AUDIT](VISUAL_AUDIT.md) là oracle hiện tại.
Nguồn target: [spec test §4/§6](../../technical_specification_mh07_mh08_mh09_mh17_tests.md),
T09-01…28/TX và invariant NT01–NT30 theo phần được trace trong Technical Specification.
Không mở toàn report hoặc tự map NT ID không có chứng cứ; các oracle concurrency/stock/COD giữ ở owner integration.

## Execution MH09-01 — lịch sử, không phải rerun02A

Lệnh từ project root, Flutter SDK hiện có, không pub get/dependency change:

```powershell
flutter test --no-pub test/features/orders/presentation/pages/manager_order_details_page_test.dart test/features/orders/presentation/widgets/order_action_dialog_test.dart test/features/orders/presentation/widgets/order_widgets_test.dart test/features/orders/presentation/view_models/order_foundation_test.dart test/ui_preview/mh08_preview_lifecycle_test.dart test/ui_preview/mh08_preview_query_test.dart --reporter expanded
```

**39 tests PASS, exit0**; [raw evidence](artifacts/focused_tests_elevated.log).
Lần sandbox trước không trả output, đã hủy process của lượt thử; log rỗng không tính kết quả.
Lần có kết quả dùng SDK ngoài sandbox; không sửa source/assertions để test PASS.

| Executed file | Coverage hiện có | Giới hạn |
| --- | --- | --- |
| `test/features/orders/presentation/pages/manager_order_details_page_test.dart` |9 cases: snapshots/null lifecycle/loading/network/customer deny/reject validation/external disabled/large text/stale-denial/capability recheck|fake repository; chưa disposal/nav-modal stress|
| `test/features/orders/presentation/widgets/order_action_dialog_test.dart` |reason/unsupported operation/session identity/cache blocking/source invalidation|shared dialog tests; không live mutation|
| `test/features/orders/presentation/widgets/order_widgets_test.dart` |UUID/VND/long snapshots/status semantics/timeline actor+fallback/sort/320px|shared widget assertions, không pixel diff|
| `test/features/orders/presentation/view_models/order_foundation_test.dart` |detail invalidates list; identity/scope/order checks; receipt not canonical; generations/session/late responses; adapter unavailable|fake backend; late read≠disposed receipt callback|
| `test/ui_preview/mh08_preview_lifecycle_test.dart` |6 cases: safe states/late generation/dialog unavailable/expiry/UUID→back canonical refresh/page retry|active Preview fake data, không Android|
| `test/ui_preview/mh08_preview_query_test.dart` |3 cases: canonical search/filter/paging/navigation|giữ MH08 query semantics; không new MH09 visual|

## Audit-only gates — lịch sử task01

| Check | Status/evidence |
| --- | --- |
| HTML viewport390×844/DPR1 + full screenshot |PASS, [manifest](artifacts/html_render_manifest.json), fonts9 loads,2 images,0 request failures|
| Original HTML SHA-256 unchanged |PASS, before=after + source_baseline/source_verification|
| Physical LOC inventory |PASS measurement; legacy violations recorded, không claim legacy compliant|
| New Markdown≤200/HANDOFF≤100/scripts≤150 |PASS sau final [audit_validation](artifacts/audit_validation.json)|
| Feature relative links/images exist |PASS sau final utility; brokenLinks=[]|
| Protected working files hashes |PASS, [source_verification](artifacts/source_verification.json); baseline2237|
| git diff --check |PASS; pre-existing CRLF advisory không phải whitespace failure|
| Renderer + audit utility syntax |PASS, `node --check` cả2 scripts|
| New production/Dart/test/Preview changes |0; final hash/status comparison|
| dart format |NOT RUN, không changed Dart files|
| flutter analyze |NOT RUN, production unchanged; historical PASS không dùng làm fresh result|
| Full suite / previous276 |NOT RUN; chỉ39 focused fresh; MH08 HANDOFF còn ghi release snapshot khác, không suy current full PASS|
| Fresh Flutter screenshot / Android / TalkBack / IME |NOT RUN, thuộc04A/04B|
| Supabase/RLS/RPC/concurrency/backend connectivity |NOT RUN, adapter/bridge còn missing|

## Planned tests — chưa thực thi cho UI mới

| Area / acceptance trace | Test oracle cần bổ sung | Task / status |
| --- | --- | --- |
| Authorization T09-01/21–24 |unresolved/loading,expired,customer,shipper deny MH09; own customer OP-O03 vẫn allow sanitized riêng|03A/owner integration; PLANNED|
| Canonical detail OP-O03/T09-20 |wrong order UUID/foreign item/buyer/COD amount reject; foreign delivery projection/task timeline bị server/adapter reject kể cả latestAttempt=null; aggregate error không fake partial success|existing coverage một phần; delivery ownership integration PLANNED|
| Missing projections T09-15/20 |delivery/COD null khác real pending/uncollected; returns[] không fake confirmed-none; source history incomplete|02+03A; PLANNED (legacy null case PASS)|
| Order T09-19 |server pending→preparing refresh: old buttons removed, không auto assign; capabilities false dù pending|03A; PLANNED|
| Delivery T09-10…14/25…28 |two outbound attempts order-wide, no count reset; lost/damaged/partial goods no early restock; returnPickup không áp2|owner integration NOT RUN|
| COD T09-02/03/15 |fee30k/no discount; exact VND; null distinct; collected/received full amount; refund không offset obligation|02 visual + owner integration PLANNED|
| Return/refund T09-03/16 |read-only status/refund unavailable; no bank/video/payment evidence copied; order remains delivered|02/03A + owner integration PLANNED|
| Timeline T09-04…06 |time/id stable ties; actual event wins matching fallback; unknown actor; no invented event/time/planned6steps|legacy widget PASS; MH09 composition03A PLANNED|
| Action capability T09-07/08/19 |pending with canConfirm=false; stale true/refresh/error disable; relookup before dialog/submit; hidden exceptional cancel absent capability|02/03A PLANNED|
| Action transport TX race/replay |same request retry/fingerprint conflict/manual-auto race/unknown timeout/restart; no synthetic receipt|backend separate task NOT RUN|
| Session expiry TX-08 |during open/async read/refresh/modal/pop/submit: clear private nodes/reason; late old account response dropped|03A/03B MH09-specific PLANNED|
| Owner disposal |same-frame inactive/reparent/unmount; old callback false trước ref read|03A2 red→green PASS; no silent exceptions|
| Receipt disposal dependency |hold old notifier then autoDispose and late receipt; no disposed ref read|shared provider owner task; NOT RUN|
| Navigation T09-16/17 |external callbacks correct IDs, recheck destination, unavailable safe; never SMS/manager→shipper bypass|03A/03B PLANNED|
| MH08→MH09→MH08 |repeat push/pop, exact UUID, same scope, query/status retained, canonical head/count refresh, no cursor replay|existing Preview PASS;03B extra stress PLANNED|
| Dialog T09-18 |reason trim1…1000unicode, close/reopen/reset/session clear; IME small height; background refresh invalidates old choice|02/03A/Android PLANNED|
| Async states |initial loading,error+retry,denied,expired,stale cached/read-only; missing whole detail generic error; no private flash|legacy partial PASS; new composition03A PLANNED|
| Responsive T09-18 |320/360/390/412/844×390 ×scale1/1.5/2; UUID/name/address/amount/40items; last row & footer reachable|04A PLANNED|
| Accessibility |semantic full UUID/status/amount, no color-only meaning;48px targets; logical focus/disabled reason;contrast|02 automation +04B manual PLANNED|
| Android |real launch/touch/back/repeated modal/pull refresh/rotate/large font/docked IME/TalkBack/audio|04B NOT RUN|

## Tests mới / isolation rules

- Task02 tạo namespace component tests riêng, ≤400LOC/file; không sửa production page/VM/shared tests để test cô lập PASS.
-03A tách detail test440 theo read/actions/session-layout responsibilities, giữ assertions và meaningful regression.
- Không inflate foundation test377; thêm case MH09 trong file riêng và support fixture vừa đủ.
- Preserve no fake success: confirm/reject valid input vẫn unavailable cho đến separate authorized backend task.
- Không gộp test backend transaction/RLS vào widget PASS; allowed/denied per role và idempotency phải chạy bằng actual backend setup.
- Nếu baseline test FAIL: lưu log và scope blocker; không nới assertions hoặc sửa outside feature task01.

## Acceptance evidence cần lưu sau này

Fresh pair HTML/Flutter same viewport/DPR/scale + dataset provenance; geometry/intentional deviation matrix.
Android device/API/resolution/DPR/insets/font scale, actual APK launch, action screenshots và uncaught error logs.
Docked IME/TalkBack phải có quan sát thực, không suy PASS từ build/widget tests hoặc MH08 approval.
Full regression/analyze/format/LOC + source protected hash diff trước user review; không auto APPROVED.

## MH09-02A — execution và coverage lịch sử đã duyệt

Baseline mới [02a/baseline.json](artifacts/02a/baseline.json),2257 existing files; component/test folders trước task absent.
CheckpointA **21 existing tests PASS**; B **20 Header/Identity PASS**; C **22 Recipient/Items PASS**.
Final **63 tests PASS, exit0 =42 new +21 existing regression**; [final log](artifacts/02a/final_tests.log).

| New test file dưới `test/features/orders/presentation/widgets/mh09/` | Cases / LOC | Coverage |
| --- | --- | --- |
| `mh09_header_test.dart` |10 /124|callback-only back/refresh, canPop/callback/busy gating, full header semantics, Barlow,48px targets,320/390×1/2|
| `mh09_order_identity_test.dart` |10 /95|full UUID/tooltip/semantics/typography, status labels, fixed Hanoi server time, new snapshot/attempts,320/390×1/2|
| `mh09_recipient_section_test.dart` |12 /306|buyer≠recipient, null/blank buyer, parent flag/callbacks,48px, exact semantic label/button/tap, disabled no action, missing legacy contact,320/390×1/2|
| `mh09_items_section_test.dart` |10 /155|0/1/2/40 rows, UUID keys, full snapshots/large VND/quantity, no remote Image, immutable list keeps item identity, parent scroll,320/390×1/2|
| `mh09_test_support.dart` |support /78|real domain via existing DTO fixtures; MaterialApp/theme/scroll harness, **không ProviderScope**|

Missing phone/address không tạo được bằng valid Order: defensive branch dùng test-only legacy `implements Order` stub.
Không sửa model, không fake provider/production data. Chat callback vẫn bật khi Buyer/phone thiếu nếu parent cho phép.
Regression21 chạy lại nguyên assertions: detail page9 + shared widgets6 + action dialog6, không chỉnh protected tests.
Lệnh final: `flutter test --no-pub test/features/orders/presentation/widgets/mh09 test/features/orders/presentation/pages/manager_order_details_page_test.dart test/features/orders/presentation/widgets/order_widgets_test.dart test/features/orders/presentation/widgets/order_action_dialog_test.dart --reporter expanded`.

## 03B — thực thi mới

28 cases mới trong4 `test/ui_preview/mh09_*_test.dart`; helper riêng, không sửa/skip test cũ.
Focused181 PASS gồm Preview/K1 và MH09 page/integration/component/dialog; full `flutter test --no-pub`:421 PASS.
Header và framework Back:3 cycles mỗi loại, UUID/query/filter/container/cache/head+1/no cursor replay; modal pop trước page.
Auth Back giữ denied scope; explicit DEMO recovery mới trở lại manager. Late head/detail và reset-before-loader-completion PASS.
40items→last item→timeline, nulls riêng, error/retry/stale/loading, account switch, repeated dialogs/reasons/cap revoke/expiry PASS.
Android API35 build/install/launch/ADB route+modal Back PASS; floating IME keyboard-only consumption và gesture NOT VERIFIED.
Analyzer/12-file format/diff/LOC/links/hash PASS; evidence và commands ở [PREVIEW_03B](PREVIEW_03B.md).
Các catalog backend/concurrency/RLS/TalkBack/visual acceptance phía trên vẫn chưa được chứng minh bởi component/Preview tests.

## Execution MH09-03A1 — mới thực thi

Baseline9 page tests PASS trước edit; split9 PASS với random seed20261019; từng extraction contact/footer/body đều9 PASS.
15 page tests PASS sau thêm6 ca; final focused122 PASS và full suite368 PASS, không cộng số lịch sử để suy tổng.
Lệnh final full `flutter test --no-pub`; focused gồm entry page +pages/mh09/ +widgets/mh09/ +shared order_widgets/dialog +Preview lifecycle/query, seed20261019.

| Kiểm tra / evidence trong artifacts/03a1/ | Kết quả thực tế |
| --- | --- |
| [test_preservation.json](artifacts/03a1/test_preservation.json) |PASS9 gốc/49 assertions, mỗi case đúng1 bản, tokens tương đương sau helper renames;6 mới/32 assertions|
| Split suites |entry2/read4/actions3; mới callback_navigation3/session_navigation3; hỗ trợ fixtures103/host93 LOC|
| Callback IDs |PASS COD orderId;return returnId;chat customerId;call recipientPhone snapshot|
| Exceptional cancel |PASS required reason→dependency unavailable, no success;capability absent ẩn action|
| Source-page unmount |FAIL đúng lỗi trước guard, root stack tại dialog_disposal_red_stack.log; green sau page mounted short circuit|
| Session expiry modal |PASS reason/private detail/UUID/submit biến mất, close an toàn, cùng ProviderContainer|
| Late response sau expiry |PASS dữ liệu cũ không hiển thị,1 read, cùng ProviderContainer, không Flutter exception|
| Existing read/action/privacy |PASS cả9 gốc: loading/network/stale/forbidden/role/capability/current lifecycle/layout assertions giữ nguyên|
| focused_final.log |PASS122 =15 page +86 components +12 shared widget/dialog +9 Preview navigation/query|
| full_suite_final.log |PASS368 toàn bộ suite, gồm MH07/MH08; rerun sau optional Key lint fix|
| analyze_final.log / format.log |PASS no issues;format11 Dart files,0 thay đổi ở final check|
| [verification.json](artifacts/03a1/verification.json) |PASS LOC/Markdown links/diff/hash;2273 protected files nguyên SHA-256|
| Independent review |không P1/P2; presentation parity giữ nguyên, P3 inventory đã cập nhật đủ6 newCases|
| Android/full MH09 visual approval/backend |NOT RUN; suite có fixture visual tests nhưng không thay bằng same-viewport MH09 review|

Log fail trung gian giữ để trace: lỗi helper import đã sửa; override-count test harness sửa bằng stable ProviderScope repump đủ overrides;
expiry oracle dùng đúng SessionExpiredState thay vì unauthorized label. Không sửa expected9 ca gốc hay protected/shared code.
Red disposal là lỗi thực tế đã sửa cục bộ; không suppress exception hoặc nới assertion để đạt green.
Residual: chưa chứng minh owner inactive/deactivated cùng frame hoặc toàn lifecycle route;03A2 test trước khi tích hợp7 widgets.

## Execution MH09-03A2 — mới thực thi, gateE BLOCKED

A122 focused baseline PASS. B16 existing/same-frame PASS;C20 page PASS;final138 focused PASS,seed20261019.
25 new runtime cases trong6files;15 existing cases/81 assertions tương đương sau explicit finder migrations, [preservation](artifacts/03a2/test_preservation.json).
New cases:component/data4;per-op/action/refresh/repeated dialogs8;access/foreignUUID/retry/account7;owner2;navigation3;existingPreview contract1.
Same aggregate identities/40items reachable/exactVND/missing projections/four lifecycles/actual timeline PASS; no provider dependency trong body/layout.
Footer per-op enum/sourceCache/current capability/busy/stale PASS; repeated confirm/reject reason/unavailable PASS; không mutation/success.
Owner same-frame mounted+inactive probe FAIL trước guard/PASS sau active ticket; reparent không revive callback, post-unmount/rapid pop/push PASS.
Null-parent-callback probe FAIL trước ?.call/PASS sau4destinations; async completion/disposed container/session/role/late account responses PASS.
Access unresolved kiểm semantics LoadingState đúng API; compile import transient đã sửa, không weaken privacy expectations.
Final `flutter test --no-pub`: **391 PASS/2 FAIL**, không báo full-green; xem full_suite_final.log trong03a2/.
2 FAIL chỉ protected Preview lifecycle/query tests có legacy UUID/BackButton finders; actual header contract test PASS giữ query/container/head refresh.
Không sửa/skip2tests; cần quyền đổi3finder calls tại [INTEGRATION_03A2](INTEGRATION_03A2.md) trước rerun full/03B.
Analyze no issues;format17files/0changed;owned LOC/diff/links/hash PASS;2287 protected working files nguyên SHA-256.
All7 components tests chạy lại; approved MH07/MH08 regression nằm trong full suite,2blocked cases ghi rõ, không khẳng định cảsuitePASS.
Independent review P2 null callback đã sửa và recheck không P1/P2; fixture visual tests không thay thế fresh MH09 visual/Android acceptance.
[verification03A2](artifacts/03a2/verification.json):scopeChecksPass=true,requiredVerificationPass=false,status=PARTIAL/BLOCKED.
`flutter analyze --no-pub`: **No issues found**, exit0; [analyzer log](artifacts/02a/analyze.log).
`dart format --output=none --set-exit-if-changed` trên2new dirs:9files/0changed, exit0; [format log](artifacts/02a/final_format.log).
diff/physical LOC/links/2252 protected hashes PASS;5 existing docs được phép cập nhật; [verification](artifacts/02a/verification.json).
Initial B/C failures là test harness cleanup/expected label/missing enum API/wrong semantics owner; đã sửa trong new tests;
P2 contact duplicated semantics từ review đã sửa production02A và có semantic tap regression, không nới existing assertions.
**NOT RUN02A:** full suite, fresh screen screenshot comparison, Android/IME/TalkBack, backend/RLS/concurrency.
Standalone component PASS không chứng minh screen integration; planned lifecycle/session/nav rows bên trên vẫn pending03A/03B.

## MH09-02B — fresh execution

New baseline [02b/baseline.json](artifacts/02b/baseline.json):2270files, approved02A/components/tests/artifacts protected.
A **63 existing PASS**; B **12 Payment PASS**; C **17 Footer PASS**; D **15 Operational PASS**.
Final **107 PASS =44 new02B +42 existing02A +21 page/widgets/dialog**, exit0; [final log](artifacts/02b/final_tests.log).

| New test file dưới `test/features/orders/presentation/widgets/mh09/` | Cases / LOC | Coverage |
| --- | --- | --- |
| `mh09_payment_section_test.dart` |12 /154|exact VND/large/full semantics/subtotal0/fee/total, method,3 authoritative COD states/null, no discount, delivered không infer COD,320/390×1/2|
| `mh09_action_footer_test.dart` |17 /261|each cap only, fail-closed fresh/scope/busy/null callback, exact enum dispatch, newly disabled rebuild, order/separate exceptional block,48px/semantics/320390×1/2/landscape|
| `mh09_operational_actions_test.dart` |15 /181|all-false hidden,5 caps individually true still disabled/no tap, exact module labels, no unrelated/refund/COD operations, long/blank reason, revoked cap,320390×1/2|
| `mh09_02b_test_support.dart` |support /64|valid domain/DTO fixtures and capabilities; reuses readonly02A no-ProviderScope host|

Order domain cấm fee khác30000/inconsistent total; không tạo invalid fee fixture/stub để đổi contract.
Production render actual financial fields, không hardcode replacement fee hoặc recompute total; test-only fixture arithmetic xây valid Order.
Null CodSummary chỉ unavailable, không default zero/uncollected/received; return lifecycle không làm giảm obligation trong component.
Footer no OrderStatus input; per-op booleans là eligibility, additional scope/fresh/busy flags không thể bật cap=false.
Ops no callback input, capability true không chứng minh owner API readiness; disabled semantic tap không tạo dialog/success state.
All tests dùng valid snapshots, callbacks/semantics owner đúng node, không backend success mocks trong production.
Format-check7new Dart files/0changed; analyzer và diff/LOC/links/protected hashes theo [verification](artifacts/02b/verification.json).
02A42 tests và existing21 chạy lại không chỉnh source/assertions; full suite/Android/fresh full-screen screenshot/backend NOT RUN.
Review độc lập không P1/P2. Nhận định String* ban đầu đã được rút: SDK core/string.dart hiện có operator*, D15 compile/PASS.
Lệnh final: `flutter test --no-pub test/features/orders/presentation/widgets/mh09 test/features/orders/presentation/pages/manager_order_details_page_test.dart test/features/orders/presentation/widgets/order_widgets_test.dart test/features/orders/presentation/widgets/order_action_dialog_test.dart --reporter expanded`.
