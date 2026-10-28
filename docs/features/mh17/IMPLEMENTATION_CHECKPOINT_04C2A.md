# MH17 checkpoint04C2A — Filters và Feed page composition

**MH17 CHECKPOINT04C2A — FILTERS & FEED INTEGRATED, READY FOR REVIEW**
MH17 UI NOT USER APPROVED. Presentation composition only; no new coordinator/authority integration.
[Verification](artifacts/implementation_checkpoint_04c2a/verification.json), [scope proof](artifacts/implementation_checkpoint_04c2a/page_scope.json).

## Source scope và LOC

Fresh working baseline22/10/2026: feature/orders-notifications-phase2,174status entries,3511working files; no HEAD baseline.
Only existing production file changed: lib/features/notifications/presentation/pages/notifications_page.dart.
Original952→852 physical LOC, net−100; temporary Page>300 remains tracked debt, không claim whole-feature LOC compliance.
Arithmetic:952−87old inline region−76private widgets/separator+58new binding region+4hoisted predicate+1net import=852.
Private _FilterBar/_LoadMoreButton removed; approved Filters60/Feed121 remain unchanged, no duplicate dead paths.
[Working diff](artifacts/implementation_checkpoint_04c2a/page_working_diff.patch) compares fresh working copy, not Git HEAD.
Scope checker reconstructs all changes; all Page fields/listeners/state/filter/pagination/read/open/live guards/N07 remain identical.
Pure existing canLoadMore expression moved outside itemBuilder; no changed cursor/query pipeline.

## Controlled binding decisions

| Input | Current authoritative source / behavior |
| --- | --- |
| Filters.selectedFilter/onFilterChanged | _filter/_setFilter; no second selection state |
| Filters.onRefresh/isRefreshing | _refreshFirstPage via unawaited; default false deliberately preserves old always-available manual refresh |
| Feed.items/hasData/filter | visibleItems/hasVisibleData/_filter; no filtering/sorting/dedup/count derivation |
| isInitialLoading/isRefreshing/isStale | Exact original snapshot ownership/loading/stale +count freshness expressions |
| errorMessage | Original pageFailure→failureMessage; safe banner/error rendering |
| onRetry/onRefresh | _refreshFirstPage; canonical foundation remains owner |
| hasMore/isLoadingMore | visibleNextCursor!=null/_loadingMore; not list length |
| loadMoreErrorMessage | Default null: old tail error uses existing banner and retains footer label Tải thêm |
| onLoadMore | Exact old canLoadMore gate; failure→_retryLoadMore(query), otherwise _loadMore(visibleItems,queryKey) |
| onOpen/onMarkRead | actionsEnabled?existing guarded _open/_markRead:null; Feed reuses protected NotificationTile |
| pendingReadIds | actionsEnabled?interaction.pendingReadIds:empty; canonical VM owns dedup/ack |

Feed has no failure parameter. Page retains existing unauthenticated→SessionExpired and forbidden→SessionUnavailable branch.
Both states actionLabel:null match old AsyncContent; denied Feed is not built, no private rows/callbacks exposed.
All/Unread empty distinction reused; Feed owns the shared AsyncContent for non-access states, one bounded ListView.
Original explicit refresh stays enabled during busy head loads; foundation still invalidates/queues latest round.
Own ack/unread-row removal does not revoke authorized modal; no changed read/open gesture policy or target authorization.
N07 route builder/handle revocation/Page dispose/DI guard regions remain byte-identical to approved04C1.

## Tests và traceability

New test/features/notifications/presentation/pages/mh17/mh17_presentation_composition_test.dart299/400LOC,8cases; no new helper.
Actual component types/input assertions, server All/Unread count41 despite visible list0/1, pending filter/tail reset+late response.
Tail failure preserves rows/banner/Tải thêm, same-cursor retry, stable append; empty tail follows raw next cursor then null exhaustion.
Busy explicit second refresh accepted; obsolete first response dropped, latest head/count win; no optimistic count/row mutation.
Loading/error/retry/All-empty +denied parent state; mark-read-only vs authorized open, VM pending/read dedup, disposed callback.
320dp/text2 long server title/body verifies Wrap filters/bounded scrolling without overflow.
Existing original Page/session cases cover account A→B first-frame privacy, late count/list, expiry, denial recovery and stale actions.
Existing gesture characterization retains pending read forwarding/rapid authorized opens; no F05 mutex.
Existing04C1 integration23cases unchanged cover Feed→notification_only modal opening/revoke, host disposal and route lifetime.
Existing component39cases still prove standalone presentation semantics; no redundant new privacy/modal suite.
Attempt01:6PASS/1FAIL from new oracle expecting isStale:true for failed tail with no cached snapshot; source mapping was correct.
Final asserts isStale:false AND visible freshness banner via error, row retention and retry; original assertions untouched/log preserved.

## Fresh verification22/10/2026 và STOP

Before edits focused343PASS; new composition8PASS; all Page/session71PASS; all focused351PASS (343+8).
Selected safe regressions7PASS; analyzer PASS No issues found; format2files0changed; diff/LOC/docs links/protected hashes PASS.
376protected working inputs unchanged excluding authorized Page; all prior tests/components/owners/MH07/08/09/Preview/evidence preserved.
Only existing Page and HANDOFF changed; fresh working SHA and source-before copy retained in task evidence.
Independent Sol medium read-only review approve/no blocker; reviewer inspected diff/test/log, did not execute tests.
No full suite/backend/Android/native/Preview acceptance; selected Preview widget tests do not imply UI approval.
ReadCoordinator342/350 sole exception unchanged; Page852/300,InteractionVM455/250,Tile185/180 existing debt remains.
F02 unresolved and required separately before 04C2B pipeline change; F03/F05/F07/Auth/router/backend/Preview unchanged.
No Feed/Read/SessionBridge/Actions/SnapshotProjection integration, no new live pagination behavior.
Next: user review composition, then separately authorized F02 remediation/bounded orchestration preparation; do not start04C2B.
STOP. No commit/push/destructive Git operations or MH17 UI approval.
