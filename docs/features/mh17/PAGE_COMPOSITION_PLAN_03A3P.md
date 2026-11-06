# MH17-03A3-P — Page composition và LOC feasibility

Ngày 21/10/2026. **MH17-03A3-P — PAGE COMPOSITION PLAN NOT YET FEASIBLE**.
Đây là kết luận cho phương án đang xét, không khẳng định mọi kiến trúc đều bất khả thi.
MH17-01/02/03A1/03A2 đã được duyệt; MH17 UI chưa được user chấp nhận. Không thay Dart hoặc tích hợp page.

## Working-source revision và allocation

Branch `feature/orders-notifications-phase2`; fresh baseline **3504 files**, gồm ignored MH17/MH09 evidence, không dùng HEAD.
Page `lib/features/notifications/presentation/pages/notifications_page.dart`: **922 physical LOC**.
SHA-256 chính xác: `7ca8c5c50945348e46bcb71c53b3e46f6e95e096b95245280262bcad32c667f0`.
[Baseline](artifacts/composition_03a3p/workspace_baseline.json), [measured LOC/SHA](artifacts/composition_03a3p/loc_baseline.json).
[Method inventory](artifacts/composition_03a3p/method_inventory.json): 79 vùng disjoint, account mỗi dòng đúng một lần.
Includes mọi field, method, build region, annotation, comment, blank và structural closing; A–X và subsymbols là cross-reference, không cộng LOC lần nữa.
Mỗi vùng ghi range/hash, responsibility, reads, side effect, lifecycle, target file, lý do, tests/risk và estimated after LOC.
Build được partition thành regions; không cộng lại cả method build vào tổng. Range hashes dùng LF-joined text, raw source SHA ở trên.

## Budget conservation — measured baseline, estimated endpoint

| Phân bổ original page | Physical LOC đã đo |
| --- | ---: |
| Giữ source logic tại page |486|
| Chuyển receipt/projection logic sang candidate owner |146|
| Thay bằng component/coordinator bindings |215|
| Bỏ private UI trùng approved components |75|
| Tổng, không double-count |922|

Phương án giữ 486 dòng đã đo tại page nên tự nó đã vượt 300, ngay cả nếu không có glue.
Body sau substitution 609 =486 retained +123 estimated replacement/move bindings; thêm70 guard/lifetime glue =**679**.
Conservation: **922−146−215−75+123+70=679**. Moved146 không có nghĩa page giảm ròng146: page vẫn cần binding.
70 mới gồm construction/dispose6, revision/request6, intent guards18, head invalidation16, access branch8, context-slot lifetime16.
Các số endpoint là design estimates có basis theo region/API, không phải source đã triển khai hoặc đo được.

| File / owner | Current measured | Added / removed estimate | Proposed final | Limit / margin |
| --- | ---: | --- | ---: | --- |
| notifications_page.dart |922|−436 original; +193 binding/guards|679|300 / **−379**|
| Candidate notification_page_coordinator.dart |0|+162 mapped logic +75 API/structure|237|250 /13|
| notification_feed_coordinator.dart |152|reuse, +0/−0|152|250 /98|
| notification_filters.dart |60|reuse, +0/−0|60|100 /40|
| notification_feed.dart |121|reuse, +0/−0|121|180 /59|
| notification_context_sheet.dart |51|reuse, +0/−0|51|150 /99|

Candidate owner75 overhead: imports/class/constructor17, scope sync12, feed/metadata10, projection API24, disposal12.
237 là estimate với margin thấp, không phải chứng minh class mới đã đủ API/LOC hoặc được phép tạo.
Alternative: move thêm187 dòng listener/poll/refresh/accept guards; page679−187+20=**512**, owner237+187+24=**448**.
Alternative vẫn vượt300/250; không tạo thêm các forwarding layers chỉ để chia số dòng.
[File budget](artifacts/composition_03a3p/file_loc_budget.json) chứa toàn bộ row costs, risk/dependencies, additions/removals và alternative ranges.
Interaction VM455/250, Tile185/180 và test debt cũ giữ nguyên. Không tuyên bố whole-feature LOC compliance.

## Method → owner, authority và dependencies

| Working-source range | Actual responsibility | Candidate destination / reason |
| --- | --- | --- |
|1–47,273–303,378–391,846–847|API/imports/theme/gate/AppBar/structure|Page; giữ typed onNavigate và enablePolling|
|48–67|feed fields + access/provenance/subscription fields|feed fields reuse03A2; receipt fields candidate owner; subscriptions stay Page|
|68–100|initState/dispose/cache subscription|Page State lifetime; không giữ callback vào disposed Ref|
|107–126|scope clear trước query/first frame|Page gọi synchronous owner bind/reset; không giao authorization cho feed|
|127–146,166–234|query/head keepalive/provider watches/listeners|Page + foundation; canonical reads/count/tokens không chuyển authority|
|147–165,235–272,456–467|receipt, visible fallback, count/action projection|Candidate receipt owner nhận live inputs, không copy canonical cache/count|
|468–501|current-scope accept guard + head/tail accumulation|preflight stay Page; merge/loop/commit bind03A2 sau guard|
|502–536,587–598,824–845|filter/cursor/retry/query/reset/dedup|03A2 cho local transitions; Page giữ query construction/provider retry|
|392–455,537–568,599–611|poll/explicit refresh/recovery/invalidation|Page; head revision arming cần protocol và integration oracle mới|
|569–586|access denial/latch/interaction invalidation|Page invalidates existing VM; candidate owner chỉ clear local receipt/display metadata|
|612–719,780–786|action preflight/read/open/post-await/snackbar|Page + existing interaction VM; canonical ack/typed target authority không đổi|
|720–748,774–779|modal route/Consumer/session/access gate|Page; route có lifetime khác sheet content|
|749–773|authorized context layout|reuse ContextSheet; authorized payload slot cần clear ownership|
|304–377,848–922|filters/feed/tile/footer/duplicate widgets|reuse02; không copy tile, không nested list/extra gesture wrapper|
|787–823|query/resource/cache identity helpers|candidate receipt owner; giữ wire/name/resource semantics, không sửa cache API|

Candidate `presentation/view_models/mh17/notification_page_coordinator.dart` chỉ sở hữu receipt/projection metadata và feed reference.
Một instance/page, không Ref/provider/repository/router/polling/callback retained; explicit live scope/cache inputs, dispose cùng State.
Proposed constructor/getters/synchronizeScope/recordPageReceipt/recordCountReceipt/pageMatches/countMatches/visibleItems/deny/dispose
được ghi typed trong [binding design](artifacts/composition_03a3p/coordinator_binding.json); đây là rejected-plan candidate, không file mới.
Không giữ ReadSnapshot/canonical count copy; foundation/EpochCache vẫn là nguồn dữ liệu. Page vẫn sở hữu lifecycle/IO/current permission.

## Coordinator binding và read-round lifecycle

| Operation | Trigger / ticket / effect |
| --- | --- |
|constructor|once in State, empty initial revision; không construct lại mỗi build|
|reset|owner/query/filter/access loss; ++revision; clear rows/history/intents trước private render|
|refreshHead|same-owner actual refresh/poll/head invalidation; ++revision trước IO; giữ rows, bỏ obsolete tail|
|acceptHead|fresh canonical head/current cache identity + awaited-head ticket; once/revision; cached bootstrap cần cùng guards|
|beginLoadMore|deliberate tap sau accepted head; ++requestId; raw cursor chỉ là intent, không thành công IO|
|acceptTail|captured dispatch revision/requestId + live scope/cache/query/data identity/freshness; không relabel old result|
|recordLoadMoreFailure|matching non-access tail failure; giữ rows/cursor; invalid_cursor đi head refresh, denial đi reset/latch|
|retryLoadMore|explicit retry, cùng cursor/revision, requestId mới lớn hơn; existing foundation.refresh thực thi IO|
|dispose|close subscriptions/listeners, invalidate owner handle, clear local private state; late callbacks fail closed|

Parent issues tickets; không tăng revision theo build, không reset current-owner feed vì rebuild không liên quan.
Scope đổi/new generation: reset, không refreshHead; count/page receipts và context slot cũng phải clear trước first frame.
Tuple phải có live scope/generation, identical cache, full query và current cache aggregate identity; ticket match không cấp quyền.
Không gọi EpochCache.begin để tạo token thứ hai; foundation tự kiểm epoch/query/request generations.
EpochCache75–88 notify synchronous; SnapshotReadViewModel41–60 có thể enqueue ngay trong listener.
Vì acceptHead chỉ nhận một head/revision, arming sau frame có thể làm mất fast fresh head; capture revision cũ trong build cũng sai.
Arm awaited-head trước .refresh()/ngay trong invalidation callback; sau đó chỉ schedule repaint. Coalesce invalidation cùng round,
nhưng repeated real refresh phải supersede round cũ. Foundation không expose batch/request token trong ReadSnapshot.
Protocol còn cần N01/N04/N05; không dùng mutable latest ticket đơn độc để biến response cũ thành hiện tại.

## Privacy, Feed/Filters/Context và callbacks

[Guard matrix](artifacts/composition_03a3p/guard_matrix.json) có đủ20cases, detector/state/timing/reset/tickets/actions/coverage/gaps.
Bao gồm unresolved,3roles, expiry/logout/A→B/generation/role, invalidation/denial/stale/filter/refresh, late list/count/resolve,
disposal, modal scope loss và captured callbacks. First-frame proof hiện tại đến từ source107–125/session tests; future binding chưa được chứng minh.
[Presentation bindings](artifacts/composition_03a3p/presentation_bindings.json) map đủ16 Feed inputs vào actual source ranges/oracles.
Owner loss: rows/count/private slot clear trước query/render. Stale current-owner rows có thể đọc; action invocation phải fail closed.
Render nullability giữ actionsEnabled267–270; captured non-null callback vẫn recheck head/current cache tại _canInteractNow.
Feed không có AppFailure input: giữ outer access branch cho **feed body**, che badge bằng access latch; không đổi denial thành error text.
Filters refresh vẫn reachable trên branch để recover sau khi BOTH page/count fresh; Feed.onRetry không thể recover khi Feed không được render.
Exact unread count chỉ từ qualified count provider; không derive từ items. Load-more error giữ rows và đúng cursor retry.
Bind loadMoreErrorMessage=null để giữ original label `Tải thêm`; passing text sẽ đổi thành `Thử lại`, làm đổi original oracle.
Filter chỉ có feed.filter; reset query/cursor khi enum đổi. isRefreshing=false giữ refresh availability hiện tại;
busy-disable/spinner là quyết định presentation/refresh-policy riêng trước khi đổi, không lén áp dụng trong extraction.
ContextSheet chỉ dùng cho notification_only như hiện tại; unknown/missing/denied target tiếp tục unavailable snackbar, không tạo route mới.
showModalBottomSheet/Consumer/gates/Close/Back thuộc Page. Hidden safe modal state không chứng minh route đã pop.
Builder hiện720–777 capture raw item. Proposed slot chỉ giữ authorized title/body, builder capture handle, clear khi scope/access loss/close/dispose.
Đây là render/state-clearing obligation, không phải GC/zeroization proof; modal outliving Page chưa có oracle (N07), nên chưa an toàn để move.
Available read→1read/0nav; pending read hit có thể outer open; rapid authorized taps giữ multiplicity hiện tại.
Feed chỉ forward một callback, không thêm GestureDetector, không await read trước resolve, không mutex; VM giữ canonical per-ID dedup.
Before invocation và after await giữ mounted/current scope/cache/provenance checks. Read failure không chặn navigation đã authorize.

## Test traceability và missing integration evidence

[Test traceability](artifacts/composition_03a3p/test_traceability.json) giữ original descriptions, current file/line,94assertions/103expanded,
catalog tên case/declaration lines/source SHA và mapping từng nhóm. Không sửa tests/assertions.

| Fresh executed group | Cases | Extraction oracle |
| --- | ---: | --- |
|Original page,3files |19|filters/count/denial/cursors/poll/read/navigation/render|
|03A1 characterization |14|duplicate/head race, gestures, privacy, resolver lifetime|
|03A2 coordinator |26|T01–14, immutable outputs/tickets/cursors|
|02 components |39|controlled UI/callbacks/state/semantics; không authorization proof|
|Session |7|first-frame clear/late list/modal/expiry/unresolved/empty retry|
|Foundation / interaction |17 /16|canonical reads/count/ack/typed checks/lifecycles|
|DTO + existing widgets |8|mapping/tile/badge|
|Total focused |146|không cộng lại các lần chạy independent|

N01–N10 trong traceability là gaps: fast head/invalidation, all-private-state first-frame clear, ticket reuse + provenance,
cache bootstrap, double refresh/ack coalescing, transient empty mapping, surviving modal/slot lifetime, composed gestures,
access branch/footer retry và refresh availability. Reuse existing oracles; không rewrite original expectations để làm composition xanh.
Future tests dự kiến rounds280/400 và lifetime260/400LOC, chưa tạo; không tách original tests lần nữa nếu không cần.

## Stages — HOLD, không phải implementation authorization

Endpoint hiện tại không đạt nên các stage dưới chỉ chỉ ra thứ tự kiểm chứng và interim debt; không được bắt đầu.
[Staging detail](artifacts/composition_03a3p/stages.json) ghi files/functions/oracles/hashes/recovery/STOP cho từng stage.
0. Revised ownership/budget + F02 decision + head/modal protocol review; vẫn docs only, page922 giữ nguyên.
1. Candidate Filters/Feed composition giữ current guards: estimate827LOC page, không LOC compliant; tests146 + original oracles/N08–10.
2. Candidate accepted-feed/receipt binding: estimate680LOC page +237owner; tests146 + N01–06; vẫn vượt page limit.
3. Candidate Context presentation: estimate679LOC page +237owner; session/context/N07 bắt buộc; vẫn không đạt endpoint300.
Không đề nghị thực thi chuỗi827→680→679 để rồi tuyên bố thành công. Cần revised architecture chứng minh endpoint trước khi giao source work.
Mỗi future stage cần fresh working SHA; recovery chỉ reviewed inverse patch cho task-owned hunks, giữ pre-existing dirty/untracked files,
không reset/clean/checkout/delete. Nếu không tách patch an toàn được thì giữ checkpoint và STOP.

## Exclusions, evidence và decision

F02: raw malformed cursor tại begin/retry→NotificationQuery là **STOP/defer boundary**, không validation/trim/decode/recovery mới.
F03 full typed role matrix, F05 navigation decision, F07 Preview canonicality không sửa. Timeout/VM/Tile/test debt vẫn riêng.
Fresh full MH17 **146 PASS**; root page9 +session7 **16 PASS**; cả17files chạy independent, tổng146, không cộng thành baseline mới.
Expanded parallel output có thể lặp active test label, nên per-file counts lấy từ individual runs, không đoán từ nhãn parallel log.
Analyzer **No issues found/exit0**. Full suite/selected order regressions/Android/backend/Preview acceptance/TalkBack NOT RUN trong task này.
[Focused](artifacts/composition_03a3p/focused_baseline.log), [root+session](artifacts/composition_03a3p/page_session_baseline.log),
[individuals](artifacts/composition_03a3p/individual_results.json), [analyzer](artifacts/composition_03a3p/analyze.log),
[verification](artifacts/composition_03a3p/verification.json): source/region/budget arithmetic, links, LOC, diff và protected SHA.
SHA PASS:348protected inputs không đổi;3502/3504baseline files nguyên bytes, chỉ HANDOFF/ARCHITECTURE_PLAN đổi; không có Dart mới/sửa.
Decision **BLOCKED**: measured retained486>300; candidate endpoint679/237, alternative512/448; round binding và modal lifetime chưa chứng minh.
Không gọi đây là reproduced production defect. Không thêm source/tests/provider changes để vượt gate. STOP trước MH17-03A3 implementation.
