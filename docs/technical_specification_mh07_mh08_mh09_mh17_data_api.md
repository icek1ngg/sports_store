# Phụ lục Data Dictionary và API Contracts cho MH07 MH08 MH09 MH17

Tài liệu đi cùng [đặc tả chính](technical_specification_mh07_mh08_mh09_mh17.md). `VERIFIED IN CODEBASE` nghĩa có trong ba migration kết hợp, không xác nhận cloud hiện tại. Revision 1.2: thiết kế Orders/Notifications là `OWNER DECIDED — PROPOSED IMPLEMENTATION` (chưa có implementation); interfaces module khác là `SHARED CONTRACT — NOT ACCEPTED`. Không có source implementation được tạo bởi phụ lục này.

## 1. Quy ước dữ liệu và phân lớp

| SQL/wire | Dart domain `PROPOSED` | Validation |
|---|---|---|
| uuid | String | UUID hợp lệ; không dùng DH code/rút gọn làm route param |
| bigint/smallint | int | Whole VND/quantity; không float; không đổi đơn vị |
| numeric(9,6) | double dùng tọa độ | Có thể wire là number/string theo adapter; parse finite và range; không dùng cho tiền |
| timestamptz ISO8601 | DateTime UTC | Require offset; hiển thị Hanoi UTC+07:00; không clock client quyết eligibility |
| jsonb object | Map<String,Object?> immutable | Reject list/scalar khi object yêu cầu; không giả định attributes luôn có size/color |
| text[] | List<String> | Paths không null/rỗng; permission private storage |
| enum | Exact typed enum + unsupported representation | Giữ raw unknown string trong failure/unsupported view; không default pending |

Database entity là table row. API DTO ánh xạ wire keys sang domain, không mang widget/theme. Domain models immutable thuộc owner feature. UI state chứa filter/loading/error/action, không thêm các trường đó vào DB. `OrderDetails` là response aggregate, không table. `OrderTimelineEntry` map `business_events`, không có bảng `order_status_history`. Notifications mỗi row/người nhận đủ read-state, không cần tạo `notification_recipients` song song.

## 2. Database entities verified

### 2.1 Order — `public.orders`

Source: `supabase/migrations/20261006034251_sports_store_schema.sql::public.orders`. Tất cả field sau `VERIFIED IN CODEBASE`.

| Field | Type | Nullable | Description | Source | Validation |
|---|---|---|---|---|---|
| id | uuid | Không | Business ID của order | DB gen_random_uuid | PK |
| customer_id | uuid | Không | Người mua | FK profiles.id | Backend own scope; không customer chọn người khác |
| request_id | uuid | Không | Idempotency placement | Caller placement contract | UNIQUE(customer_id,request_id), không dùng làm key confirm/cancel |
| status | order_status | Không | 10 trạng thái order | DB default pending_confirmation | Enum; transition còn thiếu RPC |
| recipient_name | text | Không | Snapshot người nhận | Checkout | btrim khác rỗng |
| recipient_phone | text | Không | Snapshot điện thoại | Checkout | Nonblank; phone format chưa ký |
| address_detail | text | Không | Snapshot địa chỉ chi tiết | Checkout | Nonblank; Hanoi validation workflow chưa có |
| latitude | numeric(9,6) | Không | Snapshot tọa độ | Checkout | -90..90; range chưa đủ xác nhận Hà Nội |
| longitude | numeric(9,6) | Không | Snapshot tọa độ | Checkout | -180..180 |
| subtotal_vnd | bigint | Không | Merchandise subtotal | Placement server | >=0; bằng sum line totals là RPC responsibility |
| delivery_fee_vnd | bigint | Không | Phí original | Server default 30000 | CHECK =30000 |
| total_cod_vnd | bigint generated | Không | subtotal + fee | DB | Read-only generated |
| delivery_attempt_count | smallint | Không | Counter toàn order | Server workflow | Default0; CHECK0..2; không reset reassign |
| placed_at | timestamptz | Không | Đặt thành công | DB default now | Deadline server; bất biến theo proposed operation contract |
| confirmed_at | timestamptz | Có | Mốc confirm | Future transition | Không invent khi null |
| source | order_confirmation_source | Có | manager/automatic | Future transition | Không client tự gửi automatic |
| confirmed_by | uuid | Có | Manager confirm | FK profiles, on delete set null | Automatic đề xuất null + typed system event |
| delivered_at | timestamptz | Có | Mốc customer nhận đủ/thu đủ | Delivery transaction | Return không thay mốc |
| cancel_reason | text | Có | Lý do cancel | Future cancellation | Manager mandatory reason ở server; rejection không dùng field này; canonical order_rejected event.reason ownerdecided |
| created_at | timestamptz | Không | Row creation | DB | Default now |
| updated_at | timestamptz | Không | Last mutation | private.set_updated_at | Không thay history hoặc optimistic version toàn workflow |

Không có `order_code`, `rejection_reason`, `cancelled_at`, `rejected_at`, `discount_vnd`, ETA, OTP hoặc order image. Proposed human code cần immutable UNIQUE và backfill/migration an toàn, chưa quyết tên cột chính thức. Baseline hiển thị UUID có thể copy đầy đủ; identifier rút gọn chỉ presentation nếu nhóm đồng ý, luôn có full ID và không dùng search/route key rút gọn.

### 2.2 OrderItem — `public.order_items`

Source schema migration `public.order_items`; tất cả verified.

| Field | Type | Nullable | Description | Source | Validation |
|---|---|---|---|---|---|
| id | uuid | Không | Line identity | DB | PK |
| order_id | uuid | Không | Parent order | FK orders | Ownership via RLS |
| product_id | uuid | Không | Catalog reference | FK products | Không thay snapshot bằng product hiện tại |
| variant_id | uuid | Không | Variant reference | FK product_variants | UNIQUE(order_id,variant_id) |
| product_name | text | Không | Name snapshot | Placement | Nonblank |
| variant_label | text | Không | Variant snapshot | Placement | Nonblank |
| attributes | jsonb | Không | Attribute snapshot | Placement, default {} | Object; optional keys |
| unit_price_vnd | bigint | Không | Giá lúc đặt | Placement server | >=0 |
| quantity | bigint | Không | Ordered quantity | Placement | >0 integer |
| line_total_vnd | bigint generated | Không | unit_price * quantity | DB | Read-only |
| created_at | timestamptz | Không | Row creation | DB | Default now |

`PROPOSED`: item image snapshot field/path chỉ bổ sung nếu nhóm duyệt. Current `products.image_path` nullable, catalog customer RLS ẩn inactive product; JOIN không được inner-filter làm mất old item. Existing private product-images policy cho customer/manager đọc objects, nhưng path lịch sử chưa được lưu. Placeholder là fallback đầy đủ chức năng; ảnh catalog hiện tại nếu chọn dùng phải ghi không bảo đảm snapshot và cache account-scoped signed URLs.

### 2.3 Profile — `public.profiles`

Source schema `public.profiles`, access `profiles_read`, trigger `private.handle_new_user`; verified.

| Field | Type | Nullable | Description | Source | Validation |
|---|---|---|---|---|---|
| id | uuid | Không | Auth user ID | FK auth.users | PK; role identity auth.uid |
| role | user_role | Không | customer/manager/shipper | Trusted server | Default customer; không user_metadata auth |
| full_name | text | Có | Tên tài khoản | Auth profile | Có thể null; không có nonblank CHECK |
| phone | text | Có | Account contact | Auth trigger new.phone | Khác order recipient_phone; có thể thiếu với email auth |
| created_at | timestamptz | Không | Creation | DB | Default now |
| updated_at | timestamptz | Không | Update | Trigger | Không phải last online |

Manager được xem profiles; customer/shipper chỉ profile mình. Không có loyalty/member level, duty availability, active-account flag trong table baseline. BR-LOGIN-02 yêu cầu active account nhưng enforcement app/database chưa xác minh; Auth owner chốt ban/session behavior. Không mở rộng Auth screen trong blueprint Bảo.

### 2.4 BusinessEvent — `public.business_events`

Source schema `public.business_events` + simplify ALTER/policy; verified fields.

| Field | Type | Nullable | Description | Source | Validation |
|---|---|---|---|---|---|
| id | uuid | Không | Stable source event | DB default UUID | PK; notification FK |
| actor_id | uuid | Có | Actor | profiles FK set null on delete | Null không tự chứng minh system |
| subject_type | text | Không | Entity kind | Server producer | Nonblank; raw text chưa DB-enforced; owner typed policy §7.4/CIN09 finalized |
| subject_id | uuid | Không | Subject ID | Producer | Không polymorphic FK; server phải kiểm tra liên kết |
| from_state | text | Có | Trước transition | Producer | Nonblank nếu có; domain validation typed theo kind |
| to_state | text | Có | Sau transition | Producer | Như trên |
| reason | text | Có | Reason/audit | Producer | Incident bắt nonblank; other rule enforced RPC missing |
| created_at | timestamptz | Không | Event timestamp | DB now | Audit immutable to clients |
| task_id | uuid | Có | Task incident/reference | Simplify FK tasks | Bắt có cho incident |
| incident_kind | delivery_incident_kind | Có | damaged/lost/other | Simplify | Non-null đòi subject_type delivery_task, subject_id=task_id, actor/request/reason |
| request_id | uuid | Có | Existing idempotency slot | Simplify UNIQUE(request_id) | Generic events còn nullable; chưa enough replay result |

Read policy cuối: manager tất cả; shipper chỉ own incident on currently assigned task; customer không raw read. Không có `event_kind`, `causation_event_id`, payload old/new JSON hay result receipt. `PROPOSED` mở rộng event discriminator/causation ở §7; không suy luận mọi event type bằng title hoặc from/to text.

### 2.5 Notification — `public.notifications`

Source schema `public.notifications`; access policies + `private.stamp_read_time`; verified.

| Field | Type | Nullable | Description | Source | Validation |
|---|---|---|---|---|---|
| id | uuid | Không | Notification identity | DB | PK |
| recipient_id | uuid | Không | Individual recipient | profiles FK | RLS own; server selected |
| event_id | uuid | Không | Source event | business_events FK | UNIQUE(recipient_id,event_id) |
| subject_type | text | Không | Target entity kind | Producer | Nonblank; allowlist proposed |
| subject_id | uuid | Không | Target UUID | Producer | No FK; validate type/link/access |
| title | text | Không | Display heading | Producer | Nonblank; plain text |
| body | text | Không | Safe event message | Producer | Nonblank; no bank/private payload |
| read_at | timestamptz | Có | Null unread; first read time | Server trigger | Preserve first non-null; cannot mark unread |
| created_at | timestamptz | Không | Persisted creation time | DB | Stable ordering with id |

Không có separate `is_read`, icon, arbitrary deep_link_url, JSON payload hoặc notification_type column. UI computed `isRead=read_at != null`. Icon/route dùng allowlisted subject contract; notification có thể giữ sau target access revoked. Không join raw `business_events` cho customer để lấy event icon vì policy denies.

## 3. External-owner projections cần cho bốn màn

Chỉ các field cần đọc/tích hợp, không redesign model/schema module khác. Các cột source sau verified, projection shape proposed.

### 3.1 DeliverySummary / AttemptSummary (`PROPOSED` DTO)

| Field DTO | Type | Nullable | Description | Source verified | Validation |
|---|---|---|---|---|---|
| taskId | UUID String | Có | Current relevant outbound task | delivery_tasks.id | Không gán return_pickup làm outbound |
| kind | exact kind | Có | outbound/return_pickup/redelivery | delivery_tasks.kind | Tách original delivery và post-return redelivery |
| taskStatus | task enum | Có | Current task state | delivery_tasks.status | Không map thành order.status |
| assignedShipperId | UUID String | Có | Assignment | delivery_tasks.assigned_shipper_id | Chỉ manager summary cần, customer projection null |
| assignedShipperName | String | Có | Shipper display | profiles.full_name | Authorized manager read; không yêu cầu customer raw profile |
| assignedAt | DateTime | Có | Assignment time | delivery_tasks.assigned_at | Server time |
| acceptedAt | DateTime | Có | Task acceptance | delivery_tasks.accepted_at | Không assume store pickup until meaning signed |
| startedAt | DateTime | Có | In-transit start | delivery_tasks.started_at | Owner xác định custody meaning |
| completedAt | DateTime | Có | Result/complete | delivery_tasks.completed_at | Không tự suy ra delivered_at |
| amountToCollectVnd | int | Có | COD requirement | delivery_tasks.amount_to_collect_vnd | Non-outbound0; outbound full order contract |
| attemptCount | int | Không | Total outbound attempts | orders.delivery_attempt_count | 0..2; không sum task rows |
| latestAttempt | AttemptSummary | Có | Latest actual result | delivery_attempts | Sort attempt_number DESC then occurred_at/id |
| failureReason | String | Có | Task/result reason | task.failure_reason/attempt.reason | Không fabricate; actual result ưu tiên attempt |

AttemptSummary fields: id UUID not-null, task_id UUID not-null, order_id UUID not-null, attempt_number smallint1..2, task_kind outbound, result success/failed, reason nullable; raw/Manager failed nonblank, Customer sanitized reason=null, occurred_at DateTime not-null, shipper_id UUID nullable trong safe DTO (Customer null), database entity vẫn NOT NULL. Source `delivery_attempts` có UNIQUE task_id và `(order_id,attempt_number)`. Customer raw attempts được đọc own, customer projection không expose shipper PII không cần thiết.

Current outbound selection `PROPOSED`: active task theo existing partial unique index trước; nếu không active, latest outbound task theo `(created_at DESC,id DESC)`. Nếu source vi phạm invariant nhiều active, trả data_integrity failure thay vì tùy chọn row. Historical completed task vẫn ở detail timeline, không overwrite current return/redelivery. CIN03 custody projection exactconsumer contract, externalacceptance pending; accepted_at không pickup proof.

### 3.2 CODSummary (`PROPOSED` domain projection)

| Field | Type | Nullable | Description | Source verified | Validation |
|---|---|---|---|---|---|
| orderId | UUID | Không | COD record PK | cod_collections.order_id | FK orders |
| shipperId | UUID | Có | Collecting shipper | shipper_id | Customer projection null nếu không cần |
| status | cod_status | Không | uncollected/collected/received | status | Separate enum |
| expectedAmountVnd | int | Không | Full expected | expected_amount_vnd | >0; expected=order total là workflow check missing |
| collectedAmountVnd | int | Không | Customer paid | collected_amount_vnd | 0 uncollected; full collected/received |
| receivedAmountVnd | int | Không | Store cash | received_amount_vnd | 0 trước received; full received |
| collectedAt | DateTime | Có | Collection | collected_at | Server operation |
| collectedBy | UUID | Có | Actor collection | collected_by | No client-authorized financial writes |
| handedOverAt | DateTime | Có | Cash handover metadata | handed_over_at | Chưa workflow cho shipper tự mark handover |
| receivedAt | DateTime | Có | Store receipt | received_at | Chỉ manager full receipt |
| receivedBy | UUID | Có | Manager | received_by | Role check RPC |

Null `codSummary` khi không có row là unknown/missing, không fabricate `uncollected`. Retry/reconciliation không offset refund, original amount không thay.

### 3.3 ReturnSummary / eligibility handoff (`PROPOSED`)

| Field | Type | Nullable | Description | Source | Validation |
|---|---|---|---|---|---|
| returnId | UUID | Không | Return reference | return_requests.id verified | Owner/order relationship |
| orderId | UUID | Không | Parent | return_requests.order_id verified | Composite FK customer |
| status | return enum | Không | Separate lifecycle | return_requests.status verified | Không đổi delivered order |
| submittedAt | DateTime | Không | Submission | submitted_at verified | Deadline measured here |
| closedAt | DateTime | Có | Closed | closed_at verified | Active state definition theo existing partial index |
| decisionReason | String | Có | Return decision | decision_reason verified | Only authorized roles |
| isActive | bool computed | Không | Active request | Existing index statuses | Không chỉ closed_at null; exact index predicate authority |
| canSubmitReturn | bool | Không | Advisory current eligibility | Future Returns RPC `PROPOSED` | Server check again at submit |
| eligibilityReason | safe error enum | Có | Why denied | CIN08 offered enum | No bank details/evidence |
| returnDeadline | DateTime | Có | Deadline presentation | Future server calculation | Inclusive/calendar boundary chưa signed |

Không đọc toàn bộ return row vào notification/timeline để lấy bank fields. Manager/customer RLS có quyền đọc return_requests nhưng projections bốn màn chỉ chọn summary cần thiết. Evidence/payment receipt xử lý ở MH14/15 owner Returns.

## 4. Proposed DTOs, Domain Models và UI state fields

Bảng Orders/Notifications mục này `OWNER DECIDED — PROPOSED IMPLEMENTATION`, không DB columns; external projection semantics là SHARED CONTRACT ở Cross_Module_Integration_Contracts.md. Source class chưa tồn tại. JSON wire dùng snake_case; domain dùng lowerCamelCase.

### 4.1 Query và list response

| Field | Type | Nullable | Description | Source | Validation |
|---|---|---|---|---|---|
| query.search | String | Có | Trimmed search | UI | max200 Unicode scalar values owner decided; parameterized, escape wildcard |
| query.statuses | List<OrderStatus> | Không | Selected enum values | UI | Empty=all; only real enum |
| query.cursor | String opaque | Có | Server keyset cursor | Prior response | Bound to query/user; invalid→invalid_cursor |
| query.limit | int | Không | Page size | UI default20 | 1..100; ngoài range invalid_argument, không clamp |
| response.items | List<OrderSummary> | Không | Matching page | Server projection | Scope user; no duplicate IDs |
| response.next_cursor | String | Có | More marker | Server | Null=end; stable `(placed_at,id)` |
| response.total_count | int | Không | Whole matching result count | Server | Không page length |
| response.status_counts | Map<enum,int> | Không | Distribution query excluding status filter | Server | Same role/search/as_of; Require all 10 enum keys với count0 cho trạng thái không có đơn; key unknown unsupported |
| response.as_of | DateTime | Không | Read snapshot time | Server | UTC timestamp |

OrderSummary DTO fields:

| Field | Type | Nullable | Description | Source | Validation |
|---|---|---|---|---|---|
| order | OrderDto đầy đủ §2.1 | Không | Toàn bộ 21 keys, cùng mapper list/detail/receipt | orders | Exact required fields; no updated amount from catalog |
| customer_display_name | String | Có | Account name manager only | profiles.full_name | Distinct recipient snapshot |
| item_preview | List<OrderItem> | Không | First up to2 items | order_items | `PROPOSED` order by created_at,id; actual all rows in detail |
| item_line_count | int | Không | Number of variant rows | COUNT items | Không gọi quantity tổng là line count |
| item_quantity_total | int | Không | Sum quantity | SUM items | Nonnegative expected; no partial page sum |
| delivery_summary | projection | Có | Authorized relevant task/attempt | §3.1 | Customer sanitized variant only |
| cod_summary | projection | Có | Financial state | §3.2 | Missing not zero-confirmed |
| return_summary | projection | Có | Active/latest reference | §3.3 | Active first then latest submitted/id |
| warnings | List<Warning> | Không | Derived failures/incidents/action needs | Actual attempt/event/state | Typed code/source_id/message; proposed not DB |
| capabilities | OrderCapabilities | Không | Allowed UI actions at as_of | Future server preconditions | Advisory only; mutation recheck |

### 4.2 OrderDetails DTO / OrderTimelineEntry

| Field | Type | Nullable | Description | Source | Validation |
|---|---|---|---|---|---|
| order | Order | Không | Full snapshot | orders | Own/manager RLS |
| items | List<OrderItem> | Không | Full lines | order_items | Do not omit inactive catalog rows |
| buyer | Profile summary | Có | Manager name, ID | profiles | No unrelated profile PII |
| delivery_summary | DeliverySummaryDto | Có | Current relevant outbound summary, timeline chứa historical tasks | Delivery owner | Customer safe projection; no raw tasks baseline |
| cod_summary | CODSummary | Có | Current obligation | cod_collections | Separate status |
| return_summaries | List<ReturnSummary> | Không | History/reference | Returns owner | No sensitive bundle |
| timeline | List<OrderTimelineEntry> | Không | Full sorted actual audit trong một response aggregate | business_events + related projections | Customer sanitizer required; không silently truncate |
| history_complete | bool | Không | All expected events available | Server projection | false if fallback-only; no fake timeline completion |
| capabilities | OrderCapabilities | Không | Cancel/confirm/reject/handoff current | Server proposal | No security bypass |
| as_of | DateTime UTC | Không | Authority read snapshot time, không alias server_time | Server | Must not supplied client |

OrderTimelineEntry fields: eventId String? (null fallback milestone), sourceEntityType enum, sourceEntityId UUID, eventKind exactmetadata type/legacy_unknown/snapshotmilestone, fromState String?, toState String?, actorId UUID? (null customer PII), actorLabel String? authorized, actorSource manager/system/shipper/customer/unknown proposal, occurredAt DateTime non-null, reason String?, source actual_event/snapshot_milestone proposal. Validate only state belonging to entity type; never convert null actor to system without source evidence. Do not merge task redelivery with order.awaiting_redelivery by equal string name.

OrderCapabilities fields bool: canCancelCustomer, canConfirm, canReject, canCancelExceptional, canAssign, canReassign, canArrangeSecondAttempt, canRequestEarlyReturn, canReceiveUndelivered, canOpenReturnCreation. These are derived response fields, not schema columns or permission grants; external action capability needs signed owner contract.

### 4.3 Mutation request/receipt and notification DTO

| Field | Type | Nullable | Description | Source | Validation |
|---|---|---|---|---|---|
| request.order_id | UUID | Không | Target | Caller existing business UUID | Auth/object validation |
| request.request_id | UUID | Không | Logical mutation identity | Generated once by caller | Same key+payload across retry/relaunch |
| request.reason | String | Có | Reject/exceptional cancel | Dialog | Required reject/exception, trimmed1..1000 Unicode scalar values |
| receipt.operation | enum/string allowlist | Không | confirm/reject/customer_cancel/manager_cancel/auto_confirm (internal only) | Server | Must match request kind |
| receipt.request_id | UUID | Không | Echo logical key | Stored receipt | Ownership checked on lookup |
| receipt.order | Order canonical | Không | Result committed state at operation time | Stored result | Current read may be later; distinguish committed/current |
| receipt.event_id | UUID | Không | Canonical source event | Event ledger | Stable replay |
| receipt.committed_at | DateTime | Không | Server finalization time visible only after commit | Server | Server-defined |
| receipt.replayed | bool | Không | Existing receipt returned | Server | Not a second mutation |
| receipt.current_order | Order? (always null v1.2) | Có | Reserved nullable compatibility field, không đọc latest khi replay | Owner contract | Required key=null; latest từ OP-O03 sau invalidate |

NotificationDto maps exactly §2.5 to NotificationItem; computed isRead only. NotificationTarget is allowlisted union, not raw URL. NotificationPage proposed fields items,nextCursor,unreadCount?,asOf; direct table GET naturally returns array, not this envelope. Adapter builds page/cursor and obtains exact count separately; no claim those are DB fields. If strict one-snapshot count/list needed, new read RPC proposal; baseline allows eventual consistency + refetch.

UI state fields documented main §12.2: asynchronous state never represents authoritative business state; pendingReadIds/actionRequestId/queryGeneration are local only. On logout clear pending op state from UI; durable receipt tracking must be keyed user and restored only after matching same authenticated user.

### 4.4 OrderTimelineEntry field dictionary (`PROPOSED`)

| Field | Type | Nullable | Description | Source | Validation |
|---|---|---|---|---|---|
| eventId | UUID String | Có | Event thật hoặc null khi fallback | business_events.id / snapshot | Không tạo UUID giả cho milestone |
| sourceEntityType | Typed entity kind | Không | Order/task/COD/return | Server projection | Allowlist, không notification title inference |
| sourceEntityId | UUID String | Không | Entity liên quan | Event subject / row ID | Belongs to authorized order graph |
| eventKind | Typed event kind | Không | Classification | Proposed event contract | Unknown xử lý unsupported, không default confirmed |
| fromState | String | Có | Previous value | business_events.from_state | Validate enum thuộc source entity |
| toState | String | Có | Result value | business_events.to_state | Không gộp enum có cùng tên |
| actorId | UUID String | Có | Actor identity | business_events.actor_id | Customer payload null nếu không được phép |
| actorLabel | String | Có | Authorized display | Profile projection | Deleted/missing không chế tên |
| actorSource | manager/system/shipper/customer/unknown | Không | Attribution | source/event private typed metadata contract | Null actor không mặc định system |
| occurredAt | DateTime UTC | Không | Event/milestone timestamp | created_at/placed_at/confirmed_at/delivered_at | Server; sort time+event ID deterministic |
| reason | String | Có | Business reason | Event reason safe projection | Reject reason required; owner privacy visibility §4.7 |
| source | actual_event/snapshot_milestone | Không | Evidence quality | Aggregate adapter | Avoid double same milestone/event |

### 4.5 UI State field dictionary (`PROPOSED`)

Các fields dưới đây thuộc state Dart, không DB/response columns. Loading/error flags có thể là properties suy ra từ AsyncValue; không duy trì hai nguồn trạng thái độc lập. Tên query/cursor/data theo main§12.2 và request DTO§4.1.

| Model.field | Type | Nullable | Description | Source | Validation |
|---|---|---|---|---|---|
| OrderListState.rows | List<OrderSummary> | Không | Current page set | Repository results | Initial[], dedup ID, current session |
| OrderListState.query | OrderQuery | Không | Search/filter/page input | User/ViewModel | Valid §4.1; new query resets cursor |
| OrderListState.selectedStatus | OrderStatus | Có | Getter từ query.statuses (single chip); null All | Query | Không lưu mutable duplicate; multi-status không giả một chip |
| OrderListState.nextCursor | String | Có | More page marker | Server response | Bound query; null end only after data loaded |
| OrderListState.counts | Map<OrderStatus,int> | Có | Whole-query distribution | Server projection | Null before loaded/error, not false0 |
| OrderListState.asOf | DateTime | Có | Authority snapshot time | Server | Null initial, never device-time authority |
| OrderListState.loadingInitial/refresh/more | bool each | Không | Separate async indicators | Async lifecycle | Same query at most1 inflight; more errors don't clear head |
| OrderListState.failure | AppFailure | Có | Safe initial/refresh/more error | Adapter/VM | No SQL/token/PII |
| OrderDetailsState.detail | OrderDetails | Có | Current authoritative detail | Repository | Null initial/denied; clear on session switch |
| OrderDetailsState.authoritativeAsOf | DateTime | Có | Current detail freshness | Server | Not updated_at alias |
| OrderDetailsState.failure | AppFailure | Có | Lỗi toàn lần tải RPC aggregate | Adapter/transport | Không ghép các section thuộc snapshot khác để coi complete |
| OrderDetailsState.mutation | OrderActionState | Không | Pending logical operation | VM | Separate from business status |
| OrderActionState.orderId | UUID String | Có | Current action target | User action | Required submitting/unknown, null idle |
| OrderActionState.operation | Action kind | Có | Confirm/reject/cancel etc. | User action | Required submitting/unknown |
| OrderActionState.requestId | UUID String | Có | Stable logical action key | VM durable pending metadata | Required submitting/unknown; restore same user only |
| OrderActionState.payload | Immutable request DTO | Có | Original normalized body | Dialog | Same key same payload; preserve reason after network error |
| OrderActionState.phase | idle/submitting/unknown/confirmed/failed | Không | UI outcome | Server response/transport | confirmed only authoritative receipt |
| NotificationsState.rows | List<NotificationItem> | Không | Own notifications | Repository | No old-account rows after switch |
| NotificationsState.filter | all/unread | Không | Selected filter | UI | No state mutation when filter selected |
| NotificationsState.cursor | String | Có | Paging | Adapter | Bound recipient/filter |
| NotificationsState.unreadCount | int | Có | Whole recipient count | Exact count query | Null pending/error, nonnegative actual;99+ display only |
| NotificationsState.pendingReadIds | Set<UUID String> | Không | Read UI spinner state | VM | Remove on ack/fail; no double decrement |
| NotificationsState.failure | AppFailure | Có | List/count/read failures | Adapter | Display actionable error |
| SessionScope.userId | UUID String | Có | Auth user | Auth contract | Null logged-out; don't share keys across users |
| SessionScope.role | UserRole | Có | Resolved server role | profiles | Null loading/failed, no privileged screen flash |
| SessionScope.generation | int | Không | Discard old callbacks | Session lifecycle | Increment account boundary; compare before applying result |

OrderCapabilities (`PROPOSED`) fields are non-null booleans computed by server preconditions: canCancelCustomer, canConfirm, canReject, canCancelExceptional, canAssign, canReassign, canArrangeSecondAttempt, canRequestEarlyReturn, canReceiveUndelivered, canOpenReturnCreation. Source is signed owner operations and current state/identity/custody, not widget role checks; unknown owner capability false/unavailable and explicit dependency. These flags don't replace server mutation checks.

### 4.6 Wire convention revision 1.2 (`OWNER DECIDED — PROPOSED IMPLEMENTATION`)

Owner đã chốt một wire contract v1.2 cho Orders/Notifications; chưa có RPC/class implementation. External summaries dùng đúng shape dưới đây nhưng owners phải cung cấp semantics/fixtures theo CIN contracts, không tự coi SHARED CONTRACT đã accepted. OrderDto dùng đúng toàn bộ keys §2.1 (21), OrderItemDto dùng §2.2 (11), NotificationDto dùng §2.5 (9). Tất cả key nêu trong response đều required; nullable nghĩa có key và giá trị null, không omission. Unknown extra fields có thể bỏ qua ở adapter để forward-compatible; missing required/type sai/unknown state phải unsupported_data, không tự default pending hoặc financial0. Latitude/longitude của aggregate draft là JSON number hữu hạn; raw numeric string được normalizer riêng chuyển trước mapper; tiền chỉ JSON integer.

| DTO | Required wire keys và type; `?` = nullable value, key vẫn required |
|---|---|
| OrderListResponse | items:OrderSummaryDto[], next_cursor:string?, total_count:int>=0, status_counts:map đủ10 OrderStatus→int>=0, as_of:UTC timestamp |
| OrderSummaryDto | order:OrderDto, customer_display_name:string?, item_preview:OrderItemDto[], item_line_count:int>=0, item_quantity_total:int>=0, delivery_summary:DeliverySummaryDto?, cod_summary:CODSummaryDto?, return_summary:ReturnSummaryDto?, warnings:WarningDto[], capabilities:OrderCapabilitiesDto |
| OrderDetailsDto | order:OrderDto, items:OrderItemDto[], buyer:BuyerDto?, delivery_summary:DeliverySummaryDto?, cod_summary:CODSummaryDto?, return_summaries:ReturnSummaryDto[], timeline:OrderTimelineEntryDto[], history_complete:bool, capabilities:OrderCapabilitiesDto, as_of:UTC timestamp |
| BuyerDto | id:UUID, full_name:string?; không có phone/role/email trong projection |
| WarningDto | code:allowlisted string, source_id:UUID, message:string; codes fixed: outbound_failure/custody_incident/return_active/external_dependency_unavailable/history_incomplete/goods_discrepancy; unknown generic no action |
| OrderCapabilitiesDto | can_cancel_customer, can_confirm, can_reject, can_cancel_exceptional, can_assign, can_reassign, can_arrange_second_attempt, can_request_early_return, can_receive_undelivered, can_open_return_creation: tất cả bool non-null |
| DeliverySummaryDto | task_id:UUID?, kind:DeliveryTaskKind?, task_status:DeliveryTaskStatus?, assigned_shipper_id:UUID?, assigned_shipper_name:string?, assigned_at:UTC?, accepted_at:UTC?, started_at:UTC?, completed_at:UTC?, amount_to_collect_vnd:int>=0?, attempt_count:int0..2, latest_attempt:AttemptSummaryDto?, failure_reason:string? |
| AttemptSummaryDto | id:UUID, task_id:UUID, order_id:UUID, attempt_number:int1..2, task_kind:outbound, result:success/failed, reason:string?, occurred_at:UTC, shipper_id:UUID?; manager failed requires nonblank reason; Customer reason/shipper_id=null; raw entity failed reason vẫn nonblank theo CHECK |
| CODSummaryDto | order_id:UUID, shipper_id:UUID?, status:uncollected/collected/received, expected_amount_vnd:int>0, collected_amount_vnd:int>=0, received_amount_vnd:int>=0, collected_at:UTC?, collected_by:UUID?, handed_over_at:UTC?, received_at:UTC?, received_by:UUID? |
| ReturnSummaryDto | return_id:UUID, order_id:UUID, status:ReturnRequestStatus, submitted_at:UTC, closed_at:UTC?, decision_reason:string?, is_active:bool, can_submit_return:bool, eligibility_reason:outside_window/not_delivered/active_return/unauthorized_or_unavailable/missing_contract?, return_deadline:UTC?; Returns owner ký semantics eligibility, không đổi BR23 |
| OrderTimelineEntryDto | event_id:UUID?, source_entity_type:order/delivery_task/cod/return_request, source_entity_id:UUID, event_kind:exact CIN09 event_type/audit-only type hoặc legacy_unknown/snapshot milestone; không inferred from_state, from_state:string?, to_state:string?, actor_id:UUID?, actor_label:string?, actor_source:manager/system/shipper/customer/unknown, occurred_at:UTC, reason:string?, source:actual_event/snapshot_milestone |
| OrderMutationReceiptDto | operation:confirm/reject/customer_cancel/manager_cancel/auto_confirm (job internal), request_id:UUID, event_id:UUID, order:OrderDto **đầy đủ**, committed_at:UTC, replayed:bool, current_order:OrderDto?; current_order always null v1.2; no receipt cache-write |
| OperationResultDto | state:committed/failed/not_found; required receipt:OrderMutationReceiptDto? và failure:AppErrorDto?; committed receipt non-null/failure null, failed receipt null/failure non-null, not_found cả hai null; denied outer error không resource fields |

Domain field mapping deterministic snake_case→lowerCamelCase theo dictionary §3/4; `as_of`→asOf; detail UI authoritativeAsOf lấy detail.asOf. Không alias tasks/server_time/Order subset. NotificationPage là Dart adapter result (items,nextCursor,unreadCount nullable,asOf nullable), **không** wire envelope hoặc snapshot server của raw GET. Khi raw reads list/count riêng, asOf=null vì không có server aggregate timestamp; client fetchedAt chỉ diagnostic, không quyền quyết định nghiệp vụ.

### 4.7 Role projection allowlist (`OWNER DECIDED`, reads VERIFIED; safe RPC not implemented)

| Projection | Customer own Order | Manager | Shipper |
|---|---|---|---|
| order + items | Own snapshot đầy đủ keys §2.1/2.2; confirmed_by=null trong customer safe aggregate draft (database/raw own row vẫn có nullable UUID); không của người khác | Authorized orders | Shared OP-O03 denied, dùng Deliveries owner contract |
| buyer/customer_display_name | null | Buyer id/full_name hoặc null nếu profile missing; account name khác recipient snapshot | Denied |
| delivery_summary | Relevant outbound state/times/amount/count/reason được sanitizer cho phép; assigned_shipper_id/name và latest_attempt.shipper_id=null | Summary authorized; name nullable | Không dùng Order DTO |
| cod_summary | Own financial state/amount/times; shipper_id,collected_by,received_by=null | Full summary | Đọc COD theo owner/collecting scope, không shared detail |
| return_summaries | Own summary; không bank/video/payment evidence | Summary; private evidence vẫn ở MH15 | Denied |
| timeline | Own authorized milestones; actor_id/actor_label=null; actor_source=unknown trừ khi có source evidence; reason chỉ order_rejected/order_cancelled; không raw internal delivery/return incident reason cho Customer | Authorized typed events; actor deleted nullable | Denied |
| capabilities | can_cancel_customer hoặc can_open_return_creation khi authoritative eligible; mọi manager flag false | Customer flags false; owner actions false tới khi contract/API sẵn sàng | Shared detail denied |

Không mở raw tasks/events RLS cho Customer để đạt projection. Orders đã chốt Customer timeline: placed/confirmed/cancelled/rejected/delivered và safe outbound attempt milestones, không raw incident, bank/evidence hoặc Return internal inspection reasons. actor_id/actor_label=null và order.confirmed_by=null; actor_source chỉ dùng metadata đáng tin cậy. Customer delivery_summary.failure_reason và latest_attempt.reason=null (manager-only free text); producer classification ngoài Orders qua CIN-03/09. Không dùng profile lookup mở rộng dữ liệu. DTO cùng keys, che field bằng null. Notification raw inbox theo recipient_id kể cả Manager; notification_only không dereference event/task.

### 4.8 Historical response versus latest state

Tuân thủ [main §12.5](technical_specification_mh07_mh08_mh09_mh17.md#125-response-ordering-stale-cache-và-historical-receipts-owner-decided-sửa-aud-04). Receipt.order immutable tại commit, current_order always null v1.2 không merge canonical cache. Repository trả receipt cho action outcome rồi ViewModel invalidate/refetch latest theo resource epoch. List/detail/count giữ snapshot coherent riêng; stale read-only và actions disabled khi refresh lỗi. Tests TX-05/TX-25/TX-26/TX-27. Đây là local design correction đã xác định, không tạo backend version column.

## 5. API baseline, transport và error contract

### 5.1 Existing versus proposed

`VERIFIED IN CODEBASE`: public tables grants/RLS define Data API reads. Supabase URL configured client-safe. `GET /rest/v1/<table>` and notifications `PATCH` describe PostgREST transport underlying SDK, không custom REST server. Runtime SDK adapters chưa có. Existing table reads vẫn cần test real session/project before claiming operational connectivity.

`PROPOSED` RPC transport: `POST /rest/v1/rpc/<function>` qua shared Supabase SDK, named SQL parameters p_* below. Names/signatures not existing. GET-style business read RPC dùng POST để giữ structured filters; semantics read-only. All tables/RPC requests carry publishable/anon client key và valid Auth session JWT; secret/service_role server-only. `private.current_app_role` helper không public app RPC.

### 5.2 Error model — OWNER DECIDED client codes

Domain codes được owner chốt, RPC future dùng envelope §5.3; không cần custom SQLSTATE business mapping để client parser đoán. Raw notification Data API/platform errors vẫn normalized riêng. JSON dưới đây là AppErrorDto mẫu nằm trong envelope.error, không default PostgREST error wire.

| Domain code | Meaning / UI | Existing wire hoặc proposed mapping | Retry |
|---|---|---|---|
| unauthenticated | Login MSG07 | JWT/session error; no auth.uid | Reauthenticate rồi recheck target |
| forbidden_or_unavailable | Không quyền/không thấy target MSG08/63 | RLS0 rows hoặc 42501; generic absence | Không auto retry/escalate admin |
| invalid_argument | Field/UUID/filter/reason invalid MSG01/13 | Owner-decided business envelope, Malformed typed args SQL22P02/22023 normalize invalid_argument; uncontrolled23514 data_integrity §5.3 | Sửa input, key mới chỉ nếu prior not committed |
| state_changed | State/precondition đổi MSG26 | Owner business code + nullable safe OrderStateReference | Refetch; không mutation key mới tự động |
| cancellation_not_allowed | Cancel ineligible MSG22 | Owner business envelope | Refresh |
| idempotency_conflict | Same key different operation/payload | Orders receipt protocol §7.2 | Không retry key with changed body |
| data_integrity | Related rows inconsistent | Authoritative server validation | Stop conflicting action; safe error/report |
| invalid_cursor | Cursor invalid/query mismatch | Owner read envelope | Reset page/cursor |
| network | Read failure MSG09 | Transport/offline | Bounded read retry |
| outcome_unknown | Mutation response lost MSG10 | Timeout/network post-send | Receipt lookup or same key retry |
| unsupported_data | Unknown enum/shape | Client validation | Safe read-only display, refresh; disable mutation |

Actual PostgREST commonly returns code/message/details/hint. SQL 23505 unique is not automatic success: adapter must lookup same operation/result and payload. 23503 FK/23514 CHECK are safe validation/data-integrity categories; do not show SQL detail to user. Auth status HTTP401/403 does not cover RLS-select invisible row (may200 empty).

```json
{
  "ok": false,
  "data": null,
  "error": {
    "code": "state_changed",
    "message_key": "MSG-26",
    "retryable": false,
    "current_order": {
      "id": "10000000-0000-4000-8000-000000000001",
      "status": "preparing"
    }
  }
}
```

`PROPOSED`: only authorized caller gets current_order; denied caller receives generic code với current_order=null, không có record fields. Outcome unknown is client state, không chứng minh transaction rollback. Timeout defaults read10s/mutation15s, read retries2 with backoff; these are proposals, NFR p95 separately measured.

### 5.3 RPC envelope và error mapping v1.2 (`OWNER DECIDED — PROPOSED IMPLEMENTATION`)

Tất cả OP-O01–OP-O08 public RPC return JSONB một envelope: required `ok:bool,data:object|null,error:AppErrorDto|null`. ok=true iff data!=null,error=null; ok=false iff data=null,error!=null. HTTP200 của SQL function chỉ là transport thành công, không business success nếu ok=false. SDK rpc future adapter validate envelope rồi map data. Auth/JWT/SQL infrastructure failures có thể non200 PostgREST; không coi envelope là default SDK error. Raw OP-N01–03 vẫn array/count/PATCH theo tables, không áp envelope giả vào Data API.

AppErrorDto required fields: code:String allowlist §5.2 + external_dependency_unavailable/custody_unverified/goods_discrepancy/store_location_unavailable, message_key:String?, retryable:bool, current_order:OrderStateReference? (id UUID,status OrderStatus). No raw SQL/detail/hint/PII. current_order=null cho denied/session/validation/dependency; state_changed/cancellation_not_allowed authorized caller có thể có ref tại failure snapshot nhưng không canonical cache. Client AppFailure thêm outcomeUnknown/local context, không JSON field mới.

| Source | Mapping owner decided | Retry/result meaning |
|---|---|---|
| HTTP200 ok=true | Validate exact data DTO | Authoritative receipt hoặc read; không mutation bằng read |
| HTTP200 ok=false | Exact AppErrorDto application error | Chỉ controlled post-claim terminal business failure persist/OP-O08 failed replay; validation/auth/dependency/custody/pre-claim errors không mặc định có receipt. No UI business success; transient/infra follow rows dưới và §7.3 |
| JWT invalid/expired, HTTP401/PGRST301/303 | unauthenticated MSG07 | Reauthenticate rồi recheck quyền; không read old account cache |
| RLS invisible0 rows / HTTP403 /42501 | forbidden_or_unavailable MSG08/63 | Không phân biệt resource người khác vs nonexistent; denied không lưu terminal receipt |
| Raw23505 | data_integrity nếu không là expected PK claim conflict được server xử lý | Không tự success/admin read; receipt PK race §7.3 |
| 23503/23514 ngoài controlled input validation | data_integrity safe message | Server rollback; không show constraint text |
| 40001/40P01/57014/SQL5xx hoặc malformed reply sau submit | outcome_unknown client; không persisted terminal failure | Lookup/same-key retry; không key mới |
| Read timeout/offline | network MSG09 | Read10s, retry2 backoff0.5/1.5s |
| Mutation timeout/offline sau submit | outcome_unknown MSG10 | 15s, preserve key/body, OP-O08 recovery |
| Missing RPC/schema cache/not-installed owner handler | external_dependency_unavailable | Disable dependent actions; no silent demo |
| Unknown/missing DTO field/type/enum | unsupported_data | Safe read-only UI, no default status/money0 |

Controlled input/state failures trước write có thể return error trực tiếp; sau receipt claim thì persist terminal business error sau rollback toàn domain subtransaction. Unexpected SQL/infra errors abort outer transaction, không biến thành immutable failed receipt. §7.3; không return business error sau partial writes chưa rollback. message_key: auth07, forbidden08/63, validation01/13, network09, unknown10, state26, cancellation22; othercodes generic safe text, không bịa MSG ID.

## 6. Operation Specifications

### 6.1 Exact Orders query protocol (`OWNER DECIDED`, NOT IMPLEMENTED)

All list parameters required keys `p_search:string|null,p_statuses:string[],p_limit:int,p_cursor:string|null` in RPC examples; SQL optional defaults null/[]/20/null allowed only omitted args. search trim §7.2.1 White_Space, empty→null, max200 Unicode scalar values, no accent removal; literal case-insensitive substring (escape SQL LIKE `%`, `_`, backslash), never search phone/address. Customer: own order full UUID exact OR order_items.product_name snapshot; Manager: full UUID exact OR buyer profiles.full_name, not recipient-name fallback. No DH display code schema, no shortened UUID search. UI debounce350ms; complete normalized query defines cache scope.

statuses exactly order enum10, duplicate collapse/sort lexicographically, [] all; unknown invalid_argument. limit default20 range1..100 invalid_argument outside, no clamp. Sort `(placed_at DESC,id DESC)`, fetch limit+1, next_cursor=null if no more. total_count uses ownership+search+selected statuses; status_counts all10 keys includes zeros, same ownership/search but excludes selected-status filter. All counts/items/as_of from one SQL statement/snapshot, so not cross-request frozen dataset; new/changed orders reflected at refresh.

Cursor opaque Base64URL without padding, max2048 chars, UTF8 JSON required exact keys `{v:1,scope:customer|manager,user_id:<current UUID>,search:null|string,statuses:<sorted list>,limit:<int>,last_placed_at:<UTC ISO8601>,last_id:<UUID>}`. Server validates types/version/scope/session user/normalized query/limit and tuple; mismatch malformed→invalid_cursor. This is continuation position, not permission grant/signed auth token; every page enforces current backend authorization/RLS. Query/filter/user change resets cursor; no reuse across sessions. Client never parses for navigation/business decisions. Dataset mutations can move items across pages; merge by id and refresh from head, never promise snapshot consistency across pages.

Missing optional external summary data cannot invent defaults. Exact nullable summary contracts §4.6 carry unavailable sources/history_complete=false, capability false with external_dependency_unavailable/custody_unverified. Required owned order/item fields absent or wrong types→unsupported_data, no fake money/status fallback.


### OP-O01 Get Customer Orders

| Contract aspect | Specification |
|---|---|
| Purpose/owner/screens | Own order list/search/filter/count, Orders, MH07 |
| Status | Basic reads Existing schema/access; aggregate/search/cursor capabilities `Missing/PROPOSED` |
| Existing transport | GET `/rest/v1/orders`, `/order_items`, `/cod_collections`, `/delivery_attempts`, own returns summary via selected fields |
| Proposed endpoint | POST RPC `get_customer_orders(p_search text default null, p_statuses public.order_status[] default '{}', p_limit integer default 20, p_cursor text default null)` returns jsonb envelope §4.1 |
| Auth/authorization | Current auth.uid + profiles.role customer; do not accept customer_id as access scope parameter |
| Search | Không human code v1.2; OWNER DECIDED full UUID exact + snapshot product_name case-insensitive literal substring; parameterized/escaped input; server combines OR across order/item matching then DISTINCT order |
| Paging/filter/sort | Keyset `(placed_at DESC,id DESC)`, same cursor query scope, limit1..100; filter enum exact; new filters reset cursor |
| Response | OrderSummary own sanitized; total_count full filtered; status_counts same search excluding status filter; as_of server snapshot |
| Errors | Unauthenticated, forbidden/unavailable, invalid_argument/cursor, network; no private task/event raw data |
| Idempotency | Read no side effect; fresh result may differ from prior read; no request ID required |
| Timeout/retry | Read10s, at most2 retries, latest query generation only |
| Affected state | Only MH07 UI cache/filter/cursor; no order transition |

Server aggregate read proposal should use a consistent statement/transaction snapshot for items/counts; current separate table requests không cam kết one snapshot. Search all matching orders, không fetch1000 rồi filter client (local max_rows1000, NFR5000 orders).

### OP-O02 Get Manager Orders and Counts

| Contract aspect | Specification |
|---|---|
| Purpose/owner/screens | Store authorized operational list/counters/warnings, Orders, MH08 |
| Status/transport | Existing raw table reads; Owner POST `get_manager_orders(p_search text default null,p_statuses public.order_status[] default '{}',p_limit integer default 20,p_cursor text default null)` returning §4.1 |
| Auth/authorization | Current manager from profiles; no client role switch |
| Inputs | Same query limits; manager search full UUID exact OR profiles.full_name case-insensitive literal substring; KHÔNG recipient fallback; null buyer name không match name |
| Response | OrderSummary manager projection includes buyer name, saved recipient/address, current assignment, last attempt, safe warnings, COD/return references |
| Counters | Pending/delivering derived order statuses; active return count from Returns operation only if contract signed, separate lifecycle count; counts not loaded page |
| Pagination/sort | `(placed_at DESC,id DESC)`; cursor bound same query; aggregate status counts same as_of |
| Errors | Auth/role, query/cursor, data_integrity projection, network |
| Idempotency/retry | Read-only; same defaults OP-O01 |
| Affected UI | MH08 rows/counters; no assignments generated by load |

Composite query must select explicit profile relation using customer_id (orders has another FK confirmed_by), not ambiguous embed. Need performance explain tests before adding indexes; proposed candidates customer_id/status/placed_at/id, manager status/placed_at/id, order_items order/name search support, notifications recipient/read_at/time/id. Actual migration/index choice based query planner; no unconditional full-text package introduced.

### OP-O03 Get Order Details

| Contract aspect | Specification |
|---|---|
| Purpose/owner/screens | Snapshot/details/actual history/current capabilities, Orders, MH07 modal/MH09 |
| Status | Manager raw reads Existing; customer task/audit projection Missing; normalized response Proposed |
| Proposed transport/signature | POST `get_order_details(p_order_id uuid)` returns §4.2 jsonb; role determines sanitized shape |
| Existing reads | orders/items; manager tasks/events/profiles/COD/returns; customer own order/items/attempts/COD/return summary (not events/tasks) |
| Authorization | Manager or order's customer; shipper cannot use order detail RPC to gain raw order info |
| Inputs/output | UUID only; returns all items snapshot, separate lifecycles, historical timeline and history_complete/as_of. Toàn aggregate được dựng bằng một SQL statement với các subqueries để cùng read snapshot; không nhiều SELECT ở READ COMMITTED rồi tự cam kết snapshot chung |
| History | Related task events joined by authorized order IDs, COD target order, returns target parent order; sort actual `(created_at,id)`; audit subjects lack FK so producer links validated |
| Errors | Generic missing/denied, malformed ID, unsupported/data_integrity; lỗi network/SQL fail toàn RPC. history_complete=false chỉ khi dữ liệu audit nguồn thiếu nhưng response hợp lệ, không phải lỗi mạng từng section |
| Pagination | Một order, toàn bộ items/timeline của order trong aggregate; baseline không có API timeline phân trang riêng và không silently truncate. Nếu lượng history vượt payload/latency target, cần change contract có signature/cursor cụ thể trước khi đổi implementation |
| Idempotency/retry | Read-only; read10s/retry2; permission recheck on reopen |
| Affected state | Detail and shared order cache; no read of detail marks notifications read automatically |

Customer-safe projection allowlist `PROPOSED`: order-owned snapshots, status/time, amount, outbound attempts number/result/time/reason=null for Customer free-text delivery failure, delivery status without shipper personal profile/bank/evidence/internal incident investigation. Customer cancel/reject reason from canonical decision event as permitted. Own Orders visibility fixed §4.7; external free-text reasons private for Customer; no broad raw-event SELECT policy. Definer projection if needed must verify identity/ownership and output only allowed columns, restricted grants/search_path/tests.

### OP-O04 Confirm Order

| Contract aspect | Specification |
|---|---|
| Purpose/owner/screens | Manual pending confirmation, Orders, MH08/MH09 |
| Status/endpoint | Missing, `PROPOSED` POST RPC `confirm_order(p_order_id uuid,p_request_id uuid)` returns MutationReceipt |
| Auth/permission | Authenticated session và profiles.role=manager; actor/source từ server. Account-ban/active enforcement là dependency Auth chưa xác minh, không có active flag trong profiles |
| Preconditions | Validate request then check existing receipt; lock order; still pending_confirmation; no contradictory custody/COD; existing reservation consistent |
| Postconditions | preparing, confirmed_at server time, source manager, confirmed_by auth.uid; reservation unchanged; canonical event, customer notification, receipt committed together |
| Idempotency | Same key+same actor/operation/order returns original receipt even if order later progressed; different key already confirmed returns state_changed, not another event |
| Errors | Permission/unavailable, state_changed, idempotency_conflict/data_integrity; no release/reserve on failed request |
| Timeout/retry | 15s; unknown outcome use OP-O08 or same key; no blind new operation |
| UI/sort | No pagination; update receipt then invalidate MH08/MH09/count/MH17; MSG23 |

### OP-O05 Reject Order

| Contract aspect | Specification |
|---|---|
| Purpose/owner/screens | Manager rejects pending with reason, Orders+Inventory, MH08/MH09 |
| Status/endpoint | Missing, `PROPOSED` POST `reject_order(p_order_id uuid,p_request_id uuid,p_reason text)` returns receipt |
| Preconditions | Manager; trimmed reason1..1000 Unicode scalar values; pending under lock; existing receipt check; reservation release possible for all variants |
| Postconditions | rejected; reason canonical business_events.reason proposed source, customer-safe detail projection/notification; release all reservations once with ledger; event/notifications/receipt same transaction |
| Storage decision | OWNER DECIDED canonical order_rejected event.reason authoritative; no new rejection_reason column; never overload cancel_reason |
| Errors | Blank reason invalid_argument MSG13, stale MSG26, access, idempotency mismatch, ledger inconsistency |
| Idempotency/retry | Stable request/fingerprint including normalized reason; timeout lookup/retry same body/key |
| UI/affected state | Dialog confirm MSG25; successful row removed from pending; list/counters/details refreshed; no payment/refund |

### OP-O06 Cancel Customer Order

| Contract aspect | Specification |
|---|---|
| Purpose/owner/screens | Own pending cancel, Orders+Inventory, MH07 |
| Status/endpoint | Missing, `PROPOSED` POST `cancel_customer_order(p_order_id uuid,p_request_id uuid)` returns receipt |
| Auth/authorization | Current customer owns order; not manager using customer privileges |
| Preconditions | Existing receipt first for valid caller; order pending under lock; no pickup/custody; release reservation exact |
| Postconditions | cancelled; event stores actor/server time; release once; revoke inconsistent existing assignment if any, notify affected customer/shipper per BR13; receipt |
| Input reason | Customer reason not mandated source; baseline no reason field, no new rule |
| Errors | cancellation_not_allowed if no longer pending; generic denied for other order; idempotency conflict/data integrity |
| Concurrency | Confirm/auto/reject contenders serialize; one valid transition; losing request no side effects |
| Idempotency/timeout | Same15s/result lookup/retry; same key returns committed cancellation even if later UI refetch |
| UI/affected state | MSG21 confirmation; authoritative update, MSG22/26 on stale; shared cache invalidation |

### OP-O07 Exceptional Manager Cancellation

| Contract aspect | Specification |
|---|---|
| Purpose/owner/screens | Cancel confirmed before shipper pickup, Orders+Deliveries+Inventory, MH09 |
| Status/endpoint | Missing, `PROPOSED` POST `cancel_manager_order(p_order_id uuid,p_request_id uuid,p_reason text)` returns receipt |
| Auth | Manager identity from session |
| Preconditions | Reason nonblank; status preparing/awaiting_pickup proposal matches confirmed/pre-pickup; check ALL historical pickup/custody, not only current task; never allow after earlier outbound pickup; existing receipt first |
| Postconditions | Cancelled; cancel_reason recorded; related active task cancelled/assignment revoked with timestamp/event; release reservation once; safe notifications customer/affected shipper; receipt |
| Errors | cancellation_not_allowed if pickup wins or prior custody, state_changed if assignment/order stale; same key payload mismatch; no client authority to mark pickup false |
| Race | Lock order+task with pickup operation same order; one cancellation or pickup can commit |
| Retry/UI | 15s and stored outcome; footer exceptional action only when capability; confirmation+reason required |

### OP-O08 Retrieve Operation Result

| Contract aspect | Specification |
|---|---|
| Purpose/owner/screens | Resolve outcome unknown, Orders, all order mutations |
| Status/endpoint | Missing, `PROPOSED` POST read RPC `get_order_operation_result(p_request_id uuid,p_order_id uuid,p_operation text)`; exact signature OWNER DECIDED, NOT IMPLEMENTED |
| Auth/ownership | Original principal matching receipt, current role đúng operation và ownership; lookup không claim/create request.  Cả receipt lẫn latest details đều fail closed nếu role/resource access đã bị thu hồi; không lookup người khác để lộ target/payload |
| Response | Envelope §5.3 data={state:committed/failed/not_found,receipt:Receipt|null,failure:AppErrorDto|null}; no durable in_progress; current denied outer error |
| Validation | UUID; actor principal derived server; operation/order compare stored fingerprint. Quyền bị thu hồi trả generic unavailable không có receipt/order payload; không dùng original actor làm lý do bỏ qua current permission |
| Meaning | not_found alone does NOT prove earlier request will never commit; same-key retry remains safe while original transaction inflight |
| Retry | Read10s/retry2; client remains unknown until receipt or same-key authoritative response |
| Affected state | Action result/check UI; no new mutation/notification |

### OP-N01 Get Notifications

| Contract aspect | Specification |
|---|---|
| Purpose/owner/screens | Recipient list All/Unread, Notifications, MH17 |
| Status | Existing table/grants/RLS; app implementation Missing; page contract Proposed |
| Transport | GET `/rest/v1/notifications`; SDK select explicit §2.5 columns |
| Auth/authorization | Session; own recipient filter for query efficiency plus RLS enforced; no manager access to all notification inboxes |
| Inputs | all/unread, limit default20 max100 proposal, keyset cursor(created_at,id); recipient from session, not editable |
| Response | Actual Data API array Notification rows; adapter page wrapper and nextCursor; optional separate OP-N02 exact count |
| Filtering/sort | unread read_at IS NULL; created_at DESC,id DESC; cursor same filter/user; no mark read on fetch |
| Errors | Session/network; generic inaccessible; unknown subject still render generic tile, target unavailable |
| Idempotency/retry | Read-only; 10s/read retries; dedup rows by notification.id on page refresh |
| Affected state | List/read-display only; notifications persisted unchanged |

### OP-N02 Get Unread Notification Count

| Contract aspect | Specification |
|---|---|
| Purpose/owner/screens | Badge/count shared shell+MH17 |
| Status/transport | Existing Data API exact count over notifications, filter recipient own/read_at NULL; SDK count supported official select docs; adapter Missing |
| Auth/response | Valid user, integer actual count; zero legitimate, missing/error not zero |
| Paging | None; whole recipient unread set, not current page |
| Errors | Session/network/forbidden; preserve last confirmed count with stale marker in same session |
| Idempotency/retry | Read10s/retry2; no read-state side effects |
| State updates | After insertion/read ack, refetch; concurrent new notification can raise count while another read lowers it |

Separate N01/N02 reads eventually consistent; poll/refresh after mutation/screen resume. If requirement for exact atomic list+badge snapshot adopted, new RPC returning same snapshot proposed, no pretending table endpoint supplies envelope.

### OP-N03 Mark Notification as Read

| Contract aspect | Specification |
|---|---|
| Purpose/owner/screens | Explicit tile read/tap, Notifications, MH17 |
| Status/transport | Existing PATCH `/rest/v1/notifications` with id filter; column grant read_at and owner RLS; app adapter Missing |
| Auth/permission | Session recipient only, each role own row |
| Input | Notification UUID + non-null valid ISO timestamp signal; actual saved timestamp overwritten server; no recipient/title/body update |
| Response | Selected full9key NotificationDto updated row (actual raw array, adapter maps domain); zero rows generic unavailable, not success |
| Postconditions | First read_at server clock, repeat preserves; cannot revert null, do not create business notification for reading |
| Idempotency | Intrinsic monotonic read state; repeat same row no extra count effects; key not needed for financial workflow |
| Errors/retry | 10s; timeout refetch row then same read retry; initial read failure leaves unread UI/count |
| Affected states | Unread tile removed only after ack; invalidate exact count and list; chat read unaffected |

### OP-N04 Resolve Notification Target

| Contract aspect | Specification |
|---|---|
| Purpose/owner/screens | Safe deep-link, Notifications orchestration, MH17→target |
| Status/transport | `PROPOSED` use case calling existing/owner authorized reads; no invented public HTTP endpoint |
| Input | NotificationId + current session namespace; resolver reloads own row if stale |
| Auth/authorization | Inbox ownership then target role and resource current access; target repository does final RLS fetch |
| Output | Typed route decision `(screen,uuid,mode)` or safe unavailable; no arbitrary remote URL |
| Mapping | Owner subject_type exact: order→customer MH07 modal/manager MH09; delivery_task→current shipper MH11 or manager task→order MH09; cod→MH12 authorized order PK; return_request→MH14/15; conversation→MH20 customer/manager; notification_only→own nội dung MH17, subject_id=event_id, không query event/task raw |
| Edge cases | Unknown subject/malformed ID/missing target/reassigned task/current role changed: MSG63, stay MH17, no cached PII fallback |
| Retry/paging | No pagination; each preflight read10s; generic network retry, no business side effect |
| Read coupling | OWNER DECIDED tap marks notification read independently; target unavailable may still count read, explicitly specified main §9.3 |

### OP-N05 Persist Source Event Notifications

| Contract aspect | Specification |
|---|---|
| Purpose/owner/screens | Server producers shared across owner workflows; MH17 consumer |
| Status/transport | Missing, `PROPOSED` internal server function/service called inside transaction; not Flutter endpoint |
| Inputs | Exact CIN09 registered canonical eventId/type/module/sourcekey/trustedactorSource/SourceFacts9keys; no client recipients/title/body; server owns templates/targets |
| Auth/authorization | Trusted producer verifies original actor transition; ordinary client cannot insert events/notifications |
| Output | Stable ordered notification UUID[] từ frozen manifest §7.4, replay no fan-out even manager/assignment changes; fingerprint mismatch aborts caller |
| Atomicity | OWNER DECIDED Orders producers synchronous business+event+receipt+manifest+rows same SQL transaction. Other producers use exact CIN-09 SHARED CONTRACT, NOT ACCEPTED/IMPLEMENTED; must join caller transaction, no post-commit client fan-out |
| Dedup | UNIQUE(recipient_id,event_id), but also stable source event creation; no new event UUID on retry |
| Payload | Current notifications columns only; no bank/evidence/token/raw task PII; mỗi recipient một typed subject pair theo main §9.2; Own event fan-out fixed main§9.2; external acceptance CIN-09 pending |
| Errors/retry | Server transaction failure rolls back; retries retain event/receipt identity; no client fake success |
| Pagination/state | No paging; inserts unread, no mark read; winning business event only |

### JOB-O01 Automatic Confirmation

| Contract aspect | Specification |
|---|---|
| Purpose/owner | Confirm pending after server threshold, Orders/backend |
| Status/transport | Missing; `PROPOSED` trusted scheduled process invokes shared transition transaction; Cron mechanism configured by migration, CLI/version verified at coding |
| Authentication | Server execution identity, no client execute grant; no user-provided source automatic |
| Selection | status pending_confirmation AND placed_at <= server_now - interval1hour; batch size proposal100; lock/recheck each order |
| Postconditions | preparing, source automatic, confirmed_at server; confirmed_by null/system contract; no shipper assignment or new reservation; customer+manager event notifications |
| Schedule | OWNER DECIDED every60s; deployment EXTERNAL DEPENDENCY; NFR09 confirms within60s after threshold under normal operation; measure queue/run latency, not just configured cron expression |
| Idempotency | System principal system:orders.auto_confirm + request_id=order.id; auto_confirm fingerprint and receipt, row state under lock; restarted job skips already changed; overdue recovery same policy |
| Error behavior | Individual invalid/inconsistent order logged safely for operator; no partial stock mutation; retry recoverable errors, no duplicate events |
| Race | Manager confirm/reject/customer cancel use same order lock/service; only first valid commit; job selects eligible pending before claim, rechecks under order lock; early/ineligible skip without terminal failure poisoning later key |

## 7. Concurrency, Idempotency và Audit Design

### 7.1 Current gaps

`VERIFIED IN CODEBASE`: placement unique customer/request; movement unique event/variant; delivery attempt unique order/attempt and task; notifications unique event/recipient; generic business_event request_id nullable globally UNIQUE. Chưa có persistent operation result/fingerprint, generic request mandatory or event type; những constraint này không đủ đảm bảo retries trả kết quả tương ứng workflow BR36.

### 7.2 Orders persistent receipt (`OWNER DECIDED — PROPOSED IMPLEMENTATION`, DR-01)

Chọn phương án C, không sửa global `business_events.request_id UNIQUE`. Table mới **chưa tồn tại**: `private.order_operation_receipts`; không expose qua Data API hoặc cấp SELECT trực tiếp cho client. Đây là schema contract cho migration tương lai, không migration đã applied.

| Field | SQL type / null | Constraint và semantics |
|---|---|---|
| principal_key | text required | Server tạo `user:<auth.uid lowercase UUID>` hoặc trusted `system:orders.auto_confirm`; client không gửi |
| request_id | uuid required | UUID client tạo đúng một lần trước submit; system auto-confirm dùng order.id |
| actor_id | uuid nullable | Auth caller; system=null; không cascade xóa receipt khi profile bị xóa |
| actor_source | text required | customer / manager / system; derived trusted server |
| operation | text required | confirm/reject/customer_cancel/manager_cancel/auto_confirm; auto_confirm chỉ server job |
| order_id | uuid required | FK orders.id, không ON DELETE CASCADE |
| payload_fingerprint | jsonb required | Exact canonical object §7.2.1; JSONB equality authoritative |
| outcome | text required | success/failure; không durable pending row |
| result_envelope | jsonb required | Immutable full envelope §5.3: success ok=true/data=receipt(replayed=false)/error=null; failure ok=false/data=null/error=AppErrorDto, không lưu bare error object |
| event_id | uuid nullable | FK business_events.id; success required, failure null |
| recorded_at | timestamptz required | Server UTC; immutable |

PK `(principal_key,request_id)` **không gồm operation/order**: cùng actor không được reuse một key cho intent khác. CHECK source/actor/principal nhất quán; operation/actor role tương ứng; envelope/outcome/event nullability nhất quán. Không plaintext JWT/token/bank/video trong receipt. Retention baseline không TTL/purge, cùng vòng đời audit; chính sách xóa/archiving cần business decision riêng, không tự purge theo UI logout. Không dùng receipt Orders thay placement receipt Checkout.

### 7.2.1 Fingerprint, pending command và restart

Required object đúng bốn keys: `{v:1,operation:<exact enum>,order_id:<lowercase canonical UUID>,reason:null|string}`. Confirm/customer_cancel/auto_confirm reason=null; reject/manager_cancel reason required 1..1000 Unicode scalar values. Server/client normalize CRLF/CR thành LF rồi trim ở hai đầu Unicode White_Space U+0009–000D,0020,0085,00A0,1680,2000–200A,2028/2029,202F,205F,3000. Không collapse whitespace bên trong, lowercase reason hay Unicode NFC; không hash stringified JSON, không nhận client fingerprint. Reject NUL, malformed UUID, unexpected RPC args, unsupported operation. JSONB equality tránh key-order ambiguity, không cần crypto extension.

Trước first-send, ViewModel dùng `PendingOrderCommandStore` (PROPOSED owner interface) lưu bền vững `{user_id,request_id,operation,order_id,normalized_reason,created_at_client}` qua protected per-user storage CIN-01; client time chỉ chẩn đoán. Không plaintext preferences/log; chưa có storage package/implementation. Logout clear UI/subscriptions, account B không truy cập pending A. Pending A giữ trong namespace bảo vệ để A đăng nhập lại lookup; không submit với session B. Khi restart cùng A: lookup OP-O08; committed → show historical receipt rồi refresh; failed → show same failure và refresh; not_found → có thể còn in-flight, retry nguyên key/body. Chỉ xóa pending sau terminal acknowledgment. Intent sửa reason/order/operation phải có key mới sau kết quả cũ đã biết; không đổi key chỉ vì timeout. CIN-01 unavailable thì không bật mutation cần restart guarantee.

### 7.3 Transaction, replay và race protocol

1. Validate shape; derive trusted actor/source. Recheck current operation role + order ownership cả lookup/replay; denied generic `forbidden_or_unavailable`, không nhận target data/receipt. Invalid/auth failures trước claim không persist.
2. Trong một SQL outer transaction, logical claim qua pg_advisory_xact_lock stable64-bit server hashtextextended(orders.receipt/v1|principal_key|requestUUID,0) trước lock domain, không INSERT pending row. Collision hash chỉ serialize thêm, PK/full JSONB equality vẫn authority. Contender chờ winner commit/rollback; final terminal INSERT PK backstop. Nếu winner tồn tại: compare fingerprint; khác → idempotency_conflict, giống → return stored success/failure trước state preconditions. Overlay receipt.replayed=true cho success; không đổi stored envelope, không chạy effects. Current quyền đã mất → denied, không reveal historical result.
3. First writer lock order row, rồi tasks/variants theo UUID tăng dần; lock order giữ ngoài work subtransaction để serialize auto/confirm/cancel/retry. Recheck status/custody/dependencies/server time. Chỉ một transition thành công; job auto chỉ chọn pending đã đủ 1 giờ trước claim, recheck eligibility dưới lock; early/changed row skip **không persist failure key** làm chặn lần job sau.
4. Work subtransaction: domain update + inventory effect + canonical root/child audit + metadata + frozen notification manifest/rows + success receipt. Nếu controlled authorized terminal state/business error: rollback toàn work subtransaction trước persist failure envelope ở outer transaction, event_id=null, không stock/event/notification effect. Unexpected SQL/infrastructure errors, missing handler/custody evidence, deadlock/statement timeout abort outer transaction, không cache immutable terminal failure cho lỗi tạm thời.
5. Finalize time clock_timestamp recorded in receipt.committed_at/recorded_at; visibleonlyaftercommit, không PG exact commit timestamp or aggregate version. Commit return §5.3 envelope. Timeout sau submit không chứng minh rollback. OP-O08 không tạo receipt, không durable in_progress: data.required state/receipt/failure. committed=(receipt nonnull,failure null); failed=(receipt null,failure nonnull); not_found=(cả hai null). Auth denied outer ok=false. Lookup cùng principal + order_id/operation; mismatch key scope → idempotency_conflict. No client lookup system principal.

Success result.order là historical committed snapshot, current_order luôn null v1.2; không overwrite canonical order/list/count cache bằng receipt. App dùng actionOutcome riêng và invalidate/reload guarded bởi request epoch/session/filter; reload fail giữ last data + stale label, không giả mutation thất bại. Failure.current_order chỉ immutable safe `{id,status}` khi authorized; cũng không cache-write. Lock ordering/unique constraints và schema future phải có SQL concurrent tests trước bật runtime.

### 7.4 Audit identity, typed metadata và frozen recipients

Orders generic root `business_events.id` = UUID server-generated, `request_id=null`. Không dùng client logical key ở cột globally UNIQUE này; incident producer giữ request_id nonnull theo existing CHECK. Root event collision → bounded 3 retries với UUID mới trong work subtransaction, không reuse unrelated event. Receipt giữ logical request; movements dùng canonical root event_id, existing UNIQUE(event_id,variant_id) bảo vệ một movement/variant/event. Child event UUID khác, causation ở metadata, không thêm fictitious public column.

Owner schema mới **PROPOSED IMPLEMENTATION** `private.business_event_contracts` dùng chung behavioral bridge, raw client denied:

| Field | Type/null | Constraint |
|---|---|---|
| event_id | uuid required | PK/FK public.business_events.id |
| root_event_id | uuid required | FK same metadata; root tự tham chiếu, child trỏ trực tiếp root tự tham chiếu, không cycle/chain |
| event_type | text required | Exact main§9.2 producer types hoặc audit-only type registered by owner; unknown legacy không giả confirmed |
| origin_module | text required | checkout/orders/deliveries/cod/returns/chat/inventory |
| source_operation_key | text required | 1..200 chars stable; Orders `user:<UUID>/<requestUUID>` hoặc `system:orders.auto_confirm/<orderUUID>`; prefix module nằm trong unique tuple |
| subject_type, subject_id | text,uuid required | Match public root subject; ownership graph verified server |
| actor_source | text required | trusted customer/manager/shipper/system; không user_metadata |
| source_facts | jsonb required | Exact CIN-09 facts object; no bank/video/token/freeform PII |
| event_fingerprint | jsonb required | Immutable `{event_type,actor_source,public_fields:BusinessEventInput,root_ref:UUID\|null,source_facts}`; root_ref=null for root; canonical required keys, excludes allocated UUID/time; prevents replay ambiguity after FK actor SET NULL |
| notification_manifest | jsonb array nullable | null=not emitted/audit-only; []=emitted zero; frozen notification IDs/recipient/typed target/title/body/created_at, không read_at |
| notification_emitted_at | timestamptz nullable | Nonnull iff manifest nonnull; server time |

UNIQUE `(origin_module,source_operation_key)`; child source key appends `/audit/<event_type>/<subjectUUID>` within200chars, root key không reuse cho child. Same source key changed type/subject/root/facts/public-event fingerprint → idempotency_conflict, including concurrent registration. Logical source advisory lock before registration; authoritative source_facts compare on replay. Event registration validates root/public identity and fingerprint; arbitrary UUID collision không coi same logical event. First emit locks metadata row, validates trusted transaction source facts, computes recipient set from profiles roles + ownership/current assignment **một lần**, deduplicates recipients, persists manifest và notification rows cùng business transaction. Replay reads manifest trước live role/assignment reads; không fan-out cho Manager mới, không đổi target với reassignment, khác facts/type/source → idempotency_conflict rollback. Emit returns stable ordered UUID[]. Profile deletion có thể cascade notifications; giữ manifest audit, không recreate deleted recipient. Không cấp clients đọc manifest người khác.

Metadata link giúp cùng business root có child audit nhưng chỉ root emits. Legacy events không metadata: timeline `event_kind=legacy_unknown`, actor_source=unknown, history_complete=false; không suy actor/type từ status alone. CIN-09 là SHARED CONTRACT cho external producers, NOT ACCEPTED/IMPLEMENTED. Notification target dùng public notifications.subject_type/id độc lập với root subject, validated relationship; exact policy ở main§9.2/CIN-09.

## 8. External Integration — exact handoff, NOT ACCEPTED/IMPLEMENTED

Nguồn authoritative [Cross Module Integration Contracts](Cross_Module_Integration_Contracts.md). Consumer Orders/Notifications đã chốt DTO và behavior; không tự phê duyệt implementation của owner khác.

| Contract | Owner → consumer | Exact boundary | Runtime gate |
|---|---|---|---|
| CIN-01 | Auth/shared → Orders/Notifications | TrustedSession + ProtectedUserStore; user/role/session epoch/current permission | No feature runtime without auth isolation |
| CIN-02 | Checkout/Inventory → Orders | Atomic full reservation + immutable21/11 field snapshot, placement dedup (customer,request), order_placed event | Real order→delivery core fixture missing |
| CIN-03 | Delivery → Orders | CustodyProjection, revoke-before-pickup, outbound retry/reassign/store handover; same SQL transaction order lock | Disable dependent MH09/cancel capabilities on unknown custody |
| CIN-04 | Inventory → Orders | reserve/release/dispatch/inspection movements canonical event, once per variant | Reject/cancel/retry/receipt cannot simulate multiple client calls |
| CIN-05 | COD → Orders/Notifications | CodSummary/received event, full obligation independent Return | Show missing source unavailable; never mark collected from delivered alone |
| CIN-06 | Returns → Orders/Notifications | ReturnSummary/read/eligibility + event facts | No fabricated 7-day client eligibility or refund completion |
| CIN-07 | Catalog → Orders | Immutable historical order text/prices; current product route by product_id if still accessible | No historical image snapshot column exists; neutral placeholder |
| CIN-08 | Returns/Group → MH07 | Authoritative return cutoff/eligible+blocked_reason+active request | Exact seven-day boundary business open, action gated |
| CIN-09 | Checkout/Delivery/COD/Returns/Chat → Notifications | register/emit typed root event, required-null facts, frozen recipient manifest | Producer acceptance/integration tests required separately |

### 8.1 Custody/retry/inspection consumer flow DR-02

Recommended SHARED CONTRACT: after outbound failed attempt1, same shipper retains goods; create new outbound task attempt2 (existing UNIQUE task result prevents reuse task1). While assigned/unacknowledged task2: order awaiting_redelivery; explicit shipper retry acknowledgment → delivering, without second stock dispatch/reserve or store pickup. delivery_attempt_count equals completed outbound results, not task creation/assignment; task change/shipper change never reset. Before initial pickup only, reassignment allowed. Initial pickup authoritative event/dispatch proof; accepted_at alone is not physical pickup.

Manager exceptional cancellation OWNER DECIDED own RPC validates confirmed preparing/awaiting_pickup, mandatory reason, complete historical never-picked-up proof, then CIN-03 revoke + CIN-04 release + order/audit/notification/receipt atomically. Missing/unverified custody → custody_unverified/action disabled; no default false. Previously picked goods cannot exceptional-cancel.

After first failure Manager can early-return; revoke unacknowledged retry task2 atomically under same order lock, choose actual custodian task1 or task2 as store leg. Second outbound failure mandates awaiting_store_return. Do not create nonoutbound return_pickup without return_request (existing CHECK), do not alter original outbound customer destination/amount. Store-leg navigation explicitly uses store_settings name/address/coordinates, collects zero further COD; missing store coordinates → store_location_unavailable, no customer-address fallback. Physical store handover event by shipper differs from Manager receipt and inspection. Only Manager records actual receipt; task returned_to_store, order still awaiting_store_return. Inspection closes undeliverable_returned only when all issued quantities received/classified and ledger reconciles.

Inspection exact per line `{order_item_id,received_quantity,sellable_quantity,damaged_quantity}` required ints≥0; no duplicates; sellable+damaged=received=issued for baseline closure. Restock movement `on_hand_delta=+sellable,reserved_delta=0,damaged_delta=+damaged`; damaged never added on_hand because available=on_hand-reserved. Same event/item/variant once. Lost/missing quantities → goods_discrepancy, no automatic closure/restock; transfer to other shipper after pickup and missing/partial final disposition REQUIRES BUSINESS DECISION. Recording factual partial receipt may be supported by Delivery but cannot silently approve closure. Entire recommended Delivery flow remains SHARED CONTRACT until MH11 owner acceptance; UI/actions cannot claim runtime ready from this document alone.

## 9. JSON Examples — revision 1.2 owner contract, NOT IMPLEMENTED

Mọi giá trị sau `PROPOSED EXAMPLE`, là fixture để kiểm tra tài liệu, không seed/runtime evidence. §9.1/9.8/9.9 dùng cột đã VERIFIED; aggregate/RPC §9.2–9.7 owner-decided, chưa tồn tại; không shared approval/runtime claim. Full Order/Item dùng chung mapper, không versioned subset alternative. Customer projections §4.7; null section nghĩa chưa có dữ liệu, không false financial state. Timeline empty với history_complete=false minh họa source chưa đầy đủ, không tự thêm event giả.

### 9.1 Full OrderDto theo existing fields

```json
{
  "id": "10000000-0000-4000-8000-000000000001",
  "customer_id": "20000000-0000-4000-8000-000000000001",
  "request_id": "30000000-0000-4000-8000-000000000009",
  "status": "pending_confirmation",
  "recipient_name": "Khách hàng minh họa",
  "recipient_phone": "0900000000",
  "address_detail": "Địa chỉ minh họa Hà Nội; không đặt đơn thật",
  "latitude": 21.028,
  "longitude": 105.834,
  "subtotal_vnd": 3450000,
  "delivery_fee_vnd": 30000,
  "total_cod_vnd": 3480000,
  "delivery_attempt_count": 0,
  "placed_at": "2026-10-08T03:32:00Z",
  "confirmed_at": null,
  "source": null,
  "confirmed_by": null,
  "delivered_at": null,
  "cancel_reason": null,
  "created_at": "2026-10-08T03:32:00Z",
  "updated_at": "2026-10-08T03:32:00Z"
}
```

### 9.2 Customer list response — owner wire

```json
{
  "ok": true,
  "data": {
    "items": [
      {
        "order": {
          "id": "10000000-0000-4000-8000-000000000001",
          "customer_id": "20000000-0000-4000-8000-000000000001",
          "request_id": "30000000-0000-4000-8000-000000000009",
          "status": "pending_confirmation",
          "recipient_name": "Khách hàng minh họa",
          "recipient_phone": "0900000000",
          "address_detail": "Địa chỉ minh họa Hà Nội; không đặt đơn thật",
          "latitude": 21.028,
          "longitude": 105.834,
          "subtotal_vnd": 3450000,
          "delivery_fee_vnd": 30000,
          "total_cod_vnd": 3480000,
          "delivery_attempt_count": 0,
          "placed_at": "2026-10-08T03:32:00Z",
          "confirmed_at": null,
          "source": null,
          "confirmed_by": null,
          "delivered_at": null,
          "cancel_reason": null,
          "created_at": "2026-10-08T03:32:00Z",
          "updated_at": "2026-10-08T03:32:00Z"
        },
        "customer_display_name": null,
        "item_preview": [
          {
            "id": "60000000-0000-4000-8000-000000000001",
            "order_id": "10000000-0000-4000-8000-000000000001",
            "product_id": "70000000-0000-4000-8000-000000000001",
            "variant_id": "80000000-0000-4000-8000-000000000001",
            "product_name": "Sản phẩm minh họa",
            "variant_label": "Biến thể minh họa",
            "attributes": {},
            "unit_price_vnd": 3450000,
            "quantity": 1,
            "line_total_vnd": 3450000,
            "created_at": "2026-10-08T03:32:00Z"
          }
        ],
        "item_line_count": 1,
        "item_quantity_total": 1,
        "delivery_summary": null,
        "cod_summary": null,
        "return_summary": null,
        "warnings": [],
        "capabilities": {
          "can_cancel_customer": true,
          "can_confirm": false,
          "can_reject": false,
          "can_cancel_exceptional": false,
          "can_assign": false,
          "can_reassign": false,
          "can_arrange_second_attempt": false,
          "can_request_early_return": false,
          "can_receive_undelivered": false,
          "can_open_return_creation": false
        }
      }
    ],
    "next_cursor": null,
    "total_count": 1,
    "status_counts": {
      "pending_confirmation": 1,
      "preparing": 0,
      "awaiting_pickup": 0,
      "delivering": 0,
      "awaiting_redelivery": 0,
      "awaiting_store_return": 0,
      "delivered": 0,
      "cancelled": 0,
      "rejected": 0,
      "undeliverable_returned": 0
    },
    "as_of": "2026-10-08T03:33:00Z"
  },
  "error": null
}
```

### 9.3 Customer own details response — owner wire

```json
{
  "ok": true,
  "data": {
    "order": {
      "id": "10000000-0000-4000-8000-000000000001",
      "customer_id": "20000000-0000-4000-8000-000000000001",
      "request_id": "30000000-0000-4000-8000-000000000009",
      "status": "pending_confirmation",
      "recipient_name": "Khách hàng minh họa",
      "recipient_phone": "0900000000",
      "address_detail": "Địa chỉ minh họa Hà Nội; không đặt đơn thật",
      "latitude": 21.028,
      "longitude": 105.834,
      "subtotal_vnd": 3450000,
      "delivery_fee_vnd": 30000,
      "total_cod_vnd": 3480000,
      "delivery_attempt_count": 0,
      "placed_at": "2026-10-08T03:32:00Z",
      "confirmed_at": null,
      "source": null,
      "confirmed_by": null,
      "delivered_at": null,
      "cancel_reason": null,
      "created_at": "2026-10-08T03:32:00Z",
      "updated_at": "2026-10-08T03:32:00Z"
    },
    "items": [
      {
        "id": "60000000-0000-4000-8000-000000000001",
        "order_id": "10000000-0000-4000-8000-000000000001",
        "product_id": "70000000-0000-4000-8000-000000000001",
        "variant_id": "80000000-0000-4000-8000-000000000001",
        "product_name": "Sản phẩm minh họa",
        "variant_label": "Biến thể minh họa",
        "attributes": {},
        "unit_price_vnd": 3450000,
        "quantity": 1,
        "line_total_vnd": 3450000,
        "created_at": "2026-10-08T03:32:00Z"
      }
    ],
    "buyer": null,
    "delivery_summary": null,
    "cod_summary": null,
    "return_summaries": [],
    "timeline": [],
    "history_complete": false,
    "capabilities": {
      "can_cancel_customer": true,
      "can_confirm": false,
      "can_reject": false,
      "can_cancel_exceptional": false,
      "can_assign": false,
      "can_reassign": false,
      "can_arrange_second_attempt": false,
      "can_request_early_return": false,
      "can_receive_undelivered": false,
      "can_open_return_creation": false
    },
    "as_of": "2026-10-08T03:33:00Z"
  },
  "error": null
}
```

### 9.4 Reject request — owner wire

```json
{
  "p_order_id": "10000000-0000-4000-8000-000000000001",
  "p_request_id": "30000000-0000-4000-8000-000000000001",
  "p_reason": "Không thể đáp ứng đơn theo yêu cầu đã xác nhận với khách"
}
```

### 9.5 Full mutation receipt — owner wire

```json
{
  "ok": true,
  "data": {
    "operation": "reject",
    "request_id": "30000000-0000-4000-8000-000000000001",
    "event_id": "40000000-0000-4000-8000-000000000001",
    "order": {
      "id": "10000000-0000-4000-8000-000000000001",
      "customer_id": "20000000-0000-4000-8000-000000000001",
      "request_id": "30000000-0000-4000-8000-000000000009",
      "status": "rejected",
      "recipient_name": "Khách hàng minh họa",
      "recipient_phone": "0900000000",
      "address_detail": "Địa chỉ minh họa Hà Nội; không đặt đơn thật",
      "latitude": 21.028,
      "longitude": 105.834,
      "subtotal_vnd": 3450000,
      "delivery_fee_vnd": 30000,
      "total_cod_vnd": 3480000,
      "delivery_attempt_count": 0,
      "placed_at": "2026-10-08T03:32:00Z",
      "confirmed_at": null,
      "source": null,
      "confirmed_by": null,
      "delivered_at": null,
      "cancel_reason": null,
      "created_at": "2026-10-08T03:32:00Z",
      "updated_at": "2026-10-08T03:40:00Z"
    },
    "committed_at": "2026-10-08T03:40:00Z",
    "replayed": false,
    "current_order": null
  },
  "error": null
}
```

### 9.6 Lookup committed — owner wire

```json
{
  "ok": true,
  "data": {
    "state": "committed",
    "receipt": {
      "operation": "reject",
      "request_id": "30000000-0000-4000-8000-000000000001",
      "event_id": "40000000-0000-4000-8000-000000000001",
      "order": {
        "id": "10000000-0000-4000-8000-000000000001",
        "customer_id": "20000000-0000-4000-8000-000000000001",
        "request_id": "30000000-0000-4000-8000-000000000009",
        "status": "rejected",
        "recipient_name": "Khách hàng minh họa",
        "recipient_phone": "0900000000",
        "address_detail": "Địa chỉ minh họa Hà Nội; không đặt đơn thật",
        "latitude": 21.028,
        "longitude": 105.834,
        "subtotal_vnd": 3450000,
        "delivery_fee_vnd": 30000,
        "total_cod_vnd": 3480000,
        "delivery_attempt_count": 0,
        "placed_at": "2026-10-08T03:32:00Z",
        "confirmed_at": null,
        "source": null,
        "confirmed_by": null,
        "delivered_at": null,
        "cancel_reason": null,
        "created_at": "2026-10-08T03:32:00Z",
        "updated_at": "2026-10-08T03:40:00Z"
      },
      "committed_at": "2026-10-08T03:40:00Z",
      "replayed": true,
      "current_order": null
    },
    "failure": null
  },
  "error": null
}
```

### 9.7 Lookup not-found — owner wire

```json
{
  "ok": true,
  "data": {
    "state": "not_found",
    "receipt": null,
    "failure": null
  },
  "error": null
}
```

### 9.8 Notification raw response theo existing columns

```json
[
  {
    "id": "50000000-0000-4000-8000-000000000001",
    "recipient_id": "20000000-0000-4000-8000-000000000001",
    "event_id": "40000000-0000-4000-8000-000000000001",
    "subject_type": "order",
    "subject_id": "10000000-0000-4000-8000-000000000001",
    "title": "Đơn hàng đã được từ chối",
    "body": "Mở đơn để xem lý do và trạng thái hiện tại.",
    "read_at": null,
    "created_at": "2026-10-08T03:40:00Z"
  }
]
```

### 9.9 Read signal existing-field input

```json
{
  "read_at": "2000-01-01T00:00:00Z"
}
```

Read signal non-null do trigger ghi server time; repeat giữ first-read timestamp. Lookup not_found không chứng minh rollback. Rejection reason nằm trong authorized event projection, không nhét vào cancel_reason. Schema/time/fan-out demo chưa tạo dữ liệu thật.

### 9.10 Full customer list request

```json
{
  "p_search": null,
  "p_statuses": [],
  "p_limit": 20,
  "p_cursor": null
}
```

### 9.11 Full details request

```json
{
  "p_order_id": "10000000-0000-4000-8000-000000000001"
}
```

### 9.12 Full confirm request

```json
{
  "p_order_id": "10000000-0000-4000-8000-000000000001",
  "p_request_id": "30000000-0000-4000-8000-000000000004"
}
```

### 9.13 Full operation lookup request

```json
{
  "p_request_id": "30000000-0000-4000-8000-000000000001",
  "p_order_id": "10000000-0000-4000-8000-000000000001",
  "p_operation": "reject"
}
```

### 9.14 Business failure envelope

```json
{
  "ok": false,
  "data": null,
  "error": {
    "code": "state_changed",
    "message_key": "MSG-26",
    "retryable": false,
    "current_order": {
      "id": "10000000-0000-4000-8000-000000000001",
      "status": "preparing"
    }
  }
}
```

### 9.15 Lookup terminal failure

```json
{
  "ok": true,
  "data": {
    "state": "failed",
    "receipt": null,
    "failure": {
      "code": "state_changed",
      "message_key": "MSG-26",
      "retryable": false,
      "current_order": {
        "id": "10000000-0000-4000-8000-000000000001",
        "status": "preparing"
      }
    }
  },
  "error": null
}
```

### 9.16 Denied envelope

```json
{
  "ok": false,
  "data": null,
  "error": {
    "code": "forbidden_or_unavailable",
    "message_key": "MSG-08",
    "retryable": false,
    "current_order": null
  }
}
```

### 9.17 Customer cancel request

```json
{
  "p_order_id": "10000000-0000-4000-8000-000000000001",
  "p_request_id": "30000000-0000-4000-8000-000000000002"
}
```

### 9.18 Manager exceptional cancel request

```json
{
  "p_order_id": "10000000-0000-4000-8000-000000000001",
  "p_request_id": "30000000-0000-4000-8000-000000000003",
  "p_reason": "Khách yêu cầu hỗ trợ trước khi shipper nhận hàng"
}
```

### 9.19 Manager list request

```json
{
  "p_search": "Nguyễn",
  "p_statuses": [
    "pending_confirmation"
  ],
  "p_limit": 20,
  "p_cursor": null
}
```

### 9.20 Full manager details nonnull external projections

Fixture tổng hợp giả lập contracts consumer, không live response; externalsemantic acceptance pending. Timeline incomplete explicit, không claim source có fullaudit.

```json
{
  "ok": true,
  "data": {
    "order": {
      "id": "10000000-0000-4000-8000-000000000001",
      "customer_id": "20000000-0000-4000-8000-000000000001",
      "request_id": "30000000-0000-4000-8000-000000000009",
      "status": "delivered",
      "recipient_name": "Khách hàng minh họa",
      "recipient_phone": "0900000000",
      "address_detail": "Địa chỉ minh họa Hà Nội; không đặt đơn thật",
      "latitude": 21.028,
      "longitude": 105.834,
      "subtotal_vnd": 3450000,
      "delivery_fee_vnd": 30000,
      "total_cod_vnd": 3480000,
      "delivery_attempt_count": 1,
      "placed_at": "2026-10-08T03:32:00Z",
      "confirmed_at": "2026-10-08T03:40:00Z",
      "source": "manager",
      "confirmed_by": "20000000-0000-4000-8000-000000000003",
      "delivered_at": "2026-10-08T06:00:00Z",
      "cancel_reason": null,
      "created_at": "2026-10-08T03:32:00Z",
      "updated_at": "2026-10-08T06:00:00Z"
    },
    "items": [
      {
        "id": "60000000-0000-4000-8000-000000000001",
        "order_id": "10000000-0000-4000-8000-000000000001",
        "product_id": "70000000-0000-4000-8000-000000000001",
        "variant_id": "80000000-0000-4000-8000-000000000001",
        "product_name": "Sản phẩm minh họa",
        "variant_label": "Biến thể minh họa",
        "attributes": {},
        "unit_price_vnd": 3450000,
        "quantity": 1,
        "line_total_vnd": 3450000,
        "created_at": "2026-10-08T03:32:00Z"
      }
    ],
    "buyer": {
      "id": "20000000-0000-4000-8000-000000000001",
      "full_name": "Người mua minh họa"
    },
    "delivery_summary": {
      "task_id": "90000000-0000-4000-8000-000000000001",
      "kind": "outbound",
      "task_status": "delivered",
      "assigned_shipper_id": "20000000-0000-4000-8000-000000000004",
      "assigned_shipper_name": "Shipper minh họa",
      "assigned_at": "2026-10-08T03:50:00Z",
      "accepted_at": "2026-10-08T03:55:00Z",
      "started_at": "2026-10-08T04:00:00Z",
      "completed_at": "2026-10-08T06:00:00Z",
      "amount_to_collect_vnd": 3480000,
      "attempt_count": 1,
      "latest_attempt": {
        "id": "a0000000-0000-4000-8000-000000000001",
        "task_id": "90000000-0000-4000-8000-000000000001",
        "order_id": "10000000-0000-4000-8000-000000000001",
        "attempt_number": 1,
        "task_kind": "outbound",
        "result": "success",
        "reason": null,
        "occurred_at": "2026-10-08T06:00:00Z",
        "shipper_id": "20000000-0000-4000-8000-000000000004"
      },
      "failure_reason": null
    },
    "cod_summary": {
      "order_id": "10000000-0000-4000-8000-000000000001",
      "shipper_id": "20000000-0000-4000-8000-000000000004",
      "status": "collected",
      "expected_amount_vnd": 3480000,
      "collected_amount_vnd": 3480000,
      "received_amount_vnd": 0,
      "collected_at": "2026-10-08T06:00:00Z",
      "collected_by": "20000000-0000-4000-8000-000000000004",
      "handed_over_at": null,
      "received_at": null,
      "received_by": null
    },
    "return_summaries": [
      {
        "return_id": "b0000000-0000-4000-8000-000000000001",
        "order_id": "10000000-0000-4000-8000-000000000001",
        "status": "pending_review",
        "submitted_at": "2026-10-08T07:00:00Z",
        "closed_at": null,
        "decision_reason": null,
        "is_active": true,
        "can_submit_return": false,
        "eligibility_reason": "active_return",
        "return_deadline": null
      }
    ],
    "timeline": [
      {
        "event_id": "40000000-0000-4000-8000-000000000007",
        "source_entity_type": "order",
        "source_entity_id": "10000000-0000-4000-8000-000000000001",
        "event_kind": "order_confirmed_manual",
        "from_state": "pending_confirmation",
        "to_state": "preparing",
        "actor_id": "20000000-0000-4000-8000-000000000003",
        "actor_label": "Manager minh họa",
        "actor_source": "manager",
        "occurred_at": "2026-10-08T03:40:00Z",
        "reason": null,
        "source": "actual_event"
      }
    ],
    "history_complete": false,
    "capabilities": {
      "can_cancel_customer": false,
      "can_confirm": false,
      "can_reject": false,
      "can_cancel_exceptional": false,
      "can_assign": false,
      "can_reassign": false,
      "can_arrange_second_attempt": false,
      "can_request_early_return": false,
      "can_receive_undelivered": false,
      "can_open_return_creation": false
    },
    "as_of": "2026-10-08T07:01:00Z"
  },
  "error": null
}
```

### 9.21 Full manager list response

Fixture tổng hợp giả lập contracts consumer, không live response; externalsemantic acceptance pending. Timeline incomplete explicit, không claim source có fullaudit.

```json
{
  "ok": true,
  "data": {
    "items": [
      {
        "order": {
          "id": "10000000-0000-4000-8000-000000000001",
          "customer_id": "20000000-0000-4000-8000-000000000001",
          "request_id": "30000000-0000-4000-8000-000000000009",
          "status": "delivered",
          "recipient_name": "Khách hàng minh họa",
          "recipient_phone": "0900000000",
          "address_detail": "Địa chỉ minh họa Hà Nội; không đặt đơn thật",
          "latitude": 21.028,
          "longitude": 105.834,
          "subtotal_vnd": 3450000,
          "delivery_fee_vnd": 30000,
          "total_cod_vnd": 3480000,
          "delivery_attempt_count": 1,
          "placed_at": "2026-10-08T03:32:00Z",
          "confirmed_at": "2026-10-08T03:40:00Z",
          "source": "manager",
          "confirmed_by": "20000000-0000-4000-8000-000000000003",
          "delivered_at": "2026-10-08T06:00:00Z",
          "cancel_reason": null,
          "created_at": "2026-10-08T03:32:00Z",
          "updated_at": "2026-10-08T06:00:00Z"
        },
        "customer_display_name": "Người mua minh họa",
        "item_preview": [
          {
            "id": "60000000-0000-4000-8000-000000000001",
            "order_id": "10000000-0000-4000-8000-000000000001",
            "product_id": "70000000-0000-4000-8000-000000000001",
            "variant_id": "80000000-0000-4000-8000-000000000001",
            "product_name": "Sản phẩm minh họa",
            "variant_label": "Biến thể minh họa",
            "attributes": {},
            "unit_price_vnd": 3450000,
            "quantity": 1,
            "line_total_vnd": 3450000,
            "created_at": "2026-10-08T03:32:00Z"
          }
        ],
        "item_line_count": 1,
        "item_quantity_total": 1,
        "delivery_summary": {
          "task_id": "90000000-0000-4000-8000-000000000001",
          "kind": "outbound",
          "task_status": "delivered",
          "assigned_shipper_id": "20000000-0000-4000-8000-000000000004",
          "assigned_shipper_name": "Shipper minh họa",
          "assigned_at": "2026-10-08T03:50:00Z",
          "accepted_at": "2026-10-08T03:55:00Z",
          "started_at": "2026-10-08T04:00:00Z",
          "completed_at": "2026-10-08T06:00:00Z",
          "amount_to_collect_vnd": 3480000,
          "attempt_count": 1,
          "latest_attempt": {
            "id": "a0000000-0000-4000-8000-000000000001",
            "task_id": "90000000-0000-4000-8000-000000000001",
            "order_id": "10000000-0000-4000-8000-000000000001",
            "attempt_number": 1,
            "task_kind": "outbound",
            "result": "success",
            "reason": null,
            "occurred_at": "2026-10-08T06:00:00Z",
            "shipper_id": "20000000-0000-4000-8000-000000000004"
          },
          "failure_reason": null
        },
        "cod_summary": {
          "order_id": "10000000-0000-4000-8000-000000000001",
          "shipper_id": "20000000-0000-4000-8000-000000000004",
          "status": "collected",
          "expected_amount_vnd": 3480000,
          "collected_amount_vnd": 3480000,
          "received_amount_vnd": 0,
          "collected_at": "2026-10-08T06:00:00Z",
          "collected_by": "20000000-0000-4000-8000-000000000004",
          "handed_over_at": null,
          "received_at": null,
          "received_by": null
        },
        "return_summary": {
          "return_id": "b0000000-0000-4000-8000-000000000001",
          "order_id": "10000000-0000-4000-8000-000000000001",
          "status": "pending_review",
          "submitted_at": "2026-10-08T07:00:00Z",
          "closed_at": null,
          "decision_reason": null,
          "is_active": true,
          "can_submit_return": false,
          "eligibility_reason": "active_return",
          "return_deadline": null
        },
        "warnings": [
          {
            "code": "return_active",
            "source_id": "b0000000-0000-4000-8000-000000000001",
            "message": "Có yêu cầu trả đang xử lý"
          }
        ],
        "capabilities": {
          "can_cancel_customer": false,
          "can_confirm": false,
          "can_reject": false,
          "can_cancel_exceptional": false,
          "can_assign": false,
          "can_reassign": false,
          "can_arrange_second_attempt": false,
          "can_request_early_return": false,
          "can_receive_undelivered": false,
          "can_open_return_creation": false
        }
      }
    ],
    "next_cursor": null,
    "total_count": 1,
    "status_counts": {
      "pending_confirmation": 0,
      "preparing": 0,
      "awaiting_pickup": 0,
      "delivering": 0,
      "awaiting_redelivery": 0,
      "awaiting_store_return": 0,
      "delivered": 1,
      "cancelled": 0,
      "rejected": 0,
      "undeliverable_returned": 0
    },
    "as_of": "2026-10-08T07:01:00Z"
  },
  "error": null
}
```

### 9.22 Full confirm response

Independent syntheticfixtures; matching requests use thisrequestUUID, no appliedbackend.

```json
{
  "ok": true,
  "data": {
    "operation": "confirm",
    "request_id": "30000000-0000-4000-8000-000000000004",
    "event_id": "40000000-0000-4000-8000-000000000002",
    "order": {
      "id": "10000000-0000-4000-8000-000000000001",
      "customer_id": "20000000-0000-4000-8000-000000000001",
      "request_id": "30000000-0000-4000-8000-000000000009",
      "status": "preparing",
      "recipient_name": "Khách hàng minh họa",
      "recipient_phone": "0900000000",
      "address_detail": "Địa chỉ minh họa Hà Nội; không đặt đơn thật",
      "latitude": 21.028,
      "longitude": 105.834,
      "subtotal_vnd": 3450000,
      "delivery_fee_vnd": 30000,
      "total_cod_vnd": 3480000,
      "delivery_attempt_count": 0,
      "placed_at": "2026-10-08T03:32:00Z",
      "confirmed_at": "2026-10-08T03:38:00Z",
      "source": "manager",
      "confirmed_by": "20000000-0000-4000-8000-000000000003",
      "delivered_at": null,
      "cancel_reason": null,
      "created_at": "2026-10-08T03:32:00Z",
      "updated_at": "2026-10-08T03:40:00Z"
    },
    "committed_at": "2026-10-08T03:40:00Z",
    "replayed": false,
    "current_order": null
  },
  "error": null
}
```

### 9.23 Full customer cancel response

Independent syntheticfixtures; matching requests use thisrequestUUID, no appliedbackend.

```json
{
  "ok": true,
  "data": {
    "operation": "customer_cancel",
    "request_id": "30000000-0000-4000-8000-000000000002",
    "event_id": "40000000-0000-4000-8000-000000000003",
    "order": {
      "id": "10000000-0000-4000-8000-000000000001",
      "customer_id": "20000000-0000-4000-8000-000000000001",
      "request_id": "30000000-0000-4000-8000-000000000009",
      "status": "cancelled",
      "recipient_name": "Khách hàng minh họa",
      "recipient_phone": "0900000000",
      "address_detail": "Địa chỉ minh họa Hà Nội; không đặt đơn thật",
      "latitude": 21.028,
      "longitude": 105.834,
      "subtotal_vnd": 3450000,
      "delivery_fee_vnd": 30000,
      "total_cod_vnd": 3480000,
      "delivery_attempt_count": 0,
      "placed_at": "2026-10-08T03:32:00Z",
      "confirmed_at": null,
      "source": null,
      "confirmed_by": null,
      "delivered_at": null,
      "cancel_reason": null,
      "created_at": "2026-10-08T03:32:00Z",
      "updated_at": "2026-10-08T03:40:00Z"
    },
    "committed_at": "2026-10-08T03:40:00Z",
    "replayed": false,
    "current_order": null
  },
  "error": null
}
```

### 9.24 Full manager exceptional cancel response

Independent syntheticfixtures; matching requests use thisrequestUUID, no appliedbackend.

```json
{
  "ok": true,
  "data": {
    "operation": "manager_cancel",
    "request_id": "30000000-0000-4000-8000-000000000003",
    "event_id": "40000000-0000-4000-8000-000000000004",
    "order": {
      "id": "10000000-0000-4000-8000-000000000001",
      "customer_id": "20000000-0000-4000-8000-000000000001",
      "request_id": "30000000-0000-4000-8000-000000000009",
      "status": "cancelled",
      "recipient_name": "Khách hàng minh họa",
      "recipient_phone": "0900000000",
      "address_detail": "Địa chỉ minh họa Hà Nội; không đặt đơn thật",
      "latitude": 21.028,
      "longitude": 105.834,
      "subtotal_vnd": 3450000,
      "delivery_fee_vnd": 30000,
      "total_cod_vnd": 3480000,
      "delivery_attempt_count": 0,
      "placed_at": "2026-10-08T03:32:00Z",
      "confirmed_at": "2026-10-08T03:38:00Z",
      "source": "manager",
      "confirmed_by": "20000000-0000-4000-8000-000000000003",
      "delivered_at": null,
      "cancel_reason": "Khách yêu cầu hỗ trợ trước khi shipper nhận hàng",
      "created_at": "2026-10-08T03:32:00Z",
      "updated_at": "2026-10-08T03:40:00Z"
    },
    "committed_at": "2026-10-08T03:40:00Z",
    "replayed": false,
    "current_order": null
  },
  "error": null
}
```

### 9.25 Full SourceFacts for Orders confirmation

```json
{
  "order_id": "10000000-0000-4000-8000-000000000001",
  "task_id": null,
  "return_request_id": null,
  "customer_id": "20000000-0000-4000-8000-000000000001",
  "assigned_shipper_id": null,
  "previous_shipper_id": null,
  "collecting_shipper_id": null,
  "conversation_id": null,
  "sender_id": null
}
```

## 10. API implementation gates revision 1.2

- [x] Owner chọn module-scoped receipt, exact fingerprint, success/failure envelope, historical replay/cache isolation, Orders event identity/manifest và typed wire.
- [x] Owner chốt full UUID/search/filter/paging, Customer projection/privacy, role guards, Notification Center/read/count/target behavior và own producer fan-out.
- [ ] Implement future private tables/RPCs/server job qua actual CLI migrations trong nhiệm vụ code riêng; source chưa có.
- [ ] CIN-01–09 SHARED contracts được owner cung cấp/confirm, external fixtures và permission tests; proposal chưa accepted.
- [ ] Group business lost/partial closure/transfer-after-pickup và return cutoff resolved khi muốn bật nhánh liên quan; baseline disables safely.
- [ ] SDK/error/concurrent SQL/security/NFR/device tests run; docs validation không runtime PASS.

Nguồn: [Final Technical Decisions](Final_Technical_Decisions.md); [Cross Module Contracts](Cross_Module_Integration_Contracts.md); [Readiness1.2](Implementation_Readiness_v1.2.md). Historical revision1.1 không còn normative ở sections đã thay. All new storage/RPC/schema names PROPOSED IMPLEMENTATION, không existing table/API.

## 11. Notification paging/read adapter — OWNER DECIDED

Domain query required `{filter:all|unread,limit:int1..100 default20,cursor:string|null}`. Own recipient_id derived Auth + RLS; unread read_at IS NULL; sort created_at DESC,id DESC fetchlimit+1. Adapter builds opaque Base64URL JSON `{v:1,user_id:UUID,filter:all|unread,limit:int,last_created_at:UTC,last_id:UUID}`, max2048; invalid/mismatched user/filter/limit resets/refetch with invalid_cursor, no arbitrary raw SDK filter text. Two raw list/countrequests eventualconsistent; page.asOf=null, unreadCount nullable until exactwholeowncount response. Count All includes only unread wholeinbox, unaffected selectedfilter/page. Null count not0; UIbadge99+ onlydisplay.

MarkRead rawPATCH ownnotificationUUID read_at nonnullUTCsentinel, select updated9keys for canonicalserverread_at;0rows genericunavailable, noread-successassumption. No arbitraryrecipient parameter; duplicate/read retries samefirststamp; explicit tap read separate from navigation. Read ack bumps count/list epoch, old count response dropped; fail leaves unconfirmed no decrement and permits authorizedtargetnavigation. Eachcurrentquery max1inflight; refreshpause/resume/sessionclear per main12.5. Authoritative realtime publication absent; poll3sforeground ownpolicy. Adapter sourcefiles main12.1 proposed, no package dependency assumed.

## 12. Exact Flutter repository consumer map — OWNER DECIDED/PROPOSED paths

| Domain method (proposed) | Input -> domain output | Data mapping / owner |
|---|---|---|
| OrderRepository.getCustomerOrders / getManagerOrders | OrderQuery -> OrderPage | OP-O01/02 success data exact§4.6, currentrole/serverauthorization |
| OrderRepository.getOrderDetails | orderId:UUID -> OrderDetails | OP-O03 safeaggregate, canonicalreadcache only |
| OrderRepository.confirm / reject / cancelCustomer / cancelManager | StableOrderCommand(orderId,requestId,operation,reason?) -> OrderMutationReceipt | OP-O04–07 envelope success; terminalAppFailure state; no cacheoverwrite |
| OrderRepository.getOperationResult | requestId,orderId,operation -> OperationResult committed/failed/notFound | OP-O08 union; never auto newrequest key |
| PendingOrderCommandStore.save/list/remove | currentuser scoped StableOrderCommand / List / void | CIN01 durableatomicprotectedrecord/listKeys, pendingkey orders.pending/requestUUID, no token |
| NotificationRepository.getPage / getUnreadCount | NotificationQuery / noargs -> NotificationPage / int | OP-N01/02 rawarray/count, page.asOf=null, usernamespace |
| NotificationRepository.markRead | notificationId -> NotificationItem | OP-N03 fullupdated9keyrow,0rows genericunavailable |
| NotificationTargetResolver.resolve | notificationId -> TargetDecision(screen,uuid?,mode) | ownrecipientthen CIN-R adapters+centralrouter/currenttargetpermission; notification_only uuid=null/no rawfetch |

snake_case wire -> lowerCamelCase domain only at datamappers. Types/repository interfaces noFlutter/Supabase imports. Riverpod provides adapters/sharedclient/session; ViewModels handle AsyncValue/state/error/resourceepoch and protectedpending lifecycle. AppFailure(code,messageKey,retryable,currentOrderRef?,outcomeUnknown) maps §5.3, never parsefreeformSQL. Suggestedexistingblueprintpaths main12.1 allnewclasses NOT IMPLEMENTED, no duplicate sharedOrder/Notification model.
