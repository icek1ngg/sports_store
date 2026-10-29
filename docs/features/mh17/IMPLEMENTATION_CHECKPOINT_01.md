# MH17 — Implementation checkpoint 01

## User decision 22/10/2026

MH17-03A3-R được chấp nhận làm architecture baseline, subject to runtime/test validation.
Hủy đề xuất R2 design-only. Không cần tối ưu7 estimated LOC bằng một review kiến trúc nữa.
Ngoại lệ duy nhất: `notification_page_read_coordinator.dart` ≤280 physical LOC.
Page≤300, normal controllers≤250; mọi giới hạn khác giữ nguyên, không bỏ guards/compress/tiny helpers.
Historical R/P evidence giữ nguyên để ghi đúng kết luận theo policy lúc audit.

## Scope được chọn trước code edits

Checkpoint nhỏ nhất: isolated stateless `NotificationSnapshotProjection` query/cache/action predicates.
Đây là nền tảng của projection owner trong R, chưa triển khai entire render projection hoặc coordinator/page bindings.
Không có subscription/modal/async mới nên không đưa lifecycle owner nửa vời vào production page.

New production file:
`lib/features/notifications/presentation/view_models/mh17/notification_snapshot_projection.dart` ≤150LOC helper.
New test:
`test/features/notifications/presentation/view_models/mh17/notification_snapshot_projection_test.dart` ≤400LOC.
Existing changes chỉ MH17 ENGINEERING_RULES, revised design decision addendum, ARCHITECTURE_PLAN, TEST_PLAN, HANDOFF.
New evidence chỉ `artifacts/implementation_checkpoint_01/`.
Tất cả existing Dart/tests/components/Page/Preview/providers/models/contracts và MH07/08/09 protected nguyên bytes.

## Public API và preconditions

Stateless static methods: queryKey, resourceKey, isFirstPageResource, matchesPage, matchesCount,
canRender, receiptMatches, canInteract và isAccessFailure.
Không lưu snapshots/items/count/session/Ref/BuildContext; không async/cache writes/listener/repository/nav.
canRender nhận live scope/cache; receiptMatches so sánh explicit accepted scope/cache/query receipt.
matchesPage so sánh aggregate identity, matchesCount so sánh canonical integer; stale vẫn có thể match để hiển thị.
canInteract kiểm active/access latch/live namespace/receipt/query/cache head+current freshness và snapshot freshness.
Đây là preflight local, không thay authorization/ack của interaction VM, foundation hoặc backend.
Không thêm stricter snapshot identity rule vào canInteract ngoài current Page predicate; match API phục vụ acceptance riêng.
Caller phải truyền live inputs lại mỗi lần; không cache boolean để authorize callback sau await.
isFirstPageResource giữ nguyên detection any-filter head; không normalize/validate raw cursor F02.

## Source/test oracles trước implementation

Page source:147–165 provenance;612–636 action predicate;787–823 query/resource/cache match helpers.
Original19 +14 characterization giữ page behavior;26 coordinator giữ accepted-row policy;39 component giữ UI.
Session7, foundation17, interaction16 là regressions cho namespace/privacy/canonical ack.
New tests: exact resource identities/filter/limit/cursor; page identity/count value matching;
scope/account/generation/cache replacement, unresolved/logout/unsupported role, same-object cache block/dispose;
current/head invalidation, snapshot loading/stale/failure, access latch/mounted; independently server count.
Predicate tests là synchronous boundary evidence, không chứng minh first-frame production integration/modal disposal.
N01/N04/N05/N07 integration tests vẫn bắt buộc ở checkpoint bindings sau.

Independent read-only review chấp nhận parity/code boundaries; reviewer không tự chạy tests.
Helper96LOC, test382LOC/26cases. Existing146cases rerun riêng theo baseline list; final focused172PASS (không cộng reruns).
Lần đầu new test compile fail do const owner.userId fixture, sửa sang const string ID, không weaken assertion; failed log giữ riêng.
Batch wrapper attempt không hoàn thành trong sandbox; formatter direct ban đầu có telemetry warning ngoài workspace.
Verified runs dùng Dart executable +flutter_tools.snapshot từ cùng installed SDK với quyền SDK lock/cache ngoài workspace.
Không source-copy/mirror; mọi verified tests/analyzer chạy working source, no pub/dependency change.

## Verification/results

Xem [verification](artifacts/implementation_checkpoint_01/verification.json) cho counts, LOC, hashes và commands thực thi.
Fresh baseline chụp trước production/docs edits, không dùng HEAD. Baseline tests riêng với final tests.
Format chỉ new Dart; focused MH17 +analyzer, diff/links/LOC/hash checks. Không fixed-output capture/full suite.
Stop sau isolated helper/tests/docs verified; Page922 chưa giảm và chưa đạt final300 target.
F02 fix riêng trước live pagination; F03/F05/F07/backend/Auth/router/Preview không thuộc scope.
