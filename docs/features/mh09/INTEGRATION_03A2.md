# MH09-03A2 — Integration và lifecycle evidence

Current: **COMPONENTS INTEGRATED, FULL REGRESSION GREEN, READY FOR PREVIEW INTEGRATION** sau authorized03A2F.
Các checkpoint/blocker03A2 bên dưới là lịch sử;current fresh verification ở phần03A2F cuối tài liệu.

## Checkpoint A — baseline / thiết kế trước edit

Baseline mới: branch feature/orders-notifications-phase2,2300 working files/1620 dirty entries; không dùng HEAD.
[baseline](artifacts/03a2/baseline.json) giữ SHA-256/status; [sources](artifacts/03a2/baseline_sources.json) giữ LOC/source trước task.
Page209;entry test62;legacy body129/contact81/footer176.122 focused baseline PASS mới chạy.
Protected:7 widgets02/shared/providers/models/Preview/MH07/MH08/MH17/evidence cũ; không xóa legacy.

| Thành phần | Owner / input mapping | Thay active legacy |
| --- | --- | --- |
| Mh09Header |owner content-sized header, canPop/back guarded; canonical serialized refresh|AppBar cũ, không ép64 khi scale cao|
| Mh09OrderIdentity |Mh09DetailBody nhận details.order accepted|legacy header UUID/status/time|
| Mh09RecipientSection |same order/buyer; contactEnabled từ owner; callbacks current customerId/phone snapshot|shared recipient +legacy contact card|
| Mh09ItemsSection |details.items same aggregate, no catalog/image fetch|shared items cũ|
| Mh09PaymentSection |same order/codSummary; exact integer financial fields|shared payment cũ|
| Mh09ActionFooter |owner capabilities +fresh/scope/busy +guarded operation callback; page SafeArea/reserved bottom area|legacy command footer|
| Mh09OperationalActions |body current capabilities;external owner integrations vẫn unavailable|legacy external footer|
| OrderLifecycleSections |shared Delivery/COD/Returns cùng aggregate;guarded COD/return IDs|giữ nguyên semantics,không normalize lại|
| OrderTimeline |same entries/historyComplete|giữ nguyên normalization/timeline authority|

Body mới data/callback-only, một main SingleChildScrollView/RefreshIndicator,20 gutter/16 gap;không footer thứ hai.
Page public API6 parameters/defaults giữ nguyên; theme→manager gate→MH09 consumer state owner→foreground refresh/scaffold.
Content State chỉ sở hữu UI lifetime/dialog busy,không giữ OrderDetails/cache/provider mới.
Mọi callback đọc lại current accepted detail và scope/cache/freshness;navigation còn kiểm route validity,đúng IDs.
Không sửa components gần gate177/179,shared lifecycle/timeline/dialog,formatters hoặc provider identities.
Legacy3files giữ nguyên byte/hash nhưng không được import/render trong active composition.

## Kế hoạch dialog owner / probe trước sửa guard

Root Navigator sở hữu dialog; source ConsumerElement sở hữu WidgetRef. Mounted không đồng nghĩa active.
Probe GlobalKey/deactivate trong cùng frame:giữ modal root,source owner mounted nhưng inactive,gọi predicate/submit qua callback.
Trước sửa phải quan sát lỗi/thất bại nếu có;ghi stack/action sequence trong artifacts03a2,không suppress FlutterError.
Dự kiến scoped ConsumerStateful owner:active flag +lifetime generation cập nhật deactivate/activate/dispose.
Captured callbacks bị revoke sau deactivate dù owner được reinsert;check active/mounted trước mọi ref/ancestor lookup.
Capture submittedScope/cache identity từ owner,sourceCache truyền explicit cùng cache;current capability recheck luôn đọc canonical state.
Không dùng route.isCurrent cho dialog predicate vì dialog hợp lệ che page;route ownership cần kiểm isActive riêng nếu cần.
External callbacks/back chỉ dùng navigation context sau active guard;stale/expired/old-scope callback fail closed.
Chỉ áp strategy sau probe/review;không thay shared OrderActionDialog hoặc receipt provider.

## Checkpoints dự kiến

B wire5read components +shared lifecycle/timeline,update finders theo UI mới nhưng giữ business assertions;tests xanh.
C wire2action components,per-op/current/fresh gates;no real mutation/success;tests xanh.
D probe same-frame +post-unmount/session/account/capability/repeated modal/navigation;scoped fix nếu cần;tests xanh.
E focused/components/Preview regressions +full suite/analyze/format/LOC/diff/hash/docs;STOP,không03B.
LOC gates:public page/coordinator≤300,UI≤180,helper≤150,tests≤400,Markdown≤200,HANDOFF≤100.

Bổ sung boundary trước final extraction: owner295 LOC gần300; tách Mh09PageLayout cho SafeArea/header content-sized/footer35%-scroll/reserved body. Đây là trách nhiệm layout responsive riêng, không chuyển authorization hoặc tạo widget wrapper lifecycle.

## Kết quả wiring / LOC hiện tại

Page209→43;new consumer coordinator275/body82/layout45,đều trong gate. Legacy129/81/176 nguyên hash và unused,không cleanup.
Header/Footer do owner compose;body giữ Identity/Recipient/Items/Payment +shared lifecycle/timeline +OperationalActions.
Order/buyer/item instances/COD cùng accepted aggregate;fullUUID/exactVND/40snapshots/lastitem hit-testable không bị footer che PASS.
API6params/defaults giữ nguyên;no provider/cache/second snapshot/mutation/newrouter/shared changes.
Per-op footer capability AND fresh/scope/busy;owner recheck before dialog,nguồn current capability chứ không OrderStatus.
Ops capabilityfalse ẩn;true vẫndisabled module-unavailable;không thayfullCOD lifecycle bằng paymentoverview.

## Dialog / callback investigation và kết quả

03A1 mounted guard giữ true trong inactive window. Probe gỡ source ở sibling trước finalizeTree trong cùngframe;
source.mounted=true,source.debugIsActive=false;old predicate gọi ProviderScope ancestor lookup gây assertion.
[same_frame_red.log](artifacts/03a2/same_frame_red.log) ghi stack Element.getElementForInheritedWidgetOfExactType→ref.read→page predicate.
Scoped ConsumerState owner dùng active/generation:deactivate/dispose/orderId change revoke;activate không reset ticket.
Predicate guard owner trước ref→captured scope/current manager→same readable cache→fresh canonical matching orderId→capability đúngop.
Dialog capture submittedScope/sourceCache/sourceOrderId/ticket;underlyingroute isActive hợp lệ khi modal mở,không dùng isCurrent cho predicate.
Launcher/contacts dùng routecurrent sauowner guard;late finally không setState owner invalid hoặc ghiđè generation mới.
Same-frame,reparentoldticket,post-unmount,rapidroutepop/push,oldscope,lateasync/disposedcontainer đều PASS.
Legitimate Confirm/Reject mởđóng3vòng vẫn validation/reason/unavailable;sourceCache cùngepoch,không giảsuccess.
Reviewer phát hiện retainedcallback sau parent null → TypeError;[red](artifacts/03a2/removed_callback_red.log) và[green](artifacts/03a2/removed_callback_green.log).
Fix4destinations bằng ?.call saucurrentdetail guard;không cache businessdata hoặc suppress FlutterError.

## Tests / checks thực thi

A122 baselinefocused PASS;B16 existing/sameframe PASS;C20 page PASS. Final138 focused PASS,seed20261019.
15 existing tests/81 assertions tương đương sau explicit UI finders;[preservation](artifacts/03a2/test_preservation.json) giữ mỗi case1bản.
Migration:uppercase title,confirm/contact keys,rawUUID privacy finder và4module-disabled reasons đúng approvedcomponent output.
6newfiles/25runtimecases:components4/actions8/access7/owner2/navigation3/existingPreviewcontract1.
Access:shipper/unresolved/expired0reads,foreignUUIDfailclosed,errorretry,accountswitch pending/modal,lateoldaccountresponse PASS.
Refresh:toolbar+pull không duplicate in-flight read;stale/currentcapabilityremoved failclosed;callbackIDs exact PASS.
Transient compileimports/analyzercurlybraces/nonnull lint/test semantics finder đã sửa;log final xanh thaycho intermediatefailures.
Analyze noissues;format17files0changed;LOC/links/diff PASS;2287protected workingfiles unchanged,no out-of-scope newfiles.
Full final `flutter test --no-pub`:**391 PASS /2 FAIL**;không báo allgreen.
[verification](artifacts/03a2/verification.json):scopeChecksPass=true,requiredVerificationPass=false;taskstatus PARTIAL/BLOCKED.
Review độc lập cuối không P1/P2 trong owner/layout/integration;blocked test compatibility dưới đây chưa được sửa.

## Blocker lịch sử03A2 — đã resolve bởi authorized03A2F

1. `test/ui_preview/mh08_preview_lifecycle_test.dart:229`,case `MH09 detail keeps exact UUID and refreshes only canonical head`:
   finder legacy Text('Đơn hàng $firstId') không còn;Mh09OrderIdentity render nguyên UUID với semantics Mã đơn hàng.
2. Cùng case tại:237 và `test/ui_preview/mh08_preview_query_test.dart:91`,case `MH09 return preserves editing/status and refreshes their exact query`:
   tester.pageBack() chỉ tìm framework BackButton/CupertinoNavigationBarBackButton;approved Mh09Header dùng IconButton tooltip Quay lại.
3. Baseline122PASS trướcwiring;afterwiring2tests fail cố định như trên. Không phải claimtừhistoricalresult.
4. New `mh09_preview_navigation_contract_test.dart` qua existingPreview **PASS**:tapheaderthật,preserveUUID/search/status/query/container/headrefresh/nocursorreplay.
   Test mới là functionalprobe,không thaythế/skip2protectedtests và không làm fullsuite xanh.

Follow-up nhỏ nhất,chỉ sau khi được phép mởscope2testfiles;không production/Preview source/shared change:

```diff
# mh08_preview_lifecycle_test.dart — chỉ case nói trên
-expect(find.text('Đơn hàng $firstId'), findsOneWidget);
+expect(find.text(firstId), findsOneWidget);
-await tester.pageBack();
+await tester.tap(find.byTooltip('Quay lại'));
# mh08_preview_query_test.dart — chỉ case nói trên
-await tester.pageBack();
+await tester.tap(find.byTooltip('Quay lại'));
```

Giữmọi businessassertions/pumpAndSettle/query/count checks. Không hidden legacytext,duplicateBackButton hoặc weaken tests.
Tại03A2 proposal chưa được áp do hardscope;03A2F sau đó được user cho phép đúng3finder edits này,không tự03B.
Sauauthorization:baseline mới2files,áp3finderedits,targetedcases+fullsuite/analyze/diff/hash,newhandoff,statuschỉđổi khi allgreen.

## Stop / limitations tại checkpoint03A2 ban đầu

**MH09-03A2 — PARTIAL / BLOCKED** tại checkpointE fullsuite. Code integrated,compiles,focusedgreen;2protected finder failures outstanding.
Không Android/fresh sameviewport MH09 visualcomparison/backend/RLS/mutations;MH09 UI NOT YET APPROVED.
Không delete unusedlegacy hoặc đổiapprovedMH07/MH08/7components/shared/Preview/evidence cũ.
03B chỉ saufullgreen vàtaskmới:stablePreview scénarios/navigation/session/dialog,reuse current MH08→MH09 route;khôngreplace architecture.

## Physical LOC before→after tại checkpoint03A2 ban đầu (lịch sử)

| File | Trước→sau |
| --- | ---: |
| README.md |121→134|
| ARCHITECTURE_PLAN.md |171→188|
| SOURCE_AUDIT.md |111→123|
| TEST_PLAN.md |166→184|
| MANUAL_REVIEW.md |77→86|
| BEHAVIOR_CONTRACT.md |158→158|
| HANDOFF.md |86→83|
| INTEGRATION_03A2.md |new135/200|

New utilities preserve_tests54/150 vàverify80/150;current source/testLOC nằm HANDOFF vàverification.inventory.


## MH09-03A2F — authorized finder fix, mới thực thi19/10/2026

Scope chỉ2tests +HANDOFF/INTEGRATION +new artifacts/03a2/finder_fix/,không production/UI/Preview architecture/shared changes.
Fresh baseline2316working files/1636dirty entries,branch feature/orders-notifications-phase2;SHA-256 bảo vệ working versions,không HEAD.
CheckpointA chạy lại2failures đúng legacy Text/BackButton;render contract test1PASS xác nhận direct Text(fullUUID) +unique active tooltip.
3 authorized changes,không thêm assertion/test hoặc đổi business expectations:
- Lifecycle:find.text('Đơn hàng $firstId')→find.text(firstId),giữ canonical UUID đầy đủ.
- Lifecycle:await tester.pageBack()→await tester.tap(find.byTooltip('Quay lại'));pumpAndSettle có sẵn giữ nguyên.
- Query:cùng tap tooltip activeheader thay pageBack,không Navigator.pop bypass;mọi filter/query/count expectations giữ nguyên.
CheckpointB hai affected files PASS9tests:lifecycle6cases/51expect vàquery3cases/25expect;LOC292→292,142→142.
CheckpointC focused MH09/components/shared138PASS,seed20261019;full flutter test --no-pub **393PASS/0FAIL** mới chạy thực tế.
Analyze no issues;format check2files0changed;git diff --check PASS;physicalLOC/Markdown links PASS.
Byte comparison2files khớp chính xác baseline áp3replacements;cases/assertions giữ nguyên,no remove/skip/weaken.
2312protected existing files nguyên SHA-256,gồm approvedMH07/MH08 UI,all productionMH09,7components,shared/providers/Preview vàold evidence.
[Verification03A2F](artifacts/03a2/finder_fix/verification.json) ghi pass=true,exactThreeChanges=true;old artifacts03A2 không overwrite.
Bản thân tap header back KHÔNG kiểm Android System/hardware Back;03B phải verify đường này riêng,gồm navigation/session/dialog boundaries.
Không claim Android runtime/IME/TalkBack/fresh same-viewport fidelity/backend/RLS/concurrency;MH09 UI NOT YET APPROVED.
Chỉ2docs này được phép cập nhật03A2F;status BLOCKED trong các docs checkpoint trước vẫn là lịch sử,không sửa ngoài scope.
**MH09-03A2 — COMPONENTS INTEGRATED, FULL REGRESSION GREEN, READY FOR PREVIEW INTEGRATION. STOP.**
Không tự start03B/refine04A/04B/cleanup legacy/backend/MH17;nextscope cần task user giao rõ.
