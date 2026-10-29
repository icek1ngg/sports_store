# Implementation Readiness — revision 1.2

Ngày08/10/2026; repository snapshot `77b3623e863857237816752151067acae07f0d3d`. Đánh giá từ source thực tế + owned technical decisions; không dựa riêng độ dài tài liệu. Chưa triển khai code/RPC/schema/job, chưa chạy runtime tests trong lượt finalization.

## 1. Verified baseline

- Flutter foundation6Dartfiles: `lib/main.dart::main`, `lib/app/sports_store_app.dart::SportsStoreApp`, `lib/app/router/app_router.dart::appRouterProvider` chỉ `/`, `lib/app/theme/app_theme.dart::AppTheme.light`, `lib/core/config/supabase_config.dart::SupabaseConfig`, `lib/core/supabase/supabase_providers.dart::supabaseClientProvider`.
- pubspec Dart^3.13.2, flutter_riverpod3.4.3, go_router18.0.2, supabase_flutter2.18.0. Feature-firstMVVM là agreed structure, chưa có các featuremodels/repos/VM/pages/authguards.
- Three migrations define18publictables/grants/RLS; existing notifications recipientread + first-readstamp, raw OrdersreadOwn/Manager. No transactional OrderRPC, persistent receipts, typed event metadata, producers, job or shared custody proof. Config realtimeenabled không chứng minh publication/authorized subscriptions.

## 2. Per-screen decision

| Screen | Current conclusion | Owned work có thể bắt đầu | Không được bật/claim full trước khi đủ |
|---|---|---|---|
| MH07 | **READY FOR PARTIAL IMPLEMENTATION** | Canonical DTO/domain/query/VM/widgets, own safe list/detail RPC design, search/filter/count, detail/tracking modal, session/error/state tests; cancellation code theo exactowned receipt interface | Liveauth CIN01; actualRPC/migrations+protectedstore; stockrelease/custody CIN03/04; returncreate CIN08 cutoff+serverAPI; external events/history fixture |
| MH08 | **READY FOR PARTIAL IMPLEMENTATION** | Managerlist/count/search UI+safeprojection, confirm/reject dialogs/recovery, own manual/jobconfirmation receipt+producer futurecode | RealAuth, placedreservedorder CIN02, actualownRPC/job applied/tested; rejectstockrelease CIN04; Deliveryalerts/proofs CIN03/09; no fake servercount |
| MH09 | **READY FOR PARTIAL IMPLEMENTATION** | Details/items/payment/timeline/4lifecycle rendering, ownershipguards, ownconfirm/reject/exceptioncancel orchestration interface, disabled externalactions + unavailable UX | **BLOCKED BY EXTERNAL DEPENDENCY** for assignment/retry/revoke/storeleg/receipt/inspection CIN03/04/05/06; **REQUIRES BUSINESS DECISION** only lost/partialfinalclosure/transferafterpickup branches; no unverified custody enablement |
| MH17 | **READY FOR PARTIAL IMPLEMENTATION** | Inbox SDKadapter/list/read/count/state/filter, guardedtypedresolver, own4producerfamilies metadata/manifest futureimplementation, exacttestfixtures | Auth/routes CIN01; actualownbackendproducers/metadata; external Checkout/Delivery/COD/Returns/Chat CIN09 acknowledged/implemented, authorized targetread adapters/routes real; no producercontract-only acceptance |

Không màn nào **READY FOR FULL IMPLEMENTATION** ở trạng thái source hiện tại. “Partial” cho phép coding components owned theo một design đã chốt, không cam kết app đã chạy hoặc tiếp nhận module của thành viên khác. Auth/backend deployment absent là external/runtime integration gate, không bắt coding agent chọn lại own architecture. Local test fakes chỉ dùng trong tests, no silent productiondemo.

## 3. Shared dependency readiness

| Dependency | Design / authority | Implementation status | Gate |
|---|---|---|---|
| CanonicalOrderDTO/query/errors/cache/pending abstraction | OWNER DECIDED DR01/04 | All Dartclasses/adapter missing | Có thể code own exactcontract; secure adapter CIN01 before live commands |
| Scoped receipts/metadata/manifest | OWNER DECIDED DR01/03 | Proposedprivate tables/functions absent | FutureactualCLI migrations, privilege/atomic/concurrent tests, deployment evidence |
| SafeCustomeraggregate/Managerlist/details | OWNER DECIDED | RawSQLtables existing; RPCmissing | Implement restrictedreadprojection & deny tests; no rawCustomertask/eventRLS expansion |
| Manual/auto confirmation | OWNER DECIDED | MissingRPC/job/producer | Realreservedfixture CIN02, trustedserverjob≥1h, eligiblewithinproposed60s measured; noautoassign |
| Inventory release/dispatch/inspection | SHARED CONTRACT NOT ACCEPTED | Ledgerconstraints only | CIN04 ownedservice accepted/atomic once/malformedmovement tests |
| Custody/retry/store return | SHARED CONTRACT NOT ACCEPTED | Task/attemptconstraints only | CIN03 accepted/state/custody evidence/actionRPCs/task2fullflow |
| COD/Returns/Chat | EXTERNAL DEPENDENCY | Selectedschema only, no featurehandlers | CIN05/06/08/09 safeprojections/auth/routes/producer fixtures |
| Business residuals | REQUIRES BUSINESS DECISION | No approveddecision | Exact7-daycutoff; lost/partial disposition; postpickuptransfer; no new closure edge assumed |
| NFR/minOS/NTexact | UNAVAILABLE EVIDENCE | No benchmark/device report | Groupfullreport/platform targets, actualload/device evidence |

## 4. Audit closure status (documentation, not runtime)

| Finding | v1.2 status | Evidence / residual |
|---|---|---|
| AUD-01 | FIXED | Own OptionC decision exact DataAPI§7/DR01, no global registry ambiguity. Runtime implementation remains absent, externalmodules not included in receipt |
| AUD-02 | PARTIALLY FIXED | Owncancel/counterconsumer predicates exact; CIN03/04 recommendedflow NOT ACCEPTED; lost/transfer business unresolved |
| AUD-03 | FIXED | Owned §4.6/5.3/6.1/9 exact keys/types/null/envelope/errors/search/cursor/projections; external adapter semantics/requests not falsely approved |
| AUD-04 | FIXED | Main§12.5 outcome/cacheepochs + TX05/25–27/29; no receipt snapshot cache overwrite |
| AUD-05 | PARTIALLY FIXED | Ownproducer identity/fanout/frozenmanifest fixed; externalCIN09 acceptance and actualproducer missing |
| AUD-06 | FIXED | T09-01 route deniedCustomer vs T09-21–24 ownOrderRPC allowed; rawshipperOrderdetail denied |
| AUD-07 | PARTIALLY FIXED | 22 eventfamily oracles + CF06/EVmatrix exact; externalowners must accept/sourcefixtures; no tests run |
| AUD-08 | FIXED | Sequence/§7.3 auth-before-replay/state, terminalfailreplay, unexpectedrollback, timeout/restartsamekey |
| AUD-09 | FIXED | Frozenmanifest sequence + read/navigation independence + notification_only no dereference |
| AUD-10 | FIXED | P4C actualcoreconfirmation before P5realDelivery/COD; localownedwork independent Sharedacceptance, no delayingallintegration |

## 5. Full handoff acceptance gates

1. CIN01 authtrustedroles/sessionepoch/protectedpending store exists and account-switch/expiry/restart tests measured.
2. Own newmigrations/readRPC/mutationreceipt/metadata/notifications/job actuallycreated/applied; schemas/grants/SQLtransaction/races/rollback/replay tested, no non200/error falsely success.
3. CIN02 Checkout actualreservation/snapshot/dedup; CIN03/04 Delivery/Inventory exactagreed custody/dispatch/release/inspection and2-attemptflow; CIN05fullCOD continuity real integration.
4. CIN06/08 Returns authoritativeeligibility + groupcutoff; bank/evidence ownmodule privacy unaffected. CIN09 externalproducer21exacteventtypes/22families manifests/typedtarget/recipient fixtures. Assign/reassign family has2types →23exactnotificationeventtypes total; main22rows families.
5. Centralroute/targetaccess currentpermissions tested; raw private metadata denied; stale/query/sessioncallbacks denied; NFR measurements/platformfullNT definitions available.

Minimum group discussion: accept recommended retained-custody/new task2 + storeleg projection; Inventory movement/inspection contract; external eventfacts/recipients/parent-child convention; Auth protectedpendingstore; Returns7-dayexactedge and any lost/partial/postpickuptransfer policy. Owner routine Orders/Notifications design does not need reapproval. Everyacceptance record owner/date/revision/realfixtureevidence; not clientsidebuttonhidden proof.

References [FinalDecisions](Final_Technical_Decisions.md), [CrossContracts](Cross_Module_Integration_Contracts.md), [Main1.2](technical_specification_mh07_mh08_mh09_mh17.md), [Testplan](technical_specification_mh07_mh08_mh09_mh17_tests.md), [ChangeLog](Finalization_Change_Log.md). Historical1.1 readiness preserved, current1.2 supersedes currentdecision scope.
