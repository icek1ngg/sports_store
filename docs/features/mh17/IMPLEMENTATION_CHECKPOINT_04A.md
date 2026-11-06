# MH17 checkpoint04A — Isolated Notification Page Actions

**MH17 CHECKPOINT04A — ACTIONS IMPLEMENTED, READY FOR REVIEW**

Scope: một new Actions owner≤250LOC, new focused tests≤400/file/support≤150, HANDOFF≤100; no Page integration.
Fresh working baseline/status/SHA trong artifacts/implementation_checkpoint_04a; focused255PASS trước edits, không HEAD.
Existing Dart/tests/Preview/backend/contracts/MH07/08/09 và all historical evidence read-only.

## API/authority trước implementation

NotificationPageActions({required NotificationPageSessionBridge session,required NotificationPageReadCoordinator reads}).
markRead(NotificationItem,NotificationReadNamespace submitted,NotificationActionPorts)→Future<bool>.
open(NotificationItem,NotificationReadNamespace submitted,NotificationActionPorts)→Future<bool>;dispose().
Submitted namespace/lease phải capture cùng UI callback; không cấp lại lease mới cho stale captured callback lúc tap.
Ports: isActive,reads(live read ports),query,interaction,state,navigation getter,message,context(namespace,title,body).
Entry methods synchronous: item chỉ truyền thẳng real VM, helpers async chỉ giữ ID/namespace/revision/Future/ports.
Adapter state chỉ dependencies+disposed; no NotificationItem/count/PII cache/Ref/context/nav mutex.
Canonical VM được phép giữ item trong async operation hiện có; adapter không tạo bản sao/persistence riêng.

Entry preflight: submitted tuple khớp live, SessionBridge lease/canRead, ReadCoordinator receipt/fresh head/query +access latch.
Post-await: isActive/dispose trước mọi live getter, current scope/cache/lease và access latch kiểm lại; no auto-authorize bằng ticket.
Không yêu cầu head fresh sau own read ack invalidation vì typed resolver/VM vẫn authoritative cho ongoing open.
Stale lúc START không được read/open; cache block/replace hoặc access revoke sau await luôn fail closed.
VM owns read dedup/ack/target matrix; Actions không set readAt/count hoặc parse text thành routes.
Available read chỉ markRead; open khởi động read và target independently như Page; read failure không khóa authorized navigation.
notification_only dùng sync context callback với allowed server title/body, không await modal hoặc giữ payload trong helper.
Parent owns modal route/lifetime/authorized rechecks; checkpoint này không implement Modal owner.
Read success chỉ từ VM boolean/canonical ack hoặc existing already-read fast path; afterCanonicalRead delegate current round.
Ports/getters phải là live owner capabilities, isActive phản ánh mounted; owner dispose Actions trước Read/Bridge để đóng callbacks.

## Test plan

Real Riverpod InteractionVM +SessionBridge/ReadCoordinator, controlled repository/resolver theo existing contracts.
Canonical UUID/UTC fixtures, notification_only subject=eventID; no replacement VM permission policy.
Valid/invalid ack, same-ID pending dedup, failure, typed/missing/denied/unavailable navigation, unknown/informational subject.
Account/generation/cache switch, stale/block/access latch, captured old callback, disposed/late resolver/navigation.
Exact unread count and row state không optimistic; repeated authorized opens không introduce F05 serialization.
Original255cases/assertions nguyên bytes; tests mới chỉ isolated adapter, no production Page first-frame/modal PASS claim.

## Verification và STOP

[Verification](artifacts/implementation_checkpoint_04a/verification.json) ghi actual tests/analyzer/format/diff/LOC/links/hashes.
Fresh22/10/2026: baseline255PASS; Actions41PASS; final focused296PASS (255+41), selected regressions7PASS.
Analyzer PASS No issues found; format6files0changed; tests trên working source qua installed SDK, không pub changes.
Source notification_page_actions.dart169/250LOC. New test paths cùng presentation/view_models/mh17/:
- notification_page_actions_read_test.dart175/400:13cases, ack/dedup/no optimistic/state/publication.
- notification_page_actions_open_test.dart128/400:9cases, real typed VM/independent read/open/context/F05.
- notification_page_actions_lifecycle_test.dart192/400:19cases, owner/cache/lease/dispose/late result/context recipient.
- notification_action_fakes.dart90/150 và notification_actions_test_support.dart121/150: canonical fixtures +real VM harness.
Entry context kiểm recipient theo existing VM ownership; foreign informational body không tới context port.
Post-dispose không đọc live ports của Actions; VM/Bridge borrowed vẫn có thể hoàn tất canonical operation của chúng.
Attempt01:21PASS/1FAIL vì counter gom cả Bridge callbacks; isolated adapter counter sửa đúng oracle, log giữ nguyên.
Analyzer initial ambiguous AsyncError export đã sửa `show Completer`; final analyzer clean, initial log giữ nguyên.
Independent read-only Sol review không blocker; final2hardening cases do main review/test, không claim reviewer chạy tests.
Protected361inputs unchanged, original assertions/old evidence giữ bytes; only existing HANDOFF authorized đổi.
No full suite/Android/backend execution; selected Preview widget regression không phải native/Preview acceptance.
No heap-zeroization assertion: kiểm source fields/helper signatures, caller phải tránh capture private item trong live ports.
Modal parent phải recheck namespace/cache và close/clear khi owner loss; sync forwarding không chứng minh modal lifetime.
Next bounded checkpoint: isolated modal/context owner sau user review; không bắt đầu trong task này.
Only new Actions/tests +checkpoint04A doc/evidence và HANDOFF authorized; no existing source changes.
F02/F03/F05/F07, Auth/router/backend/Preview giữ nguyên; F02 separate fix trước live pagination.
STOP trước Page/Modal integration hoặc Checkpoint04B/04C; MH17 UI NOT USER APPROVED.
