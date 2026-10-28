# Phụ lục Test Plan và Acceptance Traceability cho MH07 MH08 MH09 MH17

Đi cùng [đặc tả chính](technical_specification_mh07_mh08_mh09_mh17.md) và [data/API contracts](technical_specification_mh07_mh08_mh09_mh17_data_api.md). Revision1.2: test oracle owned OWNER DECIDED, external oracle SHARED CONTRACT NOT ACCEPTED; tất cả tests PLANNED/NOT RUN. Bảng không tuyên bố RPC, UI hoặc integration hiện tồn tại. Feature/API thiếu là blocker thực thi, không reason bỏ test.

## 1. Chiến lược, môi trường và dữ liệu

| Level/type | Target | Technique | Completion criterion |
|---|---|---|---|
| Unit U | DTO/domain/parser, query/state machine VM, failure mapping, route decisions | Fake repository trong test-only; deterministic clocks cho display, server-time fixture cho eligibility | Normal/invalid/unknown/network states đúng, không SDK/widget trong domain |
| Widget W | Bốn page, cards/dialogs/modals/timeline/read badges | flutter_test + provider overrides; mobile sizes/text scales | Async/data/actions accessible, no clipping/duplicate request/leak |
| Integration I | Session/route/data reads/mutations/producers | Dedicated Supabase env, actual role JWT and Flutter app | End-to-end normal/error/navigation state authoritative |
| Database B | RLS/grants, transactions, same request, race, financial independence | SQL role simulation + API auth tests + concurrent client connections | Allowed/denied và atomicity/replay enforced server |
| Performance/reliability P | NFR p95/freshness/recovery | Reference hardware/network/load report; controlled disconnect/crash | Measured target or documented fail/blocker, không fake PASS |

Fixtures cần chuẩn bị bởi owners, `PROPOSED`: Customer A/B, Manager M1/M2, Shipper S1/S2; profiles đúng role; hai own orders/A khác B; ít nhất mỗi order state; pending gần/trước/sau một giờ; delivered gần/qua deadline; tasks pre-pickup/retained custody/reassigned, failures1/2; COD uncollected/collected/received; active/closed return; unread/read notifications từng recipient; unknown/malformed/deleted subject references. Không dùng tài khoản/PII thật. Order snapshot sample subtotal3.450.000 + fee30.000 = COD3.480.000; mọi amount fixtures phải consistent. Concurrent stock fixture do Inventory owner cung cấp.

Môi trường chạy database phải tách production/shared demo. SQL rollback fixture cho assertions, nhưng integration network/crash cần dedicated cleanup có scope UUID prefix đúng; không reset cloud nhóm. Giữ evidence command/environment/commit/migration version, expected/actual, logs đã redact, defect IDs. Baseline `supabase/tests/database_security.sql` có assertions quyền/constraint; ghi nhận kiểm tra lịch sử trong `docs/database.md` không được tài liệu này xác minh và không dùng làm evidence acceptance. Workflow RPC missing chưa được baseline chứng minh.

Priority P0: authorization/financial/transaction/race/lifecycle integrity, chặn release. P1: essential UI/search/filter/navigation/async. P2: optional visual/readability/performance optimization, trừ NFR đã được duyệt thành release gate. Cases optional chỉ chạy sau scope duyệt.

## 2. MH07 cases

| Test ID | Screen | Type | Scenario | Preconditions | Steps | Expected Result | Priority |
|---|---|---|---|---|---|---|---|
| T07-01 | MH07 | I/B | Customer chỉ thấy own orders | A/B có orders | Login A; list và direct read B UUID | Chỉ A; B generic unavailable, không PII | P0 |
| T07-02 | MH07 | W | Initial loading/empty | Repo delayed rồi [] | Mở page; complete request | Skeleton không data giả; empty rõ, link catalog hợp lệ | P1 |
| T07-03 | MH07 | U/I | Search across pages bằng snapshot name | >20 orders; item cần tìm ngoài page1 | Search tên snapshot; load next page | Search toàn authorized dataset, ổn định, không chỉ local page | P1 |
| T07-04 | MH07 | U/I | Catalog rename/deactivate không đổi old order | Order snapshot; product changed/inactive | Load list/detail | Snapshot name/variant/price giữ; không mất item do inner join | P0 |
| T07-05 | MH07 | U/I | Identifier search | Owner full UUID contract; UUID fixtures | Search exact accepted identifier; tap item | Đúng order; route UUID thật; unknown empty, không fabricated DH | P1 |
| T07-06 | MH07 | U/W | All10 status filters | Mỗi state fixture | Chọn từng chip, clear | Exact enum mapping, selected chip/count đúng, không created enum mới | P1 |
| T07-07 | MH07 | U/W | COD totals/item counts | Item qty2 và3, 2lines | Load card/detail | quantity total5 khác line count2; amount snapshot +30.000, format integer | P0 |
| T07-08 | MH07 | W/I | Chi tiết thuộc MH07 | Own order | Xem detail; back | Modal/sheet trong MH07, fetch ID/RLS, giữ query/scroll; không màn21 | P1 |
| T07-09 | MH07 | I/B | Cancel own pending thành công | Own pending/reserved stock | Confirm cancel, await API | cancelled, release1, one event/receipt/notifications; UI sau ack | P0 |
| T07-10 | MH07 | B/I | Customer cancel preparing | Order preparing | Direct RPC + stale button attempt | Deny MSG22/latest, stock/event unchanged | P0 |
| T07-11 | MH07 | B | Cancel order của người khác | B pending | A submit B UUID | Generic deny, không state/reason/stock/notification B leaked | P0 |
| T07-12 | MH07 | W/I | Status đổi khi cancel dialog mở | A pending; server confirm | Mở dialog; confirm elsewhere; submit | state_changed/not_allowed; latest status, không giả cancel | P0 |
| T07-13 | MH07 | W/B | Double-tap cancel | Pending | Rapid submit twice cùng logical key | One transition/release/event; UI one pending request | P0 |
| T07-14 | MH07 | I | Cancel timeout after commit | Drop server response | Submit; timeout; recover same key | Unknown trước lookup; original receipt, không release2 | P0 |
| T07-15 | MH07 | I/W | Tracking no GPS | Own delivering; safe projection | Theo dõi | Actual timeline/status; không GPS/ETA/mock six-stage timestamps | P1 |
| T07-16 | MH07 | B/I | Safe history projection | A order; internal/private task/evidence | Read detail raw/projection | Raw tasks/events denied; projection only allowed customer fields | P0 |
| T07-17 | MH07 | I | Return handoff in time | Own delivered, no active, signed boundary | Tap request; submit in MH13 dependency | Correct order UUID; server final eligibility; order remains delivered | P0 |
| T07-18 | MH07 | I | Deadline qua khi đang xem | Eligible on open; deadline passes | Open return; submit later | Returns owner denies by server submit time MSG38, no fake success | P0 |
| T07-19 | MH07 | I/W | Already active return | Active request exists | Tap return action/deep link | MH14 existing ID, không duplicate active request | P1 |
| T07-20 | MH07 | U/I | Device clock/timezone sai | UTC stored times/server eligibility | Change clock/zone, load | Hanoi display, same server deadlines/capabilities | P0 |
| T07-21 | MH07 | W | Image missing/private failure | No snapshot path or deleted image | Load card/detail | Placeholder; snapshot text/amount vẫn đúng; no public URL bypass | P1 |
| T07-22 | MH07 | W | Mua lại/support mock scope | Baseline chưa duyệt optional | Inspect actions | Không Mua lại/24-7 claim; support uses own chat contract only | P1 |

## 3. MH08 cases

| Test ID | Screen | Type | Scenario | Preconditions | Steps | Expected Result | Priority |
|---|---|---|---|---|---|---|---|
| T08-01 | MH08 | B/I | Non-manager truy cập manager list | Customer/shipper session | Navigate route/direct read proposed list RPC | Manager guard denied; server denies aggregate manager projection | P0 |
| T08-02 | MH08 | I | Search buyer name khác recipient | Buyer name X; recipient Y | Search X/Y theo contract signed | Buyer search đúng; recipient fallback label không đổi nghĩa ngầm | P1 |
| T08-03 | MH08 | I | Counts không bằng loaded-page length | 55 pending, page20 | Load/filter/search | Exact full count; distribution scope như contract; as_of consistent | P1 |
| T08-04 | MH08 | W/I | Return count separate lifecycle | Delivered order active return | Load status chips/summary | Order vẫn delivered; separate return count/MH15, không order return enum | P0 |
| T08-05 | MH08 | I/B | Immediate manager confirm | Pending age<1h | Confirm once | preparing/source manager/time/actor; no new reserve/shipper | P0 |
| T08-06 | MH08 | W/B | Reject reason blank/whitespace | Pending | Open reject; blank submit/direct RPC | MSG13/invalid_argument; zero effects | P0 |
| T08-07 | MH08 | I/B | Reject valid reason | Pending multiple variant reservation | Confirm reject reason | rejected; full release all once; customer reason projection/notification | P0 |
| T08-08 | MH08 | B | Confirm cancelled/rejected | Terminal orders | Direct confirm RPC | state_changed, no new stock/events/notifications | P0 |
| T08-09 | MH08 | I/W | List stale before click | Pending row; other user rejects | Click confirm | No invalid transition; latest row/count replaces stale | P0 |
| T08-10 | MH08 | B/I | Double-tap confirm/reject | Pending | Rapid same logical request; conflicting buttons | One request/event/effect; counterpart blocked while pending | P0 |
| T08-11 | MH08 | I | Mutation success, refresh failure | Confirm commits; block next GET | Confirm and refetch | Action success retained; list stale warning, không new request replay by new key | P0 |
| T08-12 | MH08 | W/I | Pending filter removes confirmed row | List pending | Confirm MH09 then back | Pending row disappears, count decreases; delivering/return counts independent | P1 |
| T08-13 | MH08 | I/W | Failure/incident warnings actual | Failed attempt1 + incident fixture | Load; open warning | Attempt/reason/actor time actual; incident distinct; MH09 order ID resolved | P1 |
| T08-14 | MH08 | W | Empty/error/refresh/retry | Repo variants | Open; filter no results; fail refresh/retry | Correct async states; no failed API replaced silent demo | P1 |
| T08-15 | MH08 | B/I | Confirm reservation consistency | Reservation broken fixture | Submit confirm | data_integrity rollback, no duplicate reserve/negative qty | P0 |

## 4. MH09 cases

| Test ID | Screen | Type | Scenario | Preconditions | Steps | Expected Result | Priority |
|---|---|---|---|---|---|---|---|
| T09-01 | MH09 | W/I | Manager route guard only | Authenticated Customer own order hoặc Shipper currently assigned task | Open `/manager/orders/:orderId` trực tiếp/back/deep-link | Deny manager route, không render MH09; không suy shared OP-O03 phải deny Customer own order | P0 |
| T09-02 | MH09 | U/W | Payment summary no discount | Subtotal3.450.000 fee30.000 | Load detail | Total3.480.000, no shipping promotion/voucher row | P0 |
| T09-03 | MH09 | U/I | Order/COD/return states independent | delivered, collected, active return | Load then record refund/receiveCOD via owner | Display all independently; no cancelled due return/no COD offset | P0 |
| T09-04 | MH09 | U/W | Actual timeline vs planned stages | Only placed+confirm events | Load timeline | Only actual timestamps; no fictional OTP/auto shipper/stage completion | P0 |
| T09-05 | MH09 | U/I | Timeline sort/dedup/related subjects | Same timestamp events, task/COD refs | Load pages/refetch | Stable time/id, no duplicated milestone fallback/event or notification-history conflation | P1 |
| T09-06 | MH09 | U/W | Actor null is not always system | Deleted manager actor vs automatic event | Render both | Deleted actor unknown, auto system only with source evidence | P1 |
| T09-07 | MH09 | B/I | Exceptional cancel pre-pickup | preparing/awaiting_pickup, no historical pickup | Reason/confirm submit | Cancel + revoke tasks + release once + affected notifications atomic | P0 |
| T09-08 | MH09 | B/I | Exceptional cancel after prior custody | delivering or failed1 with new unpicked task | Direct/stale cancel | Denied even latest task no pickup; no early restock | P0 |
| T09-09 | MH09 | B | Pickup/cancel race | Same order/task pre-pickup | Concurrent assigned shipper pickup + manager cancel | Exactly one commits; stock/custody consistent | P0 |
| T09-10 | MH09 | I/B | Preparing + assignment | Preparing, actual prep completed, valid shipper | Assign via signed I03 | awaiting_pickup only both conditions; one active task; no auto manager role change | P0 |
| T09-11 | MH09 | B/I | Reassignment before pickup | S1 task assigned | Reassign S2; S1 old URL | S2 current, S1 task denied; count unchanged; notify source dedup | P0 |
| T09-12 | MH09 | B/I | Second attempt/early return | First failure, count1 | Choose signed retry or early-return flow | Preserve count/custody/history, no stock release while with shipper | P0 |
| T09-13 | MH09 | B/I | No third attempt | Count2 failure | Try retry action/direct operation | Denied, awaiting_store_return; no new outbound3 | P0 |
| T09-14 | MH09 | B/I | Inspection restock selective once | Goods handed over; sellable+damaged | Manager inspection + same request retry | Only sellable available once; damaged separate; undeliverable_returned | P0 |
| T09-15 | MH09 | W/I | COD missing vs uncollected | No row vs uncollected row | Render both | Missing “Chưa có dữ liệu COD”; no false status/success | P1 |
| T09-16 | MH09 | I | COD/return/chat navigation | Manager valid references | Tap target links | Correct UUID/role recheck; MH12/MH15/MH20 owners, no shipper MH11 guard bypass | P1 |
| T09-17 | MH09 | W | Optional call capability unavailable | Calling approved, no dialer | Tap call | Safe message + number stays; no crash/SMS/business mutation | P2 |
| T09-18 | MH09 | W | Long text/item list/footer | Long address, 40items, keyboard reason | Scroll/small screen/text2.0 | Readable amount/address, footer doesn't cover content, dialog reason retained | P1 |
| T09-19 | MH09 | I/W | Detail state changed remotely | Open pending then auto-confirm | Refresh/subscription/poll | Preparing replaces pending, reject/confirm removed; no phantom shipper | P0 |
| T09-20 | MH09 | I | Aggregate detail error hoặc source audit thiếu | OP-O03 atomic aggregate; source history incomplete fixture riêng | Gây RPC/network failure rồi retry; sau đó tải fixture source thiếu audit | RPC fail thì toàn lần tải error/cached snapshot stale; response hợp lệ source thiếu thì history_complete=false, no fake6 steps | P1 |

| T09-21 | MH07 detail | B/I | Shared detail own Customer allow | Owner-decided OP-O03 projection DR-04 NOT IMPLEMENTED; order owned by Customer A | A calls OP-O03 order UUID | Allow own order/items and sanitized §4.7; buyer/shipper actor identities và order.confirmed_by null, manager capabilities false; không mở MH09 | P0 |
| T09-22 | MH07 detail | B/I | Shared detail other Customer deny | Customer A, order owned by B | A calls OP-O03 B UUID/direct nested projection | Generic unavailable, không order/recipient/item/history/receipt leakage | P0 |
| T09-23 | Shared details | B/I | Shipper shared order RPC deny | Shipper assigned task for order; OP-O03 contract signed | Call shared detail with order UUID | Denied generic even current assignee; task details remain MH11 owner contract | P0 |
| T09-24 | MH09 | B/I | Manager detail allow | Trusted Manager, authorized order; OP-O03 signed | Call detail then open MH09 UUID | Full §4.6 manager projection, correct nullability; mutation permissions still rechecked server | P0 |

| T09-25 | MH09 | B/I | Task2 retained-custody retry | failure1, goodsS1, CIN03 accepted/implemented | Managerarrange task2; Shipperack; record result2 | Newtask2; awaiting_redelivery untilack; delivering onack; count1untilresult; no redispatch/reservation/reset | P0 |
| T09-26 | MH09 handoff | I/B | Store return navigation and COD | Outbound snapshotCustomer/COD, storeSettingscoords | Earlyreturn orfailure2; readstoreleg; remove storecoords | Store destination only, amountcollectnow0, original taskCustomer/CODunchanged; missingcoords unavailable noCustomerfallback | P0 |
| T09-27 | MH09 | B/I | Inspected sellable/damaged ledger | allissued received:2sellable1damaged | Managerphysicalreceipt theninspection; replay | No earlyrestock; onhand+2/damaged+1/reserved0; available increases2; undeliverable_returned once | P0 |
| T09-28 | MH09 | B/I | Missing/partial goods closure gated | issued3 received2; missingpolicyunresolved | Inspect/close/reassignafterpickup | goods_discrepancy noauto terminal/restock; transferafterpickup disabled; decisionrecord required | P0 |

## 5. MH17 cases

| Test ID | Screen | Type | Scenario | Preconditions | Steps | Expected Result | Priority |
|---|---|---|---|---|---|---|---|
| T17-01 | MH17 | B/I | Recipient ownership every role | A/B/M/S inbox fixtures | Login each; list/count and request another recipient | Only own records/count; manager can't read other inbox | P0 |
| T17-02 | MH17 | B | Mark another user's notification | B unread | A PATCH B UUID | Zero visible rows/denied; B read_at unchanged, no success leak | P0 |
| T17-03 | MH17 | W/I | All/Unread and empty variants | Mixed read/unread; zero unread | Switch filters/refresh | Correct rows, MSG62 on unread empty; filter not mark read | P1 |
| T17-04 | MH17 | U/I | Exact unread badge >page size | 55 unread, page20 | Load/count; mark1 | Count55 then54 only confirmed; no page-length badge | P1 |
| T17-05 | MH17 | B/I | First read server timestamp | Unread notification, forged device time | PATCH sentinel; repeat | Server current read_at; repeat preserves first timestamp | P0 |
| T17-06 | MH17 | B | Cannot mark unread/edit protected columns | Read row | PATCH null then title/recipient_id changes | read_at unchanged; non-read columns denied | P0 |
| T17-07 | MH17 | B/I | Two sessions read same notification | A on devices1/2 | Concurrent mark read | One first-read time; count stable0 contribution, no double decrement | P0 |
| T17-08 | MH17 | I | Duplicate source event producer retry | Order mutation committed | Retry producer same event/recipient | One notification row; source event also not duplicated | P0 |
| T17-09 | MH17 | B/I | Same event multi-recipient | Automatic confirm | Producer customer+manager | One row each, same canonical event ID; own inbox isolation | P0 |
| T17-10 | MH17 | I | New notification concurrent read | A has1 unread; new event during read | Mark old then refresh | Count1 for new, not hardcode0; unread page reconciles | P1 |
| T17-11 | MH17 | I | Valid order deep-links by role | Own customer/manager notification | Tap each | MH07 modal vs MH09, actual UUID and target recheck | P0 |
| T17-12 | MH17 | I/B | Reassigned/revoked task link | S1 notification; task now S2 | S1 tap old link | MSG63, no cached recipient/address/item PII | P0 |
| T17-13 | MH17 | U/I | Unknown/malformed subject | Unknown kind/invalid UUID fixture | Tap tile | Safe unavailable, no arbitrary URL/route execution | P0 |
| T17-14 | MH17 | I | Target deleted/missing | Valid notification to missing target | Tap | MSG63, stay in center; read behavior matches signed tap rule | P1 |
| T17-15 | MH17 | I/B | Shipper forbidden chat/returns sensitive target | Notification forged/owner defect subject | Tap/direct target call | Guard/backend deny; no bank/evidence/chat rendered | P0 |
| T17-16 | MH17 | I | Notification read independent chat read | New support message and notification | Mark notification only | Chat message/read count unchanged; only MH20 viewing content updates chat read | P0 |
| T17-17 | MH17 | I/W | Read timeout after server ack lost | Read commits/drop response | Tap/read timeout/refetch | No optimistic double decrement; same row resolves read | P1 |
| T17-18 | MH17 | I/P | Foreground freshness | Stable network, screen open | Insert event from other session; measure | Notification/badge within5s NFR03 target; environment logged | P1 |
| T17-19 | MH17 | I | Resume/reconnect catch-up | App background/offline during events | Resume/connect | Refetch authoritative list/count, dedup; no lost WS-only updates | P1 |
| T17-20 | MH17 | W/I | Loading/error/retry/load-more | Delayed/error/empty variants | Load/next page/retry | Correct indicators, preserve own confirmed data, no silent demo | P1 |
| T17-21 | MH17 | W | No mark-all/push in baseline | Optional not approved | Inspect UI/dependencies | No mark-unread/mark-all/background push/SMS/email | P1 |
| T17-22 | MH17 | B/I | Sensitive content producer | Return/refund/task events | Inspect generated recipient body/target reads | No account details/public receipt URL/token/unnecessary task PII | P0 |
| T17-23 | MH17 | I | Thông báo hủy nhiệm vụ đã thu hồi assignment | Cancel manager committed; shipper nhận notification_only | Shipper tap thông báo | Đọc own nội dung MH17 và mark read, không query task/event raw hoặc hiển thị PII đã bị thu hồi | P0 |

| T17-24 | MH17 | U/W/I | Mark-read fail independent navigation | Own valid target with permission; PATCH fails or timeout | Tap, return read failure, resolve target | Authorized navigation still allowed; no confirmed decrement, read retry visible; denied target MSG63 independent of PATCH | P0 |
| T17-25 | MH17 producers | B/I | Parameterized all required event families | Owned fixtures EV02–05 finalized; external EV CIN09 NOT ACCEPTED; all producers missing | Commit trigger, replay logical request/event, list each role inbox and tap target; inject rollback failure | Exact owner/shared-offered recipient set/type/ID/destination; one source and row per recipient; no forbidden PII; only committed event, count correct; sync rollback policy, external acceptance prerequisite | P0 |
| T17-26 | MH17 | U/I | Old unread count response after read ack | Count request inflight before markRead; own row | Ack read then deliver older count/list callback | Discard old epoch; refetch exact count, no unread resurrection/double decrement | P0 |
| T17-27 | MH17 resolver | U/B/I | Return failure targets typed once | CIN09 offered return_pickup_failed/redelivery_failed fixtures; task return_request_id present | Manager taps return_request target, also malformed null-link fixture | MH15 actual return UUID, no guessing task target→MH09; missing relationship fails closed; external acceptance/runtime pending | P0 |

| T17-28 | MH17 | B/I | Recipient changes after emit | originalM1/S1manifest; rolesassignedchanged | Replay sameevent/intent | Frozen IDs/targets, nonewM2/S2recipient; ownrawrow independent currenttarget permissions | P0 |
| T17-29 | MH17 | B/I | Parent/assignment semanticdedup | returnapproved/rescheduled/redeliveryassigned CIN09fixture | Executeparent+child thenretry both | Parent emitsoneShipalert; child auditonly; unique recipient/event alone insufficientoracle | P0 |
| T17-30 | MH17 | B/I | Deleted recipient historicalmanifest | profileS1/inboxrows+manifest | Deleteprofile dedicatedfixture; replay | FKcascade rowgone; manifestretained; no recreation/deletedprofilefanout | P0 |
| T17-31 | MH17 | B/API | Private metadata/receipt denial | future private tables/grants applied isolatedenv | Customer/Manager/Shipper directread/executehelper attempts | Allclientsrawdenied; restricted authorizedRPC safeownprojection only | P0 |

### 5.1 Event-to-test fixture coverage — revision1.2

Each row parameterized commit/replay/facts-conflict/rollback/inbox-role/target-recheck. SourceFacts exact9keys CIN09, null irrelevant, fixture uses syntheticUUIDs A/B/M1/M2/S1/S2; cancel assignedShipper separate variant, assign/reassign two exact types, automaticCustomer/Manager two recipients. Owner EV02–05 oracle finalized, dependency setup still required; other producers must accept CIN09 and provide actual source suite/fixture symbols (not invented). All NOT RUN; external fixtures plan != producer agreement.

| Fixture/Test | Event type | Recipients | Target/ID | Destination | Source | Status |
|---|---|---|---|---|---|---|
| EV-01 / T17-25 | order_placed | Manager | order = order.id | MH09 | II.1.2.1 step 7; MSG-59 | SHARED CONTRACT NOT ACCEPTED; NOT IMPLEMENTED/NOT RUN |
| EV-02 / T17-25 | order_confirmed_manual | Customer | order = order.id | MH07 detail | II.1.2.1 step 9A; BR-COM-12 | OWNER DECIDED; NOT IMPLEMENTED/NOT RUN |
| EV-03 / T17-25 | order_confirmed_automatic | Customer + Manager | order = order.id | Customer MH07 / Manager MH09 | II.1.2.1 step 9C; BR-COM-12 | OWNER DECIDED; NOT IMPLEMENTED/NOT RUN |
| EV-04 / T17-25 | order_rejected | Customer | order = order.id | MH07 detail | II.1.2.1 step 9B; MSG-25 | OWNER DECIDED; NOT IMPLEMENTED/NOT RUN |
| EV-05 / T17-25 | order_cancelled | Customer; affected assigned Shipper nếu có | Customer order; Shipper notification_only = Customer order.id; Shipper event.id | Customer MH07 / Shipper MH17 only | II.1.2.2 step 6; BR-COM-13 | OWNER DECIDED; NOT IMPLEMENTED/NOT RUN |
| EV-06 / T17-25 | task_assigned / task_reassigned | Current assigned Shipper; old Shipper existing target rechecks, no new alert baseline | delivery_task = task.id | MH11 current assignee only | II.1.2.3 step 7; II.1.2.5 steps 12/21 | SHARED CONTRACT NOT ACCEPTED; NOT IMPLEMENTED/NOT RUN |
| EV-07 / T17-25 | outbound_delivered | Customer | order = order.id | MH07 detail | II.2.4.2.1; BR-COM-16 | SHARED CONTRACT NOT ACCEPTED; NOT IMPLEMENTED/NOT RUN |
| EV-08 / T17-25 | outbound_failed | Manager | order = order.id | MH09 | II.1.2.3 step 3; BR-COM-18 | SHARED CONTRACT NOT ACCEPTED; NOT IMPLEMENTED/NOT RUN |
| EV-09 / T17-25 | custody_incident | Manager | delivery_task = task.id | Authorized task→order→MH09 | II.2.4.2.1; MSG-32 | SHARED CONTRACT NOT ACCEPTED; NOT IMPLEMENTED/NOT RUN |
| EV-10 / T17-25 | cod_received | Collecting Shipper | cod = cod_collections.order_id | MH12 | II.1.2.4 step 7; MSG-37 | SHARED CONTRACT NOT ACCEPTED; NOT IMPLEMENTED/NOT RUN |
| EV-11 / T17-25 | return_submitted | Manager | return_request = return_request.id | MH15 | II.1.2.5 step 7; MSG-61 | SHARED CONTRACT NOT ACCEPTED; NOT IMPLEMENTED/NOT RUN |
| EV-12 / T17-25 | return_pickup_approved | Customer + assigned Shipper, same parent event | Customer return_request; Shipper delivery_task = Customer return_request.id; Shipper task.id | MH14 / MH11; assignment child audit-only | II.1.2.5 step 12; BR-COM-26 | SHARED CONTRACT NOT ACCEPTED; NOT IMPLEMENTED/NOT RUN |
| EV-13 / T17-25 | return_initial_rejected | Customer | return_request = return_request.id | MH14 | II.1.2.5 step 14; MSG-48 | SHARED CONTRACT NOT ACCEPTED; NOT IMPLEMENTED/NOT RUN |
| EV-14 / T17-25 | return_pickup_failed | Manager | return_request = task.return_request_id (non-null required) | MH15 | II.1.2.5 step 19; MSG-45 | SHARED CONTRACT NOT ACCEPTED; NOT IMPLEMENTED/NOT RUN |
| EV-15 / T17-25 | return_collection_rescheduled | Customer + current Shipper; previous changed Shipper notification_only | Customer return_request; current Shipper delivery_task; old notification_only = return_request.id / task.id / root event.id | MH14 / MH11 / MH17 only; parent emits | II.1.2.5 step 21 affected users | SHARED CONTRACT NOT ACCEPTED; NOT IMPLEMENTED/NOT RUN |
| EV-16 / T17-25 | return_more_evidence_requested | Customer | return_request = return_request.id | MH14 | II.1.2.6 step 3; MSG-46 | SHARED CONTRACT NOT ACCEPTED; NOT IMPLEMENTED/NOT RUN |
| EV-17 / T17-25 | return_inspection_rejected | Customer | return_request = return_request.id | MH14 | II.1.2.6 step 17; MSG-48/54 | SHARED CONTRACT NOT ACCEPTED; NOT IMPLEMENTED/NOT RUN |
| EV-18 / T17-25 | refund_recorded | Customer | return_request = return_request.id | MH14 | II.1.2.6 step 13; MSG-52 | SHARED CONTRACT NOT ACCEPTED; NOT IMPLEMENTED/NOT RUN |
| EV-19 / T17-25 | rejected_goods_redelivery_assigned | Current assigned Shipper | delivery_task = task.id | MH11 no COD | II.1.2.6 step 20 | SHARED CONTRACT NOT ACCEPTED; NOT IMPLEMENTED/NOT RUN |
| EV-20 / T17-25 | rejected_goods_redelivery_completed | Customer | return_request = task.return_request_id (non-null required) | MH14 | II.1.2.6 step 25 | SHARED CONTRACT NOT ACCEPTED; NOT IMPLEMENTED/NOT RUN |
| EV-21 / T17-25 | rejected_goods_redelivery_failed | Manager | return_request = task.return_request_id (non-null required) | MH15 | II.1.2.6 step 28; MSG-55 | SHARED CONTRACT NOT ACCEPTED; NOT IMPLEMENTED/NOT RUN |
| EV-22 / T17-25 | support_message_received | Customer msg→allManagers except sender; Manager msg→conversationCustomer; no Shipper/self | conversation = message.conversation_id | MH20 via Chat contract | MSG-66; BR-COM-34/35 | SHARED CONTRACT NOT ACCEPTED; NOT IMPLEMENTED/NOT RUN |

Approval/reschedule/redelivery-assignment uses parent emitted manifest; child assignment audit-only. Tests assert shipper receives one semanticalert not two distinct event IDs. Replays with Manager role/shipper changed keep original frozen recipient IDs, no additional inbox. Expected denial after role/task revoke still raw own notification readable but destination MSG63. Source PK dedup doesn't grant current object rights. Chat Customer→Managers exceptsender and Manager→Customer proposal NOT external ownerapproved.

## 6. Cross-screen, race và non-functional cases

| Test ID | Screen | Type | Scenario | Preconditions | Steps | Expected Result | Priority |
|---|---|---|---|---|---|---|---|
| TX-01 | 07/08/09 | B/I | Cancel vs manual confirm | Pending with reserved variants | Two connections concurrently submit | Exactly one valid state; losing code current status, stock/events/notifications consistent | P0 |
| TX-02 | 08/09/17 | B/I | Manager vs auto-confirm | Pending threshold reached | Manager confirm/reject concurrent job | Only winner event/source; no double notifications or reserve | P0 |
| TX-03 | 08/09 | B/I | Two managers different keys | Pending | M1 confirm and M2 reject | One commit; other state_changed; reason/effects only winning action | P0 |
| TX-04 | 07/08/09 | B | Same request different payload | Original reject receipt | Same UUID with changed reason/target/operation | idempotency_conflict, no new effects or replay of unrelated response | P0 |
| TX-05 | 07/08/09 | B/I/U | Same request replay after later state | Owner-scoped receipt fixture NOT IMPLEMENTED; confirm receipt preparing then poll cache delivering | Retry original confirm request, return historical preparing receipt; force latest refresh failure | Original receipt replay no effects; action confirmed; cache never regresses delivering; stale read-only, mutation controls disabled, refetch retry same read | P0 |
| TX-06 | 07/08/09 | B/I | Receipt lookup not-found while inflight | Long running mutation | Lookup key then retry same | Unknown until authoritative result; no new key/new business operation | P0 |
| TX-07 | All | I | App crash before/after commit | Durable pending command metadata signed | Kill/relaunch at both points | Same user recovery with same key; committed fetched, never duplicate | P0 |
| TX-08 | All | I/W | Logout/login account B | A list/detail/count/request inflight | Logout A/login B; let A responses arrive | A caches/private UI/subscriptions cleared; callbacks discarded; B scoped data only | P0 |
| TX-09 | All | I/B | Session expiry/role refresh failure/receipt sau thu hồi role | Open protected page; có receipt manager cũ | Expire token hoặc thu hồi role; thử detail và receipt lookup cũ | Hide private data, MSG07/login hoặc generic denied; receipt không lộ order payload khi quyền hiện tại mất; no metadata role bypass | P0 |
| TX-10 | All | U/W | Unknown enum/data shape | New/invalid status payload | Decode/render | unsupported safe state/read-only, no map pending or crash | P1 |
| TX-11 | All | U/I | Stable pagination same timestamp/new inserts | >20 rows equal timestamps | Page1, insert newer, page2, refetch | Cursor stable/no duplicate IDs; new rows refresh head; query change resets cursor | P1 |
| TX-12 | 08/09/17 | I | List-detail-notification sync | Pending visible in all contexts | Confirm MH09; back/tap notification | Consistent latest preparing; counters right; read notification no transition | P0 |
| TX-13 | 08/09/17 | B/P | Auto-confirm deadline/recovery | Before59:59/exact1h/overdue orders | Run normal job then outage/recovery | No early confirm; <=60s after threshold normal; overdue once, no auto assignment | P0 |
| TX-14 | All | P | p95 latency target | 50users, 5.000orders/1.000variants, fixed env | Run list/search/detail/mutations load test | Readp95<=3s; mutationp95<=5s or documented fail; no page-only search cheat | P1 |
| TX-15 | All | W/I | Mobile/text compatibility | Signed min/newer OS, sizes | 320/360/412dp, landscape,text1/1.3/2 | No essential clipping; scroll/keyboard/action footer accessible | P1 |
| TX-16 | All | I | Secure session storage/logs | Auth owner implementation | Inspect actual storage/runtime/error logs | Protected credentials; no secrets/token/bank/raw SQL disclosed | P0 |
| TX-17 | 09/17 | B/I | Immutable audit/notification creation privilege | Customer/manager/shipper | Direct INSERT/UPDATE/DELETE audit/create notification | Ordinary clients denied; read_at column only exception | P0 |
| TX-18 | All | I | Preserve exactly20 screens | All routes/dialogs integrated | Review route/screen registry + demo nav | Customer detail dialog not new primary screen; no dashboards/profile | P1 |
| TX-19 | 09/17 | B/I | COD survives refund before settlement | Delivered/collected full COD; refund recorded | Load details; settle original COD via owner | Same full obligation; no offset; each lifecycle correct | P0 |
| TX-20 | 08/09 | B/I | Atomic failure halfway stock release | Reject/cancel multi-variant, unexpected SQL error (not controlled business failure) | Inject failure after first related write | Entire transaction rolls back, no partial release/event/notification/receipt | P0 |
| TX-21 | 17 | B/I | Notification producer failure rollback | Owner sync atomicity; external acceptance perproducer, business transition producer error | Force notification/event insert error | Transaction rollback policy honored; no confirmed action without required persisted event notification | P0 |
| TX-22 | All | I/P | Backup/restore acceptance dependency | Signed backend plan | Run documented restore in separate env | RPO<=24h/RTO<=4h,>=7daily points; evidence stored; not Flutter feature claim | P1 |
| TX-23 | All | B/I | Scoped Orders identity compatible external global event key | Own receipts/meta applied dedicatedenv; external incident requires nonnull request | Same client UUID Orders confirm and external incident; crossactor lookup; changedOrder intent | Separate principals/nativeexternalkey; generic Orders root request_id=null, incident nonnull unique unaffected; no crossactor receipt leak or duplicated own effects | P0 |
| TX-24 | 09/17 | B | Child audit causation và dedup | Owner private metadata/event protocol chosen and corresponding migration applied in isolated test env | Tạo child thiếu root; retry child cùng root/kind/subject; inspect audit graph | Child thiếu causation bị chặn, child retry không thêm row, mỗi change truy được root request/actor/event | P0 |

| TX-25 | 07/08/09 | U/W/I | Delayed receipt after fresher detail | Fresh delivering cache; old confirm receipt preparing response held | Deliver old receipt; make latest refresh fail then recover | Receipt resolves action only; stale delivering retained read-only, no manager confirm/reject revival; recover latest coherent aggregate | P0 |
| TX-26 | All | U/W/I | Out-of-order reads same session and query | Read E1 inflight; mutation/invalidation bumps E2, detail E2 loaded | Deliver E1 late including page/count; switch query/session variants | Drop old epoch/query/session results, no cross-snapshot sections; only E2 accepted, cursor dedup | P0 |
| TX-27 | 07/08/09 | U | Full wire DTO/nullability/error normalization | Owner §4.6/5.3 envelope fixtures; adapter not implemented | Parse complete Order/list/detail/receipt; remove required key, null non-null, unknown enum; normalize SDK/network/business fixture | Complete exact owned wire accepted; invalid shape unsupported; no aliases/subset; current_order error ref never full cache; unauthorized ref null; no raw SQL exposed | P0 |
| TX-28 | MH07 | B/I | Cancel replay after cancelled | Owner DR-01 protocol; original cancellation receipt committed, order terminal | Retry same request+payload; lookup; retry changed body | Same old success before pending check, no second release/event; changed fingerprint conflict; no lost-response false ineligible | P0 |

| TX-29 | Orders | B/I | Terminal business failure replay after later state | pending race lost manualrequest, stored state_changed | Retry samekey after order laterdelivered; inspect ledger/event | Same immutable failure, no effects; failure ref not cachewrite; changed intent conflict | P0 |
| TX-30 | Orders | B/I | Unexpected errors never poison receipt | Domain writes then forced SQL/deadlock/notification error | Submit; lookup; retry samekey after dependency repaired | Outer rollback all stock/events/rows/receipt; not_found not proof ofinflightrollback; samekey safely succeeds once | P0 |
| TX-31 | Orders job | B/I | Early job key not permanently failed | pending55min then eligible61min serverclock | Early job then later sameorder stablekey; client tries systemsource | First skipped nofailedreceipt; later confirms once; clientsystem denied | P0 |
| TX-32 | 17 | B/I | Frozen manifest immutable replay | source emittedM1 thenM2newmanager/reassignment | Replay samefacts; changedfacts; read clientmetadata | Same old IDs/targets noM2fanout; changedfacts conflict; private manifest denied | P0 |
| TX-33 | Orders | B | Audit generic vs incident CHECK | Ownmetadata receiptfixture plus incident task | Genericroot requestNULL; incidentNULL; childmissingparent | Generic permitted withprivatekey; incidentNULL rejected existingCHECK; childFK/rootgraph invalid denied | P0 |
| TX-34 | Orders | U/B | Canonical fingerprint normalization | FP01–05 fixture below | Permutekeys/trim/reasonCRLF/changedbody/NUL | JSONBequal normalized exactintent; interiorcase/spacing differs; malformed denied | P0 |
| TX-35 | Orders | U/I | HTTP200 error/lookup union | Complete §9 envelopes | Parseokfalse, lookupfailed/notfound, invalidcombinations | Never UI success onHTTP200 alone; union validated; all nullablekeys required | P0 |
| TX-36 | Orders | B/I/U | Cursor scope/query/limit isolation | ownCustomer cursor; otheruser/role/search filters | Changebindings or malformedcursor, then authorizedsecondpage | invalid_cursor notbroadenaccess; RLS everypage; currentepochonly append | P0 |

## 7. Requirement-to-Test Traceability Matrix

Rules from DOCX II.3.1, Common II.3.2; operational flows II.1.2; exact test definitions above proposed.

| Requirement/source | Test IDs | Coverage/limitation |
|---|---|---|
| BR-COM-02/03, CR01 | T07-01, T07-11, T07-16, T08-01, T09-01, T09-21, T09-22, T09-23, T09-24, T17-01, T17-02, T17-12, T17-15, T17-22, TX-17 | Ownership, role, sensitive access, deep-link |
| BR-COM-06/07/09, CR04 | T07-04, T07-07, T07-20, T07-21, T09-02 | Snapshot and fee; Hanoi placement server validation is Checkout owner integration |
| BR-COM-08/10/11 | T07-09, T07-13, T08-05, T08-07, T08-15, T09-14, TX-20 | No re-reserve, full release/restock; concurrent placement inventory acceptance owner |
| BR-COM-12/14, NFR06/09 | T08-05, T08-08, T08-09, T09-19, TX-01, TX-02, TX-03, TX-13 | Transition/job race; requires actual RPC/job |
| BR-COM-13 | T07-09, T07-10, T07-11, T07-12, T09-07, T09-08, T09-09 | Own pending, exception pre-custody |
| BR-COM-15 | T09-10, T09-11, T17-12 | Preparation+assignment, current task access |
| BR-COM-16/20/21/22/31 | T09-03, T09-15, T09-16, TX-19, T17-16 | Four states + financial independence; fullCOD mutation owner tests linked |
| BR-COM-17/18/19 | T08-13, T09-08, T09-12, T09-13, T09-14, T17-08 | Attempts/failure alert/inspection only restock |
| BR-COM-23/24/25 | T07-17, T07-18, T07-19 | Entry and submit timing; video/bank/reason actual submit owner Returns suite |
| BR-COM-26–30 | T09-03, T09-14, T09-16, T17-22, T17-25, T17-27 (EV-11–EV-21), TX-19 | Read/integration safety; full Returns owner tests required for pickup/refund/redelivery |
| BR-COM-32/36 | T07-13, T07-14, T08-10, T17-05, T17-06, T17-07, T17-08, T17-09, T17-17, T17-23, T17-25, T17-26, T17-27, TX-04, TX-05, TX-06, TX-07, TX-17, TX-21, TX-23, TX-24, TX-28 | Persist/dedup/read/receipt replay và module-scoped identity/event compatibility |
| BR-COM-34/35 | T07-22, T09-16, T17-15, T17-16 | Text chat linkage, no shipper, separate read states |
| CR02 | TX-08, TX-09 | Account-switch lifecycle and subscription teardown |
| CR03/06 | T08-06, T08-07, T08-10, T07-09, T07-13, T09-07 | Reason/confirmation/duplicate taps |
| CR05/14/15 | T07-02, T07-12, T07-14, T07-21, T08-11, T08-14, T09-18, T09-20, T17-20, TX-15 | Async/format/scroll/error/no false success |
| CR07/08 | TX-01, TX-02, TX-03, TX-04, TX-05, TX-06, TX-07, TX-20, TX-21, TX-25, TX-26, TX-28, T07-14 | Atomicity, unknown-result recovery |
| CR09/11 | T09-03, T09-04, T09-05, T09-06, T09-21, T09-24, TX-10, TX-12, TX-17, TX-24, TX-27 | Status mapping/audit source/immutability/causation |
| CR12/13 | T07-03, T07-05, T07-06, T07-08, T08-02, T08-03, T17-03, T17-04, T17-11, T17-12, T17-13, T17-14, T17-19, TX-11 | Lists/cursors/read/navigation |
| CR10 | T17-22 | Evidence permissions only; upload validation suite belongs Returns owner |
| MSG07–13/21–26/29–32/38/41/59–63/66 | Cases corresponding auth/network/reason/stale/alerts/read/deep-link | Localization preserves English spec meaning; UI proposed strings main§5.3 |
| NFR01/02/03 | TX-14, T17-18, T17-19 | Performance thresholds proposed in group doc, measure not assume |
| NFR04/05 | Authorization cases, TX-08, TX-09, TX-16, TX-17 | Device storage unresolved Auth blocker |
| NFR06/07/08/09/10 | TX-01, TX-02, TX-03, TX-04, TX-05, TX-06, TX-07, TX-13, TX-19, TX-20, TX-21, T07-07, T07-20 | Transaction/idempotency/financial/time/recovery |
| NFR11 | TX-22 | Platform/team backup dependency; not independently within four screens |
| NFR12 | Async/error tests | Checkout5min usability is owner dependency, no invented four-screen metric |
| NFR13/14/15 | TX-15, TX-17, T09-04, T09-05, T09-06, full unit/DB suite | OS target signing pending |
| NFR16 | T17-22 + Returns evidence suite | Không duplicate file upload feature |
| OR01/02/03/04/05 | TX-18 + integration phases | Scope/stack/shared contracts/integration order |

### 7.1 NT01–NT30 đối chiếu theo nguồn thực sự có

`SPECIFIED IN GROUP DOC` II.3.4 OR-08 chỉ cung cấp nhóm chủ đề sau. Full business report/test table chưa có; không gán nội dung chi tiết từng NT riêng. Mapping này là `PROPOSED GROUP-LEVEL COVERAGE`, cần bổ sung exact acceptance câu chữ/ID khi nhóm cung cấp nguồn.

| Nhóm NT được OR08 nêu | Topic theo nguồn | Cases liên quan bốn màn | Phụ thuộc owner |
|---|---|---|---|
| NT01–NT07 | Delivery area/totals/concurrent stock/confirmation/cancellation | T07-07, T07-09, T07-10, T08-05, T08-07, T08-08, TX-01, TX-02, TX-03, TX-13, TX-20 | Checkout/Inventory server validation và oversell suite |
| NT08–NT11 | Delivery attempts/returned stock/COD | T09-03, T09-09, T09-10, T09-11, T09-12, T09-13, T09-14, TX-19 | Deliveries/COD actual operation suite |
| NT12–NT18 | Returns/refunds/denied access/duplicate actions | T07-17, T07-18, T07-19, T09-03, T09-14, T17-01, T17-02, T17-08, T17-15, T17-22, TX-04, TX-05, TX-17, TX-19 | Returns evidence/submission/refund/redelivery suite |
| NT19–NT21 | Checkout separation/idempotency | T07-08, T07-15, T07-17, TX-04, TX-05, TX-07, TX-18 | MH16 vs MH18 placement contract |
| NT22–NT24 | Notifications | T17-01, T17-02, T17-03, T17-04, T17-05, T17-06, T17-07, T17-08, T17-09, T17-10, T17-11, T17-12, T17-13, T17-14, T17-15, T17-16, T17-17, T17-18, T17-19, T17-20, T17-21, T17-22, T17-23, T17-24, T17-25, T17-26, T17-27, TX-08, TX-12, TX-21 | Event producers from all owners |
| NT25–NT26 | Maps | No maps implementation; T07-15 excludes customer GPS/MH18 | Minh Đức map tests |
| NT27–NT29 | Chat | T09-16, T17-15, T17-16 | Dung An/Sơn full chat tests |
| NT30 | Screen count/ownership | TX-18 | Shared router/screen registry review |

## 8. Execution report template và acceptance gates

| Test ID | Environment/commit/migrations | Actual result | Status | Evidence | Defect/owner |
|---|---|---|---|---|---|
| Điền khi chạy | Device/OS, user role, backend test ref, network | Không điền trước | Not run/Blocked/Pass/Fail | Redacted logs/screenshots/SQL output | Linked defect |

- Gate A contracts: Q01–Q13 liên quan đã signed; tests marked blocked có owner/API dependency, không giả Pass.
- Gate B unit/widget: mapper/status/async/action/dialog/query/read/resolver suite pass, formatter/analyzer pass.
- Gate C backend: allowed/denied RLS/RPC, stock rollback, races/replay/job/producers pass với actual versioned migrations.
- Gate D integration: order→delivery→COD, cancel/failure/returns navigation, notifications/read/deep-link/account switch pass.
- Gate E release: signed NFR/OS/layout targets đo đạt; defects P0 đóng; mỗi NT baseline có nguồn/coverage/result đầy đủ.

Đặc tả/test plan hoàn thành không đồng nghĩa tests được thực thi hoặc bốn feature sẵn sàng release.

## 9. Historical remediation test-plan delta — revision 1.1 (superseded where owned v1.2)

AUD-06 oracle FIXED bằng T09-01 (route) và T09-21–24 (API). AUD-04/08 local ordering/replay scenarios TX-05/25–28. AUD-09 read failure/notification_only T17-23/24. AUD-07 PARTIALLY FIXED: đủ 22 event-family fixture rows nhưng exact fixtures/producers/recipient policies phải ký DR-01/DR-03; chưa đủ evidence đóng integration test gap. Không tuyên bố test nào PASS.

[Decision Log](Technical_Decision_Log.md), [Remaining Issues](Remaining_Issues.md), [Remediation Report](Post_Audit_Remediation_Report.md) xác định trạng thái gates. Unit/widget design có thể chuẩn bị bằng test-only fakes ghi rõ draft contract; không dùng fake làm production fallback. Historical global alternative removed: current TX23 uses scoped protocol; no choice left to coding agent. Điều kiện này không là requirement bổ sung đã duyệt.

## 10. Finalization contract fixtures — revision1.2

No fixture executed. IDs below reference exact ownerwire §9 DataAPI, not source files/classes already written.

| Fixture | Exact inputs/oracle | Acceptance test |
|---|---|---|
| FP-01 | same UUID canonical case/keyordering; reason leading/trailing listedWhiteSpace and CRLF→LF | TX34 JSONBequal; samekey sameenvelope |
| FP-02 | reason interior two spaces vs one, uppercase/lowercase differ | TX34 idempotency_conflict, no repeated effects |
| FP-03 | changed order/operation for sameprincipalrequest | TX23/34 conflict; otherprincipal sameUUID independent |
| FP-04 | NUL/invalidUUID/unknownarg/1001scalar reason | invalid_argument beforeclaim; no receipt |
| FP-05 | SubmitA/restart/loginB/loginA, preserveexactreason/key | TX-07/08/09; B inaccessible, Alookup/samekeyretry |
| CF-01 | DataAPI§9.1/9.2/9.3/9.20/9.21 full required21/11keys/list/detail safeCustomer | TX27/T09-21–24 complete strict parse |
| CF-02 | §9.4/9.12/9.17/9.18 mutation requests and §9.5/9.22–24 historicalreceipts | TX28; receipt.current_order null, orderfullrequired |
| CF-03 | §9.6/9.7/9.15 lookup3unionvariants | TX35 rejectinvalidcombos/missingnullablekeys |
| CF-04 | §9.14/9.16 AppError terminal/denied; SDK401/403/23505/40P01/57014 | TX29/30/35 exactmapping, deniedrefnull, no rawSQL |
| CF-05 | §9.8/9.9 rawnotification vs RPCenvelope | T17-06/07; serverfirstreadtime, rawarraynotinventedenvelope |
| CF-06 | Each CIN09SourceFacts9requirednullkeys+typedtargets+manifest | EV01–22/T17-25/28–31+TX32; externalacceptance pending |

Finalization coverage additions: BR13–19 → T09-25–28/TX30/31/33; BR32/36 → TX29–35/T17-28–31; CR07/08/09/11 → TX29–36/CF01–06; DR01→FP01–05/TX23/29–35; DR02→T09-25–28; DR03→EV01–22/TX32/T17-28–31; DR04→TX27/35/36. Historical1.1 §9 remains a snapshot, current fixture/gate authority supersedes pending ownlabels. [Decisions](Final_Technical_Decisions.md), [CrossContracts](Cross_Module_Integration_Contracts.md), [Readiness](Implementation_Readiness_v1.2.md).
