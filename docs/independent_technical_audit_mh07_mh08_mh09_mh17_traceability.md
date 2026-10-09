# Phụ lục Independent Audit — Traceability, scenarios và test gaps

Ngày 08/10/2026. Đi cùng [báo cáo audit A–I](independent_technical_audit_mh07_mh08_mh09_mh17.md). Các ký hiệu G/S/D/T/E và snapshot/hash được định nghĩa tại A.1 của báo cáo. Đây là đánh giá tài liệu, không phải kết quả chạy tests.

## 1. Requirement Traceability Matrix

Coverage áp dụng **phần trách nhiệm/interface của MH07, MH08, MH09, MH17**: FULL = đã nêu đủ nguyên tắc/hành vi cần thiết cho phần đó; PARTIAL = còn contract/oracle/gate cụ thể; CONFLICTING = hai nội dung không nhất quán; NOT VERIFIABLE = thiếu nguồn. FULL không thay thế trạng thái API Missing/Proposed và không chứng nhận các module bên ngoài đã xong. Không phát hiện business family bị MISSING hoàn toàn; có các chi tiết contract/test missing được ghi trong Issue.

### 1.1 Business rules — G II.3.1

| Requirement ID | Original Requirement | Technical Document Section | Coverage | Issue |
|---|---|---|---|---|
| BR-COM-01 | Public registration chỉ Customer | S §4, §17 I01; D §2.3 | FULL | Auth dependency; spec không tạo đăng ký privileged role |
| BR-COM-02 | Customer own resources; shipper current tasks/own COD; manager store operations | S §5.2, §9.4, D OP-O03/N04; T09-01 | PARTIAL | Policy chủ trương đúng; test oracle AUD-06 và projection AUD-03 |
| BR-COM-03 | Bank/evidence chỉ owner customer + Manager; shipper không refund/chat | S §5.2/9/14; D §3.3 | FULL | Explicit minimization/denied links; runtime RLS/storage chưa test lại |
| BR-COM-04 | Price/stock per variant, active variant và integer qty | D §2.2; S §6.1, I02 | FULL | Đọc snapshot; không revalidate old orders bằng active catalog; placement owner thực thi |
| BR-COM-05 | Cart không reserve, checkout ở MH16 | S I02, §6.2; E scope | FULL | Không gán order creation/reservation cho MH07; không thêm chức năng cart |
| BR-COM-06 | COD Hà Nội, server address/coordinate check, fee30.000 | S §5.1/8.1; D §2.1 | FULL | Placement validation là dependency, đọc tiền gốc đúng |
| BR-COM-07 | Subtotal=sum price × quantity; COD=subtotal+30.000, integer VND | S §6.1/8.1; D entity validation; T07-07/T09-02 | FULL | Không discount, không amount từ catalog hiện tại |
| BR-COM-08 | All-or-none stock reserve, no oversell | S §5, I02; D §7; T §7 | FULL | Coverage handoff/stock tests owner, không coi CHECK là transactional guarantee |
| BR-COM-09 | Immutable product/variant/price/recipient/address/fee snapshots | D §2.1/2.2; S §6/8; T07-04 | FULL | Ảnh snapshot là proposal, không tự thêm vào rule gốc |
| BR-COM-10 | Confirm không giữ thêm; cancel/reject release once; issue/restock đúng mốc | D OP-O04–07/§8; S §8.3 | PARTIAL | Release chủ trương đủ; AUD-01/02 còn receipt/custody/inspection integration |
| BR-COM-11 | Hỏng/mất không tự bán lại | S §8.3; D §8; T09-14 | PARTIAL | Quantity/ledger contract chưa xác định; AUD-02 |
| BR-COM-12 | Manual pending confirm/reject reason; auto ≥1h, notify customer+manager, không auto assign | D OP-O04/05/JOB-O01; S §7/9 | FULL | Core rule đúng; implementation và receipt gates chưa đóng, không claim job đang chạy |
| BR-COM-13 | Customer own pending; manager confirmed/prepickup reason; release/revoke/notify | D OP-O06/07; S §6/8.3 | PARTIAL | Customer path rõ; authoritative custody cho manager còn AUD-02 |
| BR-COM-14 | Không reconfirm cancelled/rejected; race chỉ một thắng | D §7.3; S §13; T08-08/TX-01–03 | FULL | Row-lock/precondition đúng nguyên tắc; replay sequence riêng AUD-08 |
| BR-COM-15 | Prepared+assigned mới awaiting pickup; current shipper; pickup trước kết quả | S §8.3/13.1; D §8 | PARTIAL | Source pickup/accepted meaning và exact command contract chưa ký, AUD-02 |
| BR-COM-16 | Full goods + full COD atomic delivered | S §8.1/13.1, I03/I05; D CODSummary | FULL | Owner Deliveries thực thi; không cho MH09 tự sửa tiền/status |
| BR-COM-17 | Max2 outbound, không reset reassign; first retry/return; second return | S §8.3/13.1; D §8; T09-12/13 | PARTIAL | Hai state branches còn alternative; AUD-02 |
| BR-COM-18 | Failure delivering ghi reason/time/shipper/attempt, distinct alert; incident riêng | S §7.1/9.2; D §3.1/7.4; T08-13 | PARTIAL | Dữ liệu/alert có chủ trương; producer fixtures event/recipient chưa đầy đủ AUD-07 |
| BR-COM-19 | Hàng về + inspect mới restock sellable/close; uncollected không refund | S §8.3; D §8 | PARTIAL | AUD-02 thiếu quantity/receipt contract khả thi |
| BR-COM-20 | COD uncollected→collected→received độc lập | S §8/13; D §3.2; T09-03/15 | FULL | Missing COD row không tự map uncollected |
| BR-COM-21 | Manager nhận đủ từng order; không partial/batch/shipper receipt | S §5.2/8.3, I05; T09-16 | FULL | Navigation MH12, financial operation giữ ở COD owner |
| BR-COM-22 | Refund không offset shipper COD | S §8/14; D §3.2; TX-19 | FULL | Separate values/states đúng |
| BR-COM-23 | Own delivered return trong7ngày server, xét submit; review muộn không làm hết hạn | S §6.2/Q11; D §3.3/§8 | PARTIAL | Exact cutoff/inclusive policy chưa ký; không cho client quyết định |
| BR-COM-24 | Wrong/missing/defective, description/video/bank required; full order | S §5.1/6.2, I06; T07-17 | FULL | Validation upload thuộc MH13; MH07 handoff đúng, không scope thêm form |
| BR-COM-25 | Một active return; thu all actual received, không thu hàng thiếu | S §5.1/6.2; D §3.3; T07-19 | FULL | Active-first reference/index đã nêu; owner integration cần actual tests |
| BR-COM-26 | Approve pickup ≠ refund; fail pickup manager reschedule, không outbound limit | S §5/9.2, I06; D ReturnSummary | PARTIAL | Required event targeting/tests chưa đầy đủ AUD-05/07 |
| BR-COM-27 | Store receipt/inspection; additional evidence; only sellable restock | S §9.2/I06; D §3.3 | PARTIAL | Summary có; notification proof coverage AUD-07; inspection UI owner Sơn |
| BR-COM-28 | Full merchandise+originalfee refund, external transfer evidence | S §5/8/9.2; D §3.3; TX-19 | PARTIAL | Tách financial đúng, event refund fixture/destination cần AUD-05/07 |
| BR-COM-29 | Failed transfer/correctbank remains pending, không premature refunded | S §5.1/13 labels; I06 | FULL | Consumer không tự chuyển refunded; owner Returns action/tests là dependency |
| BR-COM-30 | Rejectionreason/evidence; free redelivery noCOD; close sau success, failed open | S §9.2/13.1; D handoff | PARTIAL | Semantics đúng; failure/closed event target/test chưa đủ AUD-05/07 |
| BR-COM-31 | Four independent lifecycles; delivered không cancelled bởi return | S §5/8/13; D enums/projections; T09-03 | FULL | Không tìm thấy hợp nhất state sai trong normative design |
| BR-COM-32 | Persist perrecipient/read, dedup eventrecipient, current target auth; inapponly | S §9; D OP-N01–05 | PARTIAL | Read SQL đúng; typed event target/fanout AUD-05, coverage AUD-07 |
| BR-COM-33 | Checkout MH16 khác shipperMH18, no moving GPS | S §6.2/12.4; E C04/C09 | FULL | “Theo dõi” là history/status; không gán GPS/MH18 cho customer |
| BR-COM-34 | Oneconversation/customer, text, no shipper | S §6.2/8.1/9; D open_or_get_conversation | FULL | Chat contract là dependency; không duplicate conversation model |
| BR-COM-35 | Message read khi xem, khác notificationread, chat không business effects | S §9.3; D OP-N03; T17-16 | FULL | Notification tap không tự mark message read |
| BR-COM-36 | Repeated operation returns original result, zero duplicate business effects | D §7/OP-O08; S §13.4; T TX-04–07 | PARTIAL | AUD-01 protocol mở, AUD-04 late receipt, AUD-08 sequence mismatch |

BR-LOGIN-02/05 (active account/role), BR-REG-05/06 (trusted role provisioning), BR-PROD-05/06/07 (inactive variant/variant stock/concurrency), BR-CHAT-01/02/03/05/06/07 được đọc từ G II.2. Chúng là dependencies tương ứng I01/I02/I07, không phải lý do mở rộng bốn màn. Active-account enforcement là `NEEDS VERIFICATION` như D §2.3; không có `profiles.is_active` để giả định.

### 1.2 Common Requirements — G II.3.2

| Requirement ID | Original Requirement | Technical Document Section | Coverage | Issue |
|---|---|---|---|---|
| CR-01 | Backend role/ownership cho mỗi read/write, recheck links | S §5.2/9.4/14; D operations | PARTIAL | Policy approach đúng; explicit role DTO và T09-01 cần AUD-03/06 |
| CR-02 | Logout/account/sessionexpiry xóa cache/sub trước user khác | S §9.3/12.2; TX-08/09 | FULL | Có generation/teardown; actual Auth missing và runtime chưa test |
| CR-03 | Required/nonblank/valid amounts/reasons, definedfieldlimits | D request/query validations; S dialogs | FULL | Reason1..1000 và search200 có nhãn proposal; Auth limits ngoài scope |
| CR-04 | VND nguyên/giờ Hà Nội/server deadlines/thời điểm đọc | D §1; S §12.3; T07-20/T17-05 | FULL | Exact return cutoff theo BR23 riêng; không dùng client clock authority |
| CR-05 | Loading/empty/data/error; preserveinput; no false success | S §6.3/7/9/12; T async cases | FULL | Receipt-cache ordering chưa đủ nằm AUD-04, không phủ nhận async cases đã có |
| CR-06 | Explicit confirm cancel/reject/financial; preventdoubletap | S §6.2/7.2/8.3; D commands | FULL | COD/refund chỉ nav owner, không thêm action tại MH09 |
| CR-07 | Atomic/recheckcurrentstate/refresh after success | D §7.3; S §7.2 | PARTIAL | AUD-01/02 transaction boundary, AUD-04 latest cache |
| CR-08 | Same request retryunknown, lookupstoredresult | D OP-O08/§7; S sequence | PARTIAL | Receipt gate AUD-01; diagram conflict AUD-08 |
| CR-09 | SharedIDs/status/fields/errors, list/detailconsistent | D §4/5, S §12/13 | PARTIAL | AUD-03 wire fields/error; AUD-04 cache order |
| CR-10 | Evidencepermission/association/serverlimits/picker | S I06/§14; T17-22 | FULL | Trong scope chỉ không lộ evidence; upload implementation giao Returns |
| CR-11 | Auditbeforeafteractor/time/reason/request, manualvsauto | D §7.4; S §8.2 | PARTIAL | Event taxonomy/actorSource/child representation chưa chốt Q05/Q08; AUD-01/03 |
| CR-12 | Stablelists/filter; readstatesseparate; reopenrefresh | S §6/7/9/12 | FULL | Cursors/query semantics có; mutable filter cursor cần actual paging tests |
| CR-13 | BusinessID navigation, current permissions | S §12.4/9.4; D N04 | PARTIAL | AUD-05 target pair thiếu ở một số event rows |
| CR-14 | Safe actionable error, no secrets/SQL, success authority | S §5.3/12/14; D §5.2 | PARTIAL | Error UI đúng; wire→domain mapping còn mở AUD-03 |
| CR-15 | Sharedtheme/controls/scroll/keyboard/retaincontext | S §6.3/8.1/12.3; TX-15 | FULL | UI theme decision shared; không clone artwork clipping |

### 1.3 Non-Functional Requirements — G II.2.2

G gọi các giá trị dưới đây là **proposed acceptance criteria**. Audit không đổi thành kết quả đã đạt. Platform/owner tests là dependency, không yêu cầu Bảo implement backup/checkout/upload.

| Requirement ID | Original Requirement | Technical Document Section | Coverage | Issue |
|---|---|---|---|---|
| NFR-01 | 95% reads≤3s,50users,1000variants/5000orders, documentedenv | S §14, T TX-14 | FULL | Performance runtime NOT VERIFIED; full timeline cần đo |
| NFR-02 | 95% business mutations≤5s cùng load | S §14, TX-14 | FULL | Timeout15s không bị nhầm target5s |
| NFR-03 | Relevantopen screen messages/notifications/unread≤5s | S §12.3/14; T17-18/19 | FULL | Poll3s là proposal có benchmark gate; latency đáp ứng chưa chứng minh |
| NFR-04 | Backend access checks, positive/negative tests | S §14; T authcases | PARTIAL | AUD-06 cần positive chi tiết đơn của mình và precise role projection |
| NFR-05 | Thông tin xác thực được bảo vệ trên thiết bị; privatebank/video/evidence; safelogs | S §4/14/Q09; TX-16 | PARTIAL | Device storage policy/evidence chưa có; không suy security từ shared_preferences transitive |
| NFR-06 | Stock atomic/không oversell, cancel/confirm chỉ một bên thắng | D §7; TX-01/20; I02 | PARTIAL | Rule/test intention đủ; AUD-01/02 protocol có thể triển khai pending |
| NFR-07 | No duplicate orders/stock/attempt/COD/refund/chat/notifs | D §7, T idempotencycases | PARTIAL | AUD-01 quyết định chung; AUD-07 event fixture coverage |
| NFR-08 | VND chính xác/snapshots/COD/refund độc lập | S §8/14; D entities/COD; TX-19 | FULL | Không phát hiện arithmeticpolicy conflict |
| NFR-09 | Deadline theo server, auto-confirm ≤60s sau1h; phục hồi đơn quá hạn, không lặp | D JOB-O01; TX-13 | FULL | Schedule/batch là proposal, testload/logs cần chứng minh target khi triển khai |
| NFR-10 | An toàn khi gián đoạn; tải lại dữ liệu authoritative trước cập nhật xung đột | S §12; D OP-O08; TX-07 | PARTIAL | AUD-04 latest state afterreceipt/recovery; durableidentity AUD-01 |
| NFR-11 | Backup hằng ngày ≥7 điểm khôi phục, RTO4h/RPO24h | S §14; TX-22 | FULL | Coverage dependency; backup/restore thực tế NOT VERIFIED |
| NFR-12 | 4/5 người dùng lần đầu checkout ≤5 phút, lỗi có hướng xử lý | S §14; T §7 | FULL | Checkout owner; bốn màn chỉ giữ lỗi có hướng xử lý |
| NFR-13 | OS tối thiểu + mới hơn, ≥2 kích thước, không cắt nút thiết yếu | S §12.3/14/Q09; TX-15 | PARTIAL | Sizes có đề xuất, minOS/platform chưa chốt |
| NFR-14 | Interfaces/rules dùng chung, normal/invalid/concurrent/repeat tests | S §12/17; D/T | PARTIAL | AUD-01/02/03/07; chưa executablecontract hoàn chỉnh |
| NFR-15 | Audit entity/actor/system/time/before/after/reason; immutable | S §8.2/14; D §7.4; TX-17/24 | PARTIAL | Schema hỗ trợ một phần; event/source/child contract Q05/Q08 |
| NFR-16 | Server kiểm tra loại/kích thước file; upload gián đoạn không được coi là evidence hợp lệ | S §14/I06; T17-22 + ownersuite | FULL | Evidence tại bốn màn không upload; owner acceptance evidence cần bàn giao |

### 1.4 Messages, scope và acceptance nguồn

| Requirement ID | Original Requirement | Technical Document Section | Coverage | Issue |
|---|---|---|---|---|
| MSG-01/13 | Field/reason bắt buộc | S §5.3, rejectdialog, D O05/O07 | FULL | Có trim/nonblank và error; không thêm customer cancel lý do bắt buộc |
| MSG-07/08 | Hết phiên/bị từ chối | S §5.3/12; D §5.2 | FULL | Failclosed, generic unavailable; mappingwire AUD-03 |
| MSG-09/10 | Lỗi mạng/kết quả chưa rõ, retry cùng key | S §5.3/12; D O08 | PARTIAL | AUD-01/04/08; text đúng nhưng recoverydesign chưa đóng |
| MSG-11/62 | Bộ lọc rỗng/không có unread | S §6.3/9.1 | FULL | Phân biệt empty list/filter/countunknown |
| MSG-21/22 | Xác nhận hủy và không còn đủ điều kiện | S §6.2/8.3; D O06/O07 | FULL | Precondition customer rõ; manager custody AUD-02 |
| MSG-23/24 | Confirm/preparing, auto1h vẫn cần assign | S §5.3/7/9.2 | FULL | Không auto shipper |
| MSG-25/26 | Xác nhận từ chối có lý do/trạng thái đã đổi | S §7.2; D O05 | FULL | Không client UPDATE trực tiếp/success giả |
| MSG-27/63 | Task bị thu hồi/resource được liên kết unavailable | S §9.4; D N04 | FULL | MH17 MSG63 chung phù hợp; owner task MSG27 ở MH11 |
| MSG-29/30/31/32 | Lần giao thất bại/lý do, max2, inspection, incident | S §7.1/8.3/9.2 | PARTIAL | Warnings có; exact eventcontract/owneraction AUD-02/05/07 |
| MSG-34–37 | COD đầy đủ/thu từ khách/nhận tại cửa hàng/thiếu tiền | S §8.1/8.3/9.2 | FULL | Bốn màn consume/link, không nhận tiền thay MH12 |
| MSG-38/41 | Hạn trả hàng/yêu cầu đang xử lý | S §6.2; D §3.3 | PARTIAL | Q11 cutoff chưa ký; active nav đúng |
| MSG-43–46/48/52/54/55 | Return submit/pickup/evidence/reject/refund/redelivery notifications | S §9.2; D N04/N05 | PARTIAL | AUD-05/07; destination/producer oracle cần exact |
| MSG-59/60/61/66 | Đơn/task/return/tin hỗ trợ mới | S §9.2; T17 genericcases | PARTIAL | Nhóm sự kiện có, fanout Q13 và test matrix AUD-05/07 |
| MSG-02–06/12/14–20/28/33/39/40/42/47/49–51/53/56–58/64/65 | Auth/catalog/checkout/task/evidence/refund/chat input/messages | S §5.3 và I01–I07 | FULL | Chỉ dependency; không yêu cầu các form/action này ở bốn màn. Các message được notification consume phải đúng authorizedcontext |
| OR-01/02 |20screens/roles, exclusions | S §1/6/9/12; TX-18 | FULL | ModalMH07; no feature additionconfirmed |
| OR-03/04 |Stack/contracts/owners đã thống nhất | S §4/12/17 | PARTIAL | Compatible foundation; contracts chưa đóng AUD-01/02/03 |
| OR-05 |Luồng order → delivery → COD trước cancellations/failures/returns | S §16 | PARTIAL | AUD-10 roadmap prerequisite |
| OR-06 |Vùng giao/tài khoản/cấu hình/dữ liệu trước demo | S I01/I02, E §4 gaps | FULL | Môi trường bên ngoài NOT VERIFIED; không fixtures giả thành migration thật |
| OR-07 |API/UI/OS/limits cuối cùng phải agreed/tested trước release | S Q09, D §10 | PARTIAL | DTO/API và minOS chưa final; unrelated media/passwordlimits thuộc owner |
| OR-08 |NT01–NT30 exact baseline/report evidence | T §7.1 | NOT VERIFIABLE | G chỉ nhómNT; chưa cung cấp fullreport |
| OR-09 |Business report v3.0/change control/shared docs | S §18/19; E | FULL | Proposals đánh dấu; chưa có signed changecontrol records |

## 2. Screen completeness review

### 2.1 MH07

| Hạng mục | Vị trí kiểm | Kết luận |
|---|---|---|
| Ownership, chi tiết đơn của mình, chặn đơn khách khác | S §5.2/6.2, D O01/O03/O06 | Design đúng, DTO/oracle cho thao tác được phép cần AUD-03/06 |
| Search code/product, trên toàn bộ các trang | S §6.1, D O01 | Proposal có debounce/serverquery; UUID đầy đủ baseline, Q01/Q04 chưa phê duyệt |
|10status filters/ordercount | S §6.1/13.1 | Enum chính xác, tổng count khác số dòng trang; không tự thêm “Đã xác nhận” enum |
| Card tên/variant/qty/price/date/image | S §6.1, D OrderItem | Snapshot rõ; placeholder đủ; không cam kết ảnh lịch sử giả |
| Tiền/trạng thái COD | S §6.1, D CODSummary | Phí30.000, collected khác received; missing khác uncollected |
| Hủy và hộp thoại xác nhận | S §6.2, D O06 | Own pending, no reasonmandatory mới; locks/release/recovery còn AUD-01/08 |
| Tạo yêu cầu trả/active tracking | S §6.2, I06 | MH13/MH14 đúng; server submit authority, cutoff Q11 mở |
| Details/navigation | S §6.1/12.4 | Modal trong MH07, UUID nghiệp vụ, giữ query/scroll |
| Theo dõi/Mua lại | S §6.2/E C03 | Lịch sử theo dõi phù hợp scope; không GPS; rebuy không baseline |
| Async/accessibility | S §6.3/12.3 | Loading/empty/error/stale/sessionexpired và nội dung dài có |
| Thay đổi trạng thái đồng thời | S §6.2/12.2 | Recheckbackend đúng; late receipt/read cache AUD-04 chưa đủ |

### 2.2 MH08

| Hạng mục | Vị trí kiểm | Kết luận |
|---|---|---|
| Chỉ Manager/danh sách được phép | S §5.2/7, D O02 | Phân quyền role server, không lấy role client |
| Search buyer vs recipient | S §7.1 | Phân biệt đúng; matching full_name null fallback cần theo signedquery |
| Filters/statuscounts | D O02/§4.1 | Counts toàn query, bỏstatus filter trongdistribution, as_of chung; DTO AUD-03 |
| Card contact/items/COD | S §7.1 | Có immutable snapshot và nhãn người mua/người nhận; không bank/evidence |
| Confirm/reject/reason | S §7.2, D O04/O05 | Khóa đơn pending, trim lý do từ chối, không reserve thêm |
| Race auto-confirm/request lặp | S §7.2, D §7/JOB | Thiết kế chỉ bên thắng đúng; registry AUD-01 và sequence AUD-08 |
| Trạng thái đổi từ xa/bị cũ | S §7.2/12 | Các nút đối nghịch disabled, refreshcount; cache AUD-04 |
| Cảnh báo giao thất bại/sự cố | S §7.1/9.2 | Attempt thực tế khác incident, bộ đếm của order; tests sự kiện AUD-07 |
| MH09 andreturnnavigation | S §7.2/12.4 | UUID entity, kiểm tra role; returncount dependency tùy chọn không gộp orderstate |
| Async/navigationcontext | S §7.2, T08-14 | Có error/refresh/retry; không âm thầm dùng dữ liệu demo |

### 2.3 MH09

| Hạng mục | Vị trí kiểm | Kết luận |
|---|---|---|
| Buyer/recipient/phone/address | S §8.1, D §2.1/2.3 | Snapshot khác profile hiện tại; badge thành viên bỏ |
| Call/chat | S §8.1/8.3, I07 | Dialer tùy chọn; message=chat in-app với khách, không SMS/chat shipper |
| Items/variant/price/qty/line total | S §8.1 | Không lấy catalog hiện tại thay snapshot |
| Subtotal/fee/total/COD | S §8.1 | No discount; phí đầy đủ; COD received độc lập |
| History/actors/timestamps/reason | S §8.2, D Timeline | Event thực/fallback có nhãn rõ; nguồn actor/quyền hiển thị contract Q08 và AUD-03 |
| Bốn lifecycle | S §8/13, D §3 | Tách đúng, không delivered→cancelled bởi return |
| Confirm/reject | S §8.3, D O04/O05 | Operations dùng chung MH08; receipt chính xác AUD-01/03 |
| Cancel/preparation/assign/reassign | S §8.3; D §8 | Có action nhưng custody/hợp đồng pickup chưa đủ AUD-02 |
| Retry/hoàn sớm/storeinspection | S §8.3/13.1; D §8 | Handoff bị chặn, chưa đầy đủ quantity/invariants AUD-02 |
| COD/Returns destinations | S §8.3/12.4 | MH12/MH15 đúng quyền sở hữu; không triển khai thanh toán ở MH09 |
| Authorization/async/layout | S §12/14, T09-01/18/20 | RLSphải enforce; test oracle AUD-06; lỗi aggregate atomic đúng |

### 2.4 MH17

| Hạng mục | Vị trí kiểm | Kết luận |
|---|---|---|
| UI tham chiếu/cây thành phần | S §9.1 | Proposed Design rõ, không có pixel verification |
| Nhóm sự kiện | S §9.2 | Các nhóm sự kiện bắt buộc xuất hiện; target/fan-out chính xác AUD-05 và testcoverage AUD-07 |
| Người nhận/lưu trữ | D §2.5, N01/N05, SQL | Một row/recipient, event FK, unique; Manager không đọc hộ inbox |
| All/unread/sort/cursor | S §9.1, D N01 | Ổn định theo (created_at,id), read_at null, fetching không mark read |
| Badge/count chính xác | D N02 | Count toàn bộ thông báo của recipient; eventual consistency giữa các query được công khai |
| Mark read/nhiều phiên | S §9.3, D N03 | Mốc đọc đầu tiên của server, không lùi về unread; không coi zero rows là success |
| Mark-all/mark-unread/push | S §9.3, T17-21 | Baseline không có; không lỗi thiếu tính năng |
| Deep-link/kiểm tra lại quyền | S §9.4, D N04 | Union có kiểu, target fetch qua RLS; AUD-05 mapping chính xác chưa đủ |
| Missing/revoked/target sai định dạng | S §9.4, T17-12–15/23 | MSG63 chung, không fallback sang PII cache; diagram AUD-09 |
| Lỗi mark-read/retry điều hướng | S §9.3, D N03/N04 | Text cho navigation độc lập; diagram chưa khớp AUD-09 |
| Logout/đổi tài khoản | S §9.3/12.2, TX-08/09 | Xóa namespace/callbacks/subscriptions theo user; Auth implementation chưa có |
| Freshness giữa các màn | S §12.3, T17-18/19, TX-12 | Đề xuất polling/invalidation; ≤5s chưa đo |

## 3. Review 14 tình huống nghiệp vụ trọng yếu

Hai bảng dùng cùng Scenario ID. **Auth** trong bảng A là backend identity/role/ownership bắt buộc, UI chỉ gợi ý. **Receipt** trong bảng B là proposal D, chưa tồn tại trong schema. Những nhận xét “đủ nguyên tắc” không phải chứng nhận transaction đã chạy.

### 3.1 Preconditions, trigger, authorization và transition

| ID | Scenario/preconditions | Trigger + authorization | Transition/expected result | Coverage/evidence |
|---|---|---|---|---|
| SC01 | Manager confirm pending, reservation consistent | OP-O04; Manager hiện tại; khóa order | pending_confirmation→preparing, không assign/không reserve thêm | D O04; đủ rule, AUD-01/03 gate |
| SC02 | Manager reject pending; lý do bắt buộc sau trim | O05; manager; validate reason và pending dưới lock | pending→rejected; lưu lý do; blank bị chặn, không side effects | D O05; T08-06/07; đủ rule |
| SC03 | Pending age≥1h theo giờ server | JOB-O01 từ server tin cậy, không client giả nguồn automatic | pending→preparing automatic; confirmed_by null/nguồn được xác minh; không assign | BR12/NFR09; D JOB; phép đo chưa chạy |
| SC04 | Customer own pending | O06; ownership + role customer | pending→cancelled sau xác nhận tường minh | D O06; T07-09; đủ rule |
| SC05 | Customer order đã preparing hoặc muộn hơn | O06 trực tiếp/nút đang cũ | Từ chối: không cho phép/trạng thái hiện tại; không transition | T07-10/12; không chỉ ẩn nút |
| SC06 | Manager và job cùng pending đủ điều kiện | Hai bên tranh chấp có quyền hiện tại, cùng khóa | Chỉ một bên: pending→preparing; source/actor của bên thắng | D §7; TX-02; đủ nguyên tắc tuần tự hóa |
| SC07 | Order cancelled/rejected | Manager confirm logical key khác | Deny state_changed; không reconfirm | T08-08; replay key gốc xử lý riêng SC08 |
| SC08 | Cùng operation gửi hai lần | Cùng actor/key/payload; quyền hiện tại | Receipt gốc; payload khác bị conflict; không transition mới | D §7; AUD-01/08 |
| SC09 | Mutation commit nhưng response bị mất | Caller hiện tại phục hồi cùng key | Unknown trước lookup; receipt đã commit xác định kết quả; order hiện tại có thể mới hơn | D O08; AUD-04/08 |
| SC10 | Màn hình/dialog đang mở, resource đổi | Action từ xa/poll; kiểm tra lại khi submit | UI snapshot mới nhất; chặn action từ trạng thái cũ, không success lạc quan | S §6/7/12; thiếu xử lý response đến muộn AUD-04 |
| SC11 | Reject/cancel giữ nhiều variants | Command có quyền thắng race; khóa transaction | Reserved giải phóng đúng một lần cho tất cả; lỗi thì rollback toàn bộ | D O05/O06/O07; gate quantity/custody AUD-02 |
| SC12 | Thay đổi nghiệp vụ đủ preconditions | Producer tin cậy trong transaction thắng | Lưu notifications cùng commit, đúng recipients, unread | D N05; target/fanout AUD-05 |
| SC13 | Producer của source event bị retry | Cùng event identity + contract recipients | Một notification cho mỗi recipient/event, không root/child trùng | SQL unique; D §7.4/N05; AUD-01/07 |
| SC14 | Customer B order/notification hoặc task không được phân công cho shipper | Đã đăng nhập nhưng sai owner/role | Denied/unavailable chung; không PII/thay đổi trạng thái | SQL RLS; D N04/O03; oracle T09 AUD-06 |

### 3.2 Atomicity, idempotency, errors, audit và side effects

| ID | Atomicity/idempotency được yêu cầu | Errors/recovery | Audit + side effects | Kết luận audit/test |
|---|---|---|---|---|
| SC01 | State + event + thông báo khách + receipt cùng commit; replay cùng key | state_changed/idempotency_conflict/integrity; timeout xem SC09 | Actor Manager/confirmed_at server/source; reservation unchanged | T08-05/15, TX-05; backend protocol chưa final |
| SC02 | Release tất cả variants + state + reason + event + notify + receipt atomic | lý do rỗng không hợp lệ; conflict do trạng thái cũ; lỗi rollback | Lý do reject event an toàn cho khách; stock ledger đúng một lần | T08-06/07, TX-20; mapper/error AUD-03 |
| SC03 | Transaction chuyển trạng thái dùng chung, overdue dedup; job identity ổn định theo order | Bỏ qua row đã đổi; phục hồi quá hạn, không confirm sớm | Nguồn system; thông báo customer + manager, không phân công | TX-13; protocol identity AUD-01 |
| SC04 | Cancel + release + revoke nếu có + event + notify + receipt atomic | không đủ điều kiện/bị từ chối; timeout retry cùng key | Actor customer, giờ server; một lần giải phóng kho | T07-09/11/13/14; diagram AUD-08 |
| SC05 | Không ghi khi precondition thất bại; replay operation đã thành công là ca riêng | MSG22/26+refresh authoritative | Không stock/event/notification từ action thua race/không hợp lệ | T07-10/12; Đủ oracle cho ca bị chặn |
| SC06 | Serialize/recheck; bên thua không side effects; cùng logical key được replay | Manual bên thua nhận state_changed; job bên thua skip | Một source event và fan-out, nguồn đúng bên thắng | TX-02/03; tests thực với nhiều connection là bắt buộc |
| SC07 | Giữ nguyên trạng thái terminal; không reserve lần hai | state_changed; không coi key mới là success cũ | Không event/notify mới | T08-08; phân biệt terminal rejection với replay |
| SC08 | Lookup receipt trước state precondition; kiểm tra actor/payload | Payload khác không được replay; bị từ chối không được đọc receipt | Giữ event identity/ledger/notify gốc | TX-04/05/23/24; AUD-01/08 chưa đóng |
| SC09 | Effects đã commit chỉ một lần dù client timeout | Lookup not_found không chứng minh rollback; retry cùng key; không key mới | Audit receipt giữ nguyên; latest state tải riêng | T07-14/TX-06/07; AT-01/02 bổ sung |
| SC10 | Server luôn kiểm tra lại; cache client không cấp quyền transition | Lỗi refresh giữ data cũ an toàn; phải áp dụng response theo thứ tự phù hợp | Chỉ bên thắng thực tế được audit; reads không có business side effect | T09-19/TX-12 kiểm tra luồng thông thường; AT-01/02 kiểm tra phản hồi muộn |
| SC11 | Khóa variants theo thứ tự xác định, ledger đúng một lần; chỉ release reservation trước pickup | Gây lỗi giữa transaction→rollback toàn bộ | Inventory movement dùng canonical event cho từng variant; không restock hàng đang do shipper giữ | TX-20/T09-09/14; contract custody thực tế AUD-02 |
| SC12 | N05 baseline đồng bộ; không success khi insert notification thất bại | Lỗi producer rollback; retry cùng operation | Canonical event → rows theo recipient, không PII trong body | TX-21; tests sự kiện AUD-07 |
| SC13 | Event identity ổn định + SQL unique(recipient,event), contract child causation | UUID trùng nhưng payload khác không tự success | Không lặp root/child/history hoặc đóng góp vào count | T17-08/09, TX-24; fan-out chính xác AUD-05 |
| SC14 | Quyền trước protected read/write/replay; không fallback admin | RLS zero rows ≠ success; thông báo chung; ẩn PII cache | Không tạo mutation/audit business success | T07-01/11/T17-01/02/12/15; tách T09-01 |

## 4. Data/API consistency audit bổ sung

| Boundary | Đã kiểm tra | Kết quả và giới hạn |
|---|---|---|
| SQL → entity dictionary | Orders/items UUID, bigint, totals sinh bởi DB, confirm nullable fields, profile fields nullable, business_events extensions, notification columns | Không phát hiện cột Order/Item/Notification bị khai có thật nhưng không tồn tại; `event_kind`/receipt đều ghi proposed |
| Schema cuối và bảng đã loại bỏ | Simplify drops inventory_balances/refunds/refund_accounts/return_evidence và chuyển data đích | D/S sử dụng schema cuối; không đề xuất đọc bảng đã drop cho bốn màn |
| Relationships | Orders/customer, item/order, task/order/return, attempts composite FK, notification event/recipient FK | ERD subset có cơ sở; subject_type/id không có polymorphic FK và spec thừa nhận |
| Status |10 order/9 task/3 COD/11 return enums, nhãn riêng | Không phát hiện enum giả từ mock; retry semantics chưa final AUD-02 |
| Money | VND nguyên, subtotal/fee/total sinh bởi DB, unit price × quantity | Phí cố định đúng; precision runtime/limits chưa kiểm thử, không coi JSON sample là fixture thật |
| Time | UTC/server làm chuẩn/ngày giờ Hà Nội; trigger lần đọc đầu | Đúng nguyên tắc; return biên chính xác Q11; job thời gian phải đo |
| Raw notification API→adapter | GET array, PATCH selected row, count riêng | D nói rõ raw shape khác NotificationPage; không bịa wrapper endpoint đang tồn tại |
| RPC aggregate→DTO→Domain | Order subset/full, key dùng dấu / alternatives, role sanitizer, errors | AUD-03; chưa có mapper/code để runtime check |
| DTO→UI | Receipt lịch sử vs latest state, current_order tùy chọn | AUD-04; immutable receipt không phải version trạng thái hiện tại |
| Pagination/filtering | Keyset time + UUID, max100, query scope, count toàn bộ query trên server, as_of | Semantics khá rõ; invalid cursor/Hanoi time có planned cases; DTO `query.statuses` vs chip đang chọn cần một nguồn suy ra khi coding, không kết luận bug runtime |
| Auth/retry | Role từ profiles tin cậy, không service key UI, read retry có giới hạn/mutation cùng key | Đúng nguyên tắc; wire errors/receipt keys/durable storage còn gates |
| Examples |5 JSON fenced blocks parse được, reject request shape phù hợp params đề xuất | Order/receipt example ghi rõ subset; không có fixture response đầy đủ để chứng nhận parser, AUD-03 |

Không có database/cloud runtime ở audit để chứng nhận actual grants, RPC đã deploy, Cron publication hoặc Supabase connectivity. Kết luận schema/policy ở đây là **VERIFIED IN CODEBASE**, không trạng thái đã triển khai verification.

## 5. Test cases cần bổ sung hoặc sửa

Các case dưới đây **PROPOSED / NOT RUN**; không tạo test code trong audit. AT-03 thay/tách oracle T09-01; AT-06 là parameterized suite nên một ID không có nghĩa chỉ một event fixture. Không dùng malformed UUID row làm fixture DB vì kiểu `uuid` sẽ chặn; malformed payload/route phải ở mapper/navigation test, dangling UUID target có thể ở notification subject vì không có polymorphic FK.

| Test ID | Screen/type | Scenario | Preconditions | Steps | Expected Result | Priority |
|---|---|---|---|---|---|---|
| AT-01 |08/09 U/I|Receipt mutation lần đầu đến muộn|Confirm commit sang preparing; giữ response; valid delivery đổi trạng thái |Poll tải delivering, sau đó thả receipt confirm, cho refresh sau đó lỗi|Action confirm thành công; cache không lùi preparing, không dùng capabilities cũ; staleness rõ|P0|
| AT-02 |07/08/09 U/I|Replay sau snapshot mới hơn và late read|Receipt gốc đã biết; order mới nhất tiến triển; initial read đang chạy|Phục hồi receipt; trả read cũ sau refresh mới|Kết quả gốc tách latest state; bỏ generation cũ, không side effects thêm|P0|
| AT-03 |07/09 B/I/W|Route vs API role/ownership matrix|Customer A/B orders, Manager, Shipper; DTO theo role đã ký|Mỗi role mở route Manager và gọi O03 dùng chung cho own/other ID|Route MH09 chặn non-manager; Customer own RPC cho phép projection an toàn; other/shipper bị chặn; Manager cho phép theo contract|P0|
| AT-04 |07/08/09 U/contract|Schema đầy đủ vs examples/errors|AUD-03 đã đóng, full fixtures có version|Parse từng list/detail/receipt/error; thiếu field bắt buộc, null tường minh, enum không biết|Valid map đúng; invalid thành safe error; không đoán alias/default pending; omit field theo privacy đúng|P0|
| AT-05 |09 B/I|Retry custody invariants|AUD-02 đã ký, thất bại attempt 1 variants; fixtures giữ/đổi custody|Bố trí attempt 2, retry cùng key, hủy sau khi đã pickup trong lịch sử, sau đó fail 2/inspection|Giữ count/history; không issue stock lần hai khi retained; không attempt thứ ba; stock đúng một lần, không oversell|P0|
| AT-06 |17 B/I|Mỗi source event × role target/fan-out|matrix chính xác AUD-05; producer states của từng owner; ca Manager thứ hai/Shipper mới|Trigger từng row; replay; change manager set then replay cùng event; gây lỗi producer|Đúng recipients/target/type, một row/event/recipient, fan-out đã commit giữ ổn định; lỗi rollback tất cả; không PII; đúng destination|P0|
| AT-07 |17 U/I|Lỗi mark-read và notification_only|Own unread notification_only khi hủy, ca business link; lỗi mark-read|Tap; PATCH lỗi; resolve target khả dụng; retry read|Notification-only no fetch task/event; business link chỉ mở sau access check; count không giảm khi lỗi|P1|
| AT-08 |07/09/17 B/I|Customer negative field allowlist của projection|Đơn của mình has shipper/internalincident/private fields; whitelist AUD-03 đã ký|Get customer list/detail andnotification targets; kiểm tra JSON thô|Chỉ các fields trong whitelist, decision reason cho customer nếu được phép; no profile không liên quan/bank/evidence/điều tra nội bộ|P0|
| AT-09 |07 I|Hạn trả hàng chính xác: deadline boundaries|Owner Sơn signed cutoff calendar/elapsed/inclusive; fixture clock server|Submit trước/đúng/sau boundary; mở trước và submit sau; review muộn|Results theo boundary đã duyệt; review muộn không vô hiệu submission đúng hạn; clock thiết bị không ảnh hưởng|P0|
| AT-10 |08/09 B/I|Cùng key cancellation replay từ terminal state|Own pending cancellation đã commit; currentrole/ownership valid|Retry cùng request khi order đã cancelled; key khác hủy lại|Cùng key trả success gốc, key khác không đủ điều kiện; không side effects mới; sequence/rule nhất quán|P0|
| AT-11 |17 I/P|Freshness with reads gần giới hạn latency|Môi trường tham chiếu đã ký; pollbaseline; queries nearing3s|Insert notification ngay sau snapshot poll; mark read trên thiết bị thứ hai; measurestored→visible|Ghi đầy đủ latency; ifvượt target 5s thì fail và điều chỉnh chiến lược, không suy đạt từinterval 3s|P1|
| AT-12 |All documentation/integration|Roadmap dependencies executable|Confirm core operation trước P5, xác định owner fixtures/API thật|Chạy luồng placed→confirmed→pickup→delivered+collected→received|Không patch status trực tiếp DB để nhận E2E đạt; lần chạy chỉ fixture phải ghi rõ; mọi operation cần thiết được xếp trước acceptance|P1|

### 5.1 Requirement-to-added-test traceability

| Requirement/defect | Added tests | Chứng minh cần đạt |
|---|---|---|
| CR-07/09, NFR-10, AUD-04 | AT-01/02 | Cachekhông lùi khi receipt/read đếnmuộn |
| BR-COM-02/03, CR-01, NFR-04, AUD-03/06 | AT-03/08 | Positiveownread và denyother; no lộ projection Manager |
| CR-09/14, NFR-14, AUD-03 | AT-04 | Exactwire/domain mapping và errors an toàn |
| BR-COM-13/15/17/19, AUD-02 | AT-05 | Custody/attempt/stock effects theo một contract đã ký |
| BR-COM-32/36, II.1.2.5–6, AUD-05/07 | AT-06 | Mỗi event family bắt buộc có recipient/target/dedup oracle |
| CR-05/12/13, AUD-09 | AT-07 | Read ack/navigation độc lập, no query fallback trái quyền |
| BR-COM-23, Q11 | AT-09 | Cutoff chính xác sau phê duyệt, client không đoán |
| BR-COM-36/CR-08, AUD-01/08 | AT-10 | Replay receipt cũ trước validation trạng thái |
| NFR-03 | AT-11 | Freshness đo thực tế; không mặc định polling đạt |
| OR-05, AUD-10 | AT-12 | Thứ tự dependency khớp acceptance |

### 5.2 Tests hiện có: những gì không nên tuyên bố

- 104 cases trong T là planned specification; repository chưa có 104 test implementations.
- `test/core/config/supabase_config_test.dart` kiểm cấu hình, không chứng minh screen/business coverage.
- `supabase/tests/database_security.sql` là source test nền có rollback, không chứng minh các proposed RPC/job/races đã PASS.
- Owner integration tests được yêu cầu nhưng chưa có identifier/result cụ thể; không tính là executed coverage.
- NT exact acceptance không thể xác nhận ngoài nhóm chủ đề G OR-08. Cần nguồn report đầy đủ hoặc baseline acceptance do nhóm chính thức chốt.
- Các alias `TX01/02`, `TX17` trong T §7 là shorthand của test IDs có dấu gạch. Nên chuẩn hóa exact IDs khi làm machine-readable traceability; đây là cải thiện độ tra cứu, không nâng thành defect nghiệp vụ mới.

## 6. Điều kiện đóng audit

Mỗi AUD-ID cần revision reference, owner, nội dung đã sửa, cross-document consistency check và oracle kiểm tra. Đóng lỗi tài liệu không đồng nghĩa tests runtime PASS. Sau khi các blocker/major được xử lý, thực hiện re-audit bounded vào sections thay đổi và integration dependencies; giữ các evidence/hash của bản audit này để tránh nhầm phiên bản.
