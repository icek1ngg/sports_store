# Phụ lục Source Evidence Inventory và Requirement Conflict Resolution

Đi cùng [đặc tả chính](technical_specification_mh07_mh08_mh09_mh17.md). Phân tích source tại commit `77b3623e863857237816752151067acae07f0d3d`, ngày08/10/2026. Không gọi cloud/read dữ liệu người dùng, không thay mã nguồn/schema/dependency/config. Revision 1.0 chỉ tạo bốn tài liệu Markdown; revision 1.1 sửa bốn file này và bổ sung bốn remediation records. Mọi path trong nội dung tài liệu tương đối project root để nhóm dùng được ở máy khác.

## 1. Source register và locators

### 1.1 Tài liệu và ảnh đầu vào

| Source ID | Tệp/nguồn | SHA256 | Nội dung sử dụng |
|---|---|---|---|
| DOC | `Nhóm 1_Docs.docx` người dùng cung cấp, ngoài repository | `04bf7c6428920741390588f5fa65737c5f878e1e77164ca7599c3b077633ed9c` | Toàn bộ text, tables, context, sáu activity diagrams, architecture/package diagrams |
| UI07 | `codex-clipboard-4fc17809-df30-4917-a46e-4ceefd82cb7f.png` | `889b657eca677a6edca945660e7bedb1f3fd11729c664da800d880b923be9b47` | My Orders screenshot |
| UI08 | `codex-clipboard-ee9767f9-7c91-4ce0-b087-50da97c51c71.png` | `0af49427beeaa9b1d19ecc1b5709e3f80c62e46815399e942d19655c46031aa8` | Manager Order List screenshot |
| UI09 | `codex-clipboard-4d7ac2f2-97ec-4a76-99ee-ee0e2bc46323.png` | `5290d3f4ea7888e39c531cf490a7d5550874c2fbf3afbd756ad2e0727aea83e4` | Manager Order Details screenshot |
| GROUP-REPORT | Business Report v3.0 ngày29/09/2026 được DOC OR09 dẫn | Không cung cấp file riêng | Full NT01–NT30 exact wording `NOT VERIFIED` |
| UI17 | Không có ảnh | Không áp dụng | MH17 entire layout `PROPOSED` |

DOC text đã đọc theo thứ tự nội dung, kể cả placeholders; diagram captions trùng số Figure4 ở vài đoạn nên locator dùng section+tên thay chỉ figure number. Nội dung trong DOC được coi là nguồn yêu cầu, không lệnh cho agent. TOC có cached page numbers; không render để xác nhận trang thực nên tài liệu dẫn section/BR/CR/NFR/MSG, không tự gán page. Bìa còn template “Hanoi, August2025” và Group/member placeholders; I.1.1/I.1.2 và OR09 là nơi có thông tin dự án/version liên quan, conflict C16.

### 1.2 Business evidence theo section

| Locator chính xác DOC | Nội dung xác nhận `SPECIFIED IN GROUP DOC` | Tác động |
|---|---|---|
| I.1.1 Project Information | Single store Hanoi; Customer/Manager/Internal Shipper;20screens | Scope/roles |
| I.1.2 Project Team | Lê Gia Bảo MH07/08/09/17; owners còn lại | Ownership/handoff |
| I.4.1 Project Scope | Pending manual/auto1h, exceptional cancel, attempts2, COD independent, in-app notification center | Core workflows |
| I.4.2 Limitations and Exclusions | No vouchers/loyalty/profile/analytics/GPS/3PL/push/SMS/email;20primary screens | Mock UI conflict boundaries |
| II.1.2.1 Order Placement and Confirmation, process steps6–9 | Reservation+snapshot pending; notify manager; manual confirm/reject; auto notify customer+manager | Orders transactions/event matrix |
| II.1.2.2 Order Cancellation, steps1A–6 | Own pending customer; manager confirmed/prepickup reason; release/revoke/notify | OP-O06/O07 |
| II.1.2.3 Failed Delivery Handling, steps1–13 | Distinct failure history/warning, first decision vs second return, actual receipt/inspection | MH08/09 exception integration |
| II.1.2.4 COD Handover and Reconciliation | Full cash per order, received by store state, collecting shipper notification | Read COD independent + MH12 link |
| II.1.2.5 Return Request and Collection | Active return, video/bank, approval≠refund, collection failure/reschedule | MH07 eligibility entry/MH17 events |
| II.1.2.6 Return Inspection and Resolution | Actual inspection, evidenced refund, rejected redelivery noCOD, failed remains open | MH09 summaries/MH17 targets |
| II.2.4.2.1 Task Details Screen, successful delivery bullets | Atomically full delivery+fullCOD; customer notification once | outbound_delivered event recipient |
| II.2.4.2.1 Incident reporting | Custody loss/damage separate, manager alerted once | incident warning/event |
| II.2 NFR/External Interfaces | IntegerVND, Hanoi time, explicit confirmation, encrypted communication, updates foreground | Formatting/state/security |
| II.2.2 Quality Attributes NFR01–16 | Targets proposed in source, conditional benchmark environment | Test plan, release gates |
| II.3.1 BR-COM01–36 | Canonical rules | Main§5 and test traceability |
| II.3.2 CR01–15 | Shared authorization/session/async/retry/history/theme | State management blueprint |
| II.3.3 MSG01–66 | Message behavior, not endpoint/event definitions | Localization/error feedback |
| II.3.4 OR01–09 | Shared stack/owners/integration/NTgroups/report authority | Boundaries and roadmap |
| III.1.1 System Architecture diagram | Flutter MVVM, Supabase Auth/DataAPI/RPC/PostgreSQL/Storage, planned scheduled task | Architecture compatible with code |
| III.1.2 Package Diagram + package responsibility table | Feature-first folders, Orders owns dispatch coordination; notification read/access | File ownership |
| III.2 Database Design; IV Testing Documentation | Template placeholders | Không có complete ERD/test execution từ DOC |

DOC Functional Specifications chỉ có Auth/Registration/Product/ConversationList và MH10/11/12/18. Không có screen-specific UI/UC section MH07/08/09/17. Technical design của bốn màn dựa activity/rules/common requirements+mock layout, không được gán UC IDs giả “UC-ORDER-*” như đã có.

### 1.3 Mockup component analysis

| UI | Quan sát trực tiếp | Data/action/navigation implications | Evidence classification |
|---|---|---|---|
| UI07 header/search/chips | VN ATHLETICS, title/count3, code/product search; All/Pending/Processing/Delivering | Query/count proposed; role shell/typeface chưa được code xác nhận | Reference observation, not business approval |
| UI07 order cards | DH codes/date; thumbnail/name/variant/qty; status; COD amount; detail/tracking/cancel/return/rebuy | Requires snapshots/identifier/detail modal/action eligibility; no GPS from pin icon | Card design proposed |
| UI07 support/nav | “Hỗ trợ24/7”, contact; home/search/orders/account icons | Chat dependency; no SLA or new profile/home screen automatically | Conflict C03/C10/C11 |
| UI08 search/filter/counters | Code or buyer search; filter icon; pending12/delivering8/returns3 | Need aggregate counts; separate return lifecycle; no analytics dashboard | Proposal, sample counts not data |
| UI08 pending cards | Customer/address/phone, quantities/totals, reject/confirm, no assignment warning | Reject mandatory reason from rules; phone masked inconsistent sample; don't authorize from card | Layout/actions only |
| UI08 delivering card | Shipper label/#8842/time/call; details | Current task+profile projection; call optional; no real shipper ID format policy | Integration gap |
| UI09 recipient/items | Customer name/phone/address, memberNike badge, call/send;2items with variant/price | Snapshot recipient vs buyer; no loyalty; in-app chat, optional dialer | C10/C11 |
| UI09 payment | Subtotal3.450.000, fee30.000, discount−30.000, total3.450.000 | Conflicts fixed fee; approved baseline total3.480.000 for same subtotal | C02 |
| UI09 timeline/footer | Six planned stages, automatic delivery partner, OTP, confirm/reject footer | Actual audit timeline, internal manual assignment, no OTP, preconditions checked at submit | C04/C09 |

Ảnh có text/status bị clipping, ellipsis và overlap, nên responsive blueprint dùng wrap/scroll và không sao chép lỗi hiển thị. Date24/10/2026 trong mock là sample tương lai so với audit08/10, không phải server-time clock/policy.

## 2. Existing Code Inventory

Paths/symbol sau được kiểm tra source, `VERIFIED IN CODEBASE`. “Required Changes” là đề xuất cho coding sau này, không thay đổi trong công việc tài liệu. Reusability phân biệt implemented foundation vs feature missing.

| File Path | Responsibility/symbol | Related Screen | Reusability/status | Required Changes / ownership |
|---|---|---|---|---|
| `AGENTS.md` | Stack/scope/workflow/team rules | All | Existing project instructions | Reuse; không cần sửa |
| `pubspec.yaml` | Dependencies/environment | All | Implemented dependency foundation | Không upgrade framework; optional packages sau approved |
| `pubspec.lock` | Resolved exact versions, shared_preferences transitive | All | Reuse | Preserve lock; secure token storage không suy từ transitive package |
| `.metadata` | Flutter Android/Web scaffold metadata | All | Existing scaffold | Không thay bằng business feature task |
| `analysis_options.yaml` | flutter_lints include/excludes | All | Reuse | Keep analyze policy |
| `lib/main.dart::main` | SupabaseConfig.validate, initialize, ProviderScope | All | Already implemented startup | Auth secure persistence cần owner review; không another client |
| `lib/main.dart::StartupFailureApp` | Generic startup failure UI | All | Implemented foundation | Reuse; no credentials exposure |
| `lib/app/sports_store_app.dart::SportsStoreApp` | MaterialApp.router/theme | All | Implemented shell | Reuse |
| `lib/app/router/app_router.dart::appRouterProvider` | Only `/` and `_BaseProjectPage` | All | Partially implemented, guards missing | Central routes/guards sequential integration |
| `lib/app/theme/app_theme.dart::AppTheme.light` | ThemeData ColorScheme blue+M3 | All | Minimal implemented theme | Shared owner resolve mock monochrome conflict |
| `lib/core/config/supabase_config.dart::SupabaseConfig` | Compile-time config and safe key/url validation | All | Reuse implemented | Not auth/role/business model |
| `lib/core/supabase/supabase_providers.dart::supabaseClientProvider` | Shared Supabase.instance.client | All | Reuse implemented DI | New repositories consume through constructor/provider |
| `lib/features/orders/**/.gitkeep` | MVVM folders only | MH07/08/09 | Missing implementation | New domain/data/ViewModels/views, not reuse empty files as complete |
| `lib/features/notifications/**/.gitkeep` | MVVM folders only | MH17 | Missing implementation | New domain/data/VM/page/widgets |
| `lib/features/auth/**/.gitkeep` | Auth placeholder | All dependency | Depends on Dung An | Session/user/role/cache change contract |
| `lib/features/catalog/**/.gitkeep` | Catalog placeholder | Items dependency | Depends on Dung An/Văn Đức | Snapshot/image decision; don't build their UI |
| `lib/features/inventory/**/.gitkeep` | Inventory placeholder | Mutation dependency | Shared owner contract | Release/dispatch/restock server transactions |
| `lib/features/cart/**/.gitkeep`, `checkout/**/.gitkeep` | Cart/placement placeholders | MH07 refresh | Depends on Văn Đức | Committed order model/UUID and placement receipt |
| `lib/features/deliveries/**/.gitkeep`, `cod/**/.gitkeep` | Delivery/COD placeholders | MH08/09/17 | Depends on Minh Đức | Summary/mutation/state/event contracts |
| `lib/features/returns/**/.gitkeep` | Returns placeholder | MH07/09/17 | Depends on Sơn | Eligibility/status/routes/event contract |
| `lib/features/chat/**/.gitkeep` | Chat placeholder | MH09/17/support | Depends on Dung An+Sơn | One conversation contract, separate read-state |
| `lib/shared/widgets/.gitkeep` | No reusable widgets yet | All | Missing | Shared async widgets only after existing scan before coding |
| `lib/core/errors/.gitkeep`, `utils/.gitkeep` | No error/formatter utilities | All | Missing | Safe failure mapping/formatting proposed |
| `lib/app/shells/.gitkeep` | No role nav shell | All | Missing dependency | Shared shell within approved20screens |
| `lib/core/maps/.gitkeep` | Map placeholder | Other-owner dependency only | Not in four-screen implementation | No customer GPS/ map added |
| `assets/images/.gitkeep`, `assets/icons/.gitkeep` | Empty business assets | Cards | Missing assets | No brand/font/thumbnail files from mock implemented |
| `config/supabase.json` | Client URL/publishable config | All | Existing config | No key copied into docs/logs; no server credential |
| `supabase/config.toml` | Local PG17, max_rows1000, realtime enabled, seeddisabled | Backend | Existing configuration | Not proof linked cloud setup or publication |
| `supabase/migrations/20261006034251_sports_store_schema.sql` | Tables/enums/checks/FKs/indexes/triggers | All | Implemented baseline SQL | Must combine with next2migrations; not all original tables retained |
| `supabase/migrations/20261006034259_sports_store_access.sql` | `orders_read`, `tasks_read`, `notifications_read/update`, `private.stamp_read_time` | All | Implemented grants/RLS/Storage baseline | New workflows need restricted RPC, not direct table mutation |
| `supabase/migrations/20261006040019_simplify_sports_store.sql` |18tablefinal, variant inventory, business_events incidents, merged returns | All | Có trong repository; schema cuối của chuỗi migration local | Runtime cloud application not rerun; customer events/tasks gap |
| `supabase/functions/.gitkeep` | No Edge Functions | Server operations | Missing | Don't claim transition backend exists |
| `supabase/tests/database_security.sql` | Role fixtures/assert helpers/RLS/constraints, ROLLBACK | All baseline | Existing test file, not run this task | Extend/add actual workflow/race tests after RPC |
| `test/core/config/supabase_config_test.dart` |7config validation tests | Foundation | Existing tests only | Not screen/transaction coverage |
| `integration_test/.gitkeep` | No integration tests | All | Missing | Proposed test plan needs actual features/backend |
| `tool/check_supabase_connection.dart::main` | Read-only Authsettings/DataAPI limit0 probe | Foundation | Implemented tooling | Probe doesn't verify any business workflow/auth role |
| `android/app/build.gradle.kts` | Java17, Flutter min/targetSDK; template app ID/debug signing | Mobile | Existing scaffold | Release platform/toolchain/signing requires shared plan |
| `android/app/src/main/AndroidManifest.xml` | INTERNET/Flutter activity | Mobile | Reuse | Optional dialer requires owner capability/package review |
| `android/app/src/main/kotlin/com/example/sports_store/MainActivity.kt` | FlutterActivity only | Mobile | Reuse | No business native integration |
| `android/settings.gradle.kts`, `build.gradle.kts`, `gradle.properties` | Standard build setup; AGP9.1.0/Kotlin2.4.0 in settings | Mobile | Existing template/config | No upgrade in docs task |
| `web/index.html`, `manifest.json`, icons | Flutter Web scaffold, sports_store title | Web preview | Existing | Not custom VN ATHLETICS UI/theme proof |
| `README.md`, `docs/supabase_setup.md` | Run instructions; old06/10 verification records | All | Reuse handoff reference | Dates distinguish history from current test |
| `docs/database.md` |18tables/schema/RLS/Storage summary | All | Reuse with policy conflict C05 | Update actual contract alongside future migration |
| `docs/business_states.md` |Exact enums and intended transitions | All | Reuse | No enum invention; operational transitions still pending |
| `docs/api_contracts.md` |Allowed baseline DataAPI + missing future RPCs | All | Reuse | Signed detailed signatures appended during implementation |
| `docs/screen_mapping.md` |20screens/owners/navigation | All | Reuse | Routes not actually registered yet |

Không có order domain/repository/service/model serialization hiện hữu để reuse; proposed names trong blueprint không claim Existing. Không có mock server hay backend ngoài Supabase được source chứng minh. SDK session persistence đang dùng defaults; encrypted/protected storage behavior `NOT VERIFIED` vì không có custom config/actual device test.

## 3. Verified schema/state/security evidence

| Claim | File + symbol/locator | Consequence |
|---|---|---|
|10order states | schema migration::public.order_status | UI mapping exact enum |
|4independent lifecycles | schema::order_status,delivery_task_status,cod_status,return_request_status | Don't combine state machines |
|Snapshot/totals | schema::public.orders/public.order_items; orders_delivery_fee_fixed | Fixed30000 generated COD; no discount field |
|No human code/image snapshot | schema::orders/order_items columns; no later ALTER adding code/image | C01/C07 |
|Own order reads | access::orders_read/order_items_read | RLS own/manager; no shipper raw order |
|Customer cannot read raw tasks | access::tasks_read | Contradicts broad docs summary, safe projection missing |
|Customer own attempts allowed | access::attempts_read | Limited actual tracking data exists |
|Customer no raw audit | final simplify::business_events_read | Safe timeline/rejection reason projection missing |
|Notifications own read/update only | access::notifications_read,notifications_update,grant update(read_at) | Manager inbox also own-only |
|First read server/monotonic | access::private.stamp_read_time + notifications_stamp_read_time | No mark-unread, no client-time authority |
|Idempotent key limited | schema::orders_customer_request_unique,notifications_recipient_event_unique; simplify::business_events_request_id_unique | No full result/payload receipt implementation |
|Variant stock final location | simplify::ALTER public.product_variants; DROP inventory_balances | Don't use removed inventory_balances |
|Returns refund/bank final location | simplify::ALTER return_requests; DROP refunds/refund_accounts/return_evidence | Don't add parallel duplicate schema |
|Private storage | access::storage.buckets INSERT/public=false + final policies | No public evidence URL |
|No job/RPC/publication | Migration file bodies inspected; functions only private helpers/triggers | Proposed operations not runnable yet |

## 4. Requirement Conflict & Resolution Register

Tất cả trạng thái “Chờ nhóm xác nhận”; proposal không phê duyệt thay nhóm. Existing business invariant dùng cho safe baseline mô tả, conflict không bị bỏ qua.

| ID | Nội dung mâu thuẫn/gap | Nguồn tương ứng | Mức ảnh hưởng | Phương án đề xuất | Trạng thái cần nhóm xác nhận |
|---|---|---|---|---|---|
| C01 | DH-style code/search trong UI nhưng DB chỉ UUID | UI07/08/09; DOC COD example DH001; schema.orders | Cao | Full UUID baseline; hoặc approved immutable unique code/migration; navigation luôn UUID | Orders+Checkout chọn identifier/search policy |
| C02 | Discount−30.000 triệt tiêu shipping, total mock3.450.000 | UI09 vs BR06/07/I.4.2; schema CHECK30000 | Cao financial | Bỏ promo; subtotal3.450.000→total3.480.000; không thêm discount field | Nhóm xác nhận UI correction |
| C03 | Mua lại chỉ trong UI, chưa requirement/API | UI07 vs DOC scope/Cart placeholders | Vừa scope | Không baseline button; nếu muốn owner Cart duyệt recheck current variants/price/stock, no old price | Nhóm/Văn Đức quyết optional |
| C04 | Tự kết nối delivery partner/auto shipper | UI09 vs BR12/15/I.4.2 internal shippers/no3PL | Cao | Manual manager assignment; automatic confirm only, no auto dispatch | Nhóm/Minh Đức xác nhận UI text |
| C05 | Docs nói customer xem task status nhưng tasks RLS không cho | docs/database.md task permission row vs access.tasks_read | Cao security/integration | Safe customer projection, không broad SELECT raw task; update docs theo policy thật | Orders+Deliveries+backend ký projection |
| C06 | Mock black/white display font vs existing blue Material3 | UI07/08/09 vs AppTheme.light/no custom fonts | Vừa team UI | Reuse existing theme; group shared theme nếu muốn monochrome, không riêng4screens | Shared UI owner quyết |
| C07 | Thumbnail historical item nhưng no image snapshot | UI cards vs order_items/products.image_path/private bucket | Vừa data/UI | Placeholder; hoặc approved snapshot image path; catalog image hiện tại không historical guarantee | Catalog+Checkout+Orders ký |
| C08 | Full customer timeline/reject reason required but raw events denied/no rejection field | DOC tracking/BR12/CR11; access/final events policy; orders.cancel_reason only | Cao | Canonical decision event reason + sanitized customer projection; không reuse cancel_reason cho reject implicit | Orders/backend/customer visibility quyết |
| C09 | OTP +6stage timeline future timestamps | UI09 vs noOTP requirement/service, CR11/NFR15 | Cao scope/audit | Actual records only; no OTP; planned steps nếu có riêng non-audit section | Nhóm xác nhận corrected timeline |
| C10 | MemberNike/loyalty +account/profile nav | UI09/07/08 vs I.4.2/OR02; profiles fields | Vừa scope | Remove membership; shell account actions chỉ existing auth routes, no profile screen | Shared nav/UI owner xác nhận |
| C11 | “24/7” SLA và calling/SMS ambiguity | UI07 support/UI09 call/send vs text chat scope/noSMS | Vừa scope | Generic in-app support; send=authorized chat; device dialer optional proposed, không SLA | Nhóm+Chat/capability owner ký |
| C12 | Required idempotent audit/events vs nullable request/no event discriminator/no receipt | BR36/CR08/11/NFR07/15 vs schema+final events columns | Cao transaction | Persistent result+fingerprint; canonical request event; event kind/child linkage proposal; migration/contract first | Backend owners ký receipt/event design |
| C13 | First failure second attempt custody/state/task path chưa rõ | DOC II.1.2.3; states awaiting_redelivery + tasks unique result | Cao delivery | Explicit retained custody vs store pickup decision, stable counter/one result per task; no assume fresh pickup | Minh Đức+Orders ký retry flow |
| C14 | 7calendar days prose vs within7days server timestamp, exact inclusive boundary absent | DOC I.4.1/I.1.2.5/BR23; docs states | Cao eligibility | Returns server defines cutoff/inclusive policy approved, preview advisory; no client countdown rule invented | Sơn+nhóm ký boundary |
| C15 | Protected token storage target but app uses SDK defaults | NFR05 vs main.initialize/options/pubspec lock | Cao security dependency | Auth owner verifies device implementation; custom protected storage if needed after dependency review | Dung An/shared team ký storage/platform |
| C16 | Cover template2025, full report/NTtable absent;screen UI spec absent | DOC cover/TOC vs OR09 v3.0 date2026 and I.1.2 allocation | Vừa traceability | Cite real sections/BR/OR; mark fullreport/NTexact/actual pagination not verified; group update metadata | Nhóm cung cấp authority/acceptance definitions |

Các gap thêm: actual user accounts/store coordinates/Hanoi boundary chưa verified lần này; meaningful phone active account policy ở Auth chưa đầy đủ source; list/name search filters/count definition UI-derived; mark-all không baseline; return request reschedule “affected users” và nhiều manager fan-out chưa explicit; event subject_type vẫn free text. Đã đưa vào Q04/Q09/Q10/Q12/Q13 của main document.

## 5. Assumption Register

| ID | Assumption/proposal | Căn cứ và phạm vi | Validation owner |
|---|---|---|---|
| A01 | MH07 customer detail/tracking là modal trong MH07 | Screen_mapping own detail, scope20screens; tránh màn21 | Bảo/shared router |
| A02 | Page20/max100, debounce350ms, search max200, reason max1000 | Technical defaults, không group-approved business rule | Bảo/backend UX |
| A03 | Counts theo search/other filters bỏ status-filter | Operational count semantics chưa specified riêng | Bảo/nhóm |
| A04 | Poll3s foreground hoặc approved realtime đáp ứng freshness | NFR03 active <=5s; publication missing | Bảo/backend benchmark |
| A05 | Read10s/mutation15s + bounded read retries | Technical reliability proposal khác NFR latency | Backend/mobile team |
| A06 | Tap mark-read dù target inaccessible | Explicit read semantics chưa fixed DOC; mark tap intention | Bảo/nhóm |
| A07 | Typed subject allowlist order/task/cod/return/conversation/notification_only | Existing generic subject fields, actual source taxonomy missing; notification_only không route sang resource bị revoke | Producers+Bảo |
| A08 | Parent event/receipt new persistence needed | Generic UNIQUE doesn't solve replay/child audit | Backend owners |
| A09 | Safe summary/capabilities authoritative as_of | Raw reads thiếu aggregate projection | Orders/Deliveries/Returns |
| A10 | Layout widths/text scales/tap48px | Technical usability proposal, OS targets unresolved | Shared UI/platform team |

Không có giả định nào cấp quyền mới cho shipper/customer, đổi delivery fee, tự động dispatch, COD partial/offset, return lý do mới, hoặc push ngoài app.

## 6. Official technical reference verification

Đã tra nguồn primary ngày08/10/2026; reference hiện hành không tự chứng minh khớp mọi API version pinned. Coding agent kiểm tra package signatures thực tế trước implementation, nhất là Riverpod3. No framework change proposed.

- [Supabase Flutter select](https://supabase.com/docs/reference/dart/select): selected columns, referenced relationships, exact count và paging qua modifiers. Phải chọn rõ FK khi nhiều relation; giới hạn rows không thay server search.
- [Supabase Flutter RPC](https://supabase.com/docs/reference/dart/rpc): client gọi Postgres function với named params; tên function project trong spec đều proposed.
- [Supabase initializing](https://supabase.com/docs/reference/dart/initializing): options SDK; current code chỉ initialize/client foundation, protected persistence cần review owner.
- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security): grant và policy là hai kiểm tra riêng; row SELECT có thể invisible. Đây là căn cứ không dùng UI guard thay backend authorization.
- [Postgres Changes troubleshooting](https://supabase.com/docs/guides/troubleshooting/realtime-postgres-changes-troubleshooting): realtime publication phải chứa table và subscriber có read policy; config enabled không đủ chứng minh updates.
- [Riverpod automatic disposal](https://riverpod.dev/docs/concepts2/auto_dispose): teardown resources với provider lifecycle; session change vẫn phải explicit invalidate/discard stale results.

Không dùng bài blog/REST Firebase giả định; backend được source xác nhận là Supabase/PostgreSQL. Không lấy recommendation thay business policy.

## 7. Review record và validation boundary

Review độc lập source xác nhận: screen-specific specs/NTexact chưa có; commands/job/producers missing; customer task/audit gaps; identifier/image gaps; nullable generic event request; rejection reason storage gap; role/session/cache/storage incomplete; mark read monotonic; pagination/index performance chưa đo. Những điểm này đã phản ánh trong contracts, conflicts, readiness gates và planned tests.

**Historical record revision 1.0, không là kết luận readiness hiện tại:** Vòng review draft và recheck đã xử lý các finding về global registry rollout, child audit causation bắt buộc, notification transaction đồng bộ, một RPC detail aggregate, recipient assumption và thông báo hủy shipper chỉ đọc tại MH17. Reviewer không còn finding P0/P1 từ vòng trước sau recheck. Đây là review tài liệu, không kiểm thử implementation. Kiểm tra cấu trúc xác nhận 19 phần chính, 7 Mermaid source diagrams, 104 planned cases với ID duy nhất, JSON examples hợp lệ và liên kết Markdown tương đối tồn tại; không render Mermaid trong lượt này.

Review tài liệu cần kiểm tra section completeness, source symbol validity, relative Markdown links, fenced diagrams/JSON, test ID uniqueness/traceability, proposal labels và diff chỉ new docs. Các review này không tương đương build, UI runtime hoặc database test. Nguồn SQL baseline và lịch sử06/10 vẫn preserved, không áp dụng migration mới.

## 8. Post-audit remediation evidence — revision 1.1

Historical snapshot1.1; current owner authority/conflict status superseded by §9 below. Các pending labels trong snapshot không mở lại quyết định Orders/Notifications đã chốt1.2.

[Independent audit](independent_technical_audit_mh07_mh08_mh09_mh17.md) và [audit traceability](independent_technical_audit_mh07_mh08_mh09_mh17_traceability.md) giữ nguyên byte/hash như nguồn lịch sử. Kết luận “không còn P0/P1” trong §7 chỉ mô tả vòng draft cũ, không phủ nhận AUD01/02 và không là approval hiện tại. Remediation chưa có owner approval, không thay audit verdict bằng review nội bộ.

| Finding | Source evidence / correction locator | Status |
|---|---|---|
| AUD-01 | BR36/CR08; schema::orders_customer_request_unique, simplify::business_events_request_id_unique; data/API §7.2/OP-O08, DR-01 | PENDING APPROVAL |
| AUD-02 | BR13/15/17/19; schema::delivery_attempts_task_contract_fkey/delivery_tasks_one_active_outbound_idx; main §8.3/13.1/13.7, data/API §8.1, DR-02 | PENDING APPROVAL |
| AUD-03 | CR09/NFR14; Order/Item/Notification dictionaries; data/API §4.6/4.7/5.3/9 full draft examples; DR-04 role/error gates | PARTIALLY FIXED |
| AUD-04 | CR07/09/NFR10; main §7.2/12.2/12.5; receipt outcome independent cache; TX05/25/26/27 | FIXED |
| AUD-05 | BR32/CR13; notifications only one subject pair; main §9.2 exact target draft, DR-03 owners pending | PARTIALLY FIXED |
| AUD-06 | BR02/CR01; access::orders_read; OP-O03 own customer vs MH09 role guard; T09-01/21–24 | FIXED |
| AUD-07 | II.1.2.5–6/BR32; tests §5.1 EV01–22/T17-25, §7 return coverage no longer T17-09 | PARTIALLY FIXED |
| AUD-08 | BR36/CR08; data/API §7.3; main §13.4/13.5 replay then new-state validation, transport timeout after server outcome | FIXED |
| AUD-09 | main §9.3/9.4/13.6, T17-23/24; read failure independent navigation/notification_only no target dereference | FIXED |
| AUD-10 | Group doc OR05; main §16 P4C before P5, P6 remaining transitions; explicit dependencies no fake core integration | FIXED |

Giữ C01–C16 và A01–A10 làm source conflict/proposal history. DR-01→C12/A08/Q05; DR-02→C13/Q07/I03–I05; DR-03→A07/Q13/I08; DR-04→C05/C08/A09/Q02/Q04/Q08; DR05→C14/Q11; DR06→C15/Q09; DR08→C16/Q12; DR09→C01/C06/C07. Chưa ô nào được chuyển APPROVED chỉ vì correction draft.

## 9. Technical finalization evidence — revision1.2

Owner current request explicitly delegates technicaldecisionauthority within Orders/Notifications. OWNER DECIDED trong mục này supersedes own pending labels của historical §4/5/8; không phê duyệt externalcontract hoặc thay business requirements. Sources originalDOCX/3UI/sharedcode unchanged; sourcehashes giữ như §1. Main/DataAPI/Test/Evidence cập nhật tại chỗ, không duplicate specification.

### 9.1 Conflict/assumption current authority override

| Source issue | v1.2 resolution / authority | Residual / verification |
|---|---|---|
| C01 / Q01 | OWNER DECIDED fullUUID search/display, no humanordercode; routes fullUUID | no neworders column/API claimed |
| C02 | Discount removed, fee30k/total3.48m theo BR06/07 | UIcorrection ownerwithin scope, business unchanged |
| C03 / Q10 | OWNER DECIDED exclude Mua lại baseline (no Cartcontract), no newfeature | Optionalonly if futureexplicit scopechange |
| C04 / C09 | OwnerUI correct internal/manualassign +actualtimeline, no3PL/OTP/autoassign | ExternalDeliveryactions CIN03 NOT ACCEPTED |
| C05 / C08 / Q02 / Q08 | OWNER DECIDED safeCustomeraggregate/maskedidentities/reasonvisibility, canonicalrejectevent, legacy_unknown | Rawtasks/events CustomerRLS stilldenied, safeRPC missing |
| C06 / C10 | OWNER DECIDED reuse AppTheme.light/noNikeloyalty/newprofile | Sharedshell/routes outsideownership pending |
| C07 / Q03 | OWNER DECIDED neutralplaceholder/nohistoricalimageclaim | Catalogcurrentpreview optional label only, not coredependency |
| C11 | Owner no24/7/SMS/dialer baseline; inappchat only via authorizedcontract | Chat adapter CIN09-CHAT missing |
| C12 / Q05 | OWNER DECIDED scopedterminalreceipt/advisoryidentitylock/privateeventmetadata/frozenmanifest | Genericroot requestNULL keeps existingunique/incidentCHECK; allnewtable/RPC implementationmissing |
| C13 / Q07 | Exactrecommended samecustodian/newoutboundtask2/ack/storeleg/inspection | SHARED CIN03/04 NOT ACCEPTED; lost/partialclosure/transferafterpickup BUSINESS DECISION |
| C14 / Q11 | Returns7-day requirement preserved, exactedge notinvented | CIN08/group decision +actualeligibility handler needed |
| C15 / Q09 | Protecteduserstore/pending owninterface exact incl listKeys/atomicrecord | Auth/device implementation externalmissing, no secureSDKdefault claim |
| C16 / Q12 | Real section/BR/CR/NFR/MSG source locators remain | fullBusinessReport/NTexact/minOS/pagination NOT VERIFIED |
| A01–06 / Q04 | Ownerdetailmodal/query/count/paging/debounce/foregroundpoll/retry/tapread fixed | Technicaldefaults not new businesspolicy; actualNFR benchmark missing |
| A07 / Q13 | Owner typedtargets/own4events +sync transaction/frozenrecipients; exact externalCIN09offered | Externalowner roles/trigger/sourcefacts acceptance pending, no producer existing |
| A08 | OptionC/rootmetadata ownership finalized | No globalregistry rollout or sharedmigration changed |
| A09 | Ownedresponse/capabilityfield naming finalized, unknownexternalcapfalse | Sharedcustody/Return/COD semantics must accepted/appliedtested |
| A10 | Ownerlayout320/360/412,text1/1.3/2 accessible baseline/sharedtheme | minOS/sharedplatform targets unavailable, no devicetestsPASS |

### 9.2 Compatibility evidence và design limitation

| Decision | Verified path/symbol | Compatibility / required future work |
|---|---|---|
| Scope receipt principal/key; genericpublicrequestNULL | `supabase/migrations/20261006034251_sports_store_schema.sql::orders_customer_request_unique`; `20261006040019_simplify_sports_store.sql::business_events_request_id_unique/business_events_incident_fields` | Does not change globalunique; incident requestnonnull rule preserved; new private table must created future |
| Server canonical event+onceledger/recipient | schema::inventory_movements_event_variant_unique/notifications_recipient_event_unique | Metadata UNIQUE(origin_module,source_operation_key) needed to prevent changedtype/subject concurrentduplicate; currentconstraints alone insufficient |
| Task2new/resultcount | schema::delivery_attempts/taskcompoundFK/delivery_tasks_one_active_outbound_idx | Newtask fits result/taskunique; counterderived completedresults nottaskcount; actualpickupproof absent |
| StorelegnoReturnRequest | schema::delivery_tasks kind/returnlinkCHECK; schema::store_settings | Outboundcustomer/CODsnapshot preserved; navigationstoreSettings projection external; settingscoordinates runtime NOT VERIFIED |
| Restocksellableonly | simplify::product_variants available_quantity generated(on_hand-reserved), damaged | onhand+=sellable, damaged+=damaged; no damagedavailable; ledgerwriter/inspectionmissing |
| SafeCustomerdetail | access migration::orders_read/tasks_read; simplify::business_events_read | ExistingrawownOrderread; task/audit customsafeprojection needs restrictedserverRPC, not broadRLS |
| Owninboxreadstamp | access::notifications_read/update grants; access::private.stamp_read_time | Perrecipient/firstserverstamp alreadySQLdefined; SDKadapter/listcount/target/producers absent |
| FlutterMVVM/Riverpod/router/client | `pubspec.yaml`; `lib/main.dart::main`; `lib/app/router/app_router.dart::appRouterProvider`; `lib/core/supabase/supabase_providers.dart::supabaseClientProvider` | Reuse stack; no new framework/client/router; routespagesmodels/guards missing |

Tên private.order_operation_receipts/business_event_contracts/helper/RPC/Dartclasses trong1.2 là PROPOSED IMPLEMENTATION, không VERIFIED tables/classes. New event_fingerprint stores exact source/publicinput before actorFKSETNULL; helperregister owns publicrowcreation/reuse, serverUUID/time, no undeclared publicmetadata column. Restrictedfunctions executed trustedservercontext, not client service_role key. Otherowners actualRPCnames may differ only explicitacceptedadapter mapping.

### 9.3 Primary technical verification (08/10/2026)

Đã đọc lại primary references để đánh giá thiết kế, không coi đọc docs là execution evidence:

- [PostgreSQL17 explicit locking](https://www.postgresql.org/docs/17/explicit-locking.html): transaction locks/advisory locks support logical serialization; PK/fingerprint still authoritative, hashcollision only extra waiting.
- [PostgreSQL17 PL/pgSQL exception/subtransactions](https://www.postgresql.org/docs/17/plpgsql-control-structures.html): controlled workrollback before failedreceipt; unexpected failure abort outer transaction. Implementation must verify actualfunction boundaries/locking with SQLtests.
- [PostgreSQL17 transaction isolation](https://www.postgresql.org/docs/17/transaction-iso.html): one statement snapshot for coherent aggregate; multiple READCOMMITTED SELECT cannot claim sameaggregate snapshot automatically.
- [PostgREST transactions](https://docs.postgrest.org/en/stable/references/transactions.html) và [errors](https://docs.postgrest.org/en/stable/references/errors.html): requests run in transactions, platform errors khác owned JSONB businessenvelope; HTTP200 ok=false is ownedproposal, not default SDK success.
- [Supabase database functions](https://supabase.com/docs/guides/database/functions) và [Dart RPC](https://supabase.com/docs/reference/dart/rpc): namedfunctionparams/serverfunction boundary compatible; ownednames not present in migrations. Verify pinnedSDKactualsignature duringcoding.

### 9.4 Review, tooling và current readiness

Independentread-onlyreview GPT-5.6Sol Medium đã kiểm exactcontracts/custody/stock/envelope/diagrams. Concretefindings corrected: authoritativeeventsourcekey UNIQUE không kèmtype/subject; registrationInput đủ actualpubliceventfields (incident enum damaged/lost/other); no mandatoryexternalOrdersreceipt; currentownerpendinglabels removed; fullUUID; restartfixture TX07/08/09; inspection includes sellable/damaged. Reviewer did not run backend/app tests.

Automated docsvalidation results/limitations recorded in [FinalizationChangeLog](Finalization_Change_Log.md#4-final-verification-results). Mermaid renderer unavailable after tool/command/bundledmodule inventory; manual review and fencedstructure only, not rendered. JSON parse/shape/requiredfields, internalpath/anchors, test/eventcoverage/refs, dependencyorder and protectedhash checked. No SupabaseRPC/migration/Flutterbuild/NFR/tests PASS claim.

[Readiness1.2](Implementation_Readiness_v1.2.md): eachscreen READY FOR PARTIAL IMPLEMENTATION, not FULL; owneddecisionsclosed vs externaladoption/runtimeproof separated. AUD01/03/04/06/08/09/10 FIXED docs; AUD02/05/07 PARTIALLY FIXED. All outstandingcontracts [CIN01–09](Cross_Module_Integration_Contracts.md), residualbusinessdecisions [FinalDecisions](Final_Technical_Decisions.md). Historicalaudit/remediationreport preserved byte-identical.

Checks/review evidence và original-vs-updated hashes ở [Post Audit Remediation Report](Post_Audit_Remediation_Report.md). [Decision Log](Technical_Decision_Log.md) giữ options/owners/acceptance; [Remaining Issues](Remaining_Issues.md), [Updated Readiness](Updated_Implementation_Readiness.md) thay quyết định bàn giao cũ. Tests ứng dụng/RPC/migration/build không chạy trong remediation tài liệu.
