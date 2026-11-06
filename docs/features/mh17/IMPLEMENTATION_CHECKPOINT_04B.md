# MH17 checkpoint04B — Modal/context lifetime

**MH17 CHECKPOINT04B — MODAL OWNER IMPLEMENTED, READY FOR REVIEW**

Scope: isolated modal + revocable handle, new widget tests, no Page integration hoặc existing Dart changes.
Fresh working SHA/status baseline tại artifacts/implementation_checkpoint_04b; không dùng HEAD.

## API và N07 protocol trước implementation

NotificationContextHandle({required NotificationReadNamespace namespace,required String recipientId,
required NotificationQuery query,required String title,required String body}).
read(liveScope,liveCache)→nullable(title,body);isRevoked;listen(callback)→cancel;revoke();release().
Mh17NotificationContextModal({required NotificationContextHandle handle,key}).
Helper có trách nhiệm riêng: revocable private cell + direct same-object cache listener trước khi route mount.
Không giữ raw NotificationItem/lease như permission, không giữ Page/Ref/BuildContext; metadata scope/cache/query là provenance.
Opener phải authorize current lease/receipt trước tạo handle, link owner denial→revoke, không capture item/title/body trong builder.
Parent push showModalBottomSheet; builder chỉ capture handle; route.whenComplete(handle.release), không await trong item-holding frame.
Modal owns live scope/cache/list/count subscriptions; giữ independent guards khi origin Page dispose.
Direct cache listener clear cell đồng bộ khi blocked event; build rechecks cache.canRead kể cả không có callback.
Denial/scope/generation/cache identity/foreign recipient revoke không đảo ngược; recovery cần new authorized handle.
Current-owner stale/ack/list row removal không revoke content; count/list Foundation owns reads, no new repository/cache policy.
Route không auto-pop khi revoke; safe state hiển thị thay private sheet. Close chỉ pop current modal route; Back do Navigator.
Route dispose closes subscriptions, releases cell; repeated revoke/release safe; không claim memory zeroization.
Host dispose không tự release route-owned handle; explicit access loss vẫn revoke qua live route guards/owner link.

## Verification

[Verification](artifacts/implementation_checkpoint_04b/verification.json) ghi working-source SHA/LOC/logs/checks.
Fresh22/10/2026: baseline296PASS; new modal24PASS; full focused320PASS; selected safe regressions7PASS.
Analyzer PASS No issues found; format6files0changed; diff/links/LOC/protected hashes PASS.
New source paths under lib/features/notifications/presentation/widgets/mh17/:
- notification_context_modal.dart156/180: ConsumerState lifetime, independent provider guards, sheet composition.
- notification_context_handle.dart73/150: independent revocable cell/cache subscription responsibility, justified N07.
New test paths under test/features/notifications/presentation/widgets/mh17/:
- notification_context_modal_test.dart155/400:8cases, display/Close/Back/initial denial/revoke/narrow long text/old Close.
- notification_context_modal_lifecycle_test.dart281/400:16cases, scope/cache/denial/late response/host disposal/stale/live render.
- notification_context_test_support.dart138/150: real Navigator/modal host-removal harness; builder giữ handle only.
- notification_context_test_providers.dart78/150: controlled trusted scope +repository fake; real foundation providers.
24cases kiểm actual widgets/routes, không chỉ helper. Private title/body absent ngay first pump sau loss; route vẫn mounted.
Synchronous handle clear +markNeedsBuild ngay ngoài build; trong persistentCallbacks defer rebuild nhưng live build gate đã clear cell.
No-event block trước mount bị live gate chặn; silent cache.dispose khi mounted cũng bị chặn trước explicit next rebuild.
Không hứa phát hiện ngay mutation hoàn toàn không event/rebuild: parent vẫn phải live-check và signal loss đúng contract.
Scope/list/count subscriptions bắt đầu ở route init; direct cache listener có từ handle creation và release khi route hoàn tất.
Existing foundations có thể read khi route subscribe; modal không gọi repository/notifier refresh, count mutation hoặc acknowledgement.
Single-route handle; opener phải dispose/release nếu push thất bại. Repeated release và late callbacks safe.
Attempt01 generic inference compile failure fixed local typed subscriptions; original log giữ nguyên.
Attempt02:20PASS/1FAIL phát hiện microtask-only rebuild trễ first pump khi explicit revoke; fixed dirty-mark ordering, giữ assertion.
Attempt03:21PASS; final bổ sung3cases pre-first-frame/rebuild/no-event để đạt24. Không cộng reruns vào total320.
Initial analyzer4braces infos chỉ new tests đã sửa; final clean, không suppressions hoặc weakened assertions.
Independent Sol medium read-only review approve isolated source/no blocker; reviewed21-case log, không tự chạy test.
Final3cases do main review/test; no Page or end-to-end modal privacy approval từ review.
Protected367inputs unchanged; 3687-file baseline chỉ existing HANDOFF authorized đổi; all prior artifacts/assertions giữ bytes.
Không chạy full suite/backend/Android acceptance; selected Preview widget tests không phải Preview/native acceptance.

## Remaining integration và STOP

Future Page phải authorize receipt/lease/recipient trước tạo handle, wire denial→revoke và detach link khi Page dispose.
Builder không giữ Page State/raw item/immutable title/body; use captured handle only và whenComplete(handle.release).
Route provider scope phải sống trên Navigator, không đặt trong subtree bị dispose theo host; harness kiểm host disposal thực tế.
Không auto-pop trên loss; không giữ stale old handle để tái authorize sau recovery; no memory-zeroization/backend-sanitization claim.
Page922/VM455/Tile185/test debt untouched; ReadCoordinator342/350 exception unchanged.
F02 separate authorized fix trước live pagination; F03/F05/F07/Auth/router/backend/Preview ngoài scope.
Next: review checkpoint04B, chỉ lập bounded integration checkpoint khi user giao; chưa start04C hoặc Page integration.
MH17 UI NOT USER APPROVED. STOP; no commit/push/destructive Git operations.
