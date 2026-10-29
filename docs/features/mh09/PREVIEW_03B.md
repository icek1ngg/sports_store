# MH09-03B — Preview integration và verification

**MH09-03B — PREVIEW INTEGRATED, READY FOR VISUAL AUDIT**. MH09 UI NOT YET APPROVED.

## Baseline và phạm vi

Baseline mới2319working files/1641dirty entries,branch feature/orders-notifications-phase2; SHA-256 working versions, không HEAD.
[Baseline](artifacts/03b/baseline.json) lưu hashes/status/source trước edit.159focused baseline PASS;393full trước task là lịch sử.
Chỉ đổi3existing Preview files, thêm4MH09 debug files/4test files+helper và feature docs/evidence; toàn production readonly.
Không sửa existing tests, seven components, old fixtures, main/App/controls, backend/Auth/router hoặc dependency.

## Kiến trúc / authority

`main.dart → Mh08PreviewApp → stable ProviderScope → Mh08PreviewSurface → MaterialApp/Navigator` giữ nguyên.
MH07 default; existing selector chuyển MH08, card mở MH09 bằng full UUID; showControls=false không có debug toolbar mới.
`Mh09PreviewRoute` thêm selector ghi DEMO MH09/scenario, không private UUID ngoài access gate, không ProviderScope/Navigator thứhai.
`Mh09PreviewDetails` sở hữu fixture-world/revision/controlled read policy, không production canonical cache hoặc ViewModel mới.
Data scene giữ SessionScope/EpochCache/container; refresh exact active detail và canonical head qua existing providers.
Cùng immutable world project selected summary/detail, không hai authority độc lập; Order object/status/UUID/money giữ nguyên.
List counts/statusCounts/cursor/asOf/query và10canonical records/page3 không đổi; chỉ selected summary projection thay trong routeMH09.
`Navigator.push` future là Route.popped, không transition.completed; finally reset world trước existing accepted-pop head refresh.
Sau Back MH08 canonical; không giữ alternate40items trên approved MH08 list.
Auth scenes reset world/gates trước generation và session invalidation; session revoked giữ nguyên sau Back, không tự login manager.
Explicit global data hoặc MH09 canonical recovery tạo generation mới; global same-data selection không early-return khi auth override còn active.
Adapter guard manager trước seed/transport; list captures submittedScope+projectionRevision và rejects late scope/world changes.
Detail rechecks revision/authorization sau canonical await, trước tạo loading gate; reset/dispose release pending và clear hold flag.
Late responses không publish qua production EpochCache; Preview adapter cũng fail closed trước khi trả aggregate cũ.
Mutations vẫn unavailable từ existing repository; không receipt,optimistic state,success toast hoặc external owner state mutation.

## Source map / LOC

| File under tool/ui_preview/ | Before→after / limit | Trách nhiệm |
| --- | ---: | --- |
| mh08_preview_surface.dart |121→151/300|stable navigation,refresh/listener wiring|
| mh08_preview_environment.dart |91→166/250|scope transitions,authorized adapter/list revision|
| mh08_manager_repository.dart |181→186/250|readonly seed accessor; old transport/query unchanged|
| mh09_preview_details.dart |new158/250|fixture world and cancellable loading/revision guards|
| mh09_preview_fixtures.dart |new245/250|deterministic valid aggregates/summary/capability variants|
| mh09_preview_route.dart |new72/180|MH09-only debug controls|
| mh09_preview_scenario.dart |new21/150|19 enum values|

Production page43/content275/body82/layout45 unchanged; seven components/shared lifecycle/timeline unchanged.
Fixture file245/250 gần cap: future distinct fixture responsibility cần helper có nghĩa, không tăng file hoặc split để giấu LOC.

## Scenario definitions / cách mở

Launch existing entrypoint; MH07→screen selector MH08→search exact UUID→card detail→tooltip `MH09: chọn kịch bản`.
Popup tự cuộn theo current scene; cuộn menu để chọn scene ngoài viewport.
Canonical giữ original detail; normal giữ base trừ delivered records thêm actual fixture return summary/event.
Record1 UUID30000000-0000-4000-8000-000000019999: pending, buyer khác recipient,2item rows,1.960.000VND COD.
Record9 UUID30000000-0000-4000-8000-000000019991: long Vietnamese account/recipient/address,subtotal3.920.000,total3.950.000.
Delivered record5 UUID…019995 hoặc record7 UUID…019993 +normal: Delivered/Delivery delivered/COD collected/Return pending_review độc lập.
Return event deterministic deliveredAt+2h, within deadline; alternate detail.asOf=submittedAt, nằm trước canonical page.asOf.
Không suy COD/return từ status trong UI; fixtures ghi các trường đó rõ ràng, không refund/ETA/OTP/GPS giả.

| Scene | Hành vi debug |
| --- | --- |
| canonical |original immutable detail, không projected list changes|
| normal |actual return fixture chỉ khi delivered; không sửa Order/COD|
| large |40snapshots,UUIDs riêng,quantity1,integer partition đúng subtotal,không totals mới|
| missingDelivery / missingCod |projection null riêng, không unassigned/uncollected mặc định|
| missingBuyer / emptyReturns |buyer null hoặc returns explicit empty, không giả successful failed-source|
| loading |800ms delay; tests holdLoading/release gate,không timeout giảsuccess|
| error |first detail read network failure,retry succeeds; authorized old snapshot retained read-only|
| stale |refresh network failure, giữ accepted authorized snapshot read-only|
| expired / unauthorized / unresolved |scope generation thật, no private seed/manager read/data/reason|
| accountSwitch |managerB ID…0099,generation mới,cache mới,cùng stable container; không restore worldA|
| confirmOnly / rejectOnly / commandsDenied |explicit independent capability variants, status không bật action|
| exceptionalCancel |preparing record3 UUID…019997,managerCancel capability riêng|
| operations |preparing hoặc awaitingRedelivery explicit external capabilities; integration luôn disabled|

Transport scene selector là refresh của accepted detail; cold loading/error/invalid-ID vẫn kiểm tra bởi existing production page tests.
Late response dùng controlled pending gates/tests, không thêm menu item tạo backend success.
Không return/refund payment evidence, external destination integration hoặc mutation được thêm trong03B.

## Verification thực thi

| Check | Kết quả mới / evidence |
| --- | --- |
| Baseline focused |159PASS, [log](artifacts/03b/checkpoint_a_tests.log)|
| Fixture+existing Preview checkpoint |23PASS, [log](artifacts/03b/checkpoint_b_verified.log)|
| New cases |28cases trong4newtestfiles, chạy trong focused/full; không skip/weakening old tests|
| Final focused |181PASS, [log](artifacts/03b/focused_tests.log)|
| Full flutter test --no-pub |421PASS,0FAIL, [log](artifacts/03b/full_tests.log)|
| Analyze --no-pub |No issues, [log](artifacts/03b/analyze_final.log)|
| Format check |12files/0changed, [log](artifacts/03b/format.log)|
| Diff/LOC/links/hash |PASS, [verification](artifacts/03b/verification.json)|

New tests LOC:details225/fixtures209/navigation186/scenarios315≤400;support56≤150.
Header Back và `binding.handlePopRoute()` riêng:3cycles mỗi loại, exactUUID/search/status/container/cache/query retained.
Mỗi accepted pop đúng1canonical head refresh, không replay cursor, no accumulated reads qua repeat cycles.
Framework Back đóng modal trước detail, không app exit; denied scope Back không refresh old manager; explicit recovery PASS.
Null projections độc lập,40items→last item→timeline,integer money/ownership,return event≤asOf PASS.
Repeat Confirm/Reject,empty/valid reason→unavailable,cap revocation,expiry clears reason PASS.
Held A→B,no old40world restored; old list/detail completions after expiry/account/reset/dispose rejected PASS.
Existing03A2 same-frame inactive/reparent/unmount/session/late/callback IDs regressions chạy lại, không protected source changes.
Old MH07/MH08/Preview lifecycle/query và original K1 keyboard tests chạy trong focused/full, không sửa assertions.
Intermediate logs giữ nguyên: lỗi import/test menu visibility/animation và debug gate/auth đã sửa; final logs ở bảng là oracle.
Independent Luna implementation/Sol review theo AGENTS; review scope/late reads/gate/asOf đã xử lý, không outstanding blocker.

## Android runtime smoke / provenance

Actual target `emulator-5554`,Pixel_5 AVD,Android API35,1080×2340,density440/DPR2.75; không giả định deviceId trước detect.
Process-local GRADLE_OPTS: `-Dorg.gradle.project.kotlin.incremental=false -Dorg.gradle.project.kotlin.compiler.execution.strategy=in-process`.
Command: `flutter run --no-pub --no-resident -d emulator-5554 -t tool/ui_preview/main.dart`; existing entrypoint, không Supabase/Auth.
Build/install/launch PASS qua [latest run](artifacts/03b/android_verified_run.log); initial run log riêng giữ build warnings/provenance.
MH07 default, MH07↔MH08 selector, MH08→MH09, repeated Back, normal/40items/long/null/stale controls reachable.
Ảnh [manifest](artifacts/03b/runtime_manifest.json) phân biệt initial/intermediate/final build, raw attempts không dùng claim.
Ảnh runtime có viewport thực/DPR2.75 và debug controls; không phải HTML390×844/DPR1 visual comparison.
Header Back tap tooltip thật PASS; framework Back riêng PASS; Android ADB KEYCODE_BACK modal và route PASS.
Confirm dialog→KEYCODE_BACK:modal đóng,MH09 còn; MH09→KEYCODE_BACK:MH08 còn,không app exit.
Floating IME hiện hữu:focus reason→mInputShown=true;KEYCODE_BACK bỏ IME và đóng Reject cùng lúc,MH09 còn.
Không claim keyboard-only Back hoặc docked IME; không đổi global settings, không test physical gesture/TalkBack.
Runtime logs app lọc theo current PID,không uncaught Flutter/AndroidRuntime error; shader/Gradle/frame warnings không coi success evidence.
No fake backend success; external actions/destinations vẫn unavailable.

## Safety / tiếp theo

2311protected working files nguyên SHA-256 so fresh baseline2319, gồm toàn lib/,oldtests,oldfixtures/screenshots và Preview main/App/controls.
Working tree extensive dirty/untracked giữ nguyên; không commit/push/reset/clean/stash/checkout/switch/merge/delete.
HANDOFF≤100;feature Markdown≤200;source/tests/utilities đúng physical LOC. Không exact context-token claim.
Đề xuất04A: render fresh Flutter390×844/DPR1 đối chiếu HTML,320/360/390/412/landscape ×scale1/1.5/2.
Ghi demonstrated geometry/footer/text/null defects và intentional contract deviations; không tự refinement hoặc Android visual approval.
STOP03B. Backend/RLS/concurrency/production router và external owner integration vẫn ngoài phạm vi.
