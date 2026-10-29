# Final Technical Decisions — revision 1.2

Ngày 08/10/2026. Owner Orders/Notifications đã ủy quyền chọn thiết kế kỹ thuật trong yêu cầu TECHNICAL DESIGN FINALIZATION. Chốt dưới đây là **OWNER DECIDED**, không chứng minh SQL/Flutter implementation đã tồn tại. Không phê duyệt thay owner Checkout, Delivery, Inventory, COD, Returns, Auth hoặc Chat. Business baseline giữ nguyên `Nhóm 1_Docs.docx`; audit1.0/remediation1.1 là lịch sử.

| Record | Kết luận | Authority / runtime status |
|---|---|---|
| DR-01 | Option C: private module-scoped Orders terminal receipts; logical client key tách public audit UUID | OWNER DECIDED; NOT IMPLEMENTED |
| DR-02 | Orders exceptional cancel pre-custody; consume attempt khi recorded result; recommended retained-custody/new task2/store-leg/inspection flow | Own consumer behavior OWNER DECIDED; Delivery/Inventory implementation SHARED CONTRACT — NOT ACCEPTED |
| DR-03 | In-app center + synchronous Orders event fan-out, typed target, frozen manifest | OWNER DECIDED; external producer CIN-09 NOT ACCEPTED |
| DR-04 | Exact owned DTO/envelope/error/query/projection definitions | OWNER DECIDED; external summaries/handoffs require acceptance, not existing API |

## DR-01 — module-scoped persistent receipt

Requirements BR-COM-09/10/12–14/32/36, CR-07/08/11. Existing `orders UNIQUE(customer_id,request_id)` chỉ placement; `business_events.request_id UNIQUE` global, incident CHECK request_id required; `inventory_movements UNIQUE(event_id,variant_id)`; `notifications UNIQUE(recipient_id,event_id)`. Không sửa các constraints chung để chọn global request registry.

Options: A global registry cần mọi owner đổi operation identity; B reuse audit request_id không đủ immutable payload/result và collision cross-module; **C chọn private Orders terminal receipts**, giữ public request_id null cho generic Orders roots, incident producer vẫn nonnull. C giảm shared migration impact, đổi lại phải có typed private metadata để audit causal/request linkage. Không giải quyết idempotency của Checkout/Delivery bằng receipt Orders.

Normative schema/protocol/fingerprint/retention ở [Data/API §7.2–7.4](technical_specification_mh07_mh08_mh09_mh17_data_api.md#72-orders-persistent-receipt-owner-decided--proposed-implementation-dr-01). Request namespace PK principal/request, intent gồm operation/order/reason; canonical JSONB equality, server principal, protected pending storage và auth-before-replay. Same key same result success **hoặc terminal business failure**, không chạy side effects lại; fingerprint khác error. Historical receipt không canonical cache. Unexpected errors abort transaction, không đóng key vĩnh viễn. Job eligibility recheck skip early/nonpending trước terminal record, system key order.id.

Identity serialization triển khai future bằng transaction-scoped advisory lock trên stable 64-bit server hash của `(principal_key,request_id)` trước receipt lookup, không insert incomplete row vào table toàn terminal fields. Hash collision chỉ serialize thêm requests, không dedup: JSONB/PK equality vẫn authoritative. Final insert receipt có PK làm backstop. Giữ order lock ngoài domain work subtransaction; controlled business failure rollback work trước lưu failed receipt. Role validation trước claim/lookup; no client system principal. SQL function return envelope §5.3; transport error có thể outcome_unknown.

No TTL baseline: giữ audit/receipt để app restart/long retry không nhân effects. Account deletion không cascade receipt; no token/bank/evidence; policy purge/retention-law nằm ngoài technical ownership, REQUIRES BUSINESS DECISION nếu cần thay. Owner không thêm crypto/UUID extension hay global registry package.

Persistent `private.business_event_contracts` mới lưu event/root/type/module/source-key/facts/frozen manifest (schema §7.4). Public root/request constraint giữ nguyên; typed metadata chưa tồn tại. Root idempotent canonical registration + receipt giữ logical request; child audit-only links root không emit lần2. `legacy_unknown` khi không metadata; không sửa history đoán actor/type. Synchronous failure rollback business transaction. Private raw tables client denied, restricted trusted functions.

Fixtures FP-01–05/CF-01–06 và TX-29–36; acceptance future: simultaneous same request results equal, semantic conflict denied, business failures replay, unknown SQL rollback all, canonical event/movement/notification counts unchanged replay, scoped key colliding external incident still legal generic root null. **Documentation decision closed; runtime tests NOT RUN.**

## DR-02 — cancellation, custody, attempts và stock

Requirements BR-COM-13–19/31/36; exact current enum/constraints VERIFIED trong migrations. Không tạo state enum mới. Own `cancel_manager_order` chỉ confirmed preparing/awaiting_pickup + reason + complete never-picked-up historical proof. Current task accepted_at không proof custody. Atomic Delivery revoke/Inventory release required; unknown -> disable/custody_unverified. Order cancellation logic owner decided; trusted custody producer vẫn EXTERNAL DEPENDENCY.

Recommended operational flow **SHARED CONTRACT**:

1. Preparation/assignment → awaiting_pickup; initial pickup authenticated current shipper atomically dispatches reserved goods exactly once → delivering.
2. Record outbound result atomically full success+COD hoặc failure reason/shipper/time. Completed result consumes attempt; failure1 → awaiting_redelivery, failure2 → awaiting_store_return. No counter increase/reset on assignment, shipper change or retry acknowledgment.
3. After failure1 same shipper holds goods. Manager creates **new outbound task2**, assigned, order remains awaiting_redelivery. Explicit shipper retry acknowledgment → accepted/in_transit and delivering, no second dispatch/reservation/store pickup. UNIQUE task-result/active-outbound constraints fit this flow; schema feasibility không đồng nghĩa Delivery owner approved.
4. Before retry acknowledgment, Manager may early-return and atomically cancel new task2 under order lock; use actual custodian outbound task for store leg. No transfer to other shipper after pickup in baseline. Second failure must return store; no third outbound result.
5. Outbound task original destination and COD snapshot remain Customer. Store-leg navigation/read projection uses singleton store_settings, no COD collection; missing store coordinates store_location_unavailable, no Customer-location fallback. Do not create return_pickup with no return_request.
6. Shipper reports handover separately; Manager records physical receipt (task returned_to_store, order awaiting_store_return), then inspection all issued quantities. Sellable goods increase on_hand, damaged increase damaged only, no premature release/restock. Complete verified inspection → undeliverable_returned, uncollected COD no refund, delivered returns use independent lifecycle.

Simplest alternate: bring goods back after first failure then new pickup, requires richer receipt/re-dispatch accounting and store custody transitions; not baseline. Updating task1 result for attempt2 violates UNIQUE(task_id). Reassigning after pickup without transfer evidence loses physical custody accountability. These are reasons for chosen consumer recommendation, not a new compulsory group policy.

REQUIRES BUSINESS DECISION: lost/missing goods final disposition/partial closure, damaged/lost liabilities, transfer after pickup and return7-day exact cutoff. Safe baseline goods_discrepancy/action-disabled, not automatic cancellation/stock restoration. Missing store settings is external setup, not license to alter customer snapshot. Exact CIN-03/04 acceptance required; MH09 UI can render disabled actions before runtime functions exist.

Owners to accept: Minh Đức Delivery/COD, inventory shared owner, Checkout for reservation/dispatch continuity; Sơn for independent Returns contracts. Closure: CIN-03/04 accepted + fixtures initial pickup, first/second failure, retryack/earlyreturn race, actual receipt/inspection, count never>2, damaged never available, duplicate effects zero.

## DR-03 — Notification Center và owned producers

BR-COM-12/13/18/32/34–36; schema notifications per recipient/event/read trigger VERIFIED, producers missing. Owner chooses **synchronous transaction** for Orders success: business state+root event+private metadata+manifest+notifications+receipt commit/rollback together. No outbox/push/email/SMS/client fan-out. Freeze recipients/typed targets at first emit, replay not recompute current manager/assignment set. Generic safe title/body, no PII bank/video/evidence or raw reason; details at authorized target.

Exact owned events: order_confirmed_manual→order customer; order_confirmed_automatic→customer + all current trusted profiles.role=manager; order_rejected→customer; order_cancelled→customer and affected assigned shipper (notification_only/event UUID). Cancellation captures affected shipper before revoke under same transaction, requires CIN-03 for that source; no unverified assignment fallback.

Notifications owner chooses resolver allowlist `order,delivery_task,cod,return_request,conversation,notification_only`, COD id=order.id, recipient-first read + role/ownership/current-target recheck, no arbitrary stored URL. Customer own detail inside MH07, Manager MH09, Shipper taskMH11 only current assignee; notification_only remains MH17 no raw event read. Read first timestamp monotonic, explicit tap only; navigation independent of read ack. No mark-all baseline. Foreground poll3s/read/count epoch isolation, pause/resume, no cross-session callbacks; no Realtime availability claim.

22 event families/main§9.2 are fully typed; 4 Orders families OWNER DECIDED, others **SHARED CONTRACT NOT ACCEPTED**. Approval+assignment share one canonical parent notification event, assignment child audit-only to prevent semantic duplicate not caught by recipient/event UNIQUE. CIN-09 exact source facts and frozen manifest; Chat fanout allManagers except sender, Customer conversation owner, no Shipper. External producers must confirm trigger/facts/recipient behavior and implement in their transaction; docs không nói họ đã đồng ý.

## DR-04 — owned API, data và Flutter mapping

Owner chooses exact Orders wire snake_case plus Dart camelCase mapper, required nullable keys, bigintVND JSON int, UUID full, timestamps explicit UTC, unknown/status/shape unsupported_data. RPC envelope `ok,data,error`; errors consistent §5.3. Receipt full21-key historical order, current_order=null. Lookup state/receipt/failure required discriminated union. No invented human code/image snapshot/version columns.

List search Customer snapshot product or fullUUID; Manager buyer profile full_name or fullUUID (not recipient), literal case-insensitive, no accent folding. StatusCounts excludes selected-status filter while total_count includes it, one statement snapshot; cursor bound role/user/query/limit tuple, re-authorize every page. Safe Customer projection masks actor/shipper IDs, manager free-text delivery reasons and internal incidents, no raw-task/event RLS expansion. Exact examples/fixtures [Data/API §9](technical_specification_mh07_mh08_mh09_mh17_data_api.md#9-json-examples--revision-12-owner-contract-not-implemented).

Riverpod DI/ViewModels, central go_router, shared Supabase client/theme reused. Domain no widgets/SDK; data SDK adapter normalizes platform errors. Route proposals for other owners remain CIN acceptance gates. Owner can implement own parsers/pages/read RPCs/receipts/producers using contracts; auth protected store/shared handlers absent means no full runtime-ready claim.

## Decision closure và hồ sơ còn mở

AUD-01 FIXED owned design; AUD-03 FIXED owned contract ambiguity; AUD-02/05/07 PARTIALLY FIXED due Shared implementation/fixture acceptance. AUD-04/06/08/09/10 FIXED documentation, not tests PASS. [Readiness1.2](Implementation_Readiness_v1.2.md) phân biệt owned coding vs end-to-end runtime. [Cross contracts](Cross_Module_Integration_Contracts.md) là exact handoff chưa accepted; không supersede external owner contracts âm thầm. Historical DR logs preserved with supersession pointer.
