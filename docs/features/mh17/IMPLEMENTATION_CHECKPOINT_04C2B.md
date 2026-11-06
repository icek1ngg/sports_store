# MH17 checkpoint04C2B — Read pipeline integration checkpoint

## Phase B orchestration — 26/10/2026

**MH17-04C2B PHASE B — REFRESH ORCHESTRATION INTEGRATED, READY FOR REVIEW**
[Verification](artifacts/phase_b_orchestration/verification.json), [focused412PASS](artifacts/phase_b_orchestration/focused_complete.log),
[Page/session89PASS](artifacts/phase_b_orchestration/page_verified.log), [new9PASS](artifacts/phase_b_orchestration/new_verified.log).
Only production edit: lib/features/notifications/presentation/pages/notifications_page.dart; all approved owners/tests remain unchanged.
Normal refresh now always calls ReadCoordinator.refresh; obsolete Page Future.wait/head-reset orchestration removed.
Owner arms before I/O, suppresses its own synchronous invalidation and accepts only current qualified head/count; typed Page ports keep live ref ownership.
ForegroundRefresh still owns the existing3second/foreground/current-route schedule; it was not modified and no owner timer was added.
Poll eligibility stays independent for page/count. Eligible head invokes owner.refresh with refreshCount disabled when count was ineligible.
Count-only polling invokes foundation count only: no head arm/reset/request, no lost tail/retry intent; count is not a feed-round authority.
Old-filter poll callbacks fail before I/O. Owner namespace/cache/revision guards and Page mounted checks cancel obsolete refresh continuations.
Canonical ack still comes from InteractionVM. Both explicit read and open completion capture namespace+revision, then call afterCanonicalRead.
N05 newer rounds are not reset by old completions; already-read tail opens adopt the qualified cached head without repository reads.
Read/open independence, canonical count/readAt, captured tile guards, single FeedCoordinator list and Phase A handoff remain intact.
Provider listeners only accept snapshots; existing owner microtask invalid_cursor recovery remains separate from unchanged F02 validation.
No Page-local accepted rows/cursor/retry/cache/latch or competing head-refresh driver. Tail retry remains the original cursor-specific foundation call.
Page still owns rendering/live UI capability checks, resource eligibility/scheduling ports, existing VM action/navigation calls and N07 modal push.
New tests under test/features/notifications/presentation/pages/mh17/: mh17_phase_b_refresh_ack_test.dart278LOC(6cases),
mh17_phase_b_poll_test.dart115LOC(3cases); fixtures reuse existing controlled repository/domain contracts, no approved assertion changed.
New cases: immediate head before next frame; repeated/queued refresh; real ack invalidation before Future completion; intervening newer head;
already-read tail zero additional reads; account-switch late head/count/callback rejection; count-only/head-only polling; old-filter poll cancellation.
Traceability: existing owner N01/N04/N05 lifecycle tests retain exact revision/coalescing oracles; new real Page tests cover binding/order.
Existing Page/session/Phase A tests cover stale display, denial/two-fresh recovery, same-cache block/generation, pending-tail/filter, disposal and N07;
F02 malformed head/tail plus deferred invalid_cursor suites remain unchanged and green. No exact total RPC-one claim across active resources.
Historical Phase A403/80/7 remains separate; fresh baseline403PASS and final412focusedPASS =403original +9new, Page/session89PASS, selected7PASS.
Fresh analyzer PASS; format3files0changed; diff/links/LOC/protected SHA PASS. Initial3lint infos were fixed; attempt log remains preserved.
Working baseline3615files/176status entries, branch feature/orders-notifications-phase2; no HEAD baseline.384protected inputs unchanged.
All prior evidence/Preview/orders/foundation/owners preserved; only Page and these two feature docs changed-existing, new test/evidence allowlist clean.
Page675→665(-10): exact working-baseline diff51added/61removed. Final≤300 remains explicitly authorized intermediate debt.
ReadCoordinator396/420 unchanged; new tests≤400, docs≤200/HANDOFF≤100, utilities≤150. No LOC-only compression or safety guard removal.
Independent Sol medium read-only review: asymmetric poll evidence gap addressed, final review no actionable finding. Luna unavailable; main implemented.
No Actions integration, final cleanup, F03/F05/F07, Preview/Android/backend/Auth/router changes or MH17 UI approval; no commit/push/destructive Git.
Next safe step: review Phase B, then separately authorize a bounded Actions integration; do not start automatically.

## Phase A integration — 26/10/2026

**MH17-04C2B PHASE A — READ STATE BINDING VERIFIED**
[Verification](artifacts/phase_a_binding/verification.json), [focused403PASS](artifacts/phase_a_binding/focused_verified.log),
[Page/session80PASS](artifacts/phase_a_binding/page_verified.log), [new5PASS](artifacts/phase_a_binding/new_verified.log).
Fresh working-source baseline398PASS; captured3588files/176status entries, branch feature/orders-notifications-phase2; not HEAD.
Only production edit: lib/features/notifications/presentation/pages/notifications_page.dart.
SessionBridge is constructed before ReadCoordinator then attached once in initState; both disposed with Page, independent modal route survives.
Bridge callback revokes contexts/action capabilities synchronously, then synchronizes the explicit live scope/cache/lease/query.
Same-owner compatible cache replacement requests opt-in BEFORE reset; account/role/generation/unreadable/denial paths fail closed.
No fallback Page row list: internal FeedCoordinator owns rows/filter/cursors/history/merge/retry; ReadCoordinator owns round/receipt/latch.
Page retains only namespace/intent metadata for provider subscription and captured UI capability checks; no canonical cache/count authority.
Foundation page/count watches/listeners pass exact snapshots and captured intents; cached head adopted only in current armed round.
SnapshotProjection supplies pure render/cache predicates; new namespace stale rows remain disabled until accepted fresh head AND observed fresh count.
Read/open closures bind namespace/lease/revision/cursor/query; old callbacks remain revoked after new head/count recovers.
Provider invalidation is deferred only when build is active, with current scope/cache recheck; context and read capability revocation is immediate.
Errors without aggregate data use the current synchronous foundation/query namespace; no fabricated successful cache provenance.
Existing Page polling/normal explicit refresh/read-open VM paths remain; accepted-round reset is delegated, duplicate list/denial/cursor code removed.
Minimal owner.refresh ports handle private two-fresh denial recovery and existing deferred invalid_cursor recovery; no second latch/recovery pipeline.
Phase B full refresh/poll/ack-completion orchestration migration NOT STARTED; NotificationPageActions remains isolated.
F02 loader guard untouched; malformed tail retry preserves exact current request cursor. N07 Modal/Handle/push implementation unchanged.
New test/features/notifications/presentation/pages/mh17/mh17_phase_a_binding_test.dart196LOC: head/count arrival orders(2),
irreversible captured read/open revocation, discarded tail/late old response, denial and explicit two-fresh recovery.
Existing tests additionally cover first-frame account/role/generation/logout/block privacy, filter/tail transition, F02, polling, gesture and modal lifetime.
Fresh26/10/2026: new5PASS, all398baseline cases preserved plus5 =403focusedPASS; Page/session80PASS; selected7PASS.
Analyzer PASS; format2files0changed; diff/links/SHA PASS. 383protected inputs unchanged INCLUDING all owners, original tests, F02/order/Preview source.
ReadCoordinator396/420 unchanged; Page852→675(-177): exact baseline-to-working diff335added/512removed, including guarded binding/structural lines.
Page still exceeds final300LOC target as expressly authorized interim debt; tests196/400 and all changed docs within limits.
Prior artifacts/failure logs preserved. Intermediate logs record error/loading mapping and build-time provider scheduling fixes;
new test initially expected literal1207, corrected to exact UnreadBadge.count because approved visual text is99+; no approved assertion changed.
Independent Sol medium read-only review: captured-callback and revocation findings fixed; no remaining security/scope blocker. Luna unavailable; main implemented.
No Android/backend/full-suite acceptance or MH17 UI approval. Stop before Phase B/Actions/final cleanup/F03/F05/F07/Auth/router/backend/Preview changes.

## Current follow-up: MH17-04C2B-H, 22/10/2026

**MH17-04C2B-H — STALE DISPLAY HANDOFF VERIFIED** under user-approved420LOC cap26/10/2026.
ReadCoordinator396LOC and source/test hashes match last verified handoff; [approval closure](artifacts/phase_a_binding/approval_closure.json).
398focused/34handoff/62coordinator/7selected/analyzer PASS below were executed22/10/2026, not rerun for this documentation closure.
The isolated closure preceded Phase A above; overall04C2B Phase B remains incomplete.
[Fresh verification](artifacts/stale_display_handoff/verification.json), [handoff/parity](artifacts/stale_display_handoff/handoff_verified.log), [focused](artifacts/stale_display_handoff/focused_verified.log).

API: `synchronize(NotificationReadNamespace live, {bool preserveSameOwnerStaleDisplay = false, NotificationQuery? query})`.
Default remains reset-on-namespace-change; original approved empty-items assertion passes unchanged.
Opt-in requires explicit current query (filter/pageSize/active cursor), exact trusted scope/user/role/generation, valid live lease/readable cache,
new cache identity, no denial, and every retained recipient matching the owner. No lease-only transfer or client-side filtering.
Existing Feed.refreshHead retains the sole presentation list while clearing receipt/head adoption/cursor/history/tail/retry eligibility.
Revision advances; pending invalid_cursor recovery is canceled. Old head/tail/count namespace/tickets cannot restore private data.
Retained rows are display-only, not a canonical fresh success or a new F02 validation.
Actions/load-more remain disabled until a new accepted head and fresh observed canonical count qualify in the new namespace/cache.
Count stays foundation-owned; no optimistic readAt/count mutation or copied Page list was introduced.
Missing/incompatible query, actual account/generation/role change, logout/expiry, blocked cache, invalid lease or existing denial clear rows.
Same-object invalidation remains read-only; live block/disposal preflight clears private rows even without a cache callback.
Count-getter owner switch is checked immediately after the callback; final live-intent check also guards action publication.
Explicit reset/dispose always clears. An existing Bridge callback that resets before captureLease/synchronize cannot be undone.
Future Page wiring must choose the handoff before an unconditional reset, synchronously revoke actions/modal, and still guard private rendering.
No Page/Bridge/Feed/Projection/F02/VM/widget/Preview change; N07 real Page/modal tests still PASS, not a new pipeline integration claim.

Fresh results22/10/2026: baseline364PASS/1known parityFAIL; final MH17398PASS = original364 +parity1 +new handoff33.
Handoff/parity34PASS, original coordinator62PASS, selected safe regressions7PASS; analyzer PASS; format5files0changed.
Parity changed only the synchronize stimulus to opt-in/query; original expected row/disabled actions and all approved assertions preserved.
New test paths: presentation/view_models/mh17/notification_read_handoff_test.dart194LOC, notification_read_handoff_privacy_test.dart279LOC,
notification_read_handoff_support.dart97LOC under test/features/notifications/; parity97LOC. Tests<=400/helper<=150 PASS.
ReadCoordinator342→396(+54) physical LOC; Page852→852. Original350 gate blocked; user explicitly approved420 on26/10/2026.
Fresh working baseline3563files;379protected inputs unchanged (authorized owner/parity excluded), prior artifacts preserved; diff/links/hash PASS.
First compile-attempt error and count-getter race reproduction logs remain in the new evidence directory; no weakened assertions.
Independent Sol medium read-only review found no further correctness issue; flagged reset-wiring constraint and LOC gate. Luna unavailable; main implemented.
User now authorizes bounded Phase A separately; Phase B remains outside scope. F02 stays implemented; F03/F05/F07,
backend/Auth/router/Preview and MH17 UI approval remain outside scope.

## Historical checkpoint evidence before this authorized follow-up

The following source ranges/results describe the original342LOC owner and unchanged prior artifacts; they are not current handoff failures.

**MH17 CHECKPOINT04C2B — PARTIAL / BLOCKED**
Last verified checkpoint: fresh364PASS baseline +Phase A compatibility preflight. Phase A production binding chưa thực hiện.
Phase B NOT STARTED. No production changes, no parallel read pipelines installed; Page852LOC unchanged.
[Verification](artifacts/implementation_checkpoint_04c2b/verification.json), [failing proof](artifacts/implementation_checkpoint_04c2b/phase_a_parity.log).

## Exact protected-owner blocker

Approved Page oracle: test/features/notifications/presentation/pages/mh17/mh17_modal_page_integration_test.dart:89–108.
Same-owner/cache replacement giữ old tile ở trạng thái disabled trong khi new snapshot pending; modal phải revoke.
Protected owner oracle: test/features/notifications/presentation/view_models/mh17/notification_read_provenance_test.dart:38–47.
Same-scope cache replacement explicitly expects coordinator.items empty, old receipt/revision rejected.
ReadCoordinator.synchronize:74–76 gọi _arm(keepItems:false) khi namespace tuple đổi; FeedCoordinator.reset:39 xóa items.
Do đó direct Page binding vào owner.items không giữ được stale-display oracle hiện tại; ticket/lease/live checks vẫn phải chạy.
Không giữ thêm một Page-local row list để che mismatch vì sẽ tái tạo competing accepted-feed ownership.
Không trì hoãn live synchronization, bypass provenance, đổi permission hoặc weaken original tests để đạt green.

## Minimal failing integration compatibility oracle

New test/features/notifications/presentation/pages/mh17/mh17_read_pipeline_parity_test.dart90/400LOC;1case, no helper mới.
Real NotificationsPage/Navigator/modal và protected owner nhận cùng canonical head snapshot từ real foundation cache.
Before replacement: owner accepts head, same row identity/recipient, canInteract true.
After replacement: scope giữ nguyên, cache mới readable; Page giữ same old tile, callbacks null, modal revoked đúng N07.
Public owner synchronize(live) succeeds, canInteract false đúng privacy, nhưng items=[] thay vì accepted stale row.
Final parity assertion FAIL(Expected[accepted],Actual[]), giữ nguyên test/log; không claim production integration đã hoàn tất.
Bridge dùng public live-value capture/synchronize path, no fake permissions và no extra reset callback ép owner clear.
Try/finally cleanup completes pending foundation read và disposes owners/host; failure duy nhất là semantic parity assertion.

## Fresh verification22/10/2026

Baseline364PASS trước edits; new parity0PASS/1FAIL. Full MH17364PASS/1FAIL, exit1; toàn bộ364existing cases vẫn PASS.
Selected safe regressions7PASS; analyzer PASS No issues found; format1file0changed; diff/LOC/links/protected SHA PASS.
New regression stays active in focused directory; focused suite cố ý chưa green cho tới khi giải quyết compatibility gate.
Independent Sol medium read-only review xác nhận blocker giữa2approved oracles; reviewer không edit/run tests.
Fresh3549working-file baseline/176status entries, feature/orders-notifications-phase2; không dùng HEAD.
380protected inputs INCLUDING Page/owners/F02 guard/tests unchanged; all prior artifacts/MH07/08/09/Preview preserved.
Only existing HANDOFF changed; new test/checkpoint doc/task evidence trong allowlist. Page852→852(delta0).
No backend/Android/native/full-suite execution or MH17 UI user approval claimed.

## Exact next safe action

Cần authorize riêng một opt-in same-owner stale-display handoff API ở protected ReadCoordinator, không full architecture audit.
Giữ default synchronize/reset contract và original unit assert(items,isEmpty) nguyên vẹn.
Opt-in chỉ giữ presentation items khi exact same readable SessionScope/cache replacement; clear receipts/recovery/cursors/request intents.
Không coi old data là fresh/F02-validated mới; actions vẫn disabled tới accepted new provenance; old intents không authorize.
Account/generation/logout/denial/blocked cache phải tiếp tục fail closed; canonical cache/count/ack/target authority không đổi.
Đây là bounded follow-up proposal chưa implemented/authorized trong task này; không sửa owner protected hoặc tự thêm mode.
Sau follow-up PASS cả owner tests +Page oracle +parity case, mới resume Phase A binding; Phase B chỉ sau Phase A focused PASS.
Khi resume: giữ tail intent sau accept để background invalid_cursor recovery hoạt động; head round armed before IO/adopt once.
F02 đã implemented và giữ nguyên; F03/F05/F07/Auth/router/backend/Preview/Actions integration ngoài scope.
STOP. MH17 UI NOT USER APPROVED; no04C2B completion claim, final Page cleanup, commit/push/destructive Git.
