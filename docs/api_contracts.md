# Hợp đồng truy cập database

## MH16 — Đặt hàng COD (27/10/2026)

Phiên bản triển khai phía Văn Đức dùng chữ ký CIN-02 đã được đề xuất, không
thay các API giao hàng/COD. Không mặc định nhánh Orders của Bảo đã tích hợp
wrapper này. Nền Order/OrderItem và hai base DTO được lấy từ Orders để dùng
chung; không tạo model đơn hàng trong checkout.

```text
place_order(p_request_id uuid, p_items jsonb, p_recipient_name text,
  p_recipient_phone text, p_address_detail text,
  p_latitude numeric, p_longitude numeric) -> jsonb
p_items = [{variant_id: UUID, quantity: positive integer}, ...]

get_placement_result(p_request_id uuid) -> jsonb
```

Envelope thành công `{ok:true,data:{order,items,event_id,replayed},error:null}`;
`order` là 21 field của Orders, mỗi item là 11 field snapshot của OrderItem.
Lookup thêm `state:committed|not_found`; not_found bắt buộc order/event_id null,
items rỗng, replayed false. Lookup trả trạng thái đơn hiện hành; snapshot món
hàng và mã sự kiện giữ nguyên. Client đối chiếu customer, request và chính xác
tập variant/số lượng trước khi coi biên nhận là thành công.

Envelope lỗi `{ok:false,data:null,error:{code}}`, gồm `invalid_argument`,
`insufficient_stock`, `outside_service_area`, `idempotency_conflict`,
`forbidden_or_unavailable`, `external_dependency_unavailable`. Lỗi transport
không được coi là rollback; giữ yêu cầu chờ và thử cùng mã. Xung đột payload
cũng không chứng minh request ID chưa có đơn.

Khách hàng hiện tại do server xác thực qua profiles. Không nhận customer ID,
giá, phí, tổng tiền, trạng thái, event ID hoặc danh sách manager từ client.
Khóa yêu cầu theo customer/request, khóa tồn theo UUID; toàn bộ đơn, snapshot,
reserve ledger, event và notification cùng transaction. Các metadata/fingerprint
và tập manager nhận thông báo được lưu riêng trong `private.checkout_placements`.
Không cấp client quyền ghi hoặc đọc bảng này. Generic event không sử dụng
`business_events.request_id` dành cho incident.

Vùng giao lấy từ `store_settings.approved_service_area_geojson`, kiểm tra Polygon/
MultiPolygon trên server và từ chối khi cấu hình hỏng/thiếu. Phí 30.000 VND,
COD, snapshot giá server, không trừ `on_hand` khi đặt. Không xóa giỏ tự động.
Xem [bàn giao và cách chạy](van_duc_completion.md) để phân biệt fixture và cloud.

## MH06 — CartRepository và thao tác giỏ (24/10/2026)

`features/cart` sở hữu `CartItem`, `CartFailure`, `CartRepository` và
`CartViewModel`. CartItem tham chiếu Product/ProductVariant của catalog; không
tạo bản sao model sản phẩm hoặc Order. Dùng client và session epoch hiện có
qua OperationalReadAccess; mọi thao tác kiểm tra role customer từ profiles và
RLS ở server. Không thêm RPC, migration hoặc dependency trong mốc MH06.

- `getItems()` đọc toàn bộ giỏ của current user qua cursor variant UUID; quan
  hệ catalog LEFT giữ dòng bị RLS ẩn biến thể/sản phẩm. Dòng đó không có giá
  khả dụng và không đủ điều kiện checkout; không giả lập tên/giá đã mất.
- `setQuantity(variantId,quantity)` đặt số lượng tuyệt đối dương, kiểm tra
  catalog/tồn đọc hiện tại. UPDATE chỉ cột quantity; nếu chưa có dòng thì INSERT
  customer_id/variant_id/quantity. Trùng khóa do thiết bị khác chèn thì lặp lại
  cùng target. Không dùng upsert đòi UPDATE key ngoài column grants.
- `removeItem(variantId)` DELETE đúng owner/key; dòng đã mất là kết quả hợp lệ
  của thao tác xóa lặp. Không xóa dòng của khách khác.
- `CartViewModel.addItem` đọc lượng hiện tại rồi cố định target = lượng cũ +
  lượng chọn. Bấm lặp đang ghi bị chặn. Lỗi chưa rõ kết quả giữ target trong
  phiên; retry ghi lại target cũ, không cộng thêm lần nữa. Refresh không bỏ
  thao tác chưa xác định, kể cả token làm mới cho cùng customer. Đổi tài khoản/
  đăng xuất xóa snapshot và intent hiển thị cũ; bỏ response đến muộn.
- Chỉ công bố thành công sau ghi được xác nhận và đọc lại giỏ. Lỗi thiếu tồn/
  hàng ngừng bán cho phép khách chỉnh giỏ. Tạm tính chỉ cộng dòng còn đọc được
  giá và ghi rõ cảnh báo nếu có dòng thiếu; giá/tồn cần kiểm tra lại khi đặt.

Cập nhật P2 ngày 29/10/2026: lock theo customer tồn tại tới khi request thật
kết thúc, độc lập với lần build/epoch. Quay A → B → A khi lệnh A chưa kết thúc
chỉ khôi phục command đang chạy của A; B không nhận dữ liệu hoặc intent của A.
Sau khi lệnh cũ kết thúc ở epoch khác, không báo thành công bằng response cũ;
giữ target để người dùng xác minh/thử lại tường minh. Lỗi phiên/quyền sau ghi
không chứng minh rollback nên không tự bỏ target. Nếu đọc giỏ sau token refresh
lỗi mạng/backend, snapshot đã biết của cùng user được đánh dấu chưa xác minh;
checkout và thao tác ghi mới vẫn bị khóa. Lỗi quyền/dữ liệu không dùng fallback.

Giỏ không giữ tồn. Các ghi tuyệt đối là last-writer-wins khi nhiều thiết bị sửa
cùng dòng; chưa có hợp đồng merge cộng dồn giữa thiết bị hoặc recovery request
giỏ qua app restart. MH16 và transaction đặt đơn vẫn là phần tích hợp tiếp theo;
không báo đặt đơn thành công từ giỏ. Các test transport dùng fixture, không
thay thế bằng chứng CRUD/Storage/Auth trên cloud.

## Catalog MH04/MH05 và bàn giao checkout của Văn Đức

Ngày 24/10/2026: [hợp đồng catalog/checkout/inventory](van_duc_catalog_checkout_contract.md)
ghi rõ repository đọc catalog đã triển khai, route customer, private images và
quy tắc phiên. Các chữ ký `place_order`, lookup và primitive tồn kho trong tài
liệu này mới là thiết kế phía Văn Đức bám CIN-02/CIN-04 của nhánh Bảo; chưa có
RPC tương ứng và chưa xác nhận đồng thuận hai phía. Không thay thế các hợp đồng
delivery/COD đã ghi bên dưới. [Hướng dẫn Supabase](supabase_catalog_guide.md)
giúp chạy catalog bằng tài khoản thật.

Lưu ý phiên bản: baseline và P00.2 dưới đây ghi hiện trạng trước P01.1.
Lớp đọc task mới và các quyền bị thu hẹp được mô tả tại mục P01.1 cuối file;
không dùng nhánh shipper của baseline làm quyền truy cập hiện hành sau migration đó.

P02.1 cuối file ghi contract list query đã triển khai trong repository;
chữ ký list ở mục P00.2 là đề xuất lịch sử, không là chữ ký để client gọi.

P03.1 cuối file ghi contract detail get_my_delivery_task; chữ ký get ở mục
P00.2 là đề xuất lịch sử. API ghi/allowed_actions/version chưa được triển
khai chỉ vì có read endpoint.

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

## P01.1 — Read projection đã có trong migration repository

Migration `20261023104903_secure_delivery_read_projections.sql` bổ sung **hai
RPC đọc bên dưới**. Đây là code trong repo; trạng thái áp dụng/test local được
ghi trong database.md, không đồng nghĩa đã deploy cloud. Các write RPC và
list/get/filter/cursor/version đầy đủ ở P00.2 vẫn là đề xuất, chưa triển khai.

| RPC trong migration | Input / caller | Output / phạm vi |
| --- | --- | --- |
| `read_my_delivery_tasks` | `p_task_id uuid DEFAULT NULL`; authenticated có profiles.role=shipper; NULL liệt kê trong scope hiện tại, UUID lọc đúng task | SETOF row: task_id/kind/status/attempt_number/snapshot_scope/completed_at/item_source; chỉ scope current có order_id/return_request_id/amount_to_collect_vnd/destination_* và assigned_at/accepted_at/started_at. Không có failure_reason/cancel_reason/customer_id/ghi chú/ảnh/allowed_actions/version. Sort created_at,id giảm dần; chưa có pagination/count/search contract P00.2. |
| `read_my_delivery_task_items` | `p_task_id uuid` bắt buộc; cùng caller; NULL trả 0 dòng | SETOF row: item_id/item_source/product_name/variant_label/attributes/quantity/quantity_collected/unit_price_vnd/line_total_vnd. Outbound từ order_items của đúng task; pickup từ return_items của đúng request trên task; redelivery trả 0 dòng với dependency minh bạch ở task.item_source. Sort item_id tăng dần. |

Quy tắc scope và hành vi deep link:

- `current`: assigned/accepted/in_transit, task.assigned_shipper_id đúng session.
  Chỉ đây mới có contact/địa chỉ/tọa độ và item. Pickup chỉ trả tên hàng thực
  tế, lượng cần lấy/đã lấy; không trả kết luận chất lượng, bank/video/evidence.
- `history`: delivered/cancelled/returned_to_store; `restricted`: các trạng
  thái còn lại, gồm failed và manager_action_required. Cả hai chỉ có trường
  tối thiểu nêu trên; toàn bộ order/request/amount/contact/tọa độ và mốc nhận/
  start đều NULL, item_source=`unavailable`, item RPC trả 0 dòng.
- Task cũ vẫn gán A có thể trả row history tối thiểu cho A khi task mới cùng
  order/request gán B. Row cũ không cấp quyền tới bất kỳ task/item mới nào.
  Đổi chính task từ A sang B hoặc bỏ phân công thu hồi toàn bộ row của A ngay
  ở lần đọc tiếp theo; không có bảng lịch sử assignment bất biến/backfill.
- ID không tồn tại/không thuộc quyền: 0 dòng cho cả hai RPC, không phân biệt
  để dò ID. Customer/manager qua RPC này cũng 0 dòng, vẫn giữ quyền bảng gốc
  của họ; anon bị chặn EXECUTE (`42501`). UUID sai định dạng lỗi cast `22P02`.
  Không ghi dữ liệu, không cần request_id; retry là đọc snapshot mới.

Không cho shipper SELECT trực tiếp task/order_items/return_items/attempts/
business_events nữa. Orders/return_requests/Storage riêng tư không được mở
quyền. COD giữ nguyên policy, không nằm trong thay đổi này. Các hàm definer
chạy dưới role chuyên biệt NOLOGIN/NOINHERIT/NOBYPASSRLS chỉ có column SELECT
và policy theo auth.uid + profiles.role; không chạy với quyền bỏ qua RLS của
postgres. API roles không là member của role đọc. `search_path=''`, SQL cố
định/schema-qualified, EXECUTE chỉ authenticated; không có dynamic SQL/input
role/shipper_id. Vì table RLS không thể che cột theo status, definer được dùng
chỉ để đọc các cột đã cấp qua RLS riêng và tạo projection, không cấp broad reads.

`order_snapshot` là snapshot đặt hàng hiện có; `return_plan` vẫn là kế hoạch
return_items hiện có, không phải snapshot assignment bất biến. Không tự tạo
plan redelivery: task current trả item_source=`unavailable_redelivery_plan`;
live item integration với Sơn còn bị chặn. Note/ảnh/custody/version không được
bịa. Số COD đọc nguyên task.amount_to_collect_vnd; đối chiếu tổng đơn và quyền
ghi vẫn thuộc phase transaction sau, chưa được read layer chứng minh.

## P01.2 — Models, repositories và providers đọc

Code Dart trong phase này chỉ đọc; không thêm RPC, migration, policy, UI hay
route. Không có model Order dùng riêng cho shipper; deliveries/COD giữ UUID
tham chiếu và projection của feature sở hữu. Auth/role/router của Dung An
chưa có implementation nghiệp vụ; providers dưới đây dùng client chung và
profiles.role hiện có, không tự tạo hệ thống đăng nhập/điều hướng khác.

| Interface/provider trong repo | Hành vi đã triển khai |
| --- | --- |
| `DeliveryRepository.listTasks()` | Gọi đúng `read_my_delivery_tasks`, order task_id, limit 200 dòng/trang và seek task_id lớn hơn ID cuối trang trước; trả immutable list, kiểm tra duplicate ID; không dùng RPC list/filter/count đề xuất P00.2. |
| `DeliveryRepository.getTask(String taskId)` | Validate UUID, gọi read_my_delivery_tasks(p_task_id); 0 row → staleAssignment (bao gồm ID không có quyền), nhiều row/sai ID → invalidData. Không suy đoán task có tồn tại. |
| `DeliveryRepository.getTaskDetails(String taskId)` | Trả DeliveryTaskDetails gồm task + immutable items và itemsAvailable. Source unavailable/history/restricted không gọi item RPC. Current outbound/pickup gọi read_my_delivery_task_items theo đúng task ID và seek item_id, limit 200; đọc lại task trước publish, thay đổi snapshot/quyền → staleAssignment. Hai RPC vẫn không là một transaction snapshot backend. |
| `CodRepository.listCollections({String? shipperId,String? orderId})` | SupabaseCodRepository đọc projection cột tường minh từ cod_collections, không gọi RPC COD chưa có. Chỉ manager/shipper; shipper luôn filter ID session và cấm filter shipper khác. Manager được filter shipper/order. Sort created_at DESC, order_id DESC, seek theo tuple (created_at,order_id) nhỏ hơn cursor, limit 200 dòng, phát hiện trùng order ID. Không có confirm receipt hoặc tính bù trừ refund. |
| `deliveryRepositoryProvider`, `codRepositoryProvider` | Inject real Supabase repositories qua operationalReadAccessProvider và supabaseClientProvider hiện có. Không chọn demo adapter tự động. |
| `deliveryTasksProvider`, `deliveryTaskDetailsProvider(taskId)` | AsyncValue loading/error/data; empty list là empty thật từ API, không phải fallback khi lỗi. Details masked giữ destination null, không gọi lại orders để bù dữ liệu. |
| `codCollectionsProvider`, `filteredCodCollectionsProvider((shipperId:...,orderId:...))` | AsyncValue riêng theo filter/account epoch. Tổng nợ một khoản qua CodCollection.outstandingAmountVnd chỉ khác 0 khi collected, không cộng uncollected/received. Chưa có màn/tổng tài chính hoặc contract server aggregate. |

Domain models thuần Dart: DeliveryTaskSnapshot/DeliveryDestination/
DeliveryTaskItem/DeliveryTaskDetails và CodCollection; enum có wire value
khớp DB. DTO từ chối enum/scope/source lạ, kiểu sai, PII xuất hiện trong
projection masked, amount/quantity không nguyên hoặc âm, integer vượt
9.007.199.254.740.991 (giới hạn chính xác Flutter web). Nhận integer string
lossless nhưng không nhận double cho VND. Timestamp phải có timezone và ngày/
giờ thực sự hợp lệ, normalize UTC; lifecycle nullable giữ null theo schema,
không bịa thời điểm. Attributes JSON được copy/freeze để tránh sửa snapshot.

`OperationalFailure` là hợp đồng lỗi đọc dùng chung do deliveries sở hữu,
COD tái sử dụng; không phụ thuộc View/ViewModel. Mã gồm sessionExpired,
permissionDenied, staleAssignment, invalidData, network, backendUnavailable,
unexpected; message tiếng Việt cố định, không nhúng raw payload/token/địa chỉ.
Auth/JWT hết hạn map sessionExpired, 42501 map permissionDenied, thiếu RPC
P01.1 map backendUnavailable, ClientException/timeout map network. Không
đổi lỗi API thành list rỗng hoặc thành công demo. Các lỗi khác không đoán
thành “chưa có dữ liệu”.

### Session/account cleanup và retry

`OperationalReadAccess` cùng Riverpod infrastructure nằm trong
`deliveries/data/repositories`; COD chỉ dùng hợp đồng này. Không sửa core
auth của Dung An. Mỗi read kiểm tra session còn hạn, đọc profiles.role theo
user ID từ server, kiểm tra lại user/token/generation sau await và từng
page. Token chỉ dùng so sánh nội bộ, không nằm trong model public/log.
Chuyển A → B → A vẫn làm response A trước đó vô hiệu. SDK replay sự kiện
ban đầu trùng session được bỏ qua để không hủy lượt đọc đầu tiên; các sự
kiện auth tiếp theo tạo epoch mới, kể cả refresh cùng user.

Providers dùng family key chứa object epoch, autoDispose scope cũ và trả
AsyncLoading/AsyncError mới không kèm previous data khi reload/error. Logout,
switch account, lỗi auth stream hoặc expiry timer xóa khả năng đọc dữ liệu
cũ; network error trên auth stream được đưa thành typed error thay vì lỗi
zone chưa xử lý. Dispose hủy listener/timer riêng, không dispose client chung.
Không có subscription Realtime trong phase này. Role không lấy từ metadata
hoặc cache JWT; role bị đổi phía server được kiểm tra lại ở mỗi read, backend
vẫn là nơi enforce quyền hiện thời.

UI/ViewModel tương lai có thể gọi
`ref.read(operationalReadAccessProvider).refreshSession()` để retry/refresh cả
hai feature, tạo epoch mới và đọc lại role. `refreshOperationalReads(Ref)` là
helper tương đương cho code provider. Riverpod automatic retry và SDK retry
trong read adapters được tắt để lỗi quyền/API không bị che bởi retry ngầm;
read timeout mặc định 20 giây. HTTP đang chạy có thể hoàn tất sau timeout/
dispose nhưng kết quả cũ không được publish; chưa có cơ chế hủy network riêng.

Paging keyset client chỉ dùng filter/order/limit trên API hiện có và max_rows=1000 trong config repo; đây
không là cursor/count contract P00.2 hoặc snapshot nhiều trang cố định. Nếu
phân công hoặc item thay đổi giữa trang vẫn cần refresh để có lượt đọc mới; keyset tránh bỏ sót row còn tồn tại chỉ vì trang trước bị xóa/chèn, nhưng không bảo đảm atomic snapshot. Duplicate ID bị từ chối,
không báo một tổng server chưa được chứng minh. Item redelivery vẫn có
itemsAvailable=false, chờ plan của Sơn; note/ảnh/version còn thiếu vẫn không
được tự tạo. Remote cần áp dụng P01.1 trước khi dùng read repositories;
không có xác nhận kết nối Supabase live trong tests transport giả lập.

Tài liệu SDK đã đối chiếu cùng source package được khóa:
[Supabase Flutter auth events](https://supabase.com/docs/reference/dart/auth-onauthstatechange).
Không thêm một Supabase client/theme/router độc lập. `http` 1.6.0 chỉ chuyển
từ transitive sang direct dependency để phân loại ClientException và dùng
MockClient trong tests; không nâng phiên bản package.

### Tệp bàn giao P01.2

Các tệp Dart mới (không tính tệp từ P00.x/P01.1 đã có trong worktree):

```text
lib/features/deliveries/domain/models/delivery_task.dart
lib/features/deliveries/domain/models/delivery_task_item.dart
lib/features/deliveries/domain/models/delivery_task_details.dart
lib/features/deliveries/domain/models/operational_failure.dart
lib/features/deliveries/domain/repositories/delivery_repository.dart
lib/features/deliveries/data/models/dto_readers.dart
lib/features/deliveries/data/models/delivery_task_dto.dart
lib/features/deliveries/data/models/delivery_task_item_dto.dart
lib/features/deliveries/data/repositories/operational_read_access.dart
lib/features/deliveries/data/repositories/operational_providers.dart
lib/features/deliveries/data/repositories/supabase_delivery_repository.dart
lib/features/deliveries/presentation/view_models/delivery_providers.dart
lib/features/cod/domain/models/cod_collection.dart
lib/features/cod/domain/repositories/cod_repository.dart
lib/features/cod/data/models/cod_collection_dto.dart
lib/features/cod/data/repositories/supabase_cod_repository.dart
lib/features/cod/presentation/view_models/cod_providers.dart
test/features/deliveries/delivery_mapper_test.dart
test/features/deliveries/delivery_repository_test.dart
test/features/deliveries/delivery_provider_test.dart
test/features/deliveries/fixtures/delivery_dtos.dart
test/features/cod/cod_mapper_test.dart
test/features/cod/cod_repository_test.dart
test/features/cod/cod_provider_test.dart
test/features/support/operational_supabase_fixture.dart
```

Tệp chỉnh sửa trong phase: pubspec.yaml/pubspec.lock (http direct, cùng version),
docs/api_contracts.md, docs/database.md, docs/screen_mapping.md. Không sửa
core client, theme, router, business_states.md hoặc migration/SQL tests trong
phase này; diff cũ của các phase trước được giữ nguyên.

Kiểm tra đã chạy ngày 23/10/2026:

- `flutter pub get`: thành công; chỉ http 1.6.0 từ transitive sang direct.
- `dart format --output=none --set-exit-if-changed lib/features/deliveries lib/features/cod test/features`:
  25 file, 0 thay đổi.
- `flutter analyze --no-pub`: No issues found.
- `flutter test --no-pub`: **51 tests passed**, gồm 44 tests feature mới và
  7 tests config hiện có; realistic DTO/null/time/money, typed errors,
  paging mutation, loading/error và account-switch/late response cleanup.
- `git diff --check`: PASS.
- `flutter build web --no-pub`: thành công (`Built build/web`, Wasm dry run
  succeeded). Có warning thiếu font CupertinoIcons; phase này không thêm icon
  hoặc UI và không thêm package để che warning. Build không chứng minh backend
  kết nối thành công hoặc bốn màn đã được dựng.

Review độc lập đã phát hiện hai điểm: offset pagination có thể bỏ sót row và
mapper thiếu kiểm tra tổng dòng. Đã sửa sang keyset và BigInt invariant,
thêm tests và chạy lại các kiểm tra trên. Lượt review độc lập sau sửa không
thực hiện được vì reviewer bị giới hạn usage; không ghi là đã re-review sạch.
Tests repository/provider là SDK thật với transport/session fixture, chưa
chứng minh kết nối/backend Supabase live.

## P01.3 — Hợp đồng điều hướng nền tảng

Router duy nhất tại `lib/app/router/app_router.dart` đăng ký bốn route trong
[screen_mapping.md](screen_mapping.md#p013--route-và-khung-điều-hướng-đã-tích-hợp).
Không thêm RPC, migration, quyền RLS, dependency hoặc client Supabase.
Guard dùng OperationalReadAccess của P01.2 để kiểm tra phiên và profiles.role;
route task gọi DeliveryRepository.getTask với UUID chính xác, route COD có
orderId gọi CodRepository.listCollections với bộ lọc đó. Đây là read contracts
hiện có của P01.1/P01.2, không phải API ghi đã triển khai.

`notificationRouteBuilderProvider` là điểm tích hợp WidgetBuilder tùy chọn
của Bảo cho `/notifications`. Giá trị null hiển thị thông báo chưa tích hợp;
không thay thế MH17 hoặc xác nhận quyền mở các business link bên trong MH17.
Các link đó vẫn phải qua guard route đích và backend RLS.

Guard gắn quyết định với URI đầy đủ và session epoch, bỏ kết quả async cũ,
recheck khi navigation/pop/refresh phiên. Đổi user ID hủy navigation được bảo
vệ về `/`; refresh cùng user kiểm tra lại quyền. Redirect chỉ dùng `/`, không
tin query redirect/from. Invalid UUID không gọi read API. Lỗi backend không
mở outlet hoặc trả fixture. Lifecycle cache/subscription tiếp tục theo P01.2.

Dung An chưa cung cấp auth UI/guard/shell trong checkout hiện tại; adapter
guard này không giả định route login hoặc home role. MH17, business screens
và map provider vẫn chưa tích hợp. Các route pages chỉ là outlet ghi rõ tình
trạng, không phải màn nghiệp vụ hoàn chỉnh. Không có thay đổi schema/API ghi
hoặc tuyên bố kết nối Supabase live trong phase này.

Tệp thuộc thay đổi P01.3 (các diff P00/P01.1/P01.2 có sẵn được giữ nguyên):

```text
lib/app/router/app_router.dart
lib/app/router/operational_route_guard.dart
lib/app/shells/shipper_shell.dart
lib/features/deliveries/data/repositories/operational_read_access.dart
lib/features/deliveries/presentation/pages/delivery_route_pages.dart
lib/features/cod/presentation/pages/cod_route_page.dart
test/app/router/operational_navigation_test.dart
docs/screen_mapping.md
docs/api_contracts.md
```

OperationalReadAccess chỉ thêm getter epoch read-only cho guard; không thêm
auth client/listener độc lập. Kiểm thử điều hướng dùng Supabase SDK thật với
transport/session fixture được ghi rõ, không chứng minh backend live.

Kiểm tra P01.3 ngày 23/10/2026:

- `dart format --output=none --set-exit-if-changed lib/app/router lib/app/shells lib/features/deliveries/presentation/pages lib/features/cod/presentation/pages lib/features/deliveries/data/repositories/operational_read_access.dart test/app/router`:
  7 files, 0 changed.
- `flutter analyze --no-pub`: No issues found.
- `flutter test --no-pub test/app/router/operational_navigation_test.dart --timeout 20s`:
  14 tests passed; role/UUID/deep link, COD filter, map scope, safe redirect,
  lỗi network, slot MH17, pop sau thu hồi quyền, refresh role, A→B và late response.
- `flutter test --no-pub`: 65 tests passed.
- `flutter build web --no-pub`: Built build/web; Wasm dry run succeeded.
  Warning CupertinoIcons font thiếu vẫn có như P01.2, không thêm dependency.
- `git diff --check`: PASS.

Lượt chạy test ban đầu lỗi/hang ở fixture async và kỳ vọng sai rằng `/cod`
không filter phải fetch collections. Đã sửa setup/disposal với tester.runAsync
và kỳ vọng chỉ role check; các kết quả đạt ở trên là sau sửa. Review độc lập
source và ba regression pop/refresh/account switch không còn blocker.
P01.3 hoàn tất phần foundation trong repository; nghiệm thu tích hợp live còn
chặn bởi auth UI/guard cuối cùng của Dung An, MH17 của Bảo và backend live.

## P02.1 — Task-list query API của MH10

Contract thực thi dưới đây thay chữ ký list đề xuất ở P00.2; các write RPC,
history archive S4 và API màn khác vẫn chưa được triển khai bởi phase này.
Không có xác nhận stakeholder bổ sung đối với D1–D10. Không dựng UI MH10.

```text
list_my_delivery_tasks(
  p_kind delivery_task_kind DEFAULT NULL,
  p_state_group text DEFAULT NULL,
  p_query text DEFAULT NULL,
  p_limit integer DEFAULT 20,
  p_cursor text DEFAULT NULL
) -> jsonb {
  items: TaskSnapshot[],
  next_cursor: string | null,
  filtered_total: integer,
  counts: {waiting: integer, in_transit: integer,
           completed: integer, ungrouped: integer},
  as_of: timestamptz
}
```

TaskSnapshot là đúng projection P01.1, không trả nguyên orders/returns hoặc
thêm PII cho history. Caller phải authenticated và profiles.role=shipper do
server quản lý; auth.uid quyết định scope. Không có tham số shipper/customer
ID; role manager/customer không được đọc danh sách shipper bằng RPC này.
Đổi assignment thu hồi row người cũ ngay ở lần đọc tiếp theo, kể cả history.
Không hứa cho người từng được phân công đọc archive bất biến chưa tồn tại.

| Tham số / kết quả | Quy tắc |
| --- | --- |
| p_kind | NULL là mọi kind; còn lại một enum thật outbound/return_pickup/redelivery. |
| p_state_group | NULL/rỗng sau chuẩn hóa là Tất cả; lowercase và trim ASCII whitespace; chỉ waiting/in_transit/completed; mapping xem business_states.md, không dùng nhánh else=Completed. |
| p_query | NULL/rỗng sau trim ASCII whitespace (HT/LF/VT/FF/CR/SPACE) là không search; literal substring không phân biệt hoa/thường, tối đa 200 Unicode codepoints sau chuẩn hóa. `%`/`_` không là wildcard. Chỉ so khớp order_id::text và destination_name **đã được projection cho phép**, không tìm hidden fields. |
| Mã đơn | DB chưa có order_code; UUID đơn là display reference đã ghi tại P00.2. Mã dễ đọc/short code vẫn cần Bảo chốt schema/snapshot, không tự bịa DH001 hoặc đọc orders. UUID/tên đã mask không có quyền search/count oracle. |
| p_limit | Integer 1..100, mặc định 20; không lấy tất cả về Flutter để lọc. |
| p_cursor | NULL là trang đầu; token opaque tối đa 4096 ký tự, không có ASCII whitespace ở đầu/cuối, có version/tuple sort/fingerprint của caller/filter chuẩn hóa. Token khác user/kind/group/query hoặc sai cấu trúc bị từ chối. Không là chữ ký hay chứng cứ quyền; mỗi request đều recheck RLS. |
| items | Scope P01.1 current/restricted/history còn assigned đúng caller; lọc kind/search/group trước limit. |
| counts | Toàn tập có quyền sau kind/search, **trước** group/cursor/limit. Tổng bốn count là kích thước tập search/kind; khác filtered_total khi chọn group. |
| filtered_total | Toàn tập sau kind/search/group, **trước** cursor/limit; page rỗng vẫn có total nếu cursor đã đi hết. |
| next_cursor | Chỉ có nếu còn row sau trang hiện tại; client không parse token. |
| as_of | Giờ server của request, không phải khóa snapshot cho request tiếp theo. |

Sort `(created_at,task_id)` giảm dần; task UUID là tie-breaker. created_at chỉ
là sort metadata nội bộ từ delivery_tasks đã chịu cùng RLS, không bổ sung
vào item DTO. Data/count/page lấy trong cùng snapshot SQL. Không row lock,
không ghi dữ liệu/notification, không request_id. Retry là lượt đọc mới có
thể khác; thay đổi trạng thái/phân công giữa trang thì refresh từ trang đầu.
Keyset tránh lỗi offset khi row trước bị xóa, không bảo đảm tập bất biến
xuyên request hoặc phục hồi quyền cũ.

Lỗi SQL: `42501` khi thiếu phiên/không phải shipper; `22023` cho input/cursor
không hợp lệ; enum/UUID do PostgreSQL parse có thể trả `22P02`. Adapter dùng
OperationalFailure: permissionDenied/invalidData tương ứng; lỗi thiếu RPC
là backendUnavailable, network giữ network. Không tự trả empty/success sau
lỗi API; không tự retry hay đổi cursor lỗi về trang đầu.

Read-only owner dùng lại sports_store_delivery_reader NOBYPASSRLS của P01.1;
không đổi policy/grant đọc bảng hoặc cấp quyền orders/return_requests.
SECURITY DEFINER chỉ cung cấp quyền cột/projection đã có, search_path rỗng,
EXECUTE chỉ authenticated, không PUBLIC/anon/service_role. Xem migration và
kết quả kiểm chứng tại database.md.

Dart API thêm `DeliveryRepository.queryTasks(DeliveryTaskQuery)` trả
DeliveryTaskPage/DeliveryTaskCounts bất biến; DTO kiểm tra page size, cursor,
total/count và item kind/state/scope, normalize timestamp UTC, giữ kiểm tra
tiền/snapshot P01.2. Một lượt gọi list RPC cho một page, không tải toàn bộ về
lọc; profile-role precheck của OperationalReadAccess vẫn có request riêng,
backend vẫn enforce quyền. `22023` được map invalidData trong mapper lỗi dùng
chung. Session epoch được kiểm tra trước/sau await; response user cũ bị loại.

`listTasks()` và deliveryTasksProvider cũ giữ nguyên để không tự nối UI ở
P02.1; phase MH10 UI sau phải dùng queryTasks cho filter/search/count/paging,
không lấy listTasks rồi tính counts cục bộ. Không thêm provider UI mới,
realtime, dependency hoặc thay core client/router/theme/COD trong phase này.

### Bàn giao và kiểm chứng P02.1

Tệp thêm/sửa trong phase (không gồm outputs/ có sẵn):

```text
supabase/migrations/20261023153729_list_my_delivery_tasks.sql
supabase/tests/delivery_task_list.sql
supabase/tests/run_delivery_read_fixture.mjs
lib/features/deliveries/domain/models/delivery_task_query.dart
lib/features/deliveries/domain/repositories/delivery_repository.dart
lib/features/deliveries/data/models/delivery_task_page_dto.dart
lib/features/deliveries/data/repositories/supabase_delivery_repository.dart
lib/features/deliveries/data/repositories/operational_read_access.dart
test/features/deliveries/delivery_task_query_test.dart
test/features/deliveries/delivery_provider_test.dart
docs/api_contracts.md
docs/database.md
docs/business_states.md
docs/screen_mapping.md
```

Provider test fixture cũ chỉ bổ sung method interface chưa dùng, ném lỗi rõ
ràng nếu gọi; không giả page thành công. Không đổi production provider sang
query mới ở phase API này.

Lệnh và kết quả cuối ngày 23/10/2026:

- `npx --yes supabase@2.119.0 migration new list_my_delivery_tasks`: tạo file
  migration thật như danh sách trên; không chạy push/reset cloud.
- `node supabase/tests/run_delivery_read_fixture.mjs p011_p021_final9`:
  áp dụng đủ 5 migration vào database cô lập mới, PostgreSQL 17.10;
  database_security.sql, delivery_read_security.sql, delivery_task_list.sql
  đều PASS + ROLLBACK; xác nhận không còn Auth user/order/task/Storage object
  fixture. Đây là SQL Auth/Storage stub, chưa phải Supabase/PostgREST live.
- `dart format --output=none --set-exit-if-changed lib/features/deliveries test/features/deliveries`:
  20 files, 0 changed.
- `flutter analyze --no-pub`: No issues found.
- `flutter test --no-pub test/features/deliveries/delivery_task_query_test.dart --timeout 20s`:
  11 tests passed.
- `flutter test --no-pub`: 75 tests passed.
- `node --check supabase/tests/run_delivery_read_fixture.mjs`: PASS.
- `git diff --check`: PASS.

SQL coverage: hai shipper, đổi assignment, mọi kind/status và nhóm tường
minh; recipient/UUID/literal wildcard search, hidden-history non-oracle,
counts trước group/page, sort hòa timestamp, duyệt hết các trang không bỏ
sót/trùng, empty, cursor sai/null/cross-filter/cross-user, role/ACL denial.
Repository tests bao phủ query/DTO, counts lớn hơn page, empty đầu/cuối,
page/cursor invariant, typed permission/invalid/network và late account response.

Review đã dẫn đến sửa cursor lấy dòng dư gây bỏ sót, counts sai tầng lọc,
strict cursor validation và page invariant; đã thêm regression và chạy lại
các lệnh cuối ở trên. Review độc lập sau sửa không còn finding. Không suy ra
đã deploy hoặc tích hợp UI từ kết quả fixture.

P02.1 hoàn tất phần query/API/repository trong repository. Nghiệm thu live
còn chờ migration qua workflow nhóm và kiểm tra Supabase Auth/PostgREST/RLS
thật; mã đơn hiển thị riêng vẫn cần Bảo chốt (hiện dùng UUID theo P00.2).
Các quyết định custody/assignment archive S2/S4 và item redelivery của Sơn
không được âm thầm xử lý bởi list query. MH10 UI là phase sau.

## P02.3 — MH10 ViewModel, search/filter/paging/refresh

DeliveryTaskListViewModel dùng trực tiếp DeliveryRepository.queryTasks của
P02.1, không gọi listTasks rồi lọc/count cục bộ. Search submit-driven bằng
Enter/nút tìm; kind/state group giữ các filter còn lại và tạo request trang
đầu. resetFilters là một query nguyên tử ở mức ViewModel, không tuần tự ba
lượt request có thể ghi đè lựa chọn mới. Không đổi RPC/schema/quyền/state.

State chứa query gốc (cursor NULL), immutable items, nullable counts/total/
asOf, nextCursor, loading đầu trang/loading thêm, lỗi đầu trang/lỗi thêm.
Counts chưa có không bị hiển thị thành số 0 giả. Mọi số đếm lấy từ response
server: counts sau search/kind trước group, filteredTotal sau group, trước
cursor/limit. Snapshot masked không được ghép lại từ orders/returns; outbound
amount NULL hiện thông tin bị giới hạn, không bị coi là không có nghĩa vụ COD.

Mỗi filter/refresh tăng request generation và bỏ rows/count/cursor cũ trước
khi query. Response chậm của filter/request trước bị loại. Load-more dùng
cursor server; trang mới không được có ID trùng, cursor lặp, count/total
drift hoặc số lượng lũy kế mâu thuẫn với terminal cursor. Khi phát hiện drift
thì reset trang đầu giữ filter một lần; nếu tiếp tục gặp drift, đóng dữ liệu
và báo invalidData, không tự retry vô hạn hoặc giả “đã tải hết”. Snapshot
xuyên nhiều request vẫn không được đóng băng; refresh là cách đồng bộ lại.

Lỗi network/backend khi load-more giữ các trang cùng query đã tải và cho
retry tường minh; lỗi session/quyền/stale assignment bỏ rows/count/cursor.
Lỗi đầu trang/refresh hiện error riêng, không fallback demo hoặc previous
data. Backend báo sessionExpired cũng xóa query/draft ngay cả khi auth stream
chưa emit. Auth epoch/loading/error/logout/account switch xóa private cache
và reset filters; không lưu vào URL/disk. Provider giữ filter trong memory
khi điều hướng cùng phiên, hủy listener theo lifecycle container hiện có;
không thêm Supabase client hoặc Realtime subscription.

RefreshIndicator chờ Future của refresh và dùng AlwaysScrollableScrollPhysics
để kéo được ở empty/error/list ngắn. Nút refresh phục vụ desktop. Mở MH11 bằng
task UUID qua go_router chung và refresh trang đầu giữ filter khi quay lại;
nếu guard/navigation tạo lại page thì recheck cache khi vào. Không thêm action
MH11; fixture trong test chỉ thay read response để kiểm chứng reload.

UI dựa mock HTML người dùng gửi nhưng kế thừa AppTheme/shell hiện có, dùng
Material icons; không mang dữ liệu mẫu, logo/font từ xa hoặc readiness/ca trực
không có backend vào app. UUID đơn là mã tham chiếu thật theo P02.1, chưa có
mã đơn dễ đọc đã được Bảo chốt. Mapping màn và nhóm trạng thái không thay đổi.

Tệp thêm/sửa riêng P02.3 (giữ nguyên các diff P02.1 có sẵn):

```text
lib/features/deliveries/presentation/pages/delivery_route_pages.dart
lib/features/deliveries/presentation/pages/delivery_task_list_page.dart
lib/features/deliveries/presentation/widgets/delivery_task_card.dart
lib/features/deliveries/presentation/view_models/delivery_task_list_view_model.dart
test/features/deliveries/delivery_task_list_page_test.dart
test/features/deliveries/delivery_task_list_view_model_test.dart
test/app/router/delivery_task_list_navigation_test.dart
docs/api_contracts.md
docs/screen_mapping.md
```

Tài liệu API/lifecycle đối chiếu với SDK đang khóa và tài liệu chính thức:
[Riverpod refs](https://riverpod.dev/docs/concepts2/refs),
[go_router navigation](https://pub.dev/documentation/go_router/latest/topics/Navigation-topic.html),
[Flutter RefreshIndicator](https://api.flutter.dev/flutter/material/RefreshIndicator-class.html).

### Kiểm chứng P02.3 ngày 24/10/2026

- `dart format --output=none --set-exit-if-changed lib/features/deliveries/presentation test/features/deliveries/delivery_task_list_page_test.dart test/features/deliveries/delivery_task_list_view_model_test.dart test/app/router/delivery_task_list_navigation_test.dart`:
  8 files, 0 changed.
- `flutter analyze --no-pub`: No issues found.
- `flutter test --no-pub test/features/deliveries/delivery_task_list_view_model_test.dart --timeout 30s`:
  12 tests passed, gồm 3 trang thực tế 20+20+1, query/refresh/load-more race,
  count drift/terminal mismatch và giới hạn reset, stream/RPC expiry cleanup,
  permission denial và network retry.
- `flutter test --no-pub test/features/deliveries/delivery_task_list_page_test.dart --timeout 20s`:
  7 tests passed, gồm controls kết hợp, masked COD, kéo refresh ở empty/error,
  draft cleanup và viewport 320px/text scale 2 không overflow.
- `flutter test --no-pub test/app/router/delivery_task_list_navigation_test.dart --dart-define=CAPTURE_MH10=true --timeout 20s`:
  1 test passed. Dùng Supabase SDK thật với transport/session fixture, router
  production; response đổi khi quay từ MH11, giữ đủ search/kind/group, đọc lại
  từ cursor NULL. Không có action ghi giả hay truy cập backend live.
- `flutter test --no-pub`: 95 tests passed.
- `flutter build web --no-pub`: Built build/web, Wasm dry run succeeded.
  Warning font CupertinoIcons đã có từ phase trước vẫn còn; không thêm package
  để che warning. Build không chứng minh Supabase live hoặc MH11 actions đã có.
- `git diff --check`: PASS.

Preview tùy chọn trong router test chỉ hoạt động khi CAPTURE_MH10=true và
MH10_PREVIEW_FONT trỏ font local có sẵn (đã dùng Arial hệ thống Windows để
kiểm tra); tải font/icon chỉ trong test để tránh font Ahem. Ảnh
`build/p023_mh10_preview.png` là **fixture UI**, không là ảnh dữ liệu live.
Đã xem ảnh ở 390x844 và kiểm tra bố cục. Không thêm font/dependency/demo
adapter vào production. File build/ bị gitignore.

Review độc lập đã dẫn đến sửa premark cursor làm mất trang thứ ba, kiểm tra
số lượng terminal, cleanup khi backend báo hết phiên và diễn đạt COD bị mask.
Các fixture phân trang ban đầu không nhất quán tổng đã được sửa về 41 và có
regression tương ứng; sau sửa review không còn blocker. Không ghi nhận đã
nghiệm thu Supabase Auth/PostgREST/live hoặc được stakeholder duyệt D1–D10.

P02.3 hoàn tất UI/query controls và kiểm thử trong repository. Tích hợp live
còn chặn bởi việc áp dụng P01.1/P02.1 trên môi trường đích và kiểm tra tài
khoản/role thật; mã đơn hiển thị riêng chờ Bảo. MH11 actions vẫn chưa có nên
reload-after-action chỉ được kiểm chứng bằng thay đổi read response fixture,
không tuyên bố luồng nghiệp vụ end-to-end hoàn tất. Không thay migrations,
API signatures, RLS, router, core client, theme hoặc dependencies trong phase.

## P02.2 — Bổ sung nghiệm thu layout/read presentation MH10 (24/10/2026)

P02.2 được đối chiếu sau P02.3 theo yêu cầu người dùng; layout/ViewModel đã
có trong lượt P02.3, nên tái sử dụng nguyên luồng View → ViewModel → typed
repository → RPC đọc P02.1. Không khai báo thêm RPC đã tồn tại hoặc tạo
client/router/provider nghiệp vụ song song. Tham chiếu ma trận màn ở mục
P02.2 của [screen_mapping.md](screen_mapping.md).

Presentation chỉ dùng DeliveryTaskSnapshot/DeliveryTaskPage có quyền; không
sao chép Order, không gọi orders/return_requests từ widget. Amount null của
history/restricted có nghĩa bị giới hạn, không có nghĩa hết nghĩa vụ COD.
Labels assigned/accepted lần lượt Đã phân công/Đã nhận hàng, không gộp hai
mốc hoặc triển khai transition. Counts do server tính; chưa tải là unknown.

Nút retry gọi lại read qua ViewModel và vẫn giữ typed error khi backend lỗi;
không ghi task/COD/attempt/event. Route mở task dùng UUID và backend recheck
hiện hành, không coi card cũ là bằng chứng quyền. Tìm/lọc/paging P02.3 giữ
nguyên như phần đã có, không phát triển thêm trong lần nghiệm thu layout.

Tệp riêng được sửa trong lượt P02.2 này:

```text
lib/features/deliveries/presentation/pages/delivery_route_pages.dart
test/features/deliveries/delivery_task_list_page_test.dart
test/app/router/delivery_task_list_navigation_test.dart
docs/screen_mapping.md
docs/api_contracts.md
```

Runtime page/card/ViewModel và theme đen–trắng đã có được dùng lại, không tính
thành implementation mới của lượt này. Sửa route page chỉ làm rõ comment đã
hết là outlet tạm; router test bổ sung assert đúng UUID path. Còn chờ kiểm
chứng Supabase Auth/PostgREST/live và migration read-layer trên môi trường
đích; chưa có action MH11 để nghiệm thu giao hàng end-to-end.

Kiểm chứng P02.2 ngày 24/10/2026:

- `dart format --output=none --set-exit-if-changed lib/features/deliveries/presentation/pages/delivery_route_pages.dart test/features/deliveries/delivery_task_list_page_test.dart test/app/router/delivery_task_list_navigation_test.dart`:
  3 files, 0 changed.
- `flutter analyze --no-pub`: No issues found.
- `flutter test --no-pub test/features/deliveries/delivery_task_list_page_test.dart --timeout 20s`:
  12 tests passed; thêm 5 tests P02.2 cho loading không có stale card/count,
  empty/reset, denied/retry, network/retry và ba kind/status/COD với counts
  lớn hơn số card. Bảy tests P02.3/masking/viewport cũ tiếp tục đạt.
- `flutter test --no-pub`: 100 tests passed, gồm router production mở đúng
  `/shipper/tasks/:taskId` và kiểm tra read authorization bằng SDK/session/
  transport fixture, không phải kết nối Supabase live.
- `git diff --check`: PASS.

Audit độc lập read-only không còn finding/blocker P02.2. Không chạy lại SQL
hay build web trong lượt này vì không thay query/schema hoặc layout/runtime
đã được build ở P02.3; thay đổi Dart production chỉ là comment route. Phần
presentation/read integration P02.2 đã đủ trong repository, nghiệm thu live
vẫn chưa hoàn tất vì dependency Supabase deployment/Auth thật nêu trên.

## P03.1 — Authorized task-detail API

`get_my_delivery_task(p_task_id uuid) -> jsonb` được triển khai trong migration
repository của P03.1, thay contract get đề xuất ở P00.2. Không suy ra các write
RPC, allowed_actions, custody/version hoặc archive history S4 đã có.

```text
{
  task: TaskSnapshot,       // đúng P01.1 projection
  items: TaskItemSnapshot[],
  notes: null,
  notes_source: "unavailable_schema",
  as_of: timestamptz
}
```

Caller là authenticated có profiles.role=shipper; identity từ auth.uid,
không nhận user/order/return ID để suy scope. UUID task bắt buộc. Task và
items đọc trong một snapshot SQL qua hai projection P01.1; item sort theo
item_id, aggregate JSON server nên không bị giới hạn row cap của PostgREST
ở 200/1000 items. Không phân trang nhiều request rồi ghép task/items khác
thời điểm; không row lock/ghi/event/request_id. Retry là một read snapshot
mới có thể khác, không cam kết trạng thái bất biến sau khi response đã về.

| Tình huống | Task / dữ liệu được trả |
| --- | --- |
| Current assigned/accepted/in_transit đúng người | Recipient name/phone, destination address/lat/lng, IDs cần thiết, kind/status/attempt/lifecycle và amount_to_collect_vnd nguyên snapshot task. Không tính lại COD từ Flutter hoặc từ giá catalog. |
| Outbound current | product_name/variant_label/attributes/quantity và unit_price_vnd/line_total_vnd nguyên order_items snapshot theo task. Không phải quyền đọc cả orders hoặc catalog/asset hiện tại. |
| Return pickup current | product_name (= actual_item_name), quantity (= quantity_to_collect) và quantity_collected qua return_items đúng task/request; variant/attributes/giá không có thì NULL, không đoán sản phẩm thực tế từ toàn đơn. |
| Redelivery current | Task vẫn đọc đúng quyền, item_source=unavailable_redelivery_plan, items=[]. Sơn chưa cung cấp plan hàng giao lại; không tự dùng toàn bộ order_items. |
| History delivered/cancelled/returned_to_store hoặc restricted | Giữ task metadata P01.1; mask order/request IDs, destination/contact/amount/assigned/accepted/started; items=[] và item_source=unavailable. Không suy null COD là hết nghĩa vụ. |
| Reassigned/null assignment/ID ngoài quyền | Cùng lỗi NOT_FOUND_OR_FORBIDDEN, không trả task/items/PII. Không có quyền vĩnh viễn từ một lần shipper từng đọc hoặc từng được phân công. |

Schema hiện tại không có cột/snapshot notes; P03.1 không tự đoán nguồn,
trả explicit notes=null và notes_source=unavailable_schema. Đây là metadata dependency, không phải
“đơn không có ghi chú”. Không lấy business_events/failure_reason hoặc dữ liệu
return_request làm ghi chú. Ảnh/asset URL cũng chưa có snapshot/quyền được
phê duyệt cho shipper: không trả path/signed/public URL, không truy cập Storage
hoặc xin quyền rộng hơn. Bank/refund/video/inspection/customer UUID không
thuộc envelope này. Những phần này chưa được live integrate bằng API mới.

| Lỗi SQL / adapter | Hành vi |
| --- | --- |
| p_task_id NULL: 22023; UUID text sai: 22P02 | invalidData; Dart chặn UUID sai trước request. |
| Thiếu identity/role khác shipper: 42501 | permissionDenied, không trả dữ liệu. Anon không có EXECUTE. |
| ID không tồn tại/ngoài quyền/đổi người: P0002 | NOT_FOUND_OR_FORBIDDEN; chỉ adapter detail map sang staleAssignment, không suy tồn tại của task. |
| RPC chưa deploy/SDK network/JWT lỗi | Typed backendUnavailable/network/sessionExpired như P01.2; không fallback về chuỗi RPC cũ hoặc fixture. |

SupabaseDeliveryRepository.getTaskDetails gọi một detail RPC trong
OperationalReadAccess.run(shipper), kiểm tra epoch trước/sau await. Profile
precheck có request riêng; backend tiếp tục enforce quyền trong snapshot
detail. DTO reuse task/item mapper nghiêm ngặt, kiểm tra đúng task ID,
items unique và khớp source/scope, masked/unavailable không có items; notes
chỉ chấp nhận unavailable/null; as_of bắt buộc có timezone, normalize UTC.
Items immutable, tiền nguyên VND và lifecycle nullable giữ nguyên schema.
DeliveryTaskDetails bổ sung metadata notes/source/asOf; không sao chép Order.

getTask(UUID) tối thiểu phục vụ route guard vẫn dùng read_my_delivery_tasks
đã có. getTaskDetails và detail provider chuyển sang envelope mới; không sửa
router, client, theme hoặc UI MH11. P01.1 item endpoint vẫn được giữ tương
thích; quyền raw tables/history không thay đổi. Chi tiết migration/test ở
[database.md](database.md).

### Bàn giao và kiểm chứng P03.1 (24/10/2026)

Tệp thêm/sửa trong P03.1; các diff P02/theme đã có được giữ nguyên:

```text
supabase/migrations/20261024010714_get_my_delivery_task.sql
supabase/tests/delivery_task_detail.sql
supabase/tests/run_delivery_read_fixture.mjs
lib/features/deliveries/domain/models/delivery_task_details.dart
lib/features/deliveries/data/models/delivery_task_details_dto.dart
lib/features/deliveries/data/repositories/supabase_delivery_repository.dart
test/features/deliveries/delivery_task_details_test.dart
test/features/deliveries/delivery_repository_test.dart
test/features/deliveries/delivery_provider_test.dart
docs/api_contracts.md
docs/database.md
docs/screen_mapping.md
```

Lệnh và kết quả cuối:

- `npx --yes supabase@2.119.0 migration new get_my_delivery_task`: tạo file
  migration thật ở trên, không push/reset cloud.
- `node supabase/tests/run_delivery_read_fixture.mjs p011_p031_final_20261024g`:
  PostgreSQL 17.10 native/Auth-Storage SQL stubs, áp dụng đủ 6 migration vào
  database fixture mới; database_security.sql, delivery_read_security.sql,
  delivery_task_list.sql và delivery_task_detail.sql đều PASS + ROLLBACK.
  Xác nhận 0 user/order/task/Storage object còn lại. SQL chi tiết bao phủ
  owner/ACL/STABLE/search_path/role lock, hai shipper, ba kind, mọi scope,
  ID bị từ chối, đổi người/hủy, optional fields và đủ 1001 item rows trong
  JSON aggregate (vượt max_rows=1000 của config, chưa là PostgREST live test).
- `node --check supabase/tests/run_delivery_read_fixture.mjs`: PASS.
- `dart format --output=none --set-exit-if-changed lib/features/deliveries/domain/models/delivery_task_details.dart lib/features/deliveries/data/models/delivery_task_details_dto.dart lib/features/deliveries/data/repositories/supabase_delivery_repository.dart test/features/deliveries/delivery_task_details_test.dart test/features/deliveries/delivery_repository_test.dart test/features/deliveries/delivery_provider_test.dart`:
  6 files, 0 changed.
- `flutter analyze --no-pub`: No issues found.
- `flutter test test/features/deliveries/delivery_task_details_test.dart test/features/deliveries/delivery_repository_test.dart`:
  19 tests passed sau các bổ sung review.
- `flutter test --no-pub`: 107 tests passed. Provider fixture legacy được đổi
  đúng envelope mới; không thêm runtime fallback để làm fixture cũ báo pass.
- `git diff --check`: PASS.

DTO/repository tests bao phủ shape/current/pickup/history/restricted/redelivery,
nullable variant/attributes/giá/lifecycle, UTC offset, mã task sai, notes/source
hoặc timestamp sai/thiếu, field lạ/nhạy cảm, item trùng/source sai, đầy đủ
array server, stale assignment, missing RPC/network và late account response.
Các test transport/session là fixture rõ ràng, không chứng minh backend live.
Review độc lập sau bổ sung ACL/1001 items và malformed envelopes không còn
finding. Sau kiểm chứng đã dừng đúng native server trong
`.temp/p011_native_data` bằng pg_ctl stop -m fast, nhận server stopped;
giữ database fixture, không xóa/reset dữ liệu hoặc tác động Supabase cloud.

Phần authorized detail read P03.1 hoàn tất trong repository theo schema
hiện tại. Không đánh dấu nghiệp vụ MH11/full live hoàn tất: notes/snapshot
nguồn chờ Bảo/Sơn, item redelivery plan chờ Sơn, ảnh/asset scope chờ owner,
deployment và kiểm tra Supabase Auth/PostgREST/RLS thật vẫn chưa xác minh.
API chỉ trả unavailable flags cho dependency thiếu, không sản xuất dữ liệu
thay thế. Chưa có xác nhận stakeholder mới cho các quyết định S1/S2/S4.

## P03.2 — MH11 read-only presentation contract

DeliveryTaskDetailViewModel(taskId) và page dùng lại
deliveryTaskDetailsProvider/getTaskDetails P03.1. Provider family key gồm
taskId/session epoch; AsyncLoading/AsyncError không mang previous data.
Không gọi Supabase, orders/returns/catalog hoặc Storage từ widget.
ViewModel chỉ có refresh/retry, không có method ghi trạng thái/COD/attempt.

refreshDeliveryTaskDetails invalidates private session-keyed future thật,
không chỉ invalidates public projection rồi tái dùng cache. Refresh có scope
một task, giữ filter MH10 và các task khác; state được cập nhật từ watched
projection, không gán kết quả cũ sau await. Khi auth/task scope thay đổi hoặc
dispose thì response trước không publish. Bấm map cũng chỉ gửi UUID; sau
quay lại refresh detail để task hủy/terminal còn quyền history không làm
hiện recipient từ current cache.

COD dùng nguyên task.amount_to_collect_vnd, không recompute/increment hoặc
thêm phí 30.000 VND hardcode. P03.1 chưa có delivery_fee/subtotal fields,
nên breakdown vẫn là dependency của owner order snapshot. Note source
unavailable_schema, redelivery plan unavailable và asset không có quyền
được thể hiện bằng thông báo/placeholder; không suy dữ liệu không có hoặc
không có quyền thành zero/no obligation. Không lấy timeline/reason/bank/
video/refund evidence từ mock hoặc nguồn riêng tư để điền UI.

Gọi điện là affordance disabled được ghi rõ chưa khả dụng, phone selectable
để người dùng copy; không thêm plugin gọi điện và không báo đã mở dialer.
Action placeholders disabled theo cặp kind/status, chỉ ở scope current.
Chưa có allowed_actions server hay API ghi để bật các nút này; không coi
nhãn disabled là chốt precondition/business contract với Bảo/Sơn/Văn Đức.
Không triển khai dialog ghi, nhận hàng, start, complete, failure hoặc incident.

Giữ nguyên schema/RLS/read signatures, shared router/theme/client và packages;
chỉ MH11 entry point thay outlet bằng page. MH18 vẫn là dependency UI riêng.
Phạm vi hiển thị chi tiết/variant và khác biệt với mock ở screen_mapping.md.

### Bàn giao P03.2 (24/10/2026)

Tệp riêng thêm/sửa trong P03.2, giữ các diff P02/P03.1 và màu đã có:

```text
lib/features/deliveries/presentation/pages/delivery_route_pages.dart
lib/features/deliveries/presentation/pages/delivery_task_detail_page.dart
lib/features/deliveries/presentation/view_models/delivery_providers.dart
lib/features/deliveries/presentation/view_models/delivery_task_detail_view_model.dart
test/features/deliveries/delivery_task_detail_page_test.dart
test/features/deliveries/delivery_task_detail_view_model_test.dart
test/app/router/delivery_task_detail_navigation_test.dart
test/app/router/delivery_task_list_navigation_test.dart
docs/screen_mapping.md
docs/api_contracts.md
```

MH10 router fixture được bổ sung detail envelope để test MH10→MH11 hiện dùng
page thật; không thay runtime thành fixture hoặc làm API lỗi báo thành công.
Refresh listener tạm theo dõi operationalSessionProvider hiện có từ container
để không bị đóng khi ViewModel tự rebuild; luôn close trong finally. So sánh
session object identity như key của FutureProvider, kiểm tra ngay khi subscribe
và không bắt đầu private read đã supersede. Lifecycle cancellation phân biệt
rebuild do refresh với disposal thật, không kết thúc refresh sớm và không chờ
network của account cũ sau switch/logout/dispose. Không gán response sau await.

Các checks được chạy:

- `dart format --output=none --set-exit-if-changed lib/features/deliveries/presentation/pages/delivery_task_detail_page.dart lib/features/deliveries/presentation/pages/delivery_route_pages.dart lib/features/deliveries/presentation/view_models/delivery_providers.dart lib/features/deliveries/presentation/view_models/delivery_task_detail_view_model.dart test/features/deliveries/delivery_task_detail_page_test.dart test/features/deliveries/delivery_task_detail_view_model_test.dart test/app/router/delivery_task_detail_navigation_test.dart test/app/router/delivery_task_list_navigation_test.dart`:
  8 files, 0 changed.
- `flutter analyze --no-pub`: No issues found.
- `flutter test --no-pub test/features/deliveries/delivery_task_detail_page_test.dart`:
  8 tests passed, gồm outbound/pickup/redelivery, image/unavailable states,
  malformed domain privacy, loading/error/retry, map URL/return-refresh, UUID
  version 7/uppercase, viewport 320px/text scale 2.
- `flutter test --no-pub test/features/deliveries/delivery_task_detail_view_model_test.dart`:
  14 tests passed; refresh reissues read, awaits settled result, keeps task
  isolation, drops old PII and completes correctly on epoch/logout/disposal.
- `flutter test --no-pub test/app/router/delivery_task_detail_navigation_test.dart --dart-define=CAPTURE_MH11=true --timeout 30s`:
  2 tests passed with production router and SDK transport/session fixture;
  map permission revoked before opening is denied; cancellation while map
  is open then returning reloads masked history and hides old recipient.
  URL only task UUID, no PII query. No backend writes executed.
- `flutter test --no-pub`: 129 tests passed.
- `flutter build web --no-pub`: Built build/web, Wasm dry run succeeded;
  warning font CupertinoIcons có từ phase trước vẫn còn. Không thêm package
  để che warning hoặc suy ra backend live đã kết nối thành công từ build.
- `git diff --check`: PASS.

Preview opt-in cần MH11_PREVIEW_FONT trỏ font local (đã dùng Arial hệ thống
khi chụp); FontLoader và dữ liệu fixture chỉ có trong test. Ảnh fixture
`build/mh11_nike_readonly_20261024.png` ở 390x844 đã được xem trực quan;
không là dữ liệu Supabase live hoặc demo adapter của production.

Review dẫn đến sửa masking note/source, amount NULL outbound, UUID đúng
contract, privacy khi task hủy lúc xem map và refresh lifecycle race. Test
refresh đầu phát hiện Future kết thúc sớm do ViewModel rebuild; đã sửa mà
không làm yếu assertion chờ kết quả. Review độc lập cuối không còn blocker.
Không nút disabled nào gọi RPC ghi hoặc làm thay đổi trạng thái.

P03.2 chỉ đọc hoàn tất theo contract P03.1 hiện có trong repository. Tích hợp
live vẫn chưa xác minh: cần deploy P03.1 và kiểm tra Auth/RLS thật; notes,
items giao lại, asset được phép, breakdown phí và dialer vẫn chưa khả dụng.
MH18 vẫn là outlet, link đã test không chứng minh map provider hoàn chỉnh.
Không schema, RLS/grant, RPC signature, dependency hoặc transition mới.

Đối chiếu bổ sung bốn mock MH11: đây là bốn trường hợp riêng trên một màn,
không phải bốn màn chính mới. Đã đọc đủ bốn HTML, nhưng test ban đầu còn thiếu
outbound in_transit và redelivery đang dùng accepted thay vì in_transit như
mock. Đã bổ sung hai widget test riêng cho trạng thái in_transit, kiểm tra
đúng nhóm action disabled/COD/lần giao và không hiện action nhận/start sai
state. Ma trận hiện tại:

| Mock | Trường hợp kiểm chứng |
| --- | --- |
| 4df85d31… | Outbound assigned — chờ nhận hàng tại cửa hàng. |
| 04a1c682… | Outbound in_transit — đang giao, đủ COD và placeholder thành công/thất bại disabled. |
| 4890b961… | Return pickup — điểm lấy, quantity kế hoạch/đã nhận, không COD; không suy enum “đang lấy” từ nhãn mock. |
| 0a839c17… | Redelivery in_transit — không COD, plan chưa khả dụng và placeholder kết quả disabled. |

`flutter test --no-pub test/features/deliveries/delivery_task_detail_page_test.dart`:
9 tests passed sau bổ sung. Không thay runtime/business state để làm khớp
các nút/dialog ghi trong mock; chúng vẫn nằm ngoài P03.2.
