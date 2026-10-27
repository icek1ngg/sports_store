> Historical revision1.1 preserved. Current authority/status superseded by [revision1.2](Final_Technical_Decisions.md); pending labels below describe the earlier snapshot, not new owner approval gates.

# Technical Decision Log — MH07, MH08, MH09, MH17

Ngày 08/10/2026, remediation revision 1.1. **Chưa có approval mới từ nhóm.** Các record dưới đây `PROPOSED — PENDING APPROVAL`. Recommendation không là lựa chọn đã thực thi. Business rules không cần phê duyệt lại; phần cần owners ký là interface/storage/flow chưa được baseline xác định. Không sửa shared baseline, schema/migrations/source hoặc DOCX.

Nguồn: Nhóm 1_Docs.docx II.1.2, II.3.1 Business Rules, II.3.2 Common Requirements, II.2 NFR, II.3.4 OR; [audit lịch sử](independent_technical_audit_mh07_mh08_mh09_mh17.md), [audit traceability](independent_technical_audit_mh07_mh08_mh09_mh17_traceability.md). `VERIFIED IN CODEBASE` = source snapshot, không runtime/cloud evidence. Full Business Report/NT exact không có trong workspace.

## DR-01 — Persistent operation receipt và idempotency scope

**Status: PENDING APPROVAL; AUD-01 chưa FIXED.**

1. **Vấn đề:** chọn request namespace, claim/serialization, canonical payload fingerprint, persistence/result lookup, retention và recovery sau relaunch. OP-O08 chỉ p_request_id hiện là draft không final signature. Một unique slot không tự trả persisted result.
2. **Business requirements:** `SPECIFIED IN GROUP DOC` BR-COM-36, CR-07/08/09/11, NFR-07/10/14/15: same logical request trả existing result, không duplicate stock/attempt/COD/message/notification; auth hiện tại trước replay, replay trước state preconditions. Không có rule bắt buộc global UUID registry giữa mọi module.
3. **Phương án:** A: registry global request_id mọi module; B: common persistence namespace `(actor, operation, request)` và subject/fingerprint; C: module-owned persistence (Orders scope trước), dùng common behavioral contract/mapping cho integration, các owner khác giữ idempotency riêng nếu tương thích.
4. **Ưu/nhược:** A dễ một lookup nhưng cần migration/rollout nhiều owners, legacy collisions/backfill và system identity; B explicit namespaces nhưng chung schema vẫn coupling và cần lookup scope; C giảm ảnh hưởng implementation Bảo nhưng cần kiểm tra cross-feature canonical event/receipt consistency, không được coi mọi feature đã idempotent. C không cho phép retries đổi fingerprint hoặc tạo child events tùy ý.
5. **Code impacts:** `supabase/migrations/20261006034251_sports_store_schema.sql::orders_customer_request_unique` UNIQUE(customer_id,request_id); `20261006040019_simplify_sports_store.sql::business_events_request_id_unique` UNIQUE(request_id), generic nullable. Chưa có receipt table/RPC. Cần chọn mapping logical key→canonical event ID phù hợp existing global event constraint; không tự kết luận scoped receipt bắt buộc thay event UNIQUE hoặc tự đổi nghĩa field đang dùng.
6. **Other owners:** Checkout Văn Đức placement key/reservation; Minh Đức delivery/COD; Sơn return/refund; Dung An/Sơn chat; Inventory stock ledger; Auth protected pending metadata. A yêu cầu tất cả owners rollout; C vẫn ký shared boundary events trước khi tích hợp. Bảo không nhận code module khác mặc định.
7. **Recommendation (`PROPOSED`):** C với một Orders receipt scope rõ, common behavior dùng chung; hạn chế migration chéo và gán rõ từng owner. Chỉ chọn khi canonical event mapping/collision/lifetime thỏa BR36; nếu nhóm cần global lookup và chấp thuận rollout thì A/B vẫn hợp lệ. Không apply C vào signatures/schema trước approval.
8. **Owners phải đồng ý:** Bảo/Orders + backend/schema owner; Văn Đức/Checkout/Inventory, Minh Đức/Deliveries/COD, Sơn/Returns, Dung An+Sơn/Chat cho các boundary bị ảnh hưởng; Dung An/Auth cho pending storage/session recovery.
9. **Docs/contracts cần đổi sau ký:** docs/api_contracts.md, database.md, business_states.md nếu state semantics đổi; data/API §4.3/5.3/OP-O04–08/7.2–7.4, main §12.5/13.4/13.5/16, tests TX-04–07/20/23/24/28, event target table DR-03. Schema/RPC migration chỉ trong nhiệm vụ implementation riêng, không lượt này.
10. **Closure acceptance:** signed scope + exact lookup params/discriminant; canonical normalized fingerprint rules/reason normalization; uniqueness/concurrent claim; receipt payload immutable/safe; auth hiện tại mỗi replay; retention/relaunch protected storage; system-job keys; root/child mapping và collision rollout approved; examples/tests updated. Sau implementation mới kiểm chứng race, rollback, historical replay, same-key unknown recovery bằng hai connections và real roles. Không cần migration phải tồn tại để approve thiết kế, nhưng phải có source/test evidence mới claim runtime-ready.

## DR-02 — Custody, attempt hai và nhận/inspection hàng không giao được

**Status: PENDING APPROVAL; AUD-02 chưa FIXED.**

1. **Vấn đề:** định nghĩa evidence “đã pickup”, nguồn lịch sử custody cho manager cancel, attempt consumption/task transition lần hai, quantity/ledger của nhận hàng và closure khi thiếu/lost/damaged.
2. **Business requirements:** `SPECIFIED IN GROUP DOC` II.1.2.3, BR-COM-10/11/13/15/17/18/19; confirmed chỉ exceptional cancel trước pickup với reason; max2 outbound toàn order, không reset task/shipper; không restock trong custody; manager receipt/inspection sellable only, không refund COD chưa thu.
3. **Phương án:** A retained goods ở shipper cho attempt2 với explicit authorized carry-over custody; B goods về store và actual repickup trước attempt2; C hỗ trợ cả hai qua command/discriminant explicit và separate evidence. Không thêm order enum hoặc assume accepted_at là pickup.
4. **Ưu/nhược:** A ít di chuyển nhưng requires handoff/custody audit trên task mới; B physical receipt rõ hơn nhưng thêm thực tế xử lý/inspection phải owner xác định, không tự restock/reserve lần nữa; C phản ánh linh hoạt nhưng contracts/test nhiều nhánh. Chọn một path tối thiểu được nhóm vận hành chấp thuận tốt hơn cho course scope; requirements chưa chọn A/B/C.
5. **Code impacts:** schema::delivery_attempts có UNIQUE(task_id), UNIQUE(order_id,attempt_number), delivery_tasks_one_active_outbound_idx; tasks accepted_at/started_at chỉ cột chưa semantics runtime. Nếu dùng current constraints, second result cần task khác; không đổi existing failed result hoặc reset delivery_attempt_count. Data/API §8.1 candidate received/sellable/damaged chưa approved, thiếu/lost ledger handling cần quyết định.
6. **Other owners:** Minh Đức MH11 custody/pickup/results/handover; Inventory dispatch/return ledger owner; Văn Đức reservation/Checkout linkage; Sơn chỉ read boundary (post-delivery return independent). Manager actions MH09 phụ thuộc owner operations, không gọi shipper ViewModel.
7. **Recommendation (`PROPOSED`):** owners chốt một operational branch trước (A nếu cửa hàng cho phép giữ hàng và audit carry-over đủ; B nếu actual custody cần về cửa hàng); dùng task mới và stable order attempt count với hiện tại constraints. Historical pickup phải có immutable trusted event/ledger source, không lấy task latest chưa pickup làm proof chưa từng pickup. Candidate inspection dictionary §8.1 chỉ dùng để review, không approve closure thiếu hàng.
8. **Owners phải đồng ý:** Bảo/Orders, Minh Đức/Deliveries/COD, Inventory/backend owner và Văn Đức/Checkout cho stock boundary; store/business representative quyết physical process; Sơn cho return boundary nếu dùng chung receipt vocabulary.
9. **Docs/contracts cần đổi:** docs/business_states.md, database.md, api_contracts.md, main §8.3/13.1/13.7/17 I03–I05, data/API §3.1/OP-O07/8–8.1, tests T09-07–14/TX-01/20/24, DR-01 lock order và DR-03 affected recipients. Hai alternatives trên state diagram được giữ có nhãn pending tới khi chọn; coding agent không execute cả hai.
10. **Closure acceptance:** signed trusted pickup fact/custody history; exact command params/results/nullability/errors; one current task/assigned shipper; when consume count; task2 route/current permissions; no repeat dispatch/re-reservation; inspection actual received/sellable/damaged/lost quantity equations/source; missing goods closure policy có căn cứ business; stock ledger once; cancel-vs-pickup và retry-vs-return tests; approved examples. Action còn thiếu contract phải unavailable, không tự chọn branch.

## DR-03 — Notification producers, recipients, typed targets và atomicity

**Status: PENDING APPROVAL; AUD-05/AUD-07 PARTIALLY FIXED.**

1. **Vấn đề:** producers ký 22 event families, server recipient fan-out, chính xác single subject pair, source/root/child identity, notification creation transaction; đặc biệt task return failures phải đến MH15.
2. **Business requirements:** `SPECIFIED IN GROUP DOC` BR-COM-12/13/18/26/30/32/34/35/36, II.1.2.1–6, CR-01/07/08/12/13, MSG-59–63/66. Persist/read/dedup đúng recipient; target rechecks permission; no push/SMS/email. Source “affected users” không định nghĩa mọi recipient cụ thể.
3. **Phương án:** A synchronous notifications/event/receipt/business commit atomic; B transactional outbox rồi producer reliable eventual delivery (chỉ nếu owners duyệt revised latency/failure semantics). Target: per-recipient projection trong existing fields, same canonical event nhiều recipients; hoặc child typed events với approved causation. Không arbitrary URL hoặc notification JSON payload mới mặc định.
4. **Ưu/nhược:** A dễ assert rollback/exact one event, producer failure có thể chặn business commit; B cần worker/outbox/recovery/freshness và rollout nhiều owners. Single canonical event giảm duplicate nhưng approval/assignment fan-out phải phối hợp; child events rõ source nhưng cần causation contract DR-01. Không BR nào tự approve kiến trúc A/B.
5. **Code impacts:** schema::notifications chỉ subject_type text/subject_id UUID/event_id FK, UNIQUE(recipient_id,event_id); access::notifications_read/update own-only + private.stamp_read_time. Không producer/event enum/outbox. Typed target draft main §9.2 dùng return_request cho return failures, cod lấy order_id, Shipper cancellation notification_only event.id. Raw constraints chưa enforce allowlist.
6. **Other owners:** Checkout order_placed; Orders transitions/job; Deliveries task/delivery/incident; COD received; Returns review/refund/reschedule/redelivery; Chat messages. Manager role set trusted server; multiple-manager fan-out, old affected assignee và support recipients chưa chốt. Recipient state được Bảo đọc, producers do owners thực hiện trong workflow của họ.
7. **Recommendation (`PROPOSED`):** A cho scope hiện tại nếu owners chấp thuận, với bảng main §9.2 draft một typed target per recipient; notification_only cho người mất task permission, ReturnRequest cho Manager pickup/redelivery failures→MH15. Server recipient selector rõ; chỉ một event source hoặc deduplicated child policy cho assignment+approval. Không apply fan-out chưa ký vào runtime. B chỉ chọn qua explicit change control và thay TX-21/sequence/NFR evidence đồng bộ.
8. **Owners phải đồng ý:** Bảo/Notifications+Orders; Văn Đức/Checkout; Minh Đức/Deliveries/COD; Sơn/Returns; Dung An+Sơn/Chat; Auth/backend cho target/resource visibility và manager set.
9. **Docs/contracts cần đổi:** shared api_contracts.md/database.md nếu persistence thay; main §9.2–9.4/13.6/17 I08, data/API OP-N04/05/§7.4, tests T17-08/09/22–27/EV-01–22/TX-21/24, DR-01 source mapping và DR-04 projections. Typed target draft không là new DB enum được tạo.
10. **Closure acceptance:** mỗi event×recipient variant ký producer owner/trigger/recipient selection/subject_type/source_id/destination/safe content/dedup; exact fixtures 22 families (assign/reassign + each role variants); old assignee/cancellation denied-target behavior; manager fan-out/support recipients; single source vs child; approved failure/rollback/retry latency; evidence test owner handoff. Chưa owner fixture signature hoặc producer evidence thì giữ tests integration BLOCKED.

## DR-04 — Exact aggregate wire, role projection và error transport

**Status: PENDING APPROVAL; AUD-03 PARTIALLY FIXED.** Local naming đã chuẩn hóa thành OrderDto đầy đủ, delivery_summary, as_of, nullable required keys và full examples; không còn alternative subset. Draft data/API §4.6/4.7/5.3 là một phương án để review. Chọn error discriminant ổn định bằng named SQLSTATE/code hoặc structured mapping phù hợp SDK, không parse message text. Đối chiếu thực tế SDK/version khi coding; không claim error envelope mặc định PostgREST. OrderStateReference chỉ id/status, không OrderDto.

Business: CR-01/09/11/14, NFR-04/14. Owners: Bảo + backend/Auth, Minh Đức summary/custody, Sơn ReturnSummary/eligibility. Phải ký list/count snapshot/search/cursor semantics, reason visibility/actor privacy (Customer confirmed_by=null draft), required-null fields, typed errors/idempotency lookup namespace; code docs database/api_contracts cùng data/API/test fixtures cập nhật đồng bộ. Closure: reviewed versioned request/response/error fixtures cho own Customer, Manager và denied Shipper/other Customer; parse tests exact shape/permissions. 21 raw Order/11 Item/9 Notification fields có code evidence, aggregate projection mới không có backend evidence.

## Các integration gates bổ sung

Tất cả entries `PENDING APPROVAL` hoặc `NOT VERIFIED` như cột Status; không tự apply recommendation. Các gate này đã có Q01–Q13, không phải feature thêm.

| ID | Problem / business source | Options / recommended direction (`PROPOSED`) | Owners | Docs/interfaces và closure acceptance | Status |
|---|---|---|---|---|---|
| DR-05 | Return cutoff inclusive/calendar chưa định nghĩa chính xác; BR23 | Elapsed vs calendar, exact inclusive boundary phải nhóm ký; preview advisory, authoritative submit owner | Sơn + nhóm | eligibility DTO, MH07 navigation/T07-17–19 và owner submission cases trước/đúng/sau cutoff; không đổi deadline sau submit | PENDING APPROVAL |
| DR-06 | Auth/session/role secure persistence/routes chưa implementation; CR01/02, NFR05 | Central session stream + server role; protected storage owner verify; role guards fail closed | Dung An/Auth + shared router/platform | Auth contract, role loading/expiry/logout/switch, pending metadata namespace; true device token storage evidence | PENDING APPROVAL |
| DR-07 | Auto-confirm job schedule/identity missing; BR12,NFR09 | Trusted server task + shared confirm transaction; schedule <=60s là proposal cần latency verify | Bảo + backend | JOB-O01, source automatic, overdue once/no assignment, permission/clock/queue tests, environment deployment evidence | PENDING APPROVAL |
| DR-08 | Full Business Report/NT01–NT30 exact, min OS/device unavailable; OR08/NFR13 | Cung cấp authoritative report/targets; giữ group-level NT mapping | Nhóm + platform/QA | Exact requirement-to-test evidence; không gán guessed NT wording hoặc PASS | NOT VERIFIED |
| DR-09 | UI DH code vs UUID; thiếu item image snapshot; shared theme khác mock | UUID full/placeholder/current AppTheme là technical baseline proposal; human code/image/theme thay đổi cần owners ký | Bảo + Văn Đức + Catalog/shared UI | identifier/search/cursor contract, safe image fallback/storage, theme/layout examples; không thêm discount/member/GPS | PENDING APPROVAL |
| DR-10 | Optional rebuy/call/mark-all không được scope phê duyệt | Postpone; chỉ thêm khi user/team explicitly approve và owner interface có | Bảo + Cart/Chat/shared UI | Scope/acceptance/API/package review nếu muốn; baseline không có tính năng mới | OPTIONAL / POSTPONED |

## Approval và change-control record

| Record | Approved option | Approvers / date / evidence | Versioned affected contracts | Status |
|---|---|---|---|---|
| DR-01 | Chưa chọn | Chưa có | Chưa có signed revision | PENDING APPROVAL |
| DR-02 | Chưa chọn | Chưa có | Chưa có signed revision | PENDING APPROVAL |
| DR-03 | Chưa chọn | Chưa có | Chưa có signed revision | PENDING APPROVAL |
| DR-04–09 | Chưa ký | Chưa có | Chưa có signed revision / evidence | PENDING / NOT VERIFIED theo register |

Không điền approved option chỉ vì recommendation đã viết vào spec. Sau nhóm quyết định, cập nhật một lần đồng bộ main/data/API/tests/evidence/shared docs, bỏ alternative không chọn khỏi executable contract nhưng giữ lịch sử trong record; re-audit exact fixtures và dependencies trước coding phần blocked. Source/migration changes phải là nhiệm vụ implementation riêng được giao owner.
