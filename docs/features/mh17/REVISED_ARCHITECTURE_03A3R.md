# MH17-03A3-R — Revised Architecture & LOC Feasibility

User decision22/10/2026: architecture R được ACCEPTED làm baseline, subject to runtime/test validation.
Hủy R2 design-only; ngoại lệ duy nhất ReadCoordinator≤280 thay250. Estimated257 nay có margin23.
Page≤300, mọi limits khác giữ nguyên. [Current policy/checkpoint](IMPLEMENTATION_CHECKPOINT_01.md).
Kết luận BLOCKED/budget250 bên dưới ghi historical review trước policy adjustment; artifacts R không regenerate.

**MH17-03A3-R — ARCHITECTURE REVISION STILL BLOCKED**

Thiết kế/documentation only, ngày 22/10/2026. Không sửa Dart, test, Preview hay contract.
Audit 03A3-P đã hoàn tất và NOT FEASIBLE; đây là revision ownership, không restart audit.

## Baseline được tái sử dụng

[Plan P](PAGE_COMPOSITION_PLAN_03A3P.md), [recovery](RECOVERY_03A3P.md) và toàn bộ evidence P giữ nguyên.
Working source `lib/features/notifications/presentation/pages/notifications_page.dart`: **922 physical LOC**.
SHA-256: `7ca8c5c50945348e46bcb71c53b3e46f6e95e096b95245280262bcad32c667f0`.
[Ownership map](artifacts/composition_03a3r/ownership_map.json) dùng lại 79 disjoint regions, range hashes và test references P.
Không re-inventory. Mỗi region tính original LOC đúng một lần; targetOwners chỉ mô tả cooperation, không cộng lại LOC.
Fresh R baseline chụp working files trước R edits; không dùng HEAD làm approved baseline.

## Blocker gốc và phân loại lại

Plan P: page679/300, owner237/250; alternative page512, owner448. Cả hai không đạt.
486 original lines trước đây giữ tại Page được phân lại theo responsibility thực:

| Responsibility | Original LOC | Proposed owner |
|---|---:|---|
| View host/composition | 82 | Page |
| Lifecycle/subscriptions/namespace signals | 51 | SessionBridge |
| Read rounds, refresh/poll, provenance | 210 | ReadCoordinator |
| Read/open asynchronous UI orchestration | 83 | Actions |
| Pure current-item action predicate | 25 | SnapshotProjection |
| Guarded context lifetime | 35 | Modal route widget |
| Total | 486 | |

Exact field/method/range mapping và measured original LOC nằm trong ownership_map, không phải estimated implementation LOC.
Toàn bộ 922 lines: **82 retained +342 moved/rewrite +423 replaced +75 duplicate presentation removed**.
Page equation: **922−840+194=276**; net giảm ước tính646.
194 gồm imports/API/bindings/guard glue/format reserve, không giả định move840 là giảm ròng840.

## Budget bảo thủ — tất cả endpoint đều là ước tính

[File budget](artifacts/composition_03a3r/revised_file_budget.json) có từng block, source basis, imports/constructors/reserve.

| Owner/file stem | Current | Estimated final | Limit | Margin |
|---|---:|---:|---:|---:|
| notifications_page | 922 | 276 | 300 | 24 |
| notification_page_read_coordinator (new) | 0 | **257** | 250 | **−7** |
| notification_page_session_bridge (new) | 0 | 142 | 250 | 108 |
| notification_page_actions (new) | 0 | 174 | 250 | 76 |
| notification_snapshot_projection (new) | 0 | 140 | 150 | 10 |
| notification_context_modal (new UI owner) | 0 | 160 | 180 | 20 |
| notification_feed_coordinator | 152 | 152 | 250 | 98 |
| notification_filters | 60 | 60 | 100 | 40 |
| notification_feed | 121 | 121 | 180 | 59 |
| notification_context_sheet | 51 | 51 | 150 | 99 |

Read owner: imports/typed ports22, fields20, query/reset16, page/count acceptance42, head arm20,
invalidation16, tail20, poll/refresh/recovery60, access latch12, projection/preflight12, dispose7, reserve10 =257.
247 core +10 reserve vẫn là257 physical LOC; không bỏ reserve để tạo PASS247.
Whole composition922+384 approved reuse=1306 →1533 estimated (+227), do thêm explicit lifecycle/ports/guards.
Không phải giảm toàn bộ source LOC; mục tiêu là responsibility và giới hạn từng file.

## Cohesive owners và boundaries

Page giữ public constructor/callback hiện tại, WidgetRef watch/listen, BuildContext, snackbar và modal push.
Không sao chép items/count; build synchronize live scope/cache trước query hoặc private rendering.
Khởi tạo read/actions trước attach fireImmediate subscriptions; dispose consumers trước bridge.

SessionBridge chỉ giữ manual subscription/cache-listener handles và namespace lease metadata.
`attach(WidgetRef ref)` dùng Ref tạm lúc đăng ký; callbacks nhận next values, không capture/store Ref.
`synchronize(liveScope,liveCache)`, `captureLease(...)`, `isCurrent(lease,liveScope,liveCache)` nhận live values.
Loss/reset callback đồng bộ clear feed/receipts và revoke UI leases trước frame; repaint có thể schedule an toàn.
Không đọc repository/snapshot hay giữ canonical Auth/count/cache copy.

ReadCoordinator là một owner của local query/read rounds/acceptance receipts/access latch; compose FeedCoordinator.
Page cấp typed ephemeral ports: scope/cache/page/count/refreshPage/refreshCount/invalidateInteractions.
Không lưu WidgetRef/BuildContext; trước mọi post-await port call phải kiểm active và current namespace lease.
SnapshotProjection là pure explicit-value predicate/render projection, không giữ latch/round/receipt/subscription.
Nó không trở thành cache hay permission source mới.

Actions có83 original lines orchestration thực, không phải forwarding layer.
Entry đồng bộ chuyển item cho existing interaction VM; continuation chỉ giữ ID/lease/Future/UI ports.
Giới hạn retention này áp dụng adapter/modal mới; existing VM vẫn nhận/giữ NotificationItem trong async operation của nó.
VM giữ canonical ack/typed target validation/per-ID dedup. Không thêm navigation mutex hoặc read state authority.
Post-await navigation kiểm current namespace/cache/access lease; không bắt head phải fresh sau chính read ack vừa invalidated.

Modal route widget có lifetime độc lập cần thiết vì Navigator route có thể sống sau Page.
Page giữ showModalBottomSheet; route widget dùng approved ContextSheet cho nội dung.
Builder chỉ giữ revocable handle, không giữ NotificationItem/Page State hay title/body immutable widget fields.
Own scope/cache subscriptions tiếp tục hoạt động khi Page disposed; không auto-pop route để thay đổi behavior.

## Head-round/modal protocol và privacy

[Lifecycle protocol](artifacts/composition_03a3r/lifecycle_protocol.json) chứa N01/N04/N05/N07, API contracts,
8 coordinator call sites, inherited guard matrix, presentation bindings và integration oracles.
Đây là design obligations; chưa có implementation để claim runtime proof.

N01: arm newer head revision trước refresh IO; không tăng revision mỗi build.
N04: cached provisional head chỉ adopt một lần trong armed round, sau live scope/cache/query/provider provenance checks.
N05: ack invalidates trước read Future complete; head có thể được accept trước afterRead.
Coalesce invalidations đang awaiting, không rearm/extra RPC khi completion đã thuộc round mới.
Already-read fast true có tail vẫn reset presentation về cached head, không gọi thêm repository.
Foundation vẫn có thể reread tất cả active resources; không hứa một backend request duy nhất.

Namespace/UI lease khác head/tail revision. Ticket match không authorize response; live current scope/cache/epoch/snapshot checks luôn cần.
Loss/switch/generation/block reset trước private frame, kể cả ticket cũ vô tình bằng ticket mới.
Current-owner stale có thể hiển thị, nhưng không bật read/open; exact count luôn từ foundation count snapshot.
Captured callbacks kiểm lại active/current lease trước navigation/message/context, không retain raw item qua await.

N07: own modal scope/cache listener clear private cell đồng bộ trên loss/deny; render cũng gate live state.
Cache cùng object bị block vẫn phải phát hiện qua cache listener, không chỉ provider replacement.
Hide content không đồng nghĩa pop route. Ack/stale/unread row biến mất không revoke nội dung còn authorized.
Page dùng route.whenComplete(handle.release); tránh async Page frame giữ title/body đến khi modal đóng.
Không claim zeroization bộ nhớ hoặc backend sanitization.

## Presentation và test traceability

Reuse [P bindings](artifacts/composition_03a3p/presentation_bindings.json) và [P tests](artifacts/composition_03a3p/test_traceability.json).
Feed inputs derive một projection: denial thắng old list/count; stale read-only; tail failure giữ rows/retry intent.
Filter chỉ một controlled source FeedCoordinator.filter; đổi filter reset query/cursor, không lọc một partial page.
pendingReadIds từ interaction VM; separate onOpen/onMarkRead, không wrapper gesture mới.
Available read→one read/no open; pending hit có thể tới outer open; repeated authorized callbacks giữ nguyên F05 observation.

Original19 page +14 characterization bảo vệ page/read/actions;26 coordinator giữ merge/retry/revisions;
39 component giữ controlled UI;7 session giữ privacy;17 foundation +16 interaction giữ canonical behavior.
DTO4 +existing widget4 bổ sung total historical146. Không sửa/bỏ assertion hoặc viết test trong R.
New oracles chỉ cho boundaries mới: immediate head/self-invalidation, cached adoption/rebuild, ack/head ordering,
already-read tail reset, first-frame loss với reused ticket, modal same-object block/Page disposal, post-dispose Ref access.

## F02 và bước tiếp theo

[F02 proposal](F02_DECISION_PROPOSAL.md): response validation trước foundation cache acceptance, separate approval.
F02 phải được quyết định trước live pagination integration; không normalize raw cursor trong coordinator.
F03/F05/F07 giữ nguyên. VM455/Tile185/oversized tests không được coi đã LOC compliant.

Không authorize Stage1 composition khi final read owner vẫn257/250.
Next bounded DESIGN review: đánh giá pure shared refresh eligibility outputs trong Projection margin10,
đo lại typed API/glue overhead; chỉ coi tiết kiệm là thật nếu endpoint budgets đều đạt.
Không tạo helper/controller chỉ để chuyển7 lines. Nếu không chứng minh được, giữ BLOCKED.
Sau design pass và F02 decision mới lập source stages nhỏ, fresh hashes và N-oracle tests; không tự bắt đầu.

## Verification và kết luận

[Verification](artifacts/composition_03a3r/verification.json): JSON/ranges922/budget/links/LOC/diff/protected hashes.
Historical146/analyzer không rerun trong task docs-only này. Không Android/Preview/backend/full suite claim.
Independent architecture review xác nhận conservation và257 budget bảo thủ; không bỏ reserve để tạo false PASS.
Page276 đạt riêng lẻ; **Read257 vi phạm hard limit**, vì vậy revised architecture chưa feasible toàn bộ.
