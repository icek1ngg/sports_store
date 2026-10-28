# MH17 checkpoint02 — Isolated SessionBridge

## Scope trước implementation

Baseline working-file hashes mới trong `artifacts/implementation_checkpoint_02/`; không dùng HEAD.
Existing focused172PASS trước edits. Riverpod/flutter_riverpod3.4.3 từ lockfile và installed source.
`WidgetRef.listenManual` supported trong initState, không trong build; fireImmediately true, close subscription idempotent.
Không đổi existing Dart/test/Page/provider/model/widgets/Preview hoặc source/evidence MH07/08/09.
New bridge≤250, tests≤400/file, cohesive test harness support≤150; docs≤200/HANDOFF≤100.

## Public API đã chọn

`NotificationPageSessionBridge({required void Function() onNamespaceChanged, required void Function(String) onResourceInvalidated})`.
`attach(WidgetRef ref)` trong initState, một lần; repeat attach là no-op. Không lưu Ref/context hoặc callback capture Ref.
`synchronize(SessionScope liveScope, EpochCache liveCache)` nhận explicit live inputs, dùng trước private render/action.
`Object? captureLease(SessionScope liveScope, EpochCache liveCache)` synchronize rồi cấp identity nếu canRender.
`bool isCurrent(Object? lease, SessionScope liveScope, EpochCache liveCache)` synchronize rồi so token+live readability.
`revokeAccess()` đổi lease và signal đồng bộ; owner giữ access latch/canonical recovery, token mới không authorize denied actions.
`dispose()` đóng handles/cache listener, bỏ metadata/callbacks; idempotent. Không dispose canonical cache/provider/container.

## Ownership và ordering

Hai manual subscriptions dùng immediate notification; scope và cache có thể tới riêng, init có thể signal nhiều lần.
Owner callback phải sẵn sàng trước attach và chỉ clear local state đồng bộ; repaint schedule an toàn do owner quyết định.
Bridge giữ scope/cache metadata để compare, không đọc snapshot/rows/count, không subscriptions khác hoặc polling.
Lease chỉ Object identity, không mang user/private payload; khác instance bridge không thể share lease.
Mỗi scope-value/cache-identity/readability transition thay lease trước onNamespaceChanged callback.
Same-owner equality/rebuild không rotate; cache resource invalidation được forward từng event, không coalesce head rounds tại bridge.
Mutable cache block phát event khi có resources; kiểm readability trước resource callback; cache rỗng/block/dispose không bảo đảm event.
Vì thế owner bắt buộc synchronize live scope/cache trước render/callback; cache namespace lệch hoặc unresolved fail closed.
Callback cache cũ/late copied-list callback phải bỏ qua khi disposed hoặc cache đã đổi.
Owner phải clear feed/receipts/context khi nhận namespace signal; bridge không chứa hoặc xóa hộ private UI.
Reentrant dispose trong immediate callback phải đóng cả subscription vừa tạo, không attach phần còn lại.

## Test plan/oracles

Controlled ConsumerStatefulWidget initState attach/dispose; build gọi synchronize với ref.watch live providers.
Controlled test providers dùng Notifier cho scope/cache override, không production provider behavior changes.
Harness ghi sync signal order và chỉ giữ synthetic display marker tại owner; không notification business fake.
Coverage: unresolved/stable/account swap/generation/logout/unknown role, cache replacement/block/invalidation,
repeated events, cleanup/dispose/late events, immediate notifications, old lease, rebuild subscriptions, no private lease payload.
Direct tests bảo vệ explicit-input fallback khi no resources emit, cache disposal, explicit revoke và cross-bridge lease.
Existing172cases giữ regression source; new tests không sửa original assertions.
Chỉ harness signal ordering được chứng minh, không full NotificationsPage first-frame privacy/modal lifetime.

## Verification và STOP

Bridge123/250LOC; lifecycle test236/400 (15cases), lease test83/400 (6cases), harness support112/150.
Fresh existing baseline172PASS; new21PASS; focused final193PASS; selected safe shared/Preview smoke7PASS.
Smoke tests chỉ widget harness, không Preview acceptance; no capture writes. Counts reruns không cộng vào193.
Analyzer final No issues found; format4files0changed. Initial analyzer2constructor infos giữ analyze.log, fixed không suppress lint.
Review độc lập read-only APPROVE boundaries; khoảng trống immediate cache disposal đã bổ sung test thứ15.
Không claims canonical backend/server RLS, full Page first frame hay modal lifetime từ harness signals.

[Verification](artifacts/implementation_checkpoint_02/verification.json) lưu actual counts/LOC/commands/hash/link/diff results.
Working source tests/analyzer dùng installed Dart+flutter_tools.snapshot cùng SDK, quyền SDK cache ngoài workspace khi cần.
Không full suite/fixed-output capture/backend/Android/Preview acceptance claim.
STOP sau isolated bridge/tests; Page922 chưa đổi, ReadCoordinator/Actions/modal chưa implement.
F02 phải có fix task riêng trước live pagination; F03/F05/F07/Auth/router/backend ngoài scope.
Next checkpoint đề xuất isolated read-round owner,≤280 exception, chỉ sau scope user riêng; chưa live pagination binding.
