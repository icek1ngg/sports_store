# MH17 checkpoint03 — Approval closure

**MH17 CHECKPOINT03 — READCOORDINATOR IMPLEMENTED, READY FOR REVIEW**
User explicit approval22/10/2026: sole file-specific cap350, thay280. Actual342PASS, mọi other limits giữ nguyên.
Architecture/API giữ nguyên; không restart/audit/refactor Page. MH17 UI NOT USER APPROVED.

## Ba nguyên nhân và repairs

1. Denial từng gắn vào lease tạm, reset/synchronize xóa latch khi lease đổi.
   Nay receipt gắn actual owner tuple(scope/generation/role value,EpochCache identity), tách khỏi lease.
   reset revoke round/feed/receipts nhưng giữ same-owner denial. synchronize chỉ clear khi lease hợp lệ VÀ owner thực khác.
   Null/foreign lease dù có scope/cache tuple khớp nhau vẫn không xóa denial cũ.
   Logout/unreadable scope clear private feed/intents, không authorize reads; generic denial receipt giữ đến valid replacement/recovery/dispose.
   Chỉ explicit refresh có head+count current/fresh/provenance-valid, count cache không stale mới phục hồi same owner.
2. Repeated denial từng rearm và invalidate interactions mỗi event.
   Nay transition từ unlatched chỉ invalidate một lần; latest reason vẫn cập nhật, không globally ignore provider events.
   Legitimate recovery hoặc actual owner/cache transition cho phép xử lý denial mới như transition mới.
3. invalid_cursor từng refresh đồng bộ trong listener.
   Nay microtask coalesce theo exact intent+provider snapshot; trước IO recheck disposed/live lease/scope/cache/revision/cursor/requestId,
   current provider snapshot identity và invalid_cursor eligibility. Recheck sau provider getter để ngăn callback publication lỗi thời.
   Reset/filter/new head cancel schedule; old retry không overwrite job mới; requestId chỉ commit sau successful Feed begin.
   Current accepted tail bị background invalid_cursor vẫn recover như protected Page, không áp pending-loading-only restriction mới.
   Đây là request-token recovery, không phải F02 malformed server nextCursor fix.

## Evidence thực thi 22/10/2026 — reuse, không rerun trong closure

Fresh hashes/status trước edits trong [fix baseline](artifacts/implementation_checkpoint_03_fix/workspace_baseline.json).
Ba oracles chạy riêng BEFORE: mỗi case FAIL1; sau repair chạy riêng FINAL: mỗi case PASS1.
Original37cases và test support nguyên bytes/assertions;25new edge cases, all Checkpoint03 **62PASS**.
Full focused MH17 **255PASS**, thực thi22/10/2026, log completed08:03:03+07 (01:03:03UTC).
Access/session25PASS, head/pagination19PASS là targeted intermediate runs, không cộng thêm.
Analyzer **PASS: No issues found**, thực thi22/10/2026, log completed08:03:33+07 (01:03:33UTC).
Ngày/giờ dựa file timestamps của verified logs; closure chỉ đối chiếu logs/hashes, KHÔNG chạy mới tests/analyzer/format.
8curly-braces infos cũ đã sửa bằng readable blocks, không suppress lint.
Format3files0changed; diff/link/hash final results ở [verification](artifacts/implementation_checkpoint_03_fix/verification.json).
Các failed logs cũ [new](artifacts/implementation_checkpoint_03/new_tests_reproduction.log),
[focused](artifacts/implementation_checkpoint_03/focused_reproduction.log), [analyzer](artifacts/implementation_checkpoint_03/analyze.log) giữ nguyên.
No skips/weakened assertions, no dependency/pub changes/mirror; SDK Dart+flutter_tools.snapshot cùng installed Flutter trên working source.
SDK lock/cache ngoài workspace được cấp quyền cho test/analyze/format; không chạy backend/Android/Preview acceptance/full suite.
Independent read-only review không còn finding correctness trong targeted scope; không claim full Page/modal privacy proof.

## Actual physical LOC và approved exception

| File | LOC | Approved limit | Result |
|---|---:|---:|---|
| notification_page_read_coordinator.dart |342|350|PASS margin8|
| notification_read_head_lifecycle_test.dart |200|400|PASS unchanged|
| notification_read_provenance_test.dart |317|400|PASS unchanged|
| notification_read_pagination_intent_test.dart |165|400|PASS unchanged|
| read_coordinator_test_support.dart |126|150|PASS unchanged|
| notification_read_denial_repair_test.dart |157|400|PASS new10cases|
| notification_read_deferred_repair_test.dart |202|400|PASS new15cases|

Source dưới lib/features/notifications/presentation/view_models/mh17/; tests/support dưới test/features/notifications/presentation/view_models/mh17/.
Đã consolidate repeated live preflight vào _prepare, dùng FeedCoordinator.activeCursor làm single cursor source.
Không chuyển ownership, không thêm file/layer forwarding, không compress statements hoặc bỏ guards để đạt LOC.
342 gồm typed input contracts, owner-bound denial, scheduled recovery/rechecks và readable lint-compliant blocks.
**User đã APPROVED ngoại lệ duy nhất cho file này≤350 physical LOC**, actual342/margin8.
[ENGINEERING_RULES](ENGINEERING_RULES.md) cập nhật; historical R budgets/fix verification ghi cap280 và BLOCKED cũ giữ nguyên.
Không còn failing gate của isolated Checkpoint03; không đồng nghĩa Page integration hoặc MH17 UI accepted.

## Safety và next step

Fix trước closure chỉ đổi draft coordinator +checkpoint03doc/HANDOFF; thêm2repair tests/evidence, old tests/assertions giữ nguyên.
Protected approved Page/Projection/SessionBridge/Feed/foundation/models/VM/orders/Preview và toàn bộ old artifacts nguyên SHA.
358protected inputs unchanged;3630/3633baseline files unchanged, chỉdraft coordinator/checkpoint03doc/HANDOFF đổi.
No private rows/count cache mới, no stored Ref/context/polling/navigation, no optimistic mutation.
F02/F03/F05/F07 chưa đổi; F02 separate authorized fix trước live pagination. Page922/VM455/Tile185/test debt còn nguyên.
Closure chỉ cập nhật3authorized docs và thêm task-specific hash/link/LOC/diff verification, không đổi Dart hoặc old evidence.
[Closure verification](artifacts/checkpoint_03_closure/verification.json) đối chiếu actual LOC, exact source/test hashes với latest fix evidence.
Closure PASS:361protected inputs unchanged;3656/3659existing files unchanged, chỉ3authorized docs đổi; no remaining failing Checkpoint03 gate.
Next safe step: user review isolated Checkpoint03; Checkpoint04 chỉ khi được giao riêng, không tự integrate.
STOP trước Page integration/Actions/Modal/Auth/router/backend và commit/push.
