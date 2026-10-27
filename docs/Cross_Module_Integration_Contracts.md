# Cross Module Integration Contracts — revision 1.2

Orders/Notifications consumer contract do Bảo OWNER DECIDED. Tất cả interfaces đòi hỏi owner khác thực hiện là **SHARED CONTRACT — NOT ACCEPTED / NOT IMPLEMENTED**, trừ facts SQL chỉ rõ VERIFIED. Không sửa API/schema/implementation của họ trong lượt này. Normative owned DTO/error/receipt ở [Data/API](technical_specification_mh07_mh08_mh09_mh17_data_api.md). Business baseline BR-COM-09–36/CR-07/08/11. Không dùng View/ViewModel khác làm API, không client ghép SQL transactions.

## 1. Common boundary conventions

- UUID đầy đủ, integer VND/counts, server UTC ISO8601 offset. Required field nullable phải có key=null. Unexpected argument/unknown enum -> invalid_argument; missing/malformed response -> unsupported_data, không fake default.
- Public **proposed** operation args `p_*`, own RPC envelope `{ok,data,error}` §5.3. Internal proposed SQL helpers không là client endpoint: trusted principal derived context, PUBLIC/anon/authenticated EXECUTE revoked, return data object hoặc raise controlled condition để caller rollback. Module chủ quản có thể giữ tên internal hiện tại khi mapping chính xác contract này; không coi tên đề nghị đã được họ accept.
- Commands lock order trước tasks/financial rows/variants theo UUID tăng dần. Same business transaction joins shared helpers, no nested independent remote RPC/client request. request identity owner module chịu trách nhiệm; same request returns same result, mismatch idempotency_conflict. Audit/source key must be stable, effects once; generic Orders public events request_id=null không thay existing incident rule.
- Error allowlist owned §5.3; current_order safe id/status only authorized. Dependency unavailable/custody unknown/transient SQL không terminal receipt; terminal state failure no effects. UI capability false + typed warning until implementation and tests verified. SHARED proposal cannot silently override owner actual API.

## CIN-01 — Auth/session/protected pending commands

Owner Dung An/Auth + shared infrastructure; consumers all4screens. **Existing** shared initialized Supabase client only; no feature auth/guard/storage implementation. Interface proposals:

```text
SessionRepository.watchSession() -> Stream<TrustedSession?>
TrustedSession = {user_id:UUID, role:customer|manager|shipper,
                  session_epoch:int>=0, role_resolved:bool}
ProtectedUserStore.write(user_id:UUID,key:String,value:UTF8 JSON) -> void
ProtectedUserStore.read(user_id:UUID,key:String) -> UTF8 JSON|null
ProtectedUserStore.remove(user_id:UUID,key:String) -> void
ProtectedUserStore.listKeys(user_id:UUID,prefix:String) -> List<String>
```

Key namespace `orders.pending/<requestUUID>`, single-record atomic durable write before firstsend; listKeys sameuser namespace permits apprestart without lost key index. Current user only storage access, protected at rest/no plaintext prefs/logs. role server-managed profiles/authoritative source not user_metadata; role unresolved/loading fail closed, role change increments epoch. Account B can't access pending A; logout clears UI, A pending encrypted namespace inaccessible until same A return; app restart sameA restores key/payload (Data/API§7.2.1). Session transport/token expiry unauthenticated, storage unavailable external_dependency_unavailable; no fallback lost key. Login route allowlist provided Auth owner, not invented. Acceptance TX-07/08/09/16,T17-24,FP-05; two-account restart+expired-token tests. Runtime gate all protected screens and mutations; own UI unit/provider overrides can start.

## CIN-02 — Checkout/Inventory placement handoff

Owner Văn Đức Checkout + Inventory shared owner; consumer Orders. VERIFIED orders/items fields/reservation/ledger constraints; placement function missing. Proposed public operation concept `place_order` **name not accepted**, exact consumer result `OrderDto`21keys + `OrderItemDto[]`11keys + canonical order_placed event UUID/source key + `replayed:bool`, all required. Offered exact SHARED request (NOT ACCEPTED): `place_order(p_request_id uuid,p_items jsonb,p_recipient_name text,p_recipient_phone text,p_address_detail text,p_latitude numeric,p_longitude numeric)`; p_items nonempty unique variant entries `{variant_id:UUID,quantity:int>0}`, no duplicates, all args required/nonnull. Customer identity, snapshots/prices/fee/time derived server, no clienttotals/customer override. Mapping existing Checkout API nếu owner có version khác phải cung cấp explicit accepted adapter, không chỉnh implementation họ.

Business: full order reserve atomic, no reserve adding cart, fee30k/Hanoi server validation, snapshot immutable; `UNIQUE(customer_id,request_id)` same key same order, same key changed intent conflict, insufficient stock atomically no order/items/partialreserve/event/notifications. Initial pending_confirmation, job time placed_at server, one order_placed canonical root and CIN-09 Managers alert. Auth current Customer only. Errors forbidden/invalid_argument/insufficient stock through future Checkout code mapped by adapter (offered wire errors insufficient_stock/outside_service_area/invalid_argument/idempotency_conflict/forbidden_or_unavailable; exact owned consumer mapping + external adoption still pending), network submit unknown same-key lookup owner. Acceptance CF-01/T07-04/T07-07,EV-01 + concurrent all-or-nothing stock. Lookup offered SHARED `get_placement_result(p_request_id uuid)` currentCustomer principal returns `{state:committed|not_found,order:OrderDto|null,items:OrderItemDto[],event_id:UUID|null,replayed:bool}`; committed allnonnull order/event, notfound order/eventnull/items[]/replayedfalse, notfound notrollbackproof. Same request reuse normalized recipient/coordinates/items sortedvariantfingerprint, mismatch conflict; server price changes not excuse duplicate placement. Runtime blocked adoption/actualhandler/fixtures; no Checkout API approval.

## CIN-03 — Delivery custody/operational bridge

Owner Minh Đức Delivery MH10/11; consumers MH08/09, Orders cancel and notification producers. VERIFIED delivery task/attempt tables; no commands/pickup evidence producers. Exact projection **offered consumer contract**:

```text
CustodyProjection = {
 order_id:UUID, history_complete:bool, ever_picked_up:bool|null,
 initial_pickup_event_id:UUID|null, picked_up_at:UTC|null,
 current_shipper_id:UUID|null, custodian_task_id:UUID|null,
 phase:unpicked|with_shipper|store_handover_pending|store_received|unknown,
 completed_outbound_attempts:int0..2, active_outbound_task_id:UUID|null
}
```

history_complete=false iff unverified facts; ever_picked_up=null/phaseunknown gates cancel/reassign/receipt; completed attempts from actual delivery_attempts not active-task count. Proof initial dispatch/audit authoritative, accepted_at alone insufficient. Manager only raw custody projection; Customer safe DeliverySummaryDto§4.7, Shipper only currently assigned own task+necessary recipient. Historical proof complete required after task cancellation/deletion, not absence of current task inferred neverpicked.

Proposed internal `private.order_delivery_command(p_order_id uuid,p_action text,p_event_id uuid,p_actor_id uuid,p_payload jsonb)`; caller trusted Orders operation/restricted EXECUTE. actor derived caller context; helper checks manager/current Shipper per action. Result required `{order_id,task_id:UUID|null,custody:CustodyProjection,affected_shipper_id:UUID|null}`; failure authoritative rolled back. Exact action payloads:

| Action | Actor / required payload | Preconditions / output effect |
|---|---|---|
| assign_initial | Manager; `{shipper_id:UUID}` | preparing ready; one active outbound; task1 assigned, awaiting_pickup; pickup proof false |
| reassign_before_pickup | Manager; `{task_id:UUID,shipper_id:UUID,reason:string}` | full no-ever-pickup proof, task current; assignment changes, no attempts reset; old/new affected facts |
| revoke_before_pickup | Manager/Customer Orders cancel trusted; `{reason:string\|null}` | full neverpicked proof; revoke all active tasks same transaction; affected shipper captured before revoke |
| acknowledge_initial_pickup | Current assigned Shipper; `{task_id:UUID}` | awaiting_pickup; dispatch CIN-04 once, audit pickup, delivering |
| arrange_second_attempt | Manager; `{task_id:UUID}` | failure1, same custodian; create NEW outboundtask2 assigned; order awaiting_redelivery, no redispatch |
| acknowledge_retained_retry | Current same custodian Shipper; `{task_id:UUID}` | new task2assigned/custodyretained; order delivering, counter stays1 until result; no dispatch |
| request_store_return | Manager; `{task_id:UUID,reason:string}` | after failure1 early or failure2 mandatory; cancel unacked task2 if any, use actual custodian leg; awaiting_store_return |
| declare_store_handover | Current custodian Shipper; `{task_id:UUID,items:[{order_item_id:UUID,received_quantity:int>=0}]}` | return leg at store; immutable event not Manager receipt/inspection; no restock |
| record_store_receipt | Manager; same items payload | physically received quantities validated against issued ledger; task returned_to_store, order awaiting_store_return; no stock increase |

Reason normalize Data/API§7.2.1, manager reason required1..1000; quantities unique/all issued lines required. Missing/partial may record fact but not classify final sellable/close; goods_discrepancy remains unresolved. Stock dispatch joins CIN-04 in same order transaction, not call client RPC twice. At most2 outbound completed results across all tasks; `task_kind=outbound`, UNIQUE(task_id/order,attempt) prevents retry overwriting task1. Outbound result command belongs Delivery: public name/request draft **not approved here**, must exact payload `{task_id,request_id,result:success|failed,reason:string|null}` and serverowned timestamps/shipper; success requires entire goods/full COD CIN-05; failure nonblankreason. Client amount cannot overwrite originalCOD.

Store-leg projection required `{task_id:UUID,order_id:UUID,navigation_mode:store_return,store_name:string,store_address:string|null,store_latitude:number|null,store_longitude:number|null,amount_to_collect_now_vnd:0}` from store_settings singleton. Original outbound customer address/COD fields unchanged; no return_pickup without ReturnRequest, no Customer-location fallback; absent coordinates store_location_unavailable. Missing handler -> external_dependency_unavailable, missing custody -> custody_unverified, conflict -> state_changed, thirdattempt -> invalid_argument/state_changed mapped owner agreed wire. Acceptance T09-12–17/T09-25–28,TX-30,EV-06–09. **Shared flow recommended, NOT ACCEPTED; transfer after physical pickup requires business decision.**

## CIN-04 — Inventory ledger bridge

Owner Inventory shared module; consumers Orders/Checkout/Delivery. Proposed internal `private.apply_order_inventory_event(p_order_id uuid,p_event_id uuid,p_effect text,p_items jsonb,p_actor_id uuid,p_reason text)` returns required `{event_id:UUID,order_id:UUID,movements:[{variant_id:UUID,on_hand_delta:int,reserved_delta:int,damaged_delta:int}]}`. Trusted caller only, never Flutter directly. `p_effect=release|dispatch|inspect_undelivered`; quantities aggregated pervariant while retaining order-item inspection facts.

- release payload full reserved order lines `{order_item_id,quantity}`; cancelled/rejected predispatch releases reserved once, on_hand unchanged. Reservation must belong order; replay same event yields existing movements, never release twice.
- dispatch payload full reserved lines `{order_item_id,quantity}`; initial pickup only, on_hand−qty/reserved−qty once; retained retry no call. Canonical event+variant unique current schema.
- inspect_undelivered payload all unique issued items `{order_item_id,received_quantity,sellable_quantity,damaged_quantity}` ints≥0; sellable+damaged=received=issued for closure. on_hand +=sellable; damaged +=damaged; reserved delta0. Existing available=on_hand−reserved: damaged **not** on_hand. Missing/lost→goods_discrepancy, no partial automatic closure/restock under baseline.

Inspection aggregate one movement pervariant/event; proposed kind restock if sellable_delta>0 (even damaged_delta also positive), else damage when only damaged_delta>0, never zero-effectrow. kind is actual inventory_movement_kind enum; this offered rule requires Inventory owner acceptance.

Business event/root receipt shared transaction; event UUID mismatch/movement payload mismatch -> idempotency_conflict/data_integrity no effects. Manager inspection auth, dispatch current assignedShipper via Delivery trusted bridge; no arbitrary actor. No client service-role key. Acceptance TX-01–04/20/21/28–30,T09-07/09/14/27–28,T07-09,TX-29–33. Reservation placement external CIN-02 request remains Checkout-owned. Runtime disabled until ledger/custody transaction proof exists.

## CIN-05 — COD projection/producer

Owner Minh Đức COD; consumers OrderDetails and Notifications. DTO exact CODSummaryDto/DataAPI§4.6 keys, safeCustomer§4.7. Read internal `get_order_cod_summary(order_id:UUID,caller context) -> CODSummaryDto|null`; no record means null/unavailable, not fake received. Proposed received producer callback CIN-09 typecod_received uses subject cod/order UUID, collecting_shipper_id from COD original obligation. Only Manager confirms full received amount; collected atomically with successful delivery fullCOD; no partial/offsetreturn. Return does not cancel/erase shipper obligation. Public record/reconcile request shape/API stays COD owner, needs exact accepted adapter mapping before wiring MH12 link. Authorization Manager/allauthorized, Customerown safe, Shipperown COD even historical task reassigned (backend COD scope, not raw Order). Acceptance T09-03/15/16,TX-19,EV-07/10; handlers/UI missing, schema only VERIFIED.

## CIN-06 — Returns summary/read/routes

Owner Sơn Returns; consumers MH07/09/17. Proposed safe internal `get_order_return_summaries(order_id:UUID,caller context)->ReturnSummaryDto[]` exact DataAPI§4.6; empty only successful authoritative read of none, unavailable null/dependency marker never [] manufactured. is_active exact active-return unique-index statuses, one active perorder. Customer own/Manager only, no bank/video/payment evidence in Orders DTO/notification. Full merchandise+originalfee refund recorded externally with evidence at MH15; pickupapproved notrefundapproved; rejectedafterinspection free redelivery COD0; failed remains manager resolution, not closed/delivered-order cancelled. Routes proposed `/customer/returns/:returnId`, `/manager/returns/:returnId` must owner accept. Errors deniedgeneric/state_changed/external_dependency_unavailable; public Return requests/status migrations not changed here. Acceptance T07-17–20,T09-03/16,TX-19,EV-11–21; implementation missing.

## CIN-07 — Catalog context

Owner Văn Đức/catalog shared; consumer Orders. Existing order_items.product_id/variant_id/name/variant_label/attributes/unit_price/quantity snapshots VERIFIED. Proposed route resolver `resolveProduct(product_id:UUID)->{available:bool,product_id:UUID}` with existing catalog access; unavailable -> genericunavailable. Own order text/prices never livecatalog overwrite. No historical image snapshot column; owner baseline neutral placeholder, current catalog image optional only explicit current-preview labeling if supplied later, not prerequisite. No Mua lại contract baseline, no auto-cart mutation. Acceptance T07-04/21/22, missingroute optional; core Orders read not blocked by thumbnail.

## CIN-08 — authoritative return eligibility/cutoff

Owner Returns + business group; consumer Customer MH07. Proposed `get_order_return_eligibility(order_id:UUID)` authenticatedown -> required `{order_id:UUID,eligible:bool,blocked_reason:outside_window|not_delivered|active_return|unauthorized_or_unavailable|missing_contract|null,deadline_at:UTC|null,active_return_id:UUID|null,as_of:UTC}`. GroupBR23 says within7days at submission; exact inclusive/calendar-vs-elapsed boundary unresolved. Consumer does not invent deadline from device clock. Eligibility advisory, create-return submit MUST recheck server time/video/reason/bank/fullreceivedgoods/active request atomically. Until agreed cutoff+actual authoritative API, can_open_return_creation=false, active known request navigation allowed. Owner errors must map forbidden/validation/state/time codes before adapter integration. Acceptance T07-17–20; boundary fixtures blocked businessdecision, no hiddenpolicychosen.

## CIN-09 — typed event registration/notification producer

Owner Notifications interface Bảo; producer owners Checkout/Delivery/COD/Returns/Chat. **Own Orders event policy OWNER DECIDED; external acceptance pending.** Proposed private trusted helpers within producer SQL transaction:

```text
register_business_event_contract(
 p_root_event_id:UUID|null,p_event_type:String,p_event:BusinessEventInput,
 p_origin_module:String,p_source_operation_key:String,
 p_actor_source:customer|manager|shipper|system,p_facts:SourceFacts
) -> canonical event_id:UUID
BusinessEventInput required: actor_id:UUID|null,subject_type:String,subject_id:UUID,
 from_state:String|null,to_state:String|null,reason:String|null,task_id:UUID|null,
 incident_kind:damaged|lost|other|null,request_id:UUID|null
emit_notifications(p_event_id:UUID,p_event_type:String,p_origin_module:String,
 p_source_operation_key:String,p_actor_source:String,p_facts:SourceFacts)
 -> UUID[]   // stable sorted notification IDs from frozen manifest
SourceFacts required keys (each UUID|null): order_id,task_id,return_request_id,
 customer_id,assigned_shipper_id,previous_shipper_id,collecting_shipper_id,
 conversation_id,sender_id
```

register creates/reuses canonical public event plus private metadata under source identity advisory lock, validates business_event subject/object graph, trusted actor and source logical key; stable origin/key tuple (§7.4) returns canonical identity, changed facts conflict. Helper owns public row creation/reuse in same producer transaction; server creates UUID/time (not p_event_id fromclient). Stored required event_fingerprint (§7.4) includes exact public fields + type/actorSource/root/sourcefacts, excluding allocated UUID/time. Root p_root_event_id=null→newid selflink; child uses realroot and stable source key suffix /audit/<event_type>/<subjectUUID>. Unique(origin_module,source_operation_key) blocks changedtype/subject too, not only fulltype tuple. Arbitrary client events denied; genericOrdersrequest_id=null, incident requestnonnull existingCHECK. Actor derived caller, payload never client authorization. Root metadata selflink, children directroot, constraint nochain/cycle; helper verify declared parent type/ownership. SourceFacts includes all9keys null irrelevant; no recipientlist/clientrole/textPII accepted. server derives customer/shipper/Managers from locked actual rows/trusted business change; verify supplied snapshots exactly at initial emit. On replay frozen manifest read BEFORE live-target/role recomputation; changed facts conflict. Current recipient-set changes cannot generate new notification rows. Raw metadata manifests client denied. Atomic notification failure aborts producer business transaction; owner must not swallow failure and report businesssuccess.

| Event type exact | Module / required non-null facts (all other keys null unless described) | Recipients / typed target |
|---|---|---|
| order_placed | checkout; order_id,customer_id | allManagers → order/order_id |
| order_confirmed_manual | orders; order_id,customer_id | Customer → order/order_id |
| order_confirmed_automatic | orders; order_id,customer_id | Customer + allManagers → order/order_id |
| order_rejected | orders; order_id,customer_id | Customer → order/order_id |
| order_cancelled | orders; order_id,customer_id; assigned_shipper_id nullable pre-revoke, task_id nullable iff none | Customer → order; affectedShipper → notification_only/root event UUID |
| task_assigned / task_reassigned (two exact types) | deliveries; task_id,order_id,customer_id,assigned_shipper_id; return_request_id iff nonoutbound; previous_shipper_id nullable | currentShipper → delivery_task/task_id; old reassignedShipper no new alert baseline, old existing target rechecks rights |
| outbound_delivered | deliveries; order_id,customer_id,task_id,assigned_shipper_id | Customer → order/order_id |
| outbound_failed | deliveries; order_id,customer_id,task_id,assigned_shipper_id | allManagers → order/order_id |
| custody_incident | deliveries; order_id,customer_id,task_id,assigned_shipper_id | allManagers → delivery_task/task_id; authorized task→orderMH09 |
| cod_received | cod; order_id,customer_id,collecting_shipper_id | collectingShipper → cod/order_id |
| return_submitted | returns; order_id,customer_id,return_request_id | allManagers → return_request/return_request_id |
| return_pickup_approved | returns; order_id,customer_id,return_request_id,task_id,assigned_shipper_id | Customer → return_request; Shipper → delivery_task; **one parent emits**, assignment child audit-only |
| return_initial_rejected | returns; order_id,customer_id,return_request_id | Customer → return_request |
| return_pickup_failed | deliveries; order_id,customer_id,return_request_id,task_id,assigned_shipper_id | allManagers → return_request, task.return_request_id mandatory |
| return_collection_rescheduled | returns; order_id,customer_id,return_request_id,task_id,assigned_shipper_id; previous_shipper_id nullable | Customer → return_request; currentShipper → delivery_task; old changedShipper → notification_only; parent only emits |
| return_more_evidence_requested | returns; order_id,customer_id,return_request_id | Customer → return_request |
| return_inspection_rejected | returns; order_id,customer_id,return_request_id | Customer → return_request |
| refund_recorded | returns; order_id,customer_id,return_request_id | Customer → return_request |
| rejected_goods_redelivery_assigned | returns; order_id,customer_id,return_request_id,task_id,assigned_shipper_id | currentShipper → delivery_task; assignment child audit-only |
| rejected_goods_redelivery_completed | deliveries; order_id,customer_id,return_request_id,task_id,assigned_shipper_id | Customer → return_request |
| rejected_goods_redelivery_failed | deliveries; order_id,customer_id,return_request_id,task_id,assigned_shipper_id | allManagers → return_request |
| support_message_received | chat; conversation_id,customer_id,sender_id | Customer message → allManagers except sender; Manager message → conversationCustomer; noShip/no self |

Manager set server profiles.role=manager singleStore, dedup Customer/Manager overlaps not possible trustedroles. Old rescheduledShipper policy is concrete **Shared proposal**, affected-users original requires producer review; not external ownerapproved. Ordercancel assigned snapshot must captured before revoke. All sourcefacts verify FK graph plus task kind; returnevent not null ReturnUUID; cod order ID not task; Chat sender role and conversation owner verified. Titles/bodies fixed localized event templates (main§9.2), no reason/address/phone/bank/evidence links; localization key event type no arbitrary producer text. event_type exact used domain timeline only classified safe; audit-only own types `order_pickup,order_store_handover,order_store_received,order_inventory_inspected,task_assignment_audit`, never auto notification without tableentry.

Dedup: source-operation unique metadata + frozen manifest + existing(recipient,event) unique. No newevent retry, no parentandchildShipdoublealert, profiledeletedmanifestpreserved/no recreation. Notification persistence distinct from read/chat state. Target owner must provide current-authorization fetch; revoked assignedShipper gets MSG63. Acceptance EV-01–22, T17-25/28–31,TX-17/21/32/33; eachproducer supplies real transaction/rollback/replay/recipient-change fixtures. **No producer currently implemented**, including owned Orders. Inbox raw schema/grants/readtrigger exist, client readers missing.

## 2. Handoff acceptance record

| Contract | Requested acknowledgment | Current status | Coding boundary |
|---|---|---|---|
| CIN-01 | Auth role stream/loginroute/protected persistence tests | NOT ACCEPTED / missing | own state/VM tests possible; live session dependent |
| CIN-02 | Checkout exact place request/errors/replay fixture | NOT ACCEPTED / missing | own OrderDTO done design; real placement dependent |
| CIN-03/04 | Delivery recommendedcustodyflow + Inventory ledger signatures/atomicity | NOT ACCEPTED / missing | own cancellation/capability interface; actions disabled until proof |
| CIN-05/06 | Safe projections/code mapping/actual reads | NOT ACCEPTED / missing | render null/unavailable; avoid financial defaults |
| CIN-07 | catalog route access | NOT ACCEPTED / route missing | placeholder is owner baseline, no core blocker |
| CIN-08 | business7-dayedge and authoritative eligibility | REQUIRES BUSINESS DECISION / missing | no create-return enablement based localclock |
| CIN-09 | eachproducer typedroot/facts/transaction fixtures | Own subset OWNER DECIDED; others NOT ACCEPTED | own consumer/4own events can code; external triggers unavailable |

Acceptance owner name/date/reviewed revision/tests/environment actual outputs must be attached when accepted; signature placeholder/consumer decision is not agreement. Only shared documents pointer to offered contract, no change to other owner's existing tables/APIs in this revision. Unknown external error/RPC transport remains an integration gate, not a guessed implementation.

## 3. Exact external read/deep-link adapter offers

Each method consumer-owned contract, target owner accepts concrete route/adapter mapping; no new main screen. Return Result<T,AppFailure> using consumer codes §5.3, backend currentpermission mandatory, nonexistent/denied generic.

| ID | Proposed interface / exact result | Authorization / gates |
|---|---|---|
| CIN03-R | `resolveDeliveryTask(task_id:UUID)->{task_id:UUID,order_id:UUID,kind:DeliveryTaskKind,assigned_shipper_id:UUID\|null}` | Manager targettask→OrderMH09; currentassignedShipper→MH11; Customerdenied; storeleg info separate CIN03 |
| CIN05-R | `resolveCod(order_id:UUID)->CODSummaryDto` | Manager/collectingShipper ownscope; return/render nullcount not financialsuccess; `/cod?orderId=` ownerpending |
| CIN06-R | `resolveReturn(return_id:UUID)->{return_id:UUID,order_id:UUID,status:ReturnRequestStatus}` | OwnCustomerMH14/ManagerMH15, ShipperrawReturndenied; no bank/video |
| CIN09-CHAT | `resolveConversation(conversation_id:UUID)->{conversation_id:UUID,customer_id:UUID}`; `openCustomerConversation(customer_id:UUID)->same` | OwnCustomer/Manager, uniqueconversationperCustomer; Shipperdenied; CHATowner routes `/chat/:conversationId` proposed, business textonly |

Acceptance each read allowed/denied/currentroleloss/nonexistent/invalidUUID/network/timeout, deep-link T17-10–16/23–27 plus T09-16. No route accepted claim; cross-module future function names can differ only explicit mapped accepted interface, not inferred from rawSQL.
