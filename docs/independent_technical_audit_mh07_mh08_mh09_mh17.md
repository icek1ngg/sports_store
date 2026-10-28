# Independent Technical Audit — MH07, MH08, MH09, MH17

Ngày đánh giá: **08/10/2026**. Phạm vi: tài liệu thiết kế, khả năng tích hợp và mức sẵn sàng giao việc; không sửa source code hoặc đặc tả được review.

## A. Executive Audit Summary

**Kết luận: NOT READY FOR IMPLEMENTATION đối với việc giao trọn bốn màn hình cho AI coding agent tự triển khai mà không phải quyết định thêm nghiệp vụ/hợp đồng.** Có thể dùng bộ tài liệu để chốt thiết kế và chia việc; chưa thể coi đó là một baseline triển khai đã được phê duyệt.

Đánh giá ghi nhận **10 vấn đề: 2 BLOCKER, 6 MAJOR, 2 MINOR; không có CRITICAL được chứng minh trong thiết kế đã đọc**. Hai BLOCKER là quyết định tích hợp chưa khép kín, vốn đã được đặc tả thừa nhận; chúng không phải cáo buộc tài liệu che giấu tính năng chưa làm. Những lỗi mới có căn cứ gồm hợp đồng DTO còn đa nghĩa, thiếu quy tắc xử lý receipt cũ đối với cache mới, test quyền truy cập có oracle không rõ/không đúng cho API dùng chung, thiếu kiểm thử theo từng notification event và sơ đồ cancellation không biểu diễn đúng replay/timeout sau commit.

Các quy tắc cốt lõi về phí 30.000 VND, snapshot, hủy pending, xác nhận sau một giờ, hai lần giao, bốn lifecycle độc lập và in-app notifications được phản ánh đúng về chủ trương. Không phát hiện đặc tả bắt buộc triển khai voucher, GPS, OTP, push, SMS hoặc email. Tuy nhiên, đúng nguyên tắc nghiệp vụ chưa đủ để viết các adapter và transaction tương thích giữa năm thành viên: còn thiếu quyết định về receipt, custody, wire schema, quyền của projection và target của từng notification.

### A.1 Nguồn, định danh và khả năng truy cập

Các ký hiệu sau dùng xuyên báo cáo; số dòng áp dụng cho snapshot này. Đường dẫn nội dung tương đối project root theo AGENTS.md.

| Ký hiệu | Nguồn đã kiểm tra | Kết quả/phạm vi bằng chứng |
|---|---|---|
| G | `../Nhóm 1_Docs.docx` | Truy cập được; toàn bộ text/table gồm 505 body blocks, các phụ lục, sáu activity diagrams và sơ đồ kiến trúc/package. Dẫn section/BR/CR/NFR/MSG; không tự gán số trang vì chưa render phân trang Word |
| S | [Đặc tả chính](technical_specification_mh07_mh08_mh09_mh17.md) | 811 dòng, 19 phần, 7 Mermaid source blocks |
| D | [Data/API](technical_specification_mh07_mh08_mh09_mh17_data_api.md) | 713 dòng; data dictionary, operations, error, receipt, integration contracts, JSON |
| T | [Test plan](technical_specification_mh07_mh08_mh09_mh17_tests.md) | 212 dòng; 104 planned cases, không phải kết quả thực thi |
| E | [Evidence/conflicts](technical_specification_mh07_mh08_mh09_mh17_evidence.md) | 200 dòng; đã kiểm tra các claim liên quan với nguồn thay vì mặc định review cũ là đúng |
| C | Codebase tại commit `77b3623e863857237816752151067acae07f0d3d` | 6 file Dart trong `lib/`, cấu hình, shared docs, 3 SQL migrations và tests nền; feature orders/notifications chưa có triển khai |
| UI07/08/09 | Ba PNG người dùng cung cấp | Truy cập được và đối chiếu bố cục/action. Không dùng số tiền, ngày, số đếm, OTP hoặc auto-dispatch của mock làm policy |
| UI17 | Không có ảnh được phê duyệt | Chỉ đánh giá tính hợp lý/nhất quán của Proposed Design, không chứng nhận độ khớp ảnh |
| Full Business Report v3.0, NT01–NT30 chi tiết | G dẫn tại OR-08/09 nhưng không có file độc lập trong bộ đầu vào | `NOT VERIFIABLE` đối với câu chữ từng NT; không gán nội dung riêng cho NT01…NT30 |
| DOCX/PDF đặc tả, Mermaid/PlantUML tách riêng | Không tìm thấy bản bổ sung trong repository bằng inventory các định dạng này | Đối tượng audit là bốn Markdown trên cùng sơ đồ nhúng, không tuyên bố đã đọc bản DOCX đặc tả |

Hash SHA-256 của G là `04bf7c6428920741390588f5fa65737c5f878e1e77164ca7599c3b077633ed9c`, khớp source register E. Hash ba PNG cũng khớp E §1.1.

| Input B | SHA-256 tại audit |
|---|---|
| S | `3bb914a362cf7efb5cebc70cf1a578080b4ab2b65929aeeba6e8915666256190` |
| D | `4d06ea533b7ea3d83f661b03adcbad7f38e990a282cf6408b7a9ff0ae2f31802` |
| E | `e32c63360a8babdc17617b17cceaf52c93d9f833284e486256842e184089f958` |
| T | `e09345371a77023239c53dd7e3ba5dffad2f9b919a7ec71a97363d3d6baf2f46` |

### A.2 Giới hạn xác minh

- `CONFIRMED DOCUMENT DEFECT`: xác minh được thiếu sót/mâu thuẫn trong tài liệu; không có nghĩa lỗi runtime đã tái hiện.
- `CONFIRMED READINESS BLOCKER`: tài liệu còn để ngỏ quyết định bắt buộc; chưa đủ điều kiện triển khai phần liên quan.
- `NEEDS VERIFICATION`: cần môi trường chạy, phê duyệt owner hoặc tài liệu chưa cung cấp.
- `FULL` trong traceability chỉ là coverage thiết kế trong phạm vi bốn màn; không có nghĩa implementation/test PASS.

Không chạy Flutter build/analyze/tests, SQL migrations, cloud connectivity, load test hoặc thiết bị thật. Không có business RPC để kiểm thử bốn màn ở baseline hiện tại. Mermaid được đọc và kiểm tra cấu trúc thủ công, **chưa chạy renderer/parser Mermaid**. Kiểm tra bằng công cụ chỉ xác nhận 5 JSON code blocks parse được, 104 test IDs duy nhất, 19 phần chính, 7 Mermaid blocks và không có Markdown relative link hỏng trong bốn input. JSON hợp lệ cú pháp không chứng minh phù hợp DTO.

## B. Audit Scorecard

Điểm đánh giá **chất lượng thiết kế được ghi lại**, không chấm chất lượng runtime. Mốc 10: nhất quán, quyết định cần thiết đã khép kín và có test oracle; 5: đủ định hướng nhưng agent còn phải tự quyết định đáng kể; 0: không sử dụng được. Không tính điểm trung bình để bù trừ BLOCKER.

| Category | Score | Evidence | Main Problems |
|---|---:|---|---|
| Requirement Compliance | 8/10 | S §5–9, §14; G BR-COM/CR/NFR; RTM phụ lục audit | Quy tắc chính có; projection/event/deadline và acceptance chi tiết còn mở |
| Business Logic Correctness | 7/10 | D OP-O04–08, §7; S §13 | Replay/current-state ở UI chưa khép kín; custody/retry chưa chốt |
| Architecture Compatibility | 8/10 | `pubspec.yaml`, router/client/theme; S §12 | Đúng stack/layer; API/DTO và shared contract chưa đủ định danh để tích hợp |
| Screen Completeness | 7/10 | S §6–9; checklist phụ lục audit | MH09 có action nhưng thiếu contract thực thi; MH17 thiếu target/fan-out chính xác cho một số events |
| Data & API Consistency | 5/10 | D §4, §5.2, §7–9 | Union/alias bằng dấu `/`, subset/full Order, error mapping và receipt persistence chưa thống nhất |
| Security & Reliability | 7/10 | SQL RLS/grants; S §9/12/14; T | Thiết kế backend enforcement đúng; payload allowlist/receipt-cache/test oracle cần sửa. Device/cloud security: N/A |
| Diagram Consistency | 6/10 | S §13.2–13.8 | Cancellation replay/timeout sai cấu trúc; notification-only/read-error thiếu nhánh. Render syntax: N/A |
| Testing Coverage | 6/10 | T §2–7, 104 cases | T09-01 đa nghĩa; traceability return dùng test auto-confirm; chưa có event-by-event producer oracle |
| Implementation Readiness | 4/10 | S §16–19; D §10 | Hai blocker thiết kế tích hợp, các wire contracts và dependencies chưa đóng; chưa thể giao trọn feature không cần đoán |

## C. Complete Defect Register

### C.1 Danh mục

| ID | Severity | Phạm vi | Vấn đề | Verification status |
|---|---|---|---|---|
| AUD-01 | BLOCKER | Orders/Notifications và producers | Chưa chọn scope/persistence/replay protocol cuối cùng | CONFIRMED READINESS BLOCKER |
| AUD-02 | BLOCKER | MH09, Deliveries/Inventory handoff | Custody, retry, receipt/inspection chưa thành contract duy nhất | CONFIRMED READINESS BLOCKER |
| AUD-03 | MAJOR | MH07/08/09, DTO/API | Wire schema và error mapping chưa xác định đơn nghĩa | CONFIRMED DOCUMENT DEFECT |
| AUD-04 | MAJOR | MH07/08/09, cache | Receipt lịch sử có thể ghi đè dữ liệu mới do thiếu quy tắc áp dụng | CONFIRMED DOCUMENT DEFECT; runtime impact chưa chạy |
| AUD-05 | MAJOR | MH17, event producers | Event matrix chưa ánh xạ chính xác target/recipient thành wire fields | CONFIRMED DOCUMENT DEFECT / acknowledged Q13 |
| AUD-06 | MAJOR | Test MH09/MH07 | T09-01 không tách route manager và shared detail RPC | CONFIRMED DOCUMENT DEFECT |
| AUD-07 | MAJOR | Test MH17, requirements | Coverage producer events chưa đầy đủ, có mapping test không chứng minh rule | CONFIRMED DOCUMENT DEFECT |
| AUD-08 | MAJOR | S sequence cancellation | Replay branch thiếu và lost response bị mô hình hóa như nhánh precondition | CONFIRMED DOCUMENT DEFECT |
| AUD-09 | MINOR | S notification sequence | Không biểu diễn notification_only và read-failure độc lập navigation | CONFIRMED DOCUMENT DEFECT |
| AUD-10 | MINOR | Roadmap P5/P6 | Acceptance P5 cần confirm backend được đặt ở P6 | CONFIRMED DOCUMENT DEFECT |

### C.2 Hồ sơ bằng chứng và tác động

#### AUD-01 — Hợp đồng idempotency chưa chốt

- **Vị trí:** D §7.2, dòng 570–590; OP-O08; S Q05 dòng 782; T TX-23.
- **Expected:** agent biết namespace request, nơi lưu kết quả, cách claim/replay, fingerprint, lifetime, caller scope, phục hồi sau relaunch; shared owners có một hợp đồng đã chọn.
- **Actual:** global registry là phương án có điều kiện; phương án scoped cũng còn mở. Tên persistence chưa chốt. Nếu chọn global, D yêu cầu placement/inventory/delivery/COD/returns/chat cùng tham gia; rollout đó chưa được quyết định. Contract lookup chỉ `p_request_id` còn phụ thuộc lựa chọn namespace.
- **Evidence:** G BR-COM-36, CR-08, NFR-07/10/14; schema `orders_customer_request_unique` tại migration schema dòng 211; `business_events_request_id_unique` tại simplify dòng 174–175. Unique per-table không tự tạo persisted replay result/fingerprint.
- **Impact:** không thể viết mutations/recovery tương thích an toàn theo cả hai phương án; có nguy cơ mỗi owner xây một receipt convention khác. Không kết luận global registry tự thân sai hoặc BR36 bắt buộc global UUID xuyên mọi module.
- **Correction:** G.1; quyết định và version một protocol, giao từng owner phần tích hợp; không tự giao Bảo sửa toàn bộ module khác.
- **Status:** blocker đã có trong đặc tả, được audit xác nhận; chưa có implementation để kết luận lỗi duplicate đang xảy ra.

#### AUD-02 — MH09 chưa đủ contract cho custody và các hành động ngoại lệ

- **Vị trí:** S §8.3, §13.1 và Q07 dòng 784; D §3.1 dòng 148, §8 bảng `arrange_second_outbound`, `receive_undelivered_goods`.
- **Expected:** một định nghĩa pickup/custody có thể kiểm tra server; transition cho lần hai, active task, attempt consumption và inspection quantity/ledger nhất quán giữa MH09 và MH11.
- **Actual:** hai cạnh retry `awaiting_pickup` hoặc `delivering` vẫn là alternatives; `accepted_at`/`started_at` chưa có ý nghĩa pickup đã ký; `inspectionItems` chưa có field/type/ràng buộc số lượng. Ngoại lệ hủy dựa “ALL historical pickup/custody” nhưng chưa định nghĩa nguồn bằng chứng custody.
- **Evidence:** G BR-COM-13/15/17/19, II.1.2.3; schema `delivery_attempts_task_contract_fkey`, `delivery_attempts_order_number_unique`, `delivery_tasks_one_active_outbound_idx` (dòng 671). Một task chỉ có một attempt result; không thể tùy tiện tái dùng task thất bại cho kết quả lần hai.
- **Impact:** MH09 không thể bật cancel ngoại lệ/retry/receive một cách đầy đủ; agent có thể reset attempt, issue stock hai lần hoặc hủy sau pickup nếu tự chọn semantics.
- **Correction:** G.2; Orders + Deliveries + Inventory ký branch/custody/quantity contract trước phần action. Giữ cả hai phương án trong tài liệu thảo luận được, không coi chúng là executable state machine.
- **Status:** blocker thiết kế tích hợp đã công khai, không phải phát hiện một RPC hiện hữu sai.

#### AUD-03 — DTO/API thiếu một wire contract chuẩn

- **Vị trí:** D §4.1 dòng 207: `Order subset/domain`; §4.2 dòng 225: `delivery_summary/tasks`, dòng 231: `server_time/as_of`; §4.3 dòng 246: `receipt.order` là `Order`; §5.2 dòng 318; §9.2 dòng 680.
- **Expected:** mỗi key có một tên, một type, required/null/omitted semantics rõ, định nghĩa role projection và error discriminant; ví dụ đầy đủ parse qua cùng mapper.
- **Actual:** một số field vẫn viết bằng alternative/alias; summary không chỉ rõ subset required. Receipt example thiếu nhiều Order fields và đã được ghi rõ là minh họa subset, nhưng normative contract còn cho chọn full Order **hoặc** versioned subset chưa ký. Server error mapping được giao chọn trước khi parser viết. Customer-safe reason/actor visibility còn Q02/Q08.
- **Evidence:** G CR-09, NFR-14; `orders`/`order_items` schema là exact fields nhưng chưa có Dart DTO/RPC aggregate. JSON parser xác nhận cú pháp của 5 examples; không có full response fixture để xác nhận schema conformance.
- **Impact:** hai agent có thể tạo response/mapper đều tưởng theo tài liệu nhưng không tương thích; customer projection có thể bỏ key mà mapper yêu cầu non-null. Đây là thiếu tính quyết định, **không** cáo buộc example là response thật hoặc malformed JSON.
- **Correction:** G.3; chọn schema duy nhất cho từng response, role allowlist và error transport; thêm full fixtures, version và tests.
- **Status:** xác minh qua nội dung; runtime compatibility `NEEDS VERIFICATION`.

#### AUD-04 — Không có quy tắc chống receipt/read response cũ làm lùi cache

- **Vị trí:** S §7.2 dòng 192 “Replace canonical row”, dòng 201 “cập nhật order receipt”; §12.2 dòng 408 “Receipt confirmed mới update canonical state”. D §4.3 nêu `receipt.order` là kết quả tại thời điểm operation, `current_order` chỉ optional. T TX-05 kiểm replay backend nhưng không khẳng định UI không lùi state.
- **Expected:** action result lịch sử và latest resource state độc lập; response cũ đến muộn không làm danh sách/chi tiết/capabilities quay lại trạng thái cũ.
- **Actual:** có yêu cầu phân biệt committed/current bằng văn bản, nhưng chưa có rule áp dụng vào cache giữa mutation receipt, poll/list/detail và invalidation; query/session generation chỉ loại query/session cũ, không tự xác định thứ tự giữa các nguồn response cùng order.
- **Evidence/reproduction thiết kế:** confirm commit ở preparing → delivery owner chuyển awaiting_pickup/delivering → poll nhận trạng thái mới → receipt confirm bị trễ hoặc replay trả preparing → áp dụng “replace canonical row” làm lùi UI. Nếu refresh sau đó lỗi, trạng thái cũ có thể được giữ. G CR-07/09, NFR-10 yêu cầu state authoritative và đồng bộ.
- **Impact:** hiển thị/capabilities sai; backend recheck vẫn có thể chặn action, vì vậy không khẳng định mất tiền/kho hoặc nâng thành CRITICAL.
- **Correction:** G.4; receipt chỉ resolve outcome, latest state được refresh có generation riêng. Không dùng enum ordinal hoặc `committed_at` làm version của toàn aggregate.
- **Status:** thiếu sót thiết kế đã xác minh; chưa tái hiện runtime vì chưa có VM.

#### AUD-05 — Notification event chưa có target wire mapping đầy đủ

- **Vị trí:** S §9.2 dòng 271–272, 278–279; §9.4; D OP-N04/05; S Q13.
- **Expected:** với mỗi event/recipient, xác định chính xác `subject_type`, nguồn `subject_id`, recipient selection và destination; backend và resolver dùng cùng mapping.
- **Actual:** `return_pickup_failed` ghi payload “task/return” và destination MH15, trong khi resolver chuẩn map `delivery_task` của Manager sang MH09. Reschedule cũng “return/task”; redelivery failure tương tự. Chọn `return_request` có thể đúng, nhưng tài liệu chưa buộc producer chọn nó. Fan-out nhiều Manager/affected users vẫn mở.
- **Evidence:** SQL notifications chỉ có một `subject_type` + một `subject_id`, không payload JSON hai target; schema dòng 510. G BR-COM-32, CR-13; II.1.2.5 steps 19/21 và II.1.2.6 step 28.
- **Impact:** notification tồn tại nhưng mở sai module; producer/resolver diverge. Không khẳng định các events đã triển khai sai.
- **Correction:** G.5; thêm per-recipient typed target table, xác định manager set và root/child event identity; không đưa arbitrary URL hoặc private fields vào body.
- **Status:** thiếu mapping có căn cứ; recipients chi tiết cần owner xác nhận như Q13.

#### AUD-06 — Test T09-01 lẫn quyền route và quyền shared RPC

- **Vị trí:** T dòng 72; D OP-O03; S §5.2, §6.2.
- **Expected:** Customer bị chặn route MH09; Customer vẫn được gọi shared detail RPC cho **đơn của mình** để MH07 hoạt động, với customer-safe response. Shipper và Customer truy cập đơn người khác bị chặn.
- **Actual:** T09-01 dùng precondition “Customer/shipper”, step “Open manager UUID route/call detail as wrong role”, expected “No manager data or action, denied safe”, không định nghĩa ownership hoặc tách expected cho API và route.
- **Evidence:** OP-O03 cho phép “Manager or order's customer”; `orders_read` ở access migration dòng 87–89 cũng phân biệt manager/own customer. G BR-COM-02, CR-01.
- **Impact:** coding agent có thể viết test đòi deny tất cả customer detail calls, hoặc coi denied là đủ mà không test sanitized allow path. Đây là test oracle đa nghĩa cần sửa, không kết luận backend đã deny sai.
- **Correction:** G.6; tách role/ownership × entry-point thành các case rõ ràng.
- **Status:** mâu thuẫn/thiếu precondition được xác minh.

#### AUD-07 — Event coverage chưa được chứng minh bởi test traceability

- **Vị trí:** T §5 và §7 dòng 165; S §9.2.
- **Expected:** tất cả notification events bắt buộc có trigger, recipients, target, dedup và failure/rollback oracle; có thể dùng parameterized suite thay vì nhiều test trùng.
- **Actual:** T17-08/09 kiểm dedup/multi-recipient bằng order/auto-confirm; T17-22 kiểm sensitive content chung. Không có case/matrix fixture xác định đủ từng return approval/rejection/pickup failure/reschedule/more-evidence/refund/redelivery event. Row BR-COM-26–30 dẫn **T17-09**, nhưng T17-09 chỉ auto-confirm; không chứng minh return event đó. Owner Returns suite được nhắc nhưng không có handoff test identifier/evidence.
- **Evidence:** G II.1.2.5–1.2.6, BR-COM-32/36, NFR-14; các test bodies thực tế tại T, không suy coverage chỉ từ 104 IDs.
- **Impact:** có thể pass toàn bộ cases đã viết theo nghĩa hẹp mà vẫn thiếu thông báo của một trigger bắt buộc hoặc sai target/recipient.
- **Correction:** G.7 và phụ lục audit test AT-06; coverage mỗi event key/role cần một dataset row, sau khi AUD-05 đóng.
- **Status:** test-plan gap đã xác minh; không khẳng định tests đã chạy hoặc FAIL.

#### AUD-08 — Sequence cancellation không nhất quán với replay/unknown outcome protocol

- **Vị trí:** S §13.4, đặc biệt dòng 530–548; D §7.3 và OP-O06/O08.
- **Expected:** authorize + receipt lookup trước state precondition; replay cancellation đã commit phải trả old success. Lost response là lỗi vận chuyển có thể xảy ra **sau commit**, không phải một kết quả loại trừ của kiểm tra pending.
- **Actual:** sequence đi trực tiếp “Lock order and recheck pending/identity”, rồi alt pending / changed / lost response; không có nhánh receipt tồn tại. `else Lost response` đặt cùng cấp với branches quyết định server, không cho thấy commit → response loss → receipt lookup response.
- **Evidence:** BR-COM-36, CR-08; D §7.3 nói rõ replay trước state-precondition. Với order đã cancelled và same request, diagram hiện có chỉ biểu diễn changed branch, còn protocol yêu cầu replay success.
- **Impact:** agent lấy diagram làm flow chính có thể trả false ineligible khi retry hoặc hiểu sai timeout là không commit. Văn bản đúng chưa xóa mâu thuẫn diagram.
- **Correction:** G.8; tách server outcome và transport delivery thành hai bước, thêm replay và recovery response.
- **Status:** inconsistency về semantics đã xác minh thủ công; không phải kết luận Mermaid syntax lỗi.

#### AUD-09 — Notification sequence thiếu hai nhánh đã được đặc tả

- **Vị trí:** S §13.6 dòng 609–624 so với §9.3–9.4; D OP-N04; T17-23.
- **Expected:** `notification_only` hiển thị own notification và không gọi target repository; read fail không bắt buộc cấm navigation nếu target vẫn authorized.
- **Actual:** sơ đồ luôn đợi canonical read ack rồi `RES->>T: Current entity authorization/read`; không tách notification_only hoặc mark-read failure.
- **Impact:** diagram-only implementation có thể gọi task đã revoke hoặc chặn navigation không cần thiết. Các đoạn văn và backend permission đã có bảo vệ nên xếp MINOR, không tự kết luận leak.
- **Correction:** thêm alt notification_only / business target và alt read ack/failure độc lập; xem G.9.
- **Status:** mismatch về nhánh, không có renderer verification.

#### AUD-10 — Thứ tự roadmap chưa phản ánh dependency confirm

- **Vị trí:** S §16 dòng 747–748.
- **Expected:** phase nghiệm thu placed→preparing→delivery→COD phụ thuộc confirm transaction đã tồn tại.
- **Actual:** P5 có acceptance luồng đó nhưng P6 mới làm OP-O04–08/JOB; P5 dependency chưa chỉ P6 hoặc tách confirm backend sớm. Mã hiện tại không có confirm RPC để kế thừa.
- **Evidence:** G OR-05; inventory ba migrations chỉ có helper/trigger, không business transition RPC.
- **Impact:** giao task theo thứ tự bảng sẽ bị chặn hoặc dùng fixture preparing thay full flow mà tưởng đã tích hợp end-to-end.
- **Correction:** đưa confirm core transaction trước acceptance P5; cancellation/rejection phần còn lại có thể sau core delivery/COD. G.10.
- **Status:** planning defect, không phải lỗi nghiệp vụ runtime.

## D. Missing Requirements Matrix

**Không tìm thấy một nhóm nghiệp vụ cốt lõi bị bỏ hẳn khỏi văn bản.** Những phần thiếu chủ yếu là contract/test có thể thực thi. Bảng dưới chỉ liệt kê coverage chưa đủ; [phụ lục audit](independent_technical_audit_mh07_mh08_mh09_mh17_traceability.md) có RTM toàn bộ BR-COM-01–36, CR-01–15, NFR-01–16, messages và 14 tình huống.

| Requirement ID | Original Requirement | Technical Document Section | Coverage | Issue |
|---|---|---|---|---|
| BR-COM-36, CR-08 | Retry cùng operation trả kết quả cũ, không duplicate | D §7.2; OP-O08 | PARTIAL | AUD-01: scope/persistence/relaunch còn mở |
| BR-COM-13/15/17/19 | Hủy trước pickup, retry tối đa hai, nhận kiểm tra mới restock | S §8.3/13.1; D §8 | PARTIAL | AUD-02: custody, quantities, operation contracts chưa chốt |
| CR-09, NFR-14 | Shared field/status/error/interface thống nhất | D §4/5/9 | PARTIAL | AUD-03: ambiguous fields/response/error mapping |
| CR-07/09, NFR-10 | UI refresh authoritative; không cho conflicting update với trạng thái cũ | S §7.2/12.2 | PARTIAL | AUD-04: receipt cũ vs cache mới |
| BR-COM-32, CR-13 | Notifications đúng recipient, mở đúng resource có quyền | S §9.2/9.4 | PARTIAL | AUD-05: target pair/fan-out chưa hoàn chỉnh |
| BR-COM-02, CR-01 | Own customer detail được đọc, manager screen bị guard | T09-01 vs D OP-O03 | CONFLICTING | AUD-06: oracle không phân biệt route/API/ownership |
| II.1.2.5–6, NFR-14 | Notification events các nhánh return được tích hợp/kiểm thử | T §5/7 | PARTIAL | AUD-07: thiếu event coverage rows, mapping T17-09 không đúng nội dung |
| BR-COM-36, CR-08 | Replay/timeout sau commit | S §13.4 vs D §7.3 | CONFLICTING | AUD-08: sequence khác protocol |
| OR-05 | Core order→delivery→COD trước nhánh ngoại lệ | S §16 | PARTIAL | AUD-10: dependency confirm chưa nằm trước nghiệm thu P5 |
| BR-COM-23 | Hạn bảy ngày tại submit theo server | S Q11, D ReturnSummary | PARTIAL | Source dùng cả “calendar days” và delivery timestamp; owner Returns phải chốt biên, không để MH07 tính tự do |
| NFR-05/13, OR-07 | Protected storage, platform/min OS và compatibility | S Q09, §14 | PARTIAL | Biết dependency nhưng chưa có quyết định/device evidence; không kết luận SDK mặc định unsafe khi chưa kiểm tra |
| OR-08 | NT01–NT30 exact acceptance | T §7.1 | NOT VERIFIABLE | Input chỉ có nhóm NT, thiếu full report độc lập |

Không đưa upload/video/bank validation của MH13–15 thành thiếu tính năng trong MH07/09. Phần phải bàn giao là eligibility/summary/route/event và quyền; implementation upload/refund nằm ở owner khác.

## E. Requirement Conflicts

| Nguồn đối chiếu | Conflict/gap | Đánh giá resolution hiện tại | Trạng thái/việc cần làm |
|---|---|---|---|
| UI09 vs BR-COM-06/07, `orders_delivery_fee_fixed` | Promo −30.000 làm tổng mất phí | S bỏ promo, tổng mẫu 3.480.000 đúng | Không defect business; nhóm cập nhật UI reference |
| UI09 vs BR-COM-12/15, I.4.2 | Auto-connect delivery partner, OTP, six hardcoded stages | S dùng internal manual assignment, bỏ OTP, real timeline | Không feature vượt scope trong baseline |
| UI07 “Mua lại” vs G/code | Không requirement/API đã duyệt | S loại baseline, chỉ nêu optional | Đúng phân loại; không đòi thêm để audit đạt |
| UI brand/black-white vs `AppTheme.light` | Mock typography/theme khác M3 xanh | S reuse shared theme, C06 mở | Cần quyết định shared UI; không tạo theme riêng bốn màn |
| UI DH-code/ảnh vs `orders`/`order_items` | Không human code/image snapshot | S dùng UUID/placeholder baseline, proposal nâng cấp | Không bịa cột; không coi thiếu historical image là vi phạm BR09 về mô tả/giá |
| `docs/database.md` vs SQL `tasks_read` | Summary cho customer xem status, raw task policy không cho | E C05 ghi gap, D đề xuất projection | Chưa đóng Q02, không nới RLS toàn task để chữa nhanh |
| G I.4.1 vs BR-COM-23 | Calendar days vs elapsed boundary chưa chính xác | E C14/Q11 giữ open | `NEEDS VERIFICATION` business cutoff; không tự chọn từ mock dates |
| D OP-O03 vs T09-01 | Customer own detail allowed nhưng test gộp denied route/RPC | Chưa giải quyết | AUD-06 |
| D replay protocol vs S §13.4 | Lookup receipt trước precondition vs diagram bỏ nhánh replay | Chưa giải quyết | AUD-08 |
| S §9.2 vs §9.4 | “task/return → MH15” vs manager task resolver → MH09 | Chưa buộc chọn typed target | AUD-05 |
| S §9.3/9.4 vs §13.6 | Notification-only/read fail được phép, diagram luôn đọc target sau ack | Chưa giải quyết | AUD-09 |

Bìa G còn template năm 2025 trong khi OR-09 dẫn report 29/09/2026. E đã ghi đúng giới hạn nguồn; audit dùng nội dung BR/CR được cung cấp, không tự coi metadata bìa là version nghiệp vụ mới.

## F. Architecture & Integration Risks

### F.1 Compatibility với code thực tế

| Design Decision | Codebase Evidence | Compatible? | Required Correction |
|---|---|---|---|
| Flutter + Riverpod + go_router + Supabase | `pubspec.yaml`; `lib/main.dart::main` | Có ở dependency/foundation | Không cần đổi stack; runtime pinned SDK chưa chạy |
| Feature-first MVVM | Feature folders và AGENTS; `lib/features/orders`, `notifications` chưa Dart | Có | Phân biệt folder với implementation, như S đang làm |
| View→VM→Repository→Supabase | `supabaseClientProvider`; chưa business VM/repo | Có về blueprint | Không có existing service để duplicate; ký contracts trước tạo shared model |
| Central router, role guards | `appRouterProvider` chỉ `/` | Phù hợp để mở rộng | I01 Auth phải cung cấp current role/session; route proposals chưa được đăng ký |
| Single shared client/DI | `lib/core/supabase/supabase_providers.dart::supabaseClientProvider` | Có | Không tạo client riêng trong orders/notifications |
| Shared theme/widget reuse | `lib/app/theme/app_theme.dart::AppTheme.light`; shared widgets rỗng | Có | Không gọi mock font/brand là đã có; tránh hai owner cùng tạo async/error widget |
| Four separate state enums | schema migration `order_status`, `delivery_task_status`, `cod_status`, `return_request_status` | Có | Không merge enum; ký custody transition chứ không sửa enum theo mock |
| Notification own read/read_at | access migration `notifications_read/update`, `private.stamp_read_time` | Có ở SQL source | Adapter vẫn missing; mark-read idempotent không cần thêm financial receipt |
| Safe customer history/task projection | `tasks_read`; final `business_events_read` | Chưa có implementation, proposal hợp lý | AUD-03: explicit role allowlist; không dùng broad grants/service key client |
| Transactional mutations/job | Migration bodies chỉ helper/trigger | Missing, được S ghi đúng | AUD-01/02; triển khai sau design gates, không yêu cầu RPC có sẵn mới được thiết kế |
| Foreground polling, optional Realtime | `supabase/config.toml` bật service; không publication/app subscription | Có thể phù hợp | Poll 3s + read latency chưa chứng minh freshness ≤5s; benchmark trước claim đạt |
| Test layout/fakes | `test/core/config/supabase_config_test.dart`; integration placeholder | Phù hợp | T là plan; không dùng 7 config tests thay feature/security concurrency suite |

### F.2 Risk ownership và integration gates

| Risk | Owners | Điều kiện bàn giao cụ thể |
|---|---|---|
| Một global receipt proposal buộc thay nhiều modules cùng lúc | Bảo + toàn bộ producer owners | AUD-01: version/scope/rollout map; shared docs cập nhật có owner, không vô tình mở scope Bảo |
| Hủy/dispatch/stock issue khác lock order | Orders + Minh Đức + Inventory/Văn Đức | AUD-02: cùng lock order, pickup fact và quantities; concurrency tests riêng hai connections |
| Profile/session role loading và account switching | Dung An + Bảo | I01 contract states resolved/loading/expired/denied; clear pending/cache/subscription trước user mới; runtime chưa verified |
| Customer được raw task/event trái policy | Orders + Deliveries | Projection whitelist và deny tests; không cấp rộng quyền để tiện render timeline |
| Returns cutoff và active definition | Sơn + Bảo | Server eligibility schema, exact deadline boundary, active request mapping/index; submit ở MH13 là authoritative |
| Notifications dùng target text khác producer | Bảo + deliveries/returns/chat | AUD-05; event→recipient→subject_type/id→route table có version |
| Return bank/evidence tràn vào generic timeline | Sơn + Bảo | Summary DTO explicit columns; customer projection only authorized; shipper body không chứa PII revoked |
| Chat existing INSERT vs synchronous producer/receipt proposal | Dung An + Sơn + Bảo | Chốt nơi atomic message+event+notification; không tuyên bố direct insert hiện tại đã tạo notification; không duplicate ChatRepository |
| Shared files gây merge conflict | Cả nhóm | Một owner mỗi thời điểm cho router/pubspec/lock/shared models/migrations; các feature page không import VM màn khác |
| Performance/history dài | Bảo/backend | D OP-O03 full timeline có thể tăng payload; đo NFR01, nếu đổi pagination phải version contract; hiện chưa chứng minh vi phạm latency |

### F.3 Diagram review

| Diagram S | Kiểm tra semantic | Kết luận |
|---|---|---|
| §13.2 Component | Actor/layer/Supabase foundation vs proposed RPC | Phù hợp chủ trương; không chứng minh runtime wiring |
| §13.3 Navigation | Customer modal, Manager MH09, shared notification target guard | Phù hợp phạm vi; typed mapping phụ thuộc AUD-05 |
| §13.4 Customer view/cancel | Guard/replay/commit/timeout recovery | AUD-08 |
| §13.5 Manager confirm/reject | Manual/job serialize, only winner effects | Không thấy transition trái BR14; replay branch chưa vẽ, phải đồng bộ cùng sửa AUD-08; đây không phải defect độc lập |
| §13.6 Notification | Recipient RLS/read timestamp/target check | AUD-09; read failure/notification_only thiếu |
| §13.7 State | 10 order enums, terminals, no return→cancelled | Hai retry alternatives đã ghi proposed; AUD-02 là gate, không giả định cả hai đã được owner duyệt |
| §13.8 ERD | FK order/items/task/COD/returns/events/notification; optional parents | Các cạnh được vẽ có cơ sở SQL; subset ERD không giả polymorphic FK hoặc receipt table |

Đã đọc cả 7 diagram sources. Kiểm tra thủ công không phát hiện rõ lỗi fence/khối cấu trúc; **syntax và rendering bằng Mermaid engine vẫn NOT VERIFIED**. Không đổi đánh giá đó thành PASS vì Markdown mở được.

## G. Concrete Correction Plan

Các đoạn dưới là **PROPOSED audit corrections**, có thể dùng khi sửa đặc tả sau audit; chưa áp dụng vào S/D/T/E, chưa thiết lập API/schema hiện hữu. Mỗi thay đổi phải cập nhật các tài liệu/tests liên quan trong cùng revision.

### G.1 AUD-01 — Đóng quyết định idempotency trước mutation implementation

**Sửa:** D §7.2/7.3, OP-O08; S Q05/P0; T TX-04–07/23/24; shared `docs/api_contracts.md`, `docs/database.md` khi owner chấp thuận.

Nội dung thay thế cho gate đang chung chung:

```markdown
Idempotency decision gate — BLOCKED UNTIL SIGNED

Chỉ có một protocol được chọn cho release baseline. Decision record phải ghi:
1. Request namespace và unique key chính xác; cách phân biệt actor/system/operation.
2. Persistence owner, result schema, fingerprint normalization và retention.
3. Claim/lock/replay trước state precondition; same-key different payload bị từ chối.
4. Lookup response và current authorization; không lộ receipt của actor khác.
5. Durable client identity: lưu key/payload cần thiết trước submit, theo user;
   restart/timeout phục hồi cùng key, không mặc định tạo key mới.
6. Các producer phải tham gia trong release và cách tương thích dữ liệu cũ.
7. SQL constraints/migration implications; không mặc định UNIQUE ở bảng khác
   đã được registry mới bảo vệ.

Global registry là một phương án kỹ thuật, không phải business requirement.
Nếu chọn scoped registry, cập nhật event uniqueness và lookup signature cùng lúc.
Chưa có decision record thì không triển khai mutation/replay phụ thuộc quyết định này.
```

**Vì sao:** đáp ứng BR36 mà không ép một sở thích kiến trúc thành business rule. **Xác nhận sửa:** owner ký một phương án; đọc lại D không còn hai normative alternatives; contract tests có same key/same payload, changed payload/actor, crash trước/sau commit và lookup after permission revocation. Chưa cần các tests runtime PASS để phê duyệt bản thiết kế, nhưng oracle/fixture phải xác định.

### G.2 AUD-02 — Hoàn thiện delivery/custody handoff

**Sửa:** D §3.1/8, S §8.3/13.1/13.7/I03–I05, T09-07–14. Không tạo màn của Minh Đức hoặc viết lại module Deliveries.

```markdown
Contract custody/retry/receipt — PROPOSED, awaiting owner sign-off

Mỗi action manager phải có input/output/error schema và source authoritative:
- Pickup: xác định field/event chứng minh hàng đã rời cửa hàng; accepted task
  không tự đồng nghĩa pickup. Lịch sử pickup không bị xóa khi reassign/task mới.
- Lần hai: ghi rõ giữ shipper/custody hoặc bàn giao cho shipper khác, task ID mới
  hay quy trình nào phù hợp UNIQUE(task_id) của delivery_attempts; số lần không reset.
- Stock: chỉ issue khi thực tế xuất kho; retry khi hàng còn ở shipper không issue lại.
- Receive/inspect: định nghĩa per-variant expected/received/sellable/damaged/missing,
  quan hệ tổng lượng, xử lý chênh lệch và thời điểm được đóng undeliverable order.
- Cancel/pickup/retry/receipt dùng cùng lock ordering và current-state checks.

State diagram chỉ giữ các cạnh đã ký. Nhánh chưa quyết định được ghi BLOCKED,
không được coding agent tự chọn thông qua enum hoặc timestamp tên gần giống.
```

**Xác nhận sửa:** walkthrough các ca giữ shipper, đổi shipper, pickup/cancel race, retry sau failure1, failure2, inspection thiếu/hỏng/mất và repeated receipt. Quantities và source custody có thể đưa vào fixture, không còn `inspectionItems` không định nghĩa.

### G.3 AUD-03 — Biến dictionary thành wire schema có thể kiểm tra

**Sửa:** D §4/5.2/9, S model/repository/state names; fixture mapper tests. Khuyến nghị thay các alias/subset như sau, đây là proposal cần owner duyệt:

```markdown
Wire contract v1 — PROPOSED

- `order` trong summary/detail/receipt dùng full Order fields của D §2.1;
  không gọi một object subset là Order. Nếu cần tối ưu bằng subset, phải đặt
  tên DTO riêng, liệt kê hết fields và sửa mọi consumer trong cùng revision.
- Dùng `as_of` là key duy nhất cho snapshot timestamp của read response.
- `delivery_summary` là nullable object; danh sách task (nếu được duyệt)
  dùng key riêng `delivery_tasks`, type List, không dùng key `delivery_summary/tasks`.
- Mỗi role có explicit projection field allowlist; quy định missing khác null,
  đặc biệt actor, shipper information và business reasons cho customer.
- Chọn một wire error encoding cho RPC; bảng mapping phải ghi transport status,
  machine code, body keys, domain error, retry semantics và disclosure rule.
  Không để adapter tự parse message text hay đoán shape từ JSON minh họa.
- Cung cấp full valid responses cho customer/manager list, detail, receipt replay,
  conflict, forbidden/unavailable và unknown enum. Examples kiểm tra bằng cùng
  schema/mapper, không dùng truncated examples làm acceptance fixture.
```

**Vì sao:** field trong SQL chỉ là entity; không tự xác định aggregate response. **Xác nhận sửa:** không còn slash alternatives ở normative dictionary; mọi key required có mặt trong full fixtures; zero-row RLS, role-specific omitted fields và application-vs-PostgREST errors có oracle riêng. Khuyến nghị full Order không có nghĩa phải thêm cột DB.

### G.4 AUD-04 — Receipt xác nhận action, không mặc định là trạng thái hiện tại

**Sửa:** S §7.2/12.2, D receipt application semantics; T thêm AT-01/02 trong phụ lục audit.

```markdown
Response ordering và cache — PROPOSED

MutationReceipt xác nhận kết quả của logical operation tại committed_at.
receipt.order không được tự ghi đè latest-order cache đã tải sau đó.
Khi nhận receipt, resolve action state rồi invalidate/refetch list/detail/counts.
Khi mutation bắt đầu/kết thúc, tăng generation của các order reads liên quan;
bỏ các response từ generation cũ và không ghép aggregate thuộc snapshot khác nhau.
Trong khi refresh sau receipt chưa xác nhận, hiển thị action đã thành công nhưng
latest state đang cập nhật; không mở action đối nghịch bằng capabilities lịch sử.
Nếu refresh lỗi, giữ snapshot mới nhất đã xác nhận của cùng session, đánh dấu stale.
Không so sánh enum ordinal, không dùng clock device hoặc coi committed_at là
version toàn bộ order/task/COD/return aggregate.
```

**Vì sao:** không cần tự thêm DB revision để tránh copy một historical receipt vào live cache; nếu nhóm muốn version-based merge thì phải có contract version thực, không dùng `updated_at` một bảng thay toàn graph. **Xác nhận sửa:** response confirm/preparing bị giữ lại, poll nhận delivering, sau đó thả receipt; UI không quay về preparing; logout và late response vẫn fail closed.

### G.5 AUD-05 — Chốt typed target per recipient

**Sửa:** S §9.2/9.4, D OP-N04/05, I06/I08; T event fixtures. Phần thay thế tối thiểu cho các row đa nghĩa:

```markdown
Notification target mapping — PROPOSED, producer owners xác nhận

| Event | Recipient | subject_type | subject_id source | Destination |
|---|---|---|---|---|
| return_pickup_failed | Manager set đã ký | return_request | task.return_request_id đã kiểm tra FK | MH15 |
| rejected_goods_redelivery_failed | Manager set đã ký | return_request | task.return_request_id đã kiểm tra FK | MH15 |
| return_collection_rescheduled | Customer của return | return_request | return_requests.id | MH14 |
| return_collection_rescheduled | Shipper đang được giao task mới | delivery_task | delivery_tasks.id | MH11 |
| order_cancelled | Affected shipper trước khi revoke | notification_only | canonical cancel event id | Nội dung own MH17 |

Mỗi event còn lại cũng phải có exact subject_type/subject_id, không dùng task/return.
Recipients do server lấy theo quy tắc đã ký tại transaction; lưu riêng từng recipient.
Nếu cùng recipient có nhiều target cho cùng event, chọn một target theo contract
hoặc xác định child event riêng: không vi phạm UNIQUE(recipient_id,event_id).
Body không chứa bank/evidence/private task snapshot; route không lấy từ body.
```

**Vì sao:** dùng shape `notifications` hiện có, không cần tự thêm polymorphic payload/API. Manager set, reschedule recipients và chat fan-out cần quyết định thực của owner, audit không phê duyệt thay nhóm. **Xác nhận sửa:** mọi event/role row tạo được exact fixture; resolver chạy ra đúng màn; task→order mapping không vô tình đưa return failure về MH09.

### G.6 AUD-06 — Thay oracle T09-01

**Sửa:** T §4/7, không đổi quyền OP-O03 cho khớp một test sai.

```markdown
T09-01 được tách thành các case sau:
- Customer/shipper mở route /manager/orders/:orderId: route guard từ chối,
  không render Manager projection/action.
- Customer A gọi OP-O03 cho order A: allow, chỉ customer-safe fields;
  đây là data path của MH07, không cấp quyền MH09.
- Customer A gọi OP-O03 cho order B: generic unavailable/denied, không PII.
- Shipper gọi OP-O03 kể cả task đang được giao: deny; dùng task contract của MH11.
- Manager gọi OP-O03: allow Manager projection theo contract đã ký.
```

**Vì sao:** route authorization và resource authorization khác nhau. **Xác nhận sửa:** mỗi case ghi owner fixture và expected response fields; positive customer path không bị test “non-manager deny” bao phủ nhầm.

### G.7 AUD-07 — Đóng event-to-test coverage

**Sửa:** T §5/7; S §9.2; owner handoff test references.

```markdown
Notification producer coverage — PROPOSED

Một parameterized suite phải có row cho từng event key × recipient role của S §9.2.
Mỗi row định nghĩa source state/trigger, recipient IDs kỳ vọng, subject_type/id,
payload allowlist, destination, source event identity và expected read_at=NULL.
Chạy lần đầu, retry cùng logical event, và lỗi producer trước commit:
exactly one row mỗi recipient/event; retry không gửi người mới do recompute fan-out;
transaction failed không để lại business/event/notification/receipt riêng lẻ.
T17-09 chỉ cover automatic confirmation multi-recipient, không dùng làm evidence
cho BR-COM-26–30. Return/COD/Chat producer tests thuộc owner nhưng phải có test ID,
fixture contract và trạng thái bàn giao cụ thể cho Notifications integration.
```

**Vì sao:** assert generic dedup không chứng minh đủ event coverage. **Xác nhận sửa:** join event matrix với test dataset không còn row bắt buộc thiếu coverage; notification PII/deep-link checks giữ riêng; không bắt Bảo viết UI Returns/Chat.

### G.8 AUD-08 — Sửa sequence replay/timeout

**Sửa:** S §13.4 và nhánh shared command trong §13.5; đồng bộ D §7.3, T07-14/TX-05/06. Đoạn flow thay thế:

```markdown
1. Validate current session/role/resource access.
2. Lookup/serialize request identity và fingerprint.
   - Committed receipt: trả kết quả cũ, không re-run pending precondition/effects.
   - Chưa có receipt: lock order/dependencies, recheck eligible state, transaction.
3. Server commit business + stock/task changes + event + notifications + receipt.
4. Tách transport outcome:
   - Response nhận được: resolve action; refresh latest state theo AUD-04.
   - Timeout/lost response: outcomeUnknown, có thể commit hoặc chưa commit.
5. Lookup cùng request key / retry cùng key+payload:
   - receipt có: resolve committed outcome;
   - not_found: vẫn chưa chứng minh request cũ không commit, không tạo key mới;
   - denied: không lộ receipt và không bypass current authorization.
```

**Xác nhận sửa:** sequence có explicit replay alt trước pending validation và response-loss sau transaction; đọc theo diagram cho same-key cancelled order ra replay success. Renderer verification là bước riêng khi có engine, không thay semantic walkthrough.

### G.9 AUD-09 — Đồng bộ notification diagram

S §13.6 thêm nhánh read failure giữ badge/read state chưa xác nhận nhưng vẫn resolve target nếu hợp lệ. Resolver thêm `notification_only` → hiển thị own nội dung MH17, không gọi raw business target; các loại khác mới target authorize/fetch. Kiểm bằng T17-23 và AT-07. Không thêm màn mới.

### G.10 AUD-10 — Sắp xếp lại dependency roadmap

Tách phần confirm core transaction của P6 thành prerequisite cho acceptance P5; có receipt/notifications tối thiểu tương ứng trước khi chứng minh placed→preparing→delivery→COD. Reject/customer cancel/exceptional cancel/failure/returns theo các giai đoạn sau phù hợp OR-05. Nếu dùng fixture preparing cho read UI, ghi rõ **read integration fixture**, không ghi full checkout-to-COD flow đã đạt. Kiểm bằng dependency graph task IDs và một walkthrough không dùng transition thủ công ngoài contract.

## H. Priority Fix List

| Thứ tự | Việc cần đóng | Owner/handoff | Gate |
|---|---|---|---|
| 1 | AUD-01: chọn idempotency/receipt/event protocol | Orders/backend + impacted producers | Trước viết transition/replay/producer persistence |
| 2 | AUD-02: custody/retry/inspection contracts | Orders + Deliveries + Inventory | Trước action MH09 và cancel-pickup integration |
| 3 | AUD-03: final DTO/errors/customer projection, exact fixtures | Orders + Auth + API owners | Trước mapper/repository/UI data binding |
| 4 | AUD-05: exact notification target/recipient matrix | Notifications + producers | Trước producer/resolver integration |
| 5 | AUD-04: cache response ordering; AUD-08: sequence | Bảo | Trước ViewModel mutation/recovery |
| 6 | AUD-06/07: sửa oracle, event coverage | Bảo + QA/producer owners | Trước viết acceptance tests theo bản cũ |
| 7 | AUD-09/10: diagrams và roadmap | Bảo/coordinator | Cùng revision đóng các correction trên |
| 8 | Chốt Q11 cutoff, Auth/session/protected storage, route shell/min OS, nguồn NT | Sơn/Dung An/nhóm | Theo dependency trước phần coding tương ứng; NT/OS đầy đủ trước release acceptance |

Không yêu cầu thêm voucher, GPS, Mua lại hoặc mark-all để đạt readiness. UUID/placeholder có thể là baseline hợp lệ nếu nhóm chọn; không cần tạo human code/image snapshot chỉ để làm báo cáo đẹp.

## I. Final Go/No-Go Decision

**NOT READY FOR IMPLEMENTATION** theo mục tiêu “AI coding agent nhận tài liệu và triển khai đủ MH07, MH08, MH09, MH17 mà không tự đoán”.

Lý do quyết định là các **thiết kế tích hợp chưa đóng** và **mâu thuẫn nội bộ có thể dẫn coding sai**, không chỉ việc repo chưa có UI/RPC. Backend chưa có nghiệp vụ là trạng thái bình thường trước implementation; một thiết kế hoàn chỉnh vẫn có thể được duyệt để coding từ đầu. Ở đây, chính S/D yêu cầu owners chọn giữa các alternatives và ký contracts trước khi làm, nên không thể đồng thời coi toàn bộ thiết kế đã sẵn sàng.

Trước khi giao trọn bốn màn cho coding agent:

1. Đóng AUD-01/02 bằng decision records của các owners; không còn custody/receipt alternatives mang tính normative.
2. Sửa AUD-03–08, có exact response/error/projection/event fixtures và test oracle thống nhất.
3. Đồng bộ S/D/T/E, shared contract docs, diagrams và roadmap; mọi blocked dependency có owner, đầu ra và acceptance cụ thể.
4. Chốt eligibility deadline và Auth/navigation contract cho các phần thực sự sử dụng. Tách các lựa chọn tùy chọn khỏi gate bắt buộc.
5. Audit lại revision đã sửa; test thực thi/migrations/build/NFR là gates trong quá trình coding và trước bàn giao, không được đánh dấu PASS trước khi chạy.

Có thể bắt đầu **phần công việc độc lập sau khi chấp nhận proposal tương ứng** như component UI dùng theme hiện có, formatter, exact enum parsing và adapter own notifications read/read_at. Việc đó không đồng nghĩa full MH09 actions, customer history projection hoặc producers đã sẵn sàng tích hợp; không mở quyền cho agent tự quyết các blocker.

### I.1 Tự kiểm tra báo cáo

- Mỗi defect có vị trí input, nguồn expected, tác động và correction; không tạo defect riêng cho mỗi biểu hiện của cùng nguyên nhân.
- Không coi các proposal RPC/class/routes là implementation; không sửa source/SQL hoặc bốn input Markdown.
- Không lấy review record cũ tại E §7 làm bằng chứng phê duyệt mới.
- Không kết luận có runtime security/financial failure khi chưa có implementation hoặc test thực thi.
- Traceability chi tiết và test cases bổ sung nằm trong [phụ lục audit](independent_technical_audit_mh07_mh08_mh09_mh17_traceability.md); tất cả test bổ sung là `PROPOSED / NOT RUN`.
