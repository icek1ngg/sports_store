# MH17-03A1 — Test extraction và behavior characterization

Task chỉ tests/architecture; không sửa production page/provider/model/components02/Preview/shared hoặc evidence cũ.
User đã duyệt01/02; MH17 UI chưa approved. Fresh branch `feature/orders-notifications-phase2`,3208 working-file baseline, không HEAD.
[Baseline](artifacts/refactor_03a1/workspace_baseline.json), [LOC before](artifacts/refactor_03a1/loc_before.json).

## Original inventory trước khi split

Original721 physical LOC; không group() hoặc global setUp/tearDown;18 testWidgets declarations,19 actual cases.
Một `for (final denyCount in [true,false])` nhân đôi declaration1. Có94 expect expressions,103 khi nhân theo actual cases.
IDs bên dưới là index0-based trong [inventory](artifacts/refactor_03a1/original_tests_inventory.json), không phải business test IDs.
Inventory giữ description/body/assertion order/dependencies/fixture/setup; [snapshot](artifacts/refactor_03a1/original_page_test.dart.txt) nguyên bytes.

| ID | Original description | Expect / actual cases | New owner |
| --- | --- | --- | --- |
|0| captured tile callbacks recheck invalidated cache before a rebuild |4/1|root|
|1| count/list denial hides the entire inbox until both fresh reads recover |9/2|root loop|
|2| loads all/unread filters and shows server count |7/1|root|
|3| does not invent a badge while unread count is unknown |2/1|root|
|4| cursor pagination appends locally and filter resets cursor |10/1|pagination|
|5| next page failure keeps rows and retry loads the same cursor |5/1|pagination|
|6| polling pagination refreshes the canonical head page |7/1|pagination|
|7| poll accepts new head rows, exact count and a new cursor chain |11/1|pagination|
|8| filter change drops a late cursor response |6/1|pagination|
|9| expired cursor refetches the head instead of retrying it |4/1|pagination|
|10| dispose during a poll ignores late results and stops future polling |5/1|root|
|11| stale refresh keeps rows readable and disables read mutation |4/1|root|
|12| mark read keeps unread row and badge until canonical refresh |5/1|read/navigation|
|13| unread filter removes an acknowledged row only after canonical reload |8/1|read/navigation|
|14| long notification text lays out at320dp |2/1|root|
|15| authorized navigation remains independent from read failure |2/1|read/navigation|
|16| missing navigation callback stays explicitly unavailable |2/1|read/navigation|
|17| unknown role and unresolved session fail closed |1/1|root|

Root = `test/features/notifications/presentation/pages/notifications_page_test.dart`, now222LOC/9cases.
New files under `test/features/notifications/presentation/pages/mh17/`:

| File | Physical LOC | Cases / responsibility |
| --- | ---: | --- |
|mh17_pagination_test.dart|221|6 original cursor/poll/refetch cases|
|mh17_read_navigation_test.dart|124|4 original ack/navigation cases|
|mh17_page_test_support.dart|137|host/settle/page/scope/rows and test-library imports/exports|
|mh17_page_test_fakes.dart|52|same controllable repository/resolver, no new business contract|
|mh17_feed_characterization_test.dart|74|2 new duplicate projection/explicit head race cases|
|mh17_gesture_characterization_test.dart|146|3 new gesture/pending/stale/disposal cases|
|mh17_privacy_characterization_test.dart|116|4 new role-inbox/late-count cases|
|mh17_navigation_characterization_test.dart|130|5 new unavailable/lifecycle cases|
|mh17_characterization_support.dart|43|scoped host + synthetic own notification_only rows|

## Preservation proof và timing

Only private fixture identifiers `_row1/_row2/_row1Read/_newRow/_longRow` become public test-support identifiers.
Original fixture values, fakes, host overrides/defaults, query/retry semantics, pump order and expectations giữ nguyên.
`settle`: pump +1ms; polling cases advance3s, disposal advances4/7s; bounded pump loops và surface reset teardown không đổi.
No dependence on execution order. Original unresolved count/list Futures và explicit completions giữ đúng sequence.
Original fixtures inherited shared event IDs được giữ nguyên; không sửa F07 hoặc giả lập producer acceptance.
New scoped rows use unique canonical notification/event IDs, UTC, notification_only.subjectId=eventId; same repository interface.
[Verifier](artifacts/refactor_03a1/split_page_tests.cjs) compares normalized source preserving quoted-literal bytes,
test bodies/assertion order, executable loop enclosure/depth, cardinality/totals, pageScope/helpers/fake declarations và zero skip.
Redistributed imports/exports (dart:async show Completer) không thuộc helper/fake comparison; analyze và independent runs kiểm imports.
[Preservation report](artifacts/refactor_03a1/test_preservation_report.json):18/19/94/103 preserved.
Verifier không dùng HEAD hoặc chỉ count pass; không xóa whitespace trong literal để che thay đổi expected text.
[Mutation controls](artifacts/refactor_03a1/preservation_mutation_checks.json):5 in-memory changes (literal/missing test/loop/comment/skip) đều bị từ chối.

## New characterization và findings

| Boundary | Actual observations |
| --- | --- |
|duplicate tail ID|latest projection replaces sameID, order/unique keys giữ, count55 không derive từ2tiles|
|explicit refresh while tail pending|newhead query.cursor null; oldtail ignored; newhead56 và fresh cursor chain accepted|
|available read control|one markRead request, no resolve/navigation; unread/count41 giữ khi ack chưa tới|
|pending disabled control|inner disabled button hit goes to outer tile: one resolve/authorized onNavigate, read still dedup1|
|rapid body taps|two more deliberate body taps yield total3 resolve/nav callbacks with current scope valid; read remains1|
|stale/disabled|read affordance absent, tile.onTap/onMarkRead null, body tap causes no mark/resolve/navigation|
|captured callbacks after disposal|both old read/open callbacks no-op, no ref/container exception|
|own inbox roles|Customer/Manager/Shipper client accepts own row; foreign projection never rendered; not backend RLS proof|
|late A count after B|first frame hides A/41; B row/count3 accepted; old count99 cannot replace B badge|
|unknown/null resolver/unavailable target|no navigation, no read mutation for already-read row, plain body remains at MH17|
|pending resolve|after disposal OR same-user new generation while mounted, old resolver cannot invoke onNavigate|

No forbidden navigation reproduced. Pending acknowledgement does not forbid an otherwise authorized open under rev1.2.
F05 now has a reproducible client callback sequence; three callbacks do not prove three actual production routes.
No speculative serialization guard added. Integration must preserve or separately authorize changing this behavior.
Protected session tests reused for unresolved/logout/expiry, A→B late list, context privacy/denial; no duplicate modal tests.
Context currently replaces private modal content with safe gate on access loss, not necessarily pops the modal route.
Read success remains canonical ID/recipient/scope/readAt/cache acknowledgement in existing interaction/ack providers.

## Page method → owner inventory (production922 LOC unchanged)

| Area | Actual methods/fields | Proposed owner / authority |
| --- | --- | --- |
|A public API|NotificationsPage(onNavigate,enablePolling)|stay page; Future<bool> typed callback unchanged|
|B role/access|build FeatureAccessGate, _accessFailure, _isAccessFailure/_denyAccess|page/access gate; invalidates transient interaction, no new authorization policy|
|C canonical list|build watch/listen pageFoundation; _pageSnapshotCache/Scope/QueryKey|existing foundation is authority; provenance/acceptance bridge stays page initially|
|D exact count|unreadCountFoundationProvider, _countSnapshot*, _countSnapshotMatchesCache|existing foundation authority; page supplies badge, not feed.length|
|E filters|_filter,_setFilter,_currentQuery,_FilterBar|controlled Filters widget; selected/query state future feed coordinator|
|F accepted rows|_visibleItems,_acceptPage,_deduplicate,_mergeItems,_items|pure page-specific presentation accumulator MAY extract after page guards|
|G cursor|_cursor/_nextCursor/_cursorHistory,_loadMore,_retryLoadMore,_resetPagination|pure coordinator for local cursor/history; repository retry remains foundation/page orchestration|
|H refresh/poll|_canPoll,_poll,_refreshFirstPage,ForegroundRefresh|keep page lifecycle/read orchestration initially; foundation executes canonical refresh|
|I async UI|build AsyncContent/RefreshIndicator/ListView,_LoadMoreButton|Mh17NotificationFeed renders flags/items; AsyncContent owns state rendering|
|J read|_canInteractNow,_markRead,_resetAfterRead|page current/mounted guard + VM markRead/ack authority; no widget mutation|
|K navigation|_open,onNavigate wrapper,_showMessage|page lifetime/snackbar/route callback; interaction VM typed validation; resolver external current-target authority|
|L context|_showNotificationContext Consumer/gates, showModalBottomSheet|page owns route/session lifetime; ContextSheet only authorized strings/Close|
|M scope change|initState subscriptions, build _renderScope clear, _observeCache,_denyAccess|stay page/epoch owner; clear rows/count before new-session render|
|N late response|query/currentScope/cache identity checks in listeners/_acceptPage/_refreshFirstPage|existing foundation epochs plus page current provenance; coordinator must not bypass|
|O disposal|dispose, mounted checks, _onCacheInvalidated post-frame, callback wrappers|stay lifecycle owner; close subscriptions/listeners; no retained WidgetRef|

Identity helpers `_baseKey/_queryKey/_resourceKey/_isFirstPageResource/_snapshotMatchesCache` must retain current query/cache semantics.
Do not move session/cache/canonical-count authority into presentation accumulator for LOC convenience.

## Bounded03A2 proposal — review required, not started

Safest next step: isolated pure feed coordinator + tests before touching922LOC page. This avoids a partial page rewrite still over300.
New `lib/features/notifications/presentation/view_models/mh17/notification_feed_coordinator.dart`≤250, target160–220 estimated.
New `test/features/notifications/presentation/view_models/mh17/notification_feed_coordinator_test.dart`≤400, target200–300 estimated.
No source page integration in this narrow03A2: page, providers, VM, models, approved widgets/tests/Preview stay read-only.
Coordinator may hold accepted presentation rows/filter/cursor/history/loadingMore, reset/merge/dedup with identity-preserving order.
Inputs are already authorized/fresh accepted snapshots/query; caller owns preflight. Outputs readonly items/query/next-cursor intent.
No Ref/WidgetRef, async repository, timers, unread count, target policy, session cache or canonical readAt authority.
Preserve looped-cursor behavior; do not normalize/fix F02. Need an explicit accept/reset transition table before implementation.
Verify tests for observed append/replacement/head reset/late-query reject/repeated cursor/filter reset and no retained rows after reset.
Verify format/analyze/all focused tests plus original preservation/individual split tests/working hashes/LOC; no legacy captures.
STOP after isolated coordinator review; no integration or03B/03C automatically. Estimates are design budgets, not measured final source.
Later page-composition task needs approved method→file budget proving page≤300/widget≤180/controller≤250 at its endpoint.
Order then: validated accumulator → controlled Filters/Feed composition → context display extraction with parent-owned gates → reverify lifecycle.
If integration cannot retain provenance/mounted/session guards within budgets, STOP for revised plan; no dummy layers or Dart part files.

## Verification scope / unresolved

Fresh original baseline106 PASS; new14 cases => final focused count recorded in [final log](artifacts/refactor_03a1/focused_verified.log).
[Final individual runs](artifacts/refactor_03a1/individual_results_final.json) cover all7 affected test files, including mounted-generation branch.
All execution uses working source, not isolated mirror; full suite NOT RUN because legacy captures have fixed protected outputs.
Android/backend/Auth/router/RLS/real typed destination navigation and NFR freshness not verified by this task.
F02 cursor validation, F03 full typed role matrix, F05 route-level policy, F07 Preview canonicality remain open; no production fixes.
Existing debt: page922/300,interactionVM455/250,tile185/180,interaction test562/400,foundation418/400; touched tests/helpers meet own gates.
Final [verification](artifacts/refactor_03a1/verification.json) records exact hashes/LOC/links/diff and command results; see [HANDOFF](HANDOFF.md).
