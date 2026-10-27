# MH17-F02 — Malformed nextCursor remediation

**MH17-F02 — MALFORMED CURSOR GUARD IMPLEMENTED, READY FOR REVIEW**
User authorized riêng foundation response guard; [proposal](F02_DECISION_PROPOSAL.md) là evidence lịch sử, không bị rewrite.
[Verification](artifacts/remediation_f02/verification.json), [scope proof](artifacts/remediation_f02/source_scope.json).

## Exact production change

Only lib/features/notifications/presentation/view_models/notification_providers.dart changed,98→103physical LOC(+5).
Sau repository.getPage(query), trước return/item validation/cache acceptance:
nextCursor!=null&&(nextCursor.isEmpty||nextCursor.length>2048) → throw const AppFailure(code:AppFailure.unsupportedData).
Null hoặc nonempty≤2048 đi qua nguyên NotificationPage object; no trim/decode/normalize/replacement cursor.
Dùng Dart String.length/UTF-16 code units giống NotificationQuery, không đổi sang rune/grapheme count.
Unsupported server payload giữ existing safe failure classification, retryable:false; không tạo error code mới.
SnapshotReadViewModel nhận failure trước cache.accept, không publish malformed successful data.
Initial bad head không có accepted data; refresh bad head/tail giữ last accepted same-owner snapshot stale theo foundation hiện có.
UI tail giữ các rows đã accepted; explicit retry dùng current request cursor, không tự biến malformed nextCursor thành head request.
Existing invalid_cursor request recovery vẫn defer/refetch head theo protocol cũ; malformed response không phát invalid_cursor.
Không đổi NotificationPage constructor/NotificationQuery/raw coordinator semantics hoặc Page852LOC; no new integration authority.

## Tests và fresh results22/10/2026

Baseline working source351PASS trước edits. One empty-head regression chạy BEFORE guard:1FAIL đúng oracle(isFresh true).
Failure log [before](artifacts/remediation_f02/reproduction_before.log) giữ nguyên; không weaken/skip/remove assertion.
New test/features/notifications/presentation/view_models/notification_cursor_validation_test.dart176/400LOC,10cases:
- null/length1/length2048 giữ same response object; whitespace opaque và UTF-16 boundary2048 không normalize.
- empty/length2049/UTF-16 length2049 rejected unsupportedData trước canonical cache, no accepted success/no automatic retry.
- Bad refreshed tail giữ accepted snapshot object/cursor stale; explicit retry giữ request cursor rồi recover bằng valid response.
- Late malformed A response không publish rows/failure vào accepted B namespace; B count vẫn3.
New test/features/notifications/presentation/pages/mh17/mh17_cursor_response_test.dart78/400LOC,3cases:
- Initial malformed head safe ErrorState, no tile/footer/success; count41 độc lập; only explicit head retry recovers.
- Empty/2049 tail giữ head row, không append row từ bad page, disables actions và shows existing freshness banner.
- Explicit Tải thêm retry đúng current valid-request-cursor, không head fallback; valid subsequent page append giữ order/count.
13newPASS; existing foundation/pagination/FeedCoordinator/deferred invalid_cursor regressions64PASS; full focused364PASS(351+13).
Existing raw empty/oversized coordinator cases PASS unchanged: F02 boundary fixes live response acceptance, không sửa raw model semantics.
Selected safe regressions7PASS; analyzer PASS No issues found; format3files0changed; diff/LOC/links/protected SHA PASS.
Working-source tests via installed SDK; no pub/dependency changes/source validation mirror/full-suite/capture overwrite.
Independent Sol medium read-only review no blocker; reviewer inspected diff/tests/logs, did not execute tests.

## Safety và remaining risks

Fresh3530working-file baseline/174status entries, feature/orders-notifications-phase2; no HEAD approval assumption.
377protected inputs unchanged excluding explicitly authorized provider file; all original tests/owners/Page/MH07/08/09/Preview retained.
Only existing provider file +HANDOFF changed; new2tests/doc/evidence within task scope. All prior artifacts preserved.
Validation applies new repository responses; không retroactively rewrite existing in-memory cache or certify token ownership/producer correctness.
Malformed producers now fail closed earlier; valid server behavior unchanged. No backend integration/RLS/Android/native verification claim.
F02 loader remediation ready for review; F03/F05/F07 remain separate. Historical audit proposals/status remain as dated evidence.
Page852>300, InteractionVM455/Tile185/test LOC debt unchanged; ReadCoordinator342/350 sole exception unchanged.
No coordinator/Page refactor/integration or04C2B started. MH17 UI NOT USER APPROVED.
Next: user review F02, then separately authorized bounded orchestration stage. STOP; no commit/push/destructive Git operations.
