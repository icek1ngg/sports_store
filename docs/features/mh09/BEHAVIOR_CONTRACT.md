# MH09 — Behavior contract audit

Các nhãn: **Target** = spec1.2; **Current** = source đã đọc; **Missing** = chưa tích hợp, không fake.
HTML chỉ quyết visual. MH09 NOT YET APPROVED, task01 không đổi contract hoặc code.

## Detail read / manager access

Target [spec §8/§12](../../technical_specification_mh07_mh08_mh09_mh17.md),
[Data/API OP-O03, §4.2/4.6/4.7](../../technical_specification_mh07_mh08_mh09_mh17_data_api.md):
canonical order identity là full UUID; DH-10248 trong mock không phải ID/code mới.
MH09 chỉ manager; shared OP-O03 vẫn có own-customer sanitized projection, không mở MH09 cho customer.
Shipper đọc task qua MH11, không dùng detail API để đọc raw order/khách.
Target `get_order_details(p_order_id uuid)` trả một SQL snapshot đầy đủ: order/items/buyer/projections/timeline/capabilities/as_of.
Không ghép nhiều request thành một snapshot giả; network/SQL fail là fail toàn read, không giả source missing.
history_complete=false chỉ biểu thị lịch sử nguồn thiếu trong aggregate hợp lệ.

Current page `FeatureAccessGate(roles:{manager})`, provider family theo orderId; loader kiểm tra returned UUID.
`OrderDetails` kiểm tra item ownership/unique IDs/subtotal, buyer relation, COD identity/amount,
order/COD timeline IDs, return timeline IDs và latestAttempt.orderId; chưa validate delivery timeline task ownership.
Read VM chấp nhận response bằng lifecycle + epoch/token; invalidation refresh serialize/queue lần mới.
Missing production session bridge CIN01, adapter/RPC, RLS evidence và route guard production.
Router hiện chỉ `/`; target `/manager/orders/:orderId` chưa tồn tại. Preview DI không chứng minh backend permission.
Malformed/missing/denied phải generic, không lộ tên/người nhận/UUID ngoài quyền; client không thay RLS.

## Canonical freshness

Current `ReadSnapshot.isFresh = data != null && !loading && !stale && failure == null`.
Page actions cần manager + epochCache.canRead + fresh detail + current capability từng operation.
Refresh/retry/pull-to-refresh cùng provider; foreground/current-route polling3s (Preview tắt polling).
Detail accepted invalidates `orders/list/`; list/count refresh độc lập, receipt không overwrite cache.
Network failure giữ permitted snapshot stale/read-only; unauthenticated/forbidden xóa private data.
Không so asOf/updatedAt/device clock/enum ordinal để quyết snapshot nào mới hơn.
Target mutation success chỉ resolve receipt rồi invalidate/refetch; timeout unknown không success/rekey/retry mù.
Missing command transport/persistent pending-store implementation; task UI không bổ sung.

## A. Order lifecycle

| Mục | Audit |
| --- | --- |
| Source/model |OP-O03 → OrderDetails.order/OrderCapabilities/asOf; DTO OrderDetailsDto/OrderDto|
| UI |identity/status/placedAt/attempt count + payment snapshot + order action footer|
| Permissions |manager route/UI; backend current role/entity permission ở mỗi read/action|
| Freshness |fresh current detail để mở/submit action; pending status đơn lẻ không đủ|
| Null/error |order bắt buộc, không placeholder private record; malformed aggregate → unsupported/data_integrity|
| Current |readonly status/snapshots; confirm/reject/exceptional-cancel dialog validation/unavailable|
| Target |server pending precondition cho confirm/reject; race manual/auto/cancel chỉ1 commit; auto≥1h, không auto assign|
| External/missing |OP-O04/O05/O07/JOB-O01, Inventory custody/release, backend permission/idempotency|
| Coverage |page capability/stale/error tests; foundation receipt/order guards; backend race/replay NOT RUN|

Hủy ngoại lệ target chỉ preparing/awaiting_pickup và **chưa từng pickup**, reason bắt buộc.
Task mới chưa pickup sau failure1 không xóa lịch sử custody; MH09 không tự restock/cancel delivery.

## B. Delivery lifecycle

| Mục | Audit |
| --- | --- |
| Source/model |DeliverySummaryDto → DeliverySummary?, AttemptSummary? trong OP-O03|
| UI |OrderDeliverySection: kind/status/shipper/count/times/failure/latest attempt|
| Permissions |authorized manager projection; không shipper route bypass; không GPS/OTP/3PL|
| Freshness |projection cùng snapshot; external mutations disabled kể cả capability=true|
| Null |null summary → Chưa có dữ liệu giao hàng; null task/name/time không suy “Chưa phân công”|
| Current |failureReason và attempt reason hiển thị; không có typed warning list trong OrderDetails|
| Target |count≤2 toàn order; first failure cho retry/early return; receipt+inspection mới restock sellable|
| External/missing |CIN03/04 custody/task signatures/Inventory transaction chưa accepted/implemented|
| Coverage |page separate lifecycle/missing summary/disabled operations; no live delivery integration|

Không copy warning list của MH08 OrderSummary vào detail nếu OP-O03 chưa cung cấp.
Delivery kind returnPickup/redelivery không tự chịu rule2 outbound attempts; nhiệm vụ owner xử lý.
Current DeliverySummary không có orderId; khi latestAttempt=null, model không chứng minh projection thuộc order.
Delivery timeline sourceEntityId cũng chưa đối chiếu task→order; target server/adapter phải validate authorized links.
Đây là integration gap, không bổ sung model/DTO hoặc suy ownership từ taskId trong task visual.

## C. COD lifecycle

| Mục | Audit |
| --- | --- |
| Source/model |Order subtotalVnd/deliveryFeeVnd/totalCodVnd + CodSummaryDto → CodSummary?|
| UI |payment snapshot + independent OrderCodLifecycleSection|
| Permissions |manager đọc; chỉ manager nhận đủ tiền tại MH12, MH09 chỉ callback orderId|
| Freshness |không lấy order delivered hoặc refund làm bằng chứng COD collected/received|
| Null |null → Chưa có dữ liệu COD; không zero/uncollected/settled mặc định; model required amount không nullable|
| Current |expected/collected/received/times; model validate full amounts và order total relation|
| Target |uncollected→collectedByShipper→receivedByStore; không partial hoặc offset refund|
| External/missing |CIN05/MH12 adapter/route/receipt operation; callback Preview hiện null|
| Coverage |page independent states/null; DTO/domain integrity; real reconciliation NOT RUN|

VND integer; subtotal + original fee30.000 = totalCOD. Không shipping promotion row từ HTML.
Return/refund sau delivered không xóa shipper COD obligation; không overwrite order thành cancelled.

## D. Return / refund lifecycle

| Mục | Audit |
| --- | --- |
| Source/model |ReturnSummaryDto → List<ReturnSummary>; status/submittedAt/closedAt/decisionReason|
| UI |OrderReturnsSection; read-only status/time/reason + returnId link MH15|
| Permissions |manager summary; bank/payment evidence chỉ manager và own customer qua owner private access|
| Freshness |cùng aggregate; không tính eligibility từ local clock; không mutate return từ MH09|
| Null/empty |list empty → Chưa có dữ liệu yêu cầu trả hàng; không phân biệt source unavailable và confirmed-none bằng model hiện tại|
| Current |summary không chứa refund amount/bank/video/transfer evidence; không có refund transaction detail|
| Target |7 ngày tại submit, mandatory video,1 active request; full goods thực nhận; approve pickup≠approve refund|
| External/missing |CIN06/08/MH15, cutoff/business edge, refund/evidence private; callback Preview null|
| Coverage |delivered+collected+active-return giữ độc lập; refund/bank privacy/real transfer NOT RUN|

Refund target đủ merchandise+original fee; manager transfer ngoài app rồi record evidence tại owner module.
Reject sau inspection → free redelivery, không COD lần nữa; failure vẫn pending manager resolution.
Target CIN06: `[]` chỉ khi read authoritative thành công và thật sự không có request; unavailable phải là
dependency/error của aggregate, không tự thay bằng `[]`. Current UI label chưa thể hiện riêng confirmed-none.
Không thêm fields/DTO/models cho refund vào MH09 visual task. Sanitized free-text do backend projection chịu trách nhiệm.

## Timeline semantics

Target spec§8.2/DataAPI§4.2/4.4: actual authorized events của order + related task/COD/return.
Dedup eventId; actual `(occurredAt,eventId)` tăng dần tương ứng server `(created_at,id)`.
Current model rejects conflicting same-event rows; `OrderTimeline` còn normalize fallback/actual/tie ordering.
Snapshot fallback chỉ từ timestamp nghiệp vụ có thật, nhãn “Mốc từ bản ghi đơn”; không invented eventId/actor.
Actual milestone thay fallback cùng mốc; unknown actor không tự thành system.
System chỉ khi actorSource/source chứng minh automatic. Server instant → Hanoi UTC+07 qua shared formatter.
Empty timeline “Chưa có mốc lịch sử được xác nhận”; historyComplete=false thêm incomplete notice.
Không six hardcoded stages, inferred ETA/OTP/automatic shipper/wallet; COD receipt có thể sau refund.
Coverage widget actor/dedup/fallback/chronology hiện có; related Delivery/Return event producer chưa integrated.

## Actions và navigation

| Action | Current gate / interface | Missing / target |
| --- | --- | --- |
| Confirm |canConfirm + manager/cache/fresh; dialog no reason|OP-O04 pending + transaction/idempotency server|
| Reject |canReject + gate trên; trim reason1…1000 runes|OP-O05 pending + atomic release/notification|
| Exceptional cancel |canCancelExceptional + gate/reason|OP-O07 historical custody/Inventory proof|
| Assign/reassign/retry/early-return/receive |capability điều khiển visibility; button luôn disabled + explanation|Delivery/Inventory owner APIs; không tự local-mutate|
| COD |non-null summary + onOpenCod(orderId)|MH12 recheck manager/entity; Preview callback null|
| Return |summary + onOpenReturn(returnId)|MH15 owner guard; Preview callback null|
| Chat |onOpenChat(customerId)|openCustomerConversation owner resolves conversation; không SMS/shipper|
| Call |onCallRecipient(recipientPhone)|optional dialer handoff; unavailable giữ số; không tự thêm dependency|

Dialog `_submit` chỉ validate và báo externalDependencyUnavailable; không request ID/receipt/fake success.
03A2 `_allowed`/`_current` dùng current capabilities, không derive role/action từ order status; server precondition còn bắt buộc.
Preview MH08 chỉ truyền `orderId`, `enablePolling:false`; mọi callback external null.
MH08→MH09→pop: exact UUID, stable scope, giữ search/status; mounted/session/cache guard trước refresh canonical query.
Detail read không tự mark notification read. Không chỉnh route/callback task01.

## Session / lifecycle risk register

1. Current gate reset subtree theo SessionScope, cache clear/bỏ late reads theo epoch/lifecycle; giữ nguyên.
2. Dialog capture submittedScope, observe cache/source invalidation, clear reason khi scope đổi; close privacy-safe.
3. 03A2 tái hiện inactive còn mounted → ancestor lookup exception. MH09-local active/generation owner chặn trước ref/ancestor access.
   Same-frame/reparent/unmount/rapid route/null-callback/late async probes PASS; [INTEGRATION_03A2](INTEGRATION_03A2.md) giữ red→green evidence.
4. Shared `acceptHistoricalReceipt` đọc ref trước mounted check; chưa gọi từ dialog hiện tại, ghi dependency ngoài UI scope.
5. Current dialog capture submittedScope/sourceCache/orderId/ticket, recheck same cache/scope/fresh canonical operation; _owns trước ref read.
   Root ProviderScope không đổi; shared dialog tự dispose listener/controller; invalid owner trảfalse, không suppress errors.
6. Recheck permission khi open detail/dialog/async complete/pop/refresh/submit; scope change không private flash.
7. Backend RLS/Storage/session bridge chưa kiểm chứng; widget guards/Preview tests không thay thế các bằng chứng này.

## Traceability

Main spec§8.1 sections,8.2 timeline,8.3 actions; §12.2 lifecycle,12.3 freshness/formatting,12.4 routes,12.5 epochs/receipts.
Data/API§3 projections,4.2/4.4 detail/events,4.6 wire,4.7 allowlist; OP-O03/O04/O05/O07/O08/JOB-O01.
[CIN](../../Cross_Module_Integration_Contracts.md)01 Auth,03 Delivery,04 Inventory,05 COD,06 Returns,08 cutoff,09 events/CHAT.
Acceptance trace T09-01…28, TX generation/receipt/race và business invariants NT liên quan; xem TEST_PLAN.
