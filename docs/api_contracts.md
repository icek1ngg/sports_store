# Hợp đồng truy cập database

Lưu ý phiên bản: baseline và P00.2 dưới đây ghi hiện trạng trước P01.1.
Lớp đọc task mới và các quyền bị thu hẹp được mô tả tại mục P01.1 cuối file;
không dùng nhánh shipper của baseline làm quyền truy cập hiện hành sau migration đó.

## Baseline Data API

Ứng dụng lấy một client duy nhất từ `supabaseClientProvider`. Repository thuộc feature sở hữu dữ liệu thực hiện truy vấn; ViewModel gọi repository. Không dùng secret/service-role key trong Flutter.

| Nghiệp vụ | Data API hiện được phép |
|---|---|
| Xác định vai trò | Đọc `profiles` theo ID của session; vai trò server-managed |
| Xem sản phẩm/tồn | Đọc `categories`, `products`, `product_variants` khi role customer/manager; tồn nằm trên biến thể |
| Quản lý sản phẩm | Manager INSERT/UPDATE cột được cấp quyền của `products`, `product_variants`; ngừng bán bằng `is_active`, không xóa lịch sử |
| Quản lý giỏ | Customer CRUD `cart_items(customer_id,variant_id,quantity)` của mình, chỉ UPDATE `quantity`; giỏ rỗng là không có dòng hàng |
| Xem nghiệp vụ | Đọc đơn, nhiệm vụ, COD, yêu cầu trả và bằng chứng theo RLS; không INSERT/UPDATE trực tiếp các trạng thái |
| Thông báo | Đọc của mình; UPDATE `read_at` của mình; server giữ mốc đọc đầu tiên |
| Mở hội thoại | Customer INSERT `conversations(customer_id)`; UNIQUE ngăn tạo hai hội thoại. Nếu bị duplicate, đọc lại hội thoại của mình |
| Gửi tin | Customer/manager INSERT `messages(conversation_id,sender_id,body,client_message_id)`; sender trùng session; khách chỉ gửi hội thoại của mình |
| Đọc tin | Đọc `messages` của hội thoại được phép, sort `created_at`, rồi `id` để ổn định |
| Mốc đọc hội thoại | UPDATE `conversations.read_at_by_user` của hội thoại được phép; trigger bỏ qua JSON client gửi, ghi giờ server cho user của session và giữ mốc người khác |

Timestamp và ID tự sinh không nên gửi khi INSERT. Column grants cố ý không cho sửa ID, chủ sở hữu, thời gian tạo hoặc dữ liệu tài chính. Unique constraint trả lỗi `23505` khi INSERT trùng; Repository cần đọc lại kết quả theo khóa idempotency và kiểm tra đúng payload trước khi coi retry thành công.

`return_requests` chứa `inspection_evidence_paths`, `additional_video_paths`, các cột ngân hàng và bản ghi hoàn tiền. Shipper chỉ đọc `return_items` theo nhiệm vụ; không đọc nguyên yêu cầu trả. `business_events` ghi thêm sự cố bằng `task_id`, `incident_kind`, `request_id`, actor và lý do; sự cố dùng `subject_type = 'delivery_task'` và `subject_id = task_id`. Shipper chỉ đọc sự cố mình ghi cho nhiệm vụ hiện được phân công. Các trường này chỉ được ghi qua server.

Cập nhật mốc đọc hội thoại không thay đổi `conversations.updated_at`. Khi triển khai danh sách hội thoại, phải chốt cách cập nhật thời điểm hoạt động khi nhận/gửi tin nhắn trong API chat.

Lỗi thiếu grant/RLS thường là `42501`; FK là `23503`; CHECK là `23514`. Không xử lý lỗi quyền bằng cách đổi sang service-role key hoặc bỏ RLS.

RLS trên đối tượng đích vẫn được kiểm tra khi mở liên kết thông báo. Nội dung thông báo không được nhúng bank details hoặc snapshot riêng tư của nhiệm vụ cho người không còn quyền.

## RPC/tác vụ server cần triển khai theo feature

Các mục dưới đây là trách nhiệm tích hợp tiếp theo; chưa phải endpoint tồn tại và chưa chốt chữ ký RPC. Thành viên phải bổ sung tên/chữ ký/error code vào tài liệu cùng migration triển khai.

| Chủ sở hữu | Hợp đồng bắt buộc |
|---|---|
| Văn Đức: checkout/inventory | Xác thực địa chỉ/tọa độ Hà Nội; khóa biến thể theo thứ tự; kiểm tra toàn bộ giỏ; giữ tồn và tạo snapshot trong một transaction; retry trả cùng đơn |
| Dung An: catalog | Điều chỉnh tồn có event ID; nhập/điều chỉnh ghi ledger, không sửa trực tiếp lượng giữ của đơn |
| Bảo: orders/notifications | Xác nhận/từ chối/hủy có khóa đơn và precondition; giải phóng tồn một lần; job server tự xác nhận sau một giờ; notification theo recipient/event |
| Minh Đức: deliveries/COD | Phân công hiện tại; tối đa hai lần giao đi; nhận/xuất hàng; ghi giao thành công cùng thu đủ COD; chỉ manager xác nhận nhận đủ; không bù trừ trả hàng |
| Sơn: returns | Deadline tại thời điểm gửi; kiểm tra video; chỉ một request active; thu đúng hàng thực nhận; kiểm tra/nhập lại có event ID; hoàn đầy đủ với bằng chứng; redelivery không COD |
| Dung An + Sơn: chat | API mở/gửi chống trùng, thông báo đúng recipient, cập nhật mốc đọc theo nội dung đã hiển thị và kiểm tra concurrency |

Mọi action thay đổi tồn/tiền/trạng thái phải kiểm tra identity, role, quyền trên đối tượng, trạng thái trước đó, mã chống trùng và tính nhất quán nhiều bảng ở server. Không thay các transaction này bằng chuỗi request Flutter.

`private.current_app_role()` chỉ là helper RLS đọc vai trò của session, không phải RPC app. Trigger đăng ký không sử dụng `user_metadata.role` để quyết định quyền.

## P00.2 — Đề xuất API giao nhận/COD và tích hợp (23/10/2026)

**Toàn bộ tên RPC, DTO, error code và chữ ký dưới đây là đề xuất, chưa triển
khai, chưa được các owner duyệt.** Đối chiếu ba migration `20261006034251`,
`20261006034259`, `20261006040019` trong `supabase/migrations`, provider client
và router hiện tại; không truy vấn cloud trong phase này. Chỉ helper/trigger
private có trong migration, không có RPC giao nhận/COD public. Không suy ra
API tồn tại từ tên trong kế hoạch. Quy tắc trạng thái và quyết định D1–D10
tham chiếu [P00.1](business_states.md); thay đổi schema cần xem
[database.md](database.md), không tạo migration trong P00.2.

### Kiểu dữ liệu, kết quả và lỗi dùng chung (đề xuất)

- Tham số RPC dùng tên `p_` + tên trong bảng dưới. ID là UUID; giờ là
  `timestamptz` UTC do server tạo; tiền VND `bigint`, số lượng nguyên dương,
  enum khớp schema. Payload không nhận actor/role/giờ server/giá từ client.
- Mọi write nhận thêm `request_id:uuid` bắt buộc. Write trên task hiện có
  nhận `expected_version:bigint`; write tạo task nhận `expected_order_version`
  và `expected_return_version` nếu có request. Write chỉ order/return/COD nhận
  version của aggregate tương ứng. Version là schema mới **chưa có**, không
  dùng timestamp làm khóa chống race. Version mismatch kiểm tra sau replay.
- `TaskResult` = `{request_id,event_id,task_id,order_id,return_request_id?,
  task_status,order_status,return_status?,cod_status?,version,committed_at}`.
  Với shipper, bỏ `order_status/return_status` nếu chưa duyệt projection an
  toàn; không trả nguyên row order/return. Version là version task; các
  aggregate version khác có thể trả cho manager trong `versions` map.
  `OrderResult`/`ReceiptResult` dùng cấu trúc tương tự với versions của order,
  request và task liên quan; `CodResult` gồm order_id/status/amounts/version/
  event_id/committed_at/request_id. Không trả bank/video/evidence qua các DTO này.
- Lỗi nghiệp vụ đề xuất: `AUTH_REQUIRED`, `FORBIDDEN`, `NOT_FOUND_OR_FORBIDDEN`
  (không tiết lộ ID ngoài quyền), `INVALID_ARGUMENT`, `STATE_CONFLICT`,
  `VERSION_CONFLICT`, `ASSIGNMENT_CHANGED`, `ATTEMPT_LIMIT`,
  `CUSTODY_UNRESOLVED`, `ITEMS_MISMATCH`, `AMOUNT_MISMATCH`,
  `IDEMPOTENCY_CONFLICT`, `DEPENDENCY_NOT_READY`. Lỗi transport giữ riêng.
  Ánh xạ dự kiến qua exception `P0001` với message là mã và detail JSON an
  toàn; chưa là SQLSTATE riêng đã có. Không trả thông tin nhạy cảm trong lỗi.
  `42501/23503/23505/23514` hiện có là lỗi Postgres, không tự coi duplicate
  `23505` là success. `40001/40P01` có thể retry có giới hạn với cùng ID.

### Transaction, khóa và retry áp dụng cho từng write (đề xuất L)

L = một transaction gồm claim idempotency, khóa aggregate, kiểm tra quyền và
precondition, ghi nghiệp vụ, version, event/notification và lưu kết quả.
Quy ước khóa cần tất cả owner chốt: khóa request-id riêng trước; rồi
`orders` theo UUID → `return_requests` theo UUID nếu có → `delivery_tasks`
theo UUID → `cod_collections` → `product_variants` theo UUID → các item theo
UUID. Role/profile liên quan được đọc/khóa ổn định để cạnh tranh đổi role;
không API nào được đảo thứ tự này. Khi chưa có task/COD, khóa order làm điểm
tuần tự hóa và unique constraint làm bảo vệ cuối. Không giữ khóa qua network,
Storage upload hay chuyển tiền ngoài ứng dụng. Hủy của Bảo và nhận hàng của
Minh Đức phải dùng cùng khóa order/task; phân công và thực nhận cũng vậy.

Kho idempotency đề xuất (chưa có bảng) khóa duy nhất `(actor_id, request_id)`;
lưu operation, target, hash payload chuẩn hóa (gồm version), response an toàn
và giờ commit. Cùng ID khác operation/target/payload → `IDEMPOTENCY_CONFLICT`.
Hai request cùng ID phải đợi transaction đầu: commit thì replay, rollback
thì được thực hiện lại; không để bản ghi success nếu nghiệp vụ rollback.
Kiểm tra session/role/quyền đọc hiện tại trước replay; người mất phân công
không nhận lại snapshot riêng tư từ response cũ. Không dùng event UUID toàn
cục làm thay thế cho kiểm tra payload. Thời hạn lưu/xóa cần owner duyệt;
chưa có chính sách thì không xóa khóa của nghiệp vụ đã commit để tránh chạy lại.

Timeout/mất response: giữ ID/payload, gọi lại; không tạo ID mới để “thử lại”.
Mạng lỗi không hiện thành công. Xung đột version/state: tải lại dữ liệu,
không tự replay như hành động mới. Request ID mới vẫn phải qua precondition,
unique và kiểm tra đã dispatch/đã thu/đã nhận; không nhân đôi side effect.
Mỗi write dưới thừa hưởng lỗi auth/argument/not-found/version/idempotency,
transaction L và quy tắc retry này; cột lỗi chỉ bổ sung lỗi đặc thù.

### Danh mục write RPC đề xuất

Ràng buộc bổ sung bắt buộc cho các hàng tạo/phân công bên dưới: create pickup
chuyển R từ `pending_review` sang `awaiting_return_pickup`, create redelivery
chuyển R từ `under_inspection` sang `awaiting_redelivery`, cùng transaction
với quyết định owner. Assign outbound chuyển O từ `preparing` (lần đầu) hoặc
trạng thái retry được duyệt sang `awaiting_pickup`; reassignment giữ O.
Nếu chỉ là routine nội bộ thì không expose EXECUTE cho client: wrapper của
Bảo/Sơn phải bao trọn các chuyển aggregate này trong transaction L.

`?` là nullable; `items` là mảng `{return_item_id:uuid,quantity:bigint}` không
trùng ID, kiểm tra thuộc request. Không nhận arbitrary JSON để sửa cột.
Mọi dòng đều **pending approval** của owner ghi ở cột cuối; mã D theo P00.1.

| RPC đề xuất / input ngoài tham số chung | Caller; precondition server | Output; transaction L và side effect | Lỗi thêm; owner/dependency |
| --- | --- | --- | --- |
| `create_delivery_task(order_id:uuid,kind:delivery_task_kind,return_request_id:uuid?)` | Manager; O1a/P1a/R1a; outbound đã chuẩn bị, count<2; pickup đã duyệt lấy; redelivery có kết luận kiểm tra; không active/custody chưa giải quyết; cùng order/request | `TaskResult`; khóa order/request, tạo pending; snapshot lấy từ server; số outbound=count+1, loại khác=1; amount outbound=tổng đơn, loại khác=0; không tăng count | STATE_CONFLICT, ATTEMPT_LIMIT, CUSTODY_UNRESOLVED; Bảo/Sơn + Minh Đức D1/D3/D8/D9; snapshot S1 |
| `assign_delivery_task(task_id:uuid,shipper_id:uuid)` | Manager; pending hoặc assigned chưa accepted/started/custody; shipper role hợp lệ; O1b/P1b/R1b/O2 | `TaskResult`; khóa task và kiểm tra shipper; ghi assigned_* và lịch sử old/new; không thực nhận/xuất tồn/tăng count; đổi người thu hồi quyền cũ | STATE_CONFLICT, CUSTODY_UNRESOLVED; Bảo/Sơn D1–D3, S2 |
| `accept_delivery_task(task_id:uuid)` | Shipper hiện tại; assigned; chỉ outbound/redelivery; O3/R2; có đủ hàng và custody hợp lệ, chưa hủy | `TaskResult`; accepted_at, custody; outbound đầu dispatch một lần qua inventory **trong transaction**, redelivery không dispatch đơn lần nữa | ITEMS_MISMATCH, CUSTODY_UNRESOLVED, DEPENDENCY_NOT_READY; Văn Đức/Bảo/Sơn D1/D3/D4, S2 |
| `start_delivery_task(task_id:uuid)` | Shipper hiện tại; accepted và có custody; O4/P3/R3; outbound số dự kiến=count+1≤2 | `TaskResult`; started_at/in_transit; chỉ outbound tăng count và O=delivering; không INSERT attempt; pickup giữ returning_to_store | ATTEMPT_LIMIT, CUSTODY_UNRESOLVED; D1/D3/D8, S2 |
| `complete_outbound_delivery(task_id:uuid,received_all_items:boolean,collected_amount_vnd:bigint)` | Shipper hiện tại; outbound in_transit; nhận toàn bộ=true; task amount=order total=COD expected=tiền khai nhận; COD chưa thu | `TaskResult`; khóa COD cùng order/task; delivered, attempt success, collected/by/at và event/notification nguyên tử; không ghi tiền một phần | ITEMS_MISMATCH, AMOUNT_MISMATCH; Bảo/Văn Đức + Minh Đức D4/D7; S3 |
| `fail_delivery_task(task_id:uuid,reason:text)` | Shipper hiện tại; outbound/redelivery đang in_transit; pickup assigned chưa nhận; lý do không rỗng; không kết quả trái ngược | `TaskResult`; outbound attempt failed, count=1 chờ manager, =2 chờ về; pickup failed/chờ lấy lại; redelivery pending mapping D9; lifecycle theo P00.1; không thu COD/restock | STATE_CONFLICT, CUSTODY_UNRESOLVED; Bảo/Sơn D6/D8/D9. D9 chưa duyệt thì nhánh redelivery bị chặn, không tự chọn enum |
| `decide_outbound_retry(order_id:uuid,decision:text)` | Manager; decision=`retry` hoặc `return_to_store`; lần 1 failed; không task active khác/custody chưa xử lý | `OrderResult`; retry tạo task pending số 2 theo O7; return đổi O sang awaiting_store_return theo O8; không reset count/dispatch; không gộp phân công | ATTEMPT_LIMIT, CUSTODY_UNRESOLVED; Bảo D1/D3/D5; retry chỉ mở sau hợp đồng custody |
| `report_delivery_incident(task_id:uuid,kind:delivery_incident_kind,reason:text)` | Shipper hiện tại; chưa cancelled/delivered/returned_to_store; lý do hợp lệ; thời điểm sau nhận phải đúng custody | `TaskResult`; ghi business_events subject delivery_task, actor/task/request/kind; giữ trạng thái trừ mapping D6 được duyệt; không giả result khách từ chối | STATE_CONFLICT; Bảo/Sơn D6/D7; event kind hiện có, policy sự cố hiện có; không tự bồi thường |
| `report_store_handover(task_id:uuid,items:receipt_items)` | Shipper hiện tại đang giữ hàng; O10/P5/R6a; đủ điều kiện bàn giao, số lượng khớp custody | `TaskResult`; report event/custody report S2, trạng thái không đổi; không receipt, inspection hay restock; không tác động COD | ITEMS_MISMATCH, CUSTODY_UNRESOLVED; Bảo/Sơn D2/D5/D8/D9; với outbound cần item schema riêng S2, không dùng return_item_id |
| `collect_return_items(task_id:uuid,items:items)` | Shipper hiện tại; return_pickup assigned; R awaiting_return_pickup; mọi item thuộc request, 0≤thực nhận≤cần lấy; thiếu/sai món chưa có quyết định thì từ chối | `TaskResult`; quantity_collected, accepted_at/custody, R returning_to_store; start là request riêng; không kết luận sellable/damaged | ITEMS_MISMATCH, CUSTODY_UNRESOLVED; Sơn + Minh Đức D8, S2; hàng ngoài kế hoạch cần Sơn cập nhật trước |
| `complete_redelivery(task_id:uuid,received_all_items:boolean)` | Shipper hiện tại; redelivery in_transit; đủ hàng=true, R awaiting_redelivery | `TaskResult`; T delivered, R rejected_after_inspection/closed_at cùng transaction; không thu tiền hoặc ghi attempt | ITEMS_MISMATCH; Sơn D9, S2 |
| `receive_failed_delivery_return(task_id:uuid,items:receipt_items)` | Manager MH09; outbound failed/O awaiting_store_return; thực tế nhận hàng và đối chiếu custody, không chỉ dựa report | `ReceiptResult`; O11a T returned_to_store, O chưa kết thúc; ghi receipt một lần, không nhập tồn; inspection tách riêng | ITEMS_MISMATCH, CUSTODY_UNRESOLVED; Bảo sở hữu wrapper, Minh Đức hợp đồng task, D2/D5/S2 |
| `receive_customer_return(task_id:uuid,items:receipt_items)` | Manager MH15; pickup in_transit hoặc redelivery manager_action_required theo D9; có hàng thực tế | `ReceiptResult`; P6 T returned_to_store/R under_inspection hoặc R6b R giữ chờ manager; không restock/hoàn tiền | ITEMS_MISMATCH, CUSTODY_UNRESOLVED; Sơn wrapper + Minh Đức D2/D8/D9/S2 |
| `inspect_failed_delivery_return(order_id:uuid,items:inspection_items,reason:text)` | Manager MH09; receipt đã có, chưa inspection; đối chiếu quantity received; lượng đạt/hỏng/mất hợp lệ | `OrderResult`; O11b, inventory ledger + lượng đạt restock một lần, O undeliverable_returned; không thay COD | ITEMS_MISMATCH, DEPENDENCY_NOT_READY; Bảo + Văn Đức D4/D5; không tạo API inspection returns song song của Sơn |
| `cancel_delivery_task(task_id:uuid,reason:text)` | Manager; chỉ pending/assigned chưa custody/start và order/return cho phép hủy theo owner | `TaskResult`; T cancelled/cancel_reason/completed_at; không ghi attempt; O/return không tự đoán, wrapper owner xác định trong cùng transaction | STATE_CONFLICT, CUSTODY_UNRESOLVED; Bảo/Sơn D1/D8/D9; chưa chốt return cancellation thì chặn |
| `confirm_cod_received(order_id:uuid,received_amount_vnd:bigint)` | Chỉ manager; COD collected, số thực nhận=expected=collected, chưa received; không bù trừ refund | `CodResult`; khóa order/COD; received/by/at và received_amount đủ, event/notification một lần; không cần quyền task của shipper | AMOUNT_MISMATCH, STATE_CONFLICT; Minh Đức + Bảo D7/S3; handed_over_at chờ quyết định S3 |

`receipt_items` đề xuất: `{item_ref:uuid,received_quantity:bigint}`;
`inspection_items`: `{item_ref:uuid,sellable_quantity:bigint,damaged_quantity:bigint,
lost_quantity:bigint}`. Tham chiếu outbound là order_item, pickup/redelivery
là item snapshot của request. Để tránh input đa nghĩa, `report_store_handover`
dùng chính `receipt_items` theo kind;
server kiểm tra ref thuộc task. Schema chưa lưu received/lost/custody theo
item đầy đủ; S2 chặn triển khai các nhánh thiếu, không nhận ref tùy ý.

Riêng collect_return_items: mảng bắt buộc không rỗng và có ít nhất một quantity
dương. Khi chưa duyệt partial pickup D8, yêu cầu đủ toàn bộ item/số lượng theo
kế hoạch; payload rỗng/toàn 0/partial hoặc thiếu item trả ITEMS_MISMATCH và
rollback, không ghi accepted/custody. Số 0 ở một dòng không phải bằng chứng
đã thực nhận hàng đó.

### Projection an toàn và read RPC đề xuất

`TaskSnapshot` đề xuất: task_id/order_id/return_request_id?, order_display_ref
(tạm dùng UUID, DB chưa có mã đơn đẹp), kind/status/attempt_number,
amount_to_collect_vnd, destination_name/phone/address/latitude/longitude,
assigned_at/accepted_at/started_at/completed_at, failure_reason/cancel_reason,
version và `allowed_actions` server tính theo state/quyền. Không nhận
allowed_actions từ client; khi ghi vẫn kiểm tra lại. Note giao hàng chưa có
cột trong orders/task: trả null và ghi dependency S1, không bịa snapshot.

`TaskItemSnapshot`: ref, product_name/variant_label/attributes/quantity từ
order_items cho outbound; actual_item_name/quantity_to_collect/quantity_collected
từ return_items cho pickup; redelivery cần danh sách hàng thực tế trả lại
đã được Sơn xác nhận S1/S2, không dùng nguyên đơn để đoán. `variant_id` và
`order_item_id` nullable cho hàng giao sai. Chỉ outbound cần unit_price_vnd/
line_total_vnd; không trả sellable/damaged hoặc dữ liệu kiểm tra cho shipper.
Ảnh không có snapshot path trong order_items; không join catalog bằng quyền
rộng hơn để tải ảnh. Cho null/placeholder cho đến khi có projection/quyền S1.
Không DTO nào chứa customer UUID, bank details, video, inspection/refund evidence,
refund amount hoặc nguyên row `return_requests`/`orders` cho shipper.

| RPC read đề xuất / input | Caller và kiểm tra server | Output / nhất quán / lỗi / schema cần |
| --- | --- | --- |
| `list_my_delivery_tasks(kind:delivery_task_kind?,statuses:delivery_task_status[]?,query:text?,limit:int=20,cursor:text?)` | Shipper; auth.uid là scope, chỉ tập vận hành theo quy tắc bổ sung; không nhận shipper_id; kind/status hợp lệ, limit 1..100; query theo UUID đơn/tên snapshot được phép | `{items:TaskSnapshot[],next_cursor?,filtered_total,counts_by_kind_status,as_of}`; filter/search/count trên toàn tập có quyền trước limit; sort `(created_at,id)` giảm dần, cursor chứa tuple và hash filter; một snapshot SQL cho data/count. INVALID_ARGUMENT nếu cursor khác filter; S1/S4 |
| `get_my_delivery_task(task_id:uuid)` | Shipper hiện tại; chỉ tập vận hành theo quy tắc read bổ sung; không suy quyền từ order_id hay notification; terminal chuyển history | `{task:TaskSnapshot,items:TaskItemSnapshot[]}` trong cùng snapshot; NOT_FOUND_OR_FORBIDDEN; không khóa ghi, kết quả là thời điểm đọc; S1 |
| `list_my_delivery_history(limit:int=20,cursor:text?)` | Shipper; **chỉ khi S4 được duyệt**: snapshot bất biến gắn user từng thực hiện; không join task mới/phân công mới | `{items:HistorySnapshot[],next_cursor?}`; history chỉ task_id/kind/status/result/attempt_number/completed_at, không PII/địa chỉ/contact/item/chi tiết mới; không có thì DEPENDENCY_NOT_READY, không nới tasks_read |
| `get_my_delivery_history(task_id:uuid)` | Shipper; quyền snapshot lịch sử cá nhân S4, không là quyền đọc task live | `HistorySnapshot`; NOT_FOUND_OR_FORBIDDEN hoặc DEPENDENCY_NOT_READY; không action/map; S4 |
| `list_cod_collections(shipper_id:uuid?,order_id:uuid?,statuses:cod_status[]?,limit:int=20,cursor:text?)` | Shipper buộc shipper_id=auth.uid, manager được filter; customer không dùng endpoint này; limit 1..100 | `{items:CodSnapshot[],next_cursor?,filtered_total,outstanding_vnd,as_of}`; CodSnapshot = các ID/status/expected,collected,received amounts và by/at an toàn; sort `(created_at,order_id)` giảm dần; tổng outstanding toàn scope shipper/filter order, chỉ collected chưa received, độc lập tab status/pagination; counts/filter cùng snapshot; INVALID_ARGUMENT/FORBIDDEN; S3 |

Read không cần request_id, không side effect; retry là đọc mới có thể khác
kết quả, không giả snapshot transaction cũ. Cursor là opaque, không mang PII;
không bảo đảm cố định dữ liệu xuyên trang khi có cập nhật, refresh từ trang
đầu để đồng bộ. Auth/not-found/argument áp dụng cho mọi read. COD không có
PK riêng: dùng `order_id` UUID cho chi tiết/action; chưa cần RPC get COD riêng.

**Quyền lịch sử hiện có khác quyền đề xuất**: `tasks_read` chỉ kiểm tra
assigned_shipper_id, không lọc status; task kết thúc vẫn đọc nếu assignment
chưa đổi. Đổi người mất quyền task; chưa có assignment history snapshot để
người cũ đọc. `order_items_read` có thể đọc mọi dòng của order khi có một task
được phân công; `return_items_read` tương tự theo request; đây không phải
projection tối thiểu theo kind. P00.2 không thay policy. Không hứa rằng DTO
giới hạn cột tự nó thu hẹp Data API trực tiếp; trước triển khai phải review
grants/projection với owner bằng migration quyền tối thiểu, không mở rộng
RLS orders/return_requests để join. COD theo người giữ khoản, độc lập đổi
task; user đổi session phải hủy subscription/invalidate mọi cache user-scoped.

### Notification/event đề xuất — chờ Bảo duyệt D7

Quy tắc quyền read đề xuất bổ sung cho bảng read ở trên: tập vận hành là
`pending_assignment`, `assigned`, `accepted`, `in_transit`, `failed`,
`manager_action_required`; `failed` chỉ còn thao tác bàn giao khi custody
chưa giải quyết, không là lần giao mới. `delivered`, `cancelled`,
`returned_to_store` là terminal và không trả TaskSnapshot qua list/get live,
chỉ HistorySnapshot theo S4; get live trả STATE_CONFLICT và không kèm PII.
Baseline vẫn cho đọc terminal nếu còn assignment là **hiện trạng cần thu hẹp**,
không phải quyền đã duyệt cho API mới. Trên task vận hành, contact/destination
chỉ trả ở `assigned/accepted/in_transit` khi cần thực hiện nhiệm vụ; các trạng
thái còn lại trả null các trường PII, giữ ID/state và allowed_actions cần thiết.
MH18 cũng chỉ mở ở ba trạng thái đó; kiểm tra lại server, không chỉ guard UI.
S4 phải chốt hạn lưu snapshot/quyền trực tiếp trước tích hợp, không chỉ lọc DTO.

S2 còn phải giải quyết xung đột schema: hiện business_events.request_id unique
toàn cục, khác khóa ledger `(actor_id,request_id)`. Đề xuất thêm FK
`operation_request_id` trỏ ID ledger do server sinh, một operation có nhiều
event ID riêng; không ghi cùng client request UUID vào mọi event. Constraint
request_id hiện tại cần migration đổi/bỏ hoặc đổi nghĩa sang event token duy
nhất do server sinh (incident CHECK vẫn được giữ tương đương). Chưa chọn
phương án thì chưa triển khai; không bắt lỗi 23505 rồi báo thành công.

S3 cần chốt thêm dữ liệu COD customer: policy hiện tại cho đọc nguyên dòng
theo order của mình dù read RPC trên chỉ cho shipper/manager. Đề xuất customer
chỉ cần expected/status thu tiền của đơn, không UUID nhân viên/mốc đối soát;
phải review projection và thu hẹp direct-table grants/policy tương ứng trong
migration sau. Không coi việc từ chối customer tại RPC là đã bảo vệ Data API.

### Ma trận kiểm chứng contract cho phase triển khai (chưa chạy)

| Nhóm contract | Ca bắt buộc trước nghiệm thu |
| --- | --- |
| Mọi read/write | Anon, customer, manager, shipper đúng/sai assignment; role bị đổi; UUID khác owner, không tồn tại/sai định dạng; hết phiên; không lộ existence/PII trong lỗi |
| Mọi write L | Cùng key/payload trả cùng kết quả; khác payload/operation/target bị chặn; hai actor cùng client UUID độc lập qua operation FK; nhiều event một operation; timeout trước/sau commit; rollback không còn side effect/success ledger |
| Version/concurrency | Version cũ; cancel ↔ accept, assign ↔ accept, start ↔ start, success ↔ fail, retry ↔ return sớm, receipt/inspection/confirm COD đồng thời; chỉ một kết quả hợp lệ và không deadlock do đảo khóa |
| Outbound/inventory | Count tăng tại start một lần; kết quả chỉ ghi một attempt; đổi task/người không reset; chặn lần 3; dispatch/restock một lần và lỗi giữa transaction rollback |
| Pickup/redelivery | Mảng rỗng/toàn 0/partial/ID trùng hoặc ngoài request; report khác receipt; receipt khác inspection; redelivery miễn phí và thất bại không đóng request |
| Read/history/routes | Terminal không PII/map; người cũ chỉ history tối thiểu, không task mới; notification cũ bị chặn; counts/search/paging toàn tập quyền; cursor sai filter; logout không lộ cache |
| COD/privacy | Thiếu tiền/bù refund bị chặn; shipper không confirm; COD còn nguyên khi trả hàng; direct Data API/Storage không vượt projection đã duyệt, gồm nhánh customer; bank/video/evidence không lộ qua DTO/notification/log |

### Danh mục event đề xuất

Mỗi write tạo business event có actor/subject/from/to/giờ server; thao tác
không đổi state vẫn ghi event, không giả incident. Tên event sau cần field
event_type/payload mới S2 hoặc mapping được duyệt, **chưa là enum DB**.
Notification tạo cùng transaction, unique `(recipient_id,event_id)` chống lặp;
recipient role lấy từ server. Không push notification.

| Event đề xuất / trigger RPC | Recipient đề xuất | Đối tượng mở theo quyền |
| --- | --- | --- |
| task_assigned / assign | Shipper mới; người cũ chỉ thông báo thu hồi không có PII | task → MH11; người cũ mở lại bị từ chối nếu mất quyền |
| task_started / start | Customer của order, manager xử lý | order MH07 / MH09 hoặc return MH14/MH15; không trỏ customer tới MH11 |
| outbound_delivered / complete_outbound | Customer, manager | order; COD thu cùng event, không notification thu tiền trùng |
| outbound_failed / fail outbound | Manager, customer | order; nêu cần manager quyết định, không hứa giao lại tự động |
| return_pickup_collected / collect | Customer, manager | return |
| return_pickup_failed / fail pickup | Manager, customer | return, chưa kết thúc request |
| store_handover_reported / report_store_handover | Manager | order hoặc return; nhãn “shipper báo”, không “cửa hàng đã nhận” |
| store_items_received / receive_* | Shipper hiện tại, customer nếu Sơn/Bảo duyệt | task với shipper; order/return với customer |
| delivery_incident_reported / incident | Manager | task/đối tượng quản lý, không chia sẻ lý do nhạy cảm tự do cho customer |
| redelivery_completed hoặc redelivery_failed / complete hoặc fail | Customer, manager | return; thất bại còn mở |
| cod_received / confirm_cod_received | Shipper của COD | /cod?orderId=UUID; chưa cần gửi customer thông tin nộp tiền nội bộ |
| outbound_retry_decided, task_cancelled, failed_return_inspected / decide, cancel, inspect | Shipper liên quan và customer theo owner phê duyệt | Chọn task cho shipper, order cho customer; không gửi trạng thái inspection riêng tư |

Mỗi event cần recipient set được duyệt; không seed manager ID giả. Notification
chỉ chứa ID đối tượng và thông điệp tối thiểu, không địa chỉ/bank/video hoặc
snapshot nhiệm vụ; mở link phải đọc lại quyền hiện tại. History quyền riêng
không tự cấp map hoặc task live. S2 phải có chiến lược một event nhiều recipient
khác target (notifications có subject_type/id riêng, không ép mọi role cùng URL).

### Bàn giao và điểm chưa được duyệt

| Owner | Contract bàn giao / phụ thuộc chưa có | Điều kiện mở tích hợp |
| --- | --- | --- |
| Dung An — auth/router | Session + profiles.role server; guard role và UUID routes ở screen_mapping; shared supabaseClientProvider/theme; không dùng user_metadata.role | Chốt role refresh, lỗi hết phiên, logout/account switch cleanup; deep link chờ role tải, không render PII trước quyền. Router mới chỉ `/`; không nói route đề xuất đã có |
| Bảo — MH09/orders/notifications | create/assign/decide/receive_failed/inspect wrappers; hủy tranh chấp accept; event/recipient D7; O1/O11 mapping D1/D5 | Cùng transaction server, cùng thứ tự khóa L; không gọi lần lượt hai RPC Flutter để ghép orders + task. Xác nhận custody lần 2 D3 và snapshot order S1 |
| Văn Đức — inventory/maps | Inventory primitive nội bộ nhận order/items/event/actor đã xác thực, trả ledger IDs và quantity sau cập nhật; không public RPC để shipper tự sửa tồn. Map interface đề xuất `SavedDestination(latitude,longitude,address,label,phone?)`, `openDirections(destination)` trả opened/unavailable/error | Chốt dispatch một lần tại accept, không dispatch lại lần 2; inspection restock lượng đạt; provider/license/key/nền tảng còn mở; map mở thất bại phải trả lỗi thật. MH16 chọn điểm riêng và validation Hà Nội ở server |
| Sơn — MH15/returns | Duyệt lấy/kiểm tra/refund do returns sở hữu; gọi hợp đồng task nội bộ trong transaction; actual item plan, receipt và redelivery D8/D9 | Chốt thiếu/sai hàng, pickup retry/cancel/custody, redelivery_failed vs manager_action_required và danh sách giao lại S1/S2; không coi duyệt thu hồi là duyệt hoàn tiền |

**MH18 tập trung điểm đến đã lưu của task** theo yêu cầu P00.2, không bắt
buộc pin cửa hàng. Lấy destination_* từ get_my_delivery_task với taskId,
không yêu cầu quyền GPS nền, không sửa địa chỉ từ MH18, không dùng store_settings
giả làm điểm khách. Với pickup đang về cửa hàng, task snapshot vẫn là điểm
khách nếu đó là snapshot đã chốt; không tự đổi nghĩa destination thành điểm
cửa hàng theo status. Nếu cần hai đầu hành trình phải chốt schema riêng S1.

Các dependency S1 (snapshot), S2 (custody/event/receipt/idempotency), S3 (COD),
S4 (history/version/quyền) mô tả trong database.md đều **chưa triển khai**.
Chưa có xác nhận owner, báo cáo gốc v3.0 và file đính kèm còn thiếu như P00.1.
P00.2 bàn giao đặc tả để review; tích hợp live bị chặn, không tạo fixture
hay interface runtime khi phase chỉ yêu cầu tài liệu.

Tham khảo kỹ thuật đã kiểm tra khi viết đặc tả: [Supabase Database Functions](https://supabase.com/docs/guides/database/functions).
Ưu tiên invoker; baseline không cho client ghi nghiệp vụ nên phải thiết kế
server execution riêng. Nếu thật sự cần definer, phase triển khai phải giải
trình phạm vi, kiểm tra identity/role/object, search_path cố định và EXECUTE
tối thiểu; không thêm definer chỉ để bỏ qua lỗi RLS. Tài liệu này không cấp
quyền EXECUTE hoặc thay bất kỳ grant/policy nào.
