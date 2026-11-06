# MH17-03A2 — Isolated accepted-feed coordinator

Design ghi trước Dart implementation, ngày21/10/2026. Không integrate page922LOC hoặc thay canonical authorities.
Baseline working files3230, không HEAD; paths coordinator/test chưa tồn tại.
[Fresh baseline](artifacts/coordinator_03a2/workspace_baseline.json), [relevant LOC](artifacts/coordinator_03a2/loc_before.json).

## Goals và exact API

Một synchronous stateful coordinator cho accepted presentation accumulation, deterministic theo sequence input.
Không gọi “pure function”: object có local mutations, nhưng không external side effects hoặc hidden work.
Production: `lib/features/notifications/presentation/view_models/mh17/notification_feed_coordinator.dart`≤250LOC.
Unit tests: `test/features/notifications/presentation/view_models/mh17/notification_feed_coordinator_test.dart`≤400LOC.

```dart
NotificationFeedCoordinator({required int revision,
  NotificationFilter filter = NotificationFilter.all});
bool reset({required int revision, NotificationFilter? filter});
bool refreshHead({required int revision});
bool acceptHead({required int revision, required NotificationPage page});
String? beginLoadMore({required int revision, required int requestId});
bool acceptTail({required int revision, required int requestId, required NotificationPage page});
bool recordLoadMoreFailure({required int revision, required int requestId});
String? retryLoadMore({required int revision, required int requestId});
// Read-only getters:
int get revision;
NotificationFilter get filter;
List<NotificationItem> get items;
String? get nextCursor;
String? get activeCursor;
bool get hasAcceptedHead;
bool get hasMore;
bool get isLoadingMore;
bool get needsLoadMoreRetry;
```

Parent issues strictly increasing integer revision for query/filter/owner namespace or head refresh.
Within each revision, parent issues strictly increasing requestId for tail attempts/retries; sequence restarts after new revision.
These are local ordering tickets, not credentials or backend versions. No new domain-level ticket type/provider.
`reset`/`refreshHead` reject non-increasing revision with false and no mutation; accept methods require exact current revision.
Initial and newly reset state accepts one head per revision; duplicate head requires a new parent-declared revision to be accepted.
Tail completion/failure requires matching current requestId AND loading state; stale/duplicate completion returns false unchanged.
begin/retry return raw cursor when a local intent starts, null if rejected; no query or network request is constructed.
Failed attempt retains activeCursor; retry requires a larger requestId, so prior attempt completion cannot satisfy retry.
reset ALWAYS clears private rows/history/tickets; refreshHead explicitly retains current-owner rows but invalidates old tail/history.
Caller must choose reset on owner loss/switch. refreshHead is only for already validated same-owner head refresh.

## State ownership / invariants

- Imports only existing NotificationItem/Page/Query (filter enum); no Flutter/Riverpod/ref/cache/SessionScope or repositories.
- Parent validates current user, freshness, query identity, cache provenance, mounted lifecycle BEFORE accepted calls.
- revision binds caller's query (including filter/limit/namespace) but does not derive role/ownership or replace any guard.
- Items are immutable snapshots, preserve original NotificationItem identity; canonical projections are never rewritten.
- Head dedup: last projection for repeated ID wins, first appearance determines order, matching `_deduplicate`.
- Tail merge: replace existing ID in place; append new IDs in accepted order; last duplicate projection wins, matching `_mergeItems`.
- History stores issued cursors, never publicly exposed; pending/loading/retry flags are local intent metadata only.
- hasMore is `nextCursor != null`, not items.length. No count field, no use of NotificationPage.unreadCount/asOf as authority.
- No readAt mutation, acknowledgement, filter-on-partial-list, sort, target resolution, navigation, polling or async callbacks.
- No failure payload duplicated here; parent holds canonical failure/error text and calls recordLoadMoreFailure only for its accepted failure.

## Transition table — pre-implementation contract

All accepted inputs below require parent-owned current-session/cache/query/freshness/lifecycle checks.

| ID / current state | Input | Next state / rows / cursor-history | Accepted or rejected |
| --- | --- | --- | --- |
|T01 construction|revision/filter|empty rows, no head/next/active/history/loading/retry; no count|local initialization only|
|T02 no head for current revision|acceptHead(page)|replace rows with stable dedup; head=true; next raw; history empty|exact revision only, once|
|T03 accepted head, next present|beginLoadMore(new requestId), then acceptTail|intent captures next as active/adds history; completion merges rows, clears loading/retry|current revision/new attempt, matching pending completion|
|T04 pending tail with duplicate IDs|acceptTail(page)|one row per ID, latest projection replaces in place, stable order|same guard asT03; no count change|
|T05 filter or namespace reset|reset(new revision,filter)|clear rows/head/cursors/history/request/loading/retry; use supplied filter, else retain filter|strictly newer revision|
|T06 same-owner head refresh|refreshHead(new revision), acceptHead|old rows retained until new head replaces; no next/active/history/pending in between|strictly newer; old tail revision rejected|
|T07 pending tail failure|recordLoadMoreFailure|rows/next/history/active retained; loading=false,retry=true; no automatic request|matching current pending ticket|
|T08 failed tail|retryLoadMore(new requestId)|same active cursor, loading=true,retry=false, rows unchanged|larger requestId only, no network|
|T09 accepted tail candidate|next==active OR issued history contains next|next=null terminal; merged rows retained|completion accepted; further begin blocked|
|T10 accepted page|nextCursor=null|hasMore=false regardless page length|further begin returns null|
|T11 any state|old revision/attempt response|state exactly unchanged|false|
|T12 owner invalidation|reset(new revision)|no previous-owner items/cursors/history; all old tickets rejected|strictly newer, clear always|
|T13 stale current-owner data|no accept call; optional same-owner refreshHead|retain presentation only; no permission/action flags created|freshness still caller responsibility|
|T14 read ack|no coordinator operation|no optimistic read/count changes; later accepted canonical head may replace rows|ack handled by existing VM/foundation|

begin rejected while loading, before accepted head, exhausted, retry-needed or cursor==active; no state mutation.
retry rejected without failed tail, during loading or with repeated requestId; no implicit retry/error recovery.
Tail next candidate is blocked only for null/self/history, exactly the observed cursor loop rule.
No pagination length heuristic. Two consecutive head refreshes each invalidate older revision and preserve only explicitly retained same-owner rows.

## Correspondence to working page /03A1

| Source / observation | Coordinator boundary |
| --- | --- |
|_acceptPage head +_deduplicate|acceptHead after parent guard, replace accepted head|
|_mergeItems /03A1 duplicate projection|acceptTail stable ID replacement without count changes|
|_loadMore +_cursorHistory|beginLoadMore records raw issued cursor; no repository read|
|_retryLoadMore|failure/retry intent uses same active cursor; foundation refresh remains external|
|_setFilter/_resetPagination(clearItems:true)|reset clears rows/history, no local filter|
|_refreshFirstPage/_poll from tail|refreshHead retains same-owner rows; new accepted head discards old tail|
|late filter/head/tail response|caller ticket mismatch rejects locally in addition to mandatory foundation/page guards|
|_visibleItems cached/provisional fallback|stays parent-owned; coordinator only stores already accepted presentation rows|

Per-head revisions and per-attempt IDs expose existing response ordering explicitly; they do not change backend query/cursor contracts.
Future binding must issue revisions for actual read rounds, not every build; still preserve foundation request serialization/epoch acceptance.

## F02 boundary — unchanged, integration assumption explicitly limited

Working NotificationPage accepts empty/oversized nextCursor. Page stores candidate raw and treats non-null as a next page.
On load it stores raw cursor; NotificationQuery later converts empty string to null, or throws above2048chars.
Coordinator also stores/returns raw cursor unchanged, including empty/oversized strings; does not construct NotificationQuery.
Thus hasMore does NOT validate backend cursor usability. A returned raw intent is not a successful read or recovery.
Future integration of malformed cursor is NOT accepted by this design; STOP that affected path for separately authorized F02 work.
No trim/decode/replacement cursor/normalization/serialization change or domain validation added. F02 is not resolved.

## Tests / verification plan

Required unit coverage: empty/head/tail/duplicate ordering/immutable outputs, count independence, reset/filter/refresh,
old revision and attempt rejection, failure/retry, self/history loops/null exhaustion, readAt unchanged, repeated refresh determinism.
Test intentionally malformed F02 cursors separately as current domain-permitted boundary evidence, not valid producer fixtures.
Synthetic rows use validated UUIDs/UTC, distinct event per notification, notification_only subjectId=eventId.
Cross-check with protected03A1 pagination/feed characterization; no editing old tests to fit coordinator.
Fresh full MH17 baseline120 +relevant page pagination8 before code; final actual count/logs appended only after execution.
Format/analyze/new unit tests/full focused/original page pagination and characterization/selected regressions/LOC/links/diff/SHA.
No full suite fixed-output captures, Android/Preview/backend claims. New evidence only in artifacts/coordinator_03a2/.

## Non-goals / future composition review

F03 role target matrix, F05 navigation multiplicity/serialization, F07 Preview canonicality remain untouched; no nav state exists here.
Production page922/VM455/tile185 and interaction/foundation test debt unchanged; isolated coordinator does not make page LOC compliant.
Future page plan must allocate: display to existing Filters/Feed/Context; accepted accumulation to this coordinator;
current scope/cache/provenance/async listeners/mark-open wrappers/modal route lifecycle stay with explicitly reviewed owner.
Before editing page, provide method→file estimates proving page≤300 and each new controller≤250/widget≤180/helper≤150.
If valid guarded composition budget is not demonstrated, STOP for revised extraction review instead of arbitrary splitting.
This task does not introduce a parallel page or bind the coordinator merely to show usage. STOP after03A2 reviewable verification.

## Fresh completion evidence

- Coordinator152physical LOC, unit test379LOC,26cases; no second production/helper/test layer needed.
- Pre-edit MH17 baseline120 PASS; original pagination +feed characterization8 PASS.
- Final working-source focused146 PASS =120existing +26new; selected access/foreground/Preview regressions7 PASS.
- Individually rerun root page9, pagination6, feed2, gestures3, privacy4, navigation5, read-navigation4, new coordinator26.
- Analyzer final No issues found; first attempt had2prefer_initializing_formals infos, fixed with SDK3.13 private named formals.
  Public caller names remain revision/filter; no lint ignore, API/model/dependency change or assertion weakening.
- Final format2files0changes, diff/LOC/link/protected-SHA results: [verification](artifacts/coordinator_03a2/verification.json).
- SHA:346protected inputs unchanged;3226/3230baseline files byte-identical, only4authorized MH17docs changed; no unexpected additions.
- [Focused146](artifacts/coordinator_03a2/focused_final.log), [individual results](artifacts/coordinator_03a2/individual_results.json),
  [selected7](artifacts/coordinator_03a2/regressions_final.log), [analyzer](artifacts/coordinator_03a2/analyze_final.log),
  [format](artifacts/coordinator_03a2/format_verified.log). Historical03A1 logs/assertions unchanged.
- Independent read-only review: Sol medium APPROVE; no source/test behavior finding after LOC correction402→379 by whitespace.
- Full suite NOT RUN (fixed-output captures protected); no Android/Preview acceptance/backend/RLS/TalkBack execution.

## Next page-composition review — outline, not approved implementation

| Existing method/region | Future destination / guard that remains |
| --- | --- |
|_deduplicate/_mergeItems, accepted part of _acceptPage|this coordinator; parent still validates snapshot scope/query/cache identity|
|_loadMore/_retryLoadMore/_resetPagination/_setFilter accumulation|local transitions here; parent still constructs query and owns provider requests|
|_refreshFirstPage/_poll/_canPoll|same-owner refresh transition here only; freshness/foreground/subscriptions stay owner-controlled|
|build display, _FilterBar/_LoadMoreButton|compose02 Filters/Feed; AsyncContent/access gate and provider watches stay owner-controlled|
|_showNotificationContext body|02 ContextSheet; page/owner retains modal lifetime and scope/cache access predicate|
|_canInteractNow/_markRead/_open/_resetAfterRead|existing interaction VM plus guarded owner callbacks; no logic move authorized here|
|initState/dispose/_observeCache/_denyAccess/_onCacheInvalidated|explicit owner lifecycle; reset accumulator on invalidation before private render|
|_snapshotMatchesCache/_countSnapshotMatchesCache/_visibleItems/resource helpers|provenance/fallback remains owner responsibility, never coordinator authority|

Budget review target: page≤300, this coordinator152≤250, existing display widgets60/121/51≤their limits.
Those extractions alone do NOT demonstrate922→300: access/provenance/listeners/modal/actions remain coupled.
A proposed page-specific orchestration owner≤250 needs separate responsibility/API and method-by-method LOC estimate first;
no arbitrary helpers, moved guards, or second canonical cache may be introduced merely to satisfy a numeric gate.
Recommended next task is this bounded design/budget review, with original03A1 assertions frozen and session/async/action lifetime oracles.
Only after that review proves all file budgets and canonical guards should a separately authorized composition task be scheduled.
F02 malformed cursor path remains blocked for separate contract review; F03/F05/F07 remain open, not fixed by this outline.
