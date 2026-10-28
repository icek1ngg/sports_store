# Trạng thái nghiệp vụ

**Mốc production mới 28/10/2026:** người dùng giao bổ sung các primitive còn thiếu;
receipt manager sau full pickup handover → T returned_to_store/R under_inspection;
inspection rejected với lý do → R awaiting_redelivery + immutable full actual plan;
redelivery assigned → accepted (physical custody) → in_transit → delivered/
rejected_after_inspection/closed_at hoặc T/R manager_action_required (giữ custody,
completed_at/closed_at null). Tám RPC đã deploy; không COD mới/attempt/restock/refund.
[Contract và chứng cứ mới](demos/p083_production_redelivery.md) thay blocker
receipt/inspection/proof của mốc fixture cũ. Không suy manager resolution sau
redelivery failure hoặc UI MH15 đã được triển khai.

Mốc fixture P08.3/D9 trước khi giao bổ sung primitive: người dùng chốt redelivery thất bại T/R đều
`manager_action_required`, giữ custody/open; thành công chỉ từ T in_transit và
R awaiting_redelivery sang delivered/rejected_after_inspection + closed_at.
Giữ chặn production khi thiếu receipt/inspection/item-plan proof của Sơn;
[interface và fixture P08.3](demos/p083_redelivery_backend_contract.md) không
phải RPC đã triển khai hoặc approval của Sơn.

Pickup P5 đã bổ sung shipper report: task in_transit/request returning_to_store
giữ nguyên sau báo bàn giao đủ custody; chỉ event/report/notification chủ cửa
hàng. Manager P6 receipt/inspection vẫn thuộc Sơn và không được coi đã thực hiện.
[Contract và nghiệm thu handover](demos/p082_pickup_handover_acceptance.md).

P08.2 chỉ trình bày/điều phối P08.1: pickup nhận đủ tại khách → in_transit;
lấy thất bại trước custody → failed chờ manager; không tự returned_to_store,
inspection, nhập tồn hoặc refund. UI pickup không áp giới hạn outbound hai lần
hoặc thu COD. [Hành vi và kiểm thử](demos/p082_return_pickup_frontend.md).

P08.1 cập nhật D8 theo quyết định người dùng ngày 27/10/2026: collect pickup
phải đủ đúng kế hoạch đã duyệt, gộp P2/P3 thành assigned → in_transit với
accepted_at=started_at server; request returning_to_store. P4 thất bại chỉ trước
nhận, request vẫn awaiting_return_pickup và cho task mới không trần hai lần.
Chỉ đổi shipper trước custody. Không manager receipt/inspection/restock/refund.
[Bảng transition, dependencies và kiểm chứng P08.1](demos/p081_return_pickup_backend.md)
thay các lựa chọn D8 cũ trong phạm vi này, không suy ra approval của Sơn.

P07.5 chỉ nối giao diện reporting outbound P07.4. Báo bàn giao/sự cố không đổi
task/order/COD/attempt/stock; marker bàn giao lấy từ server không phải trạng thái
manager receipt. UI đọc flags custody từ RPC hẹp, không suy từ `failed` đơn lẻ.
Pickup/redelivery và manager resolution/inspection/restock chưa được triển khai
bởi phase này. Xem [P07.5](demos/p075_production_reporting_interfaces.md).

Tài liệu này là hợp đồng trạng thái dùng chung cho MH01–MH20 và migration schema
nền tảng. Các giá trị bên dưới đã được định nghĩa
bằng enum hoặc ràng buộc trong schema để các ViewModel, repository và policy
dùng cùng tên tiếng Anh dạng snake_case.

Migration nền chỉ tạo cấu trúc dữ liệu, ràng buộc toàn vẹn, chỉ mục, RLS và
trigger tạo hồ sơ khách hàng. Các chuyển trạng thái nhiều bảng, giữ/giải
phóng tồn, tự xác nhận sau một giờ, thu COD, trả hàng và hoàn tiền vẫn phải
được thực hiện trong RPC hoặc cơ chế xử lý server có giao dịch và kiểm tra
quyền. Migration simplification chỉ chạy khi các bảng mục tiêu còn rỗng và
khóa bảng trước khi kiểm tra; nó không backfill hoặc xóa dữ liệu nghiệp vụ.
Bảng có thể đang ở trạng thái khởi tạo; không coi enum hoặc check constraint
là bằng chứng rằng endpoint nghiệp vụ đã hoàn thành.

Schema cuối giữ 18 bảng: profiles, categories, products, product_variants,
inventory_movements, cart_items, orders, order_items, return_requests,
return_items, delivery_tasks, delivery_attempts, cod_collections,
business_events, notifications, conversations, messages và store_settings.
Các bảng phụ inventory_balances, carts, delivery_incidents, return_evidence,
refund_accounts, refunds và conversation_reads đã được gộp hoặc loại bỏ bởi
migration có guard dữ liệu.

## Vai trò tài khoản

profiles.role có ba giá trị:

- customer: khách mua hàng, được tạo mặc định khi Auth tạo người dùng mới.
- manager: quản lý cửa hàng.
- shipper: người giao hàng nội bộ.

Trigger hồ sơ luôn ghi customer, bỏ qua role trong metadata người dùng. Metadata
chỉ có thể cung cấp full_name tùy chọn; quyền được lấy từ profiles.role.

## Đơn hàng

orders.status có các giá trị:

| Giá trị | Ý nghĩa và chuyển tiếp dự kiến |
| --- | --- |
| pending_confirmation | Đơn mới đặt, chờ manager xác nhận, tự xác nhận sau ít nhất một giờ hoặc bị hủy/từ chối hợp lệ. |
| preparing | Đã xác nhận, cửa hàng chuẩn bị hàng; khách không còn hủy theo luồng thông thường. |
| awaiting_pickup | Đã chuẩn bị xong và có shipper, chờ shipper nhận hàng tại cửa hàng. |
| delivering | Hàng đang được giao ở lần 1 hoặc lần 2. |
| awaiting_redelivery | Lần giao đi trước thất bại và manager phải chọn giao lần tiếp theo hoặc hoàn sớm. |
| awaiting_store_return | Không giao được, chờ hàng về cửa hàng để manager nhận và kiểm tra. |
| delivered | Khách nhận đủ toàn bộ hàng và shipper thu đủ COD. |
| cancelled | Đơn bị khách hủy khi còn chờ xác nhận hoặc manager hủy ngoại lệ trước khi shipper nhận hàng. |
| rejected | Manager từ chối đơn đang chờ xác nhận và ghi lý do. |
| undeliverable_returned | Hàng không giao được đã về cửa hàng và được manager nhận/kiểm tra. |

delivery_attempt_count bắt đầu ở 0 và chỉ nằm trong 0..2. Thay shipper
không đặt lại bộ đếm. source phân biệt xác nhận manager và automatic.
total_cod_vnd được sinh từ subtotal_vnd + delivery_fee_vnd; phí giao bị
ràng buộc là 30_000 VND.

Một request_id của khách chỉ tạo một đơn nhờ khóa duy nhất
(customer_id, request_id). Snapshot tên sản phẩm, biến thể, thuộc tính, đơn
giá, người nhận, địa chỉ và tọa độ nằm trong đơn/dòng đơn để thay đổi catalog
không sửa lịch sử.

## Giỏ hàng và tồn kho

Giỏ hàng không còn bảng carts riêng. Mỗi dòng cart_items gắn trực tiếp với
customer_id và variant_id; khóa chính là (customer_id, variant_id). Customer
chỉ đọc/thêm/sửa số lượng/xóa dòng của mình. Không có quyền client đổi
customer_id hoặc các trạng thái tồn.

Tồn kho được lưu trên product_variants. Các cột on_hand, reserved và damaged
không âm; reserved không vượt on_hand; available_quantity được sinh bằng
on_hand - reserved. inventory_movements vẫn lưu reserve, release, dispatch,
restock, damage, loss, adjustment và return_received. Mỗi movement phải có ít
nhất một delta khác không; cặp (event_id, variant_id) là duy nhất để một sự
kiện có thể cập nhật nhiều biến thể mà không ghi lặp.

Các quy tắc giữ hàng, chống oversell, hoàn trả tồn sau hủy, xuất giao, nhận
hàng hoàn và idempotency của nhiều bảng chưa được thực hiện bằng endpoint trong
migration này. Không cộng hàng giao thất bại trở lại lượng bán được trước khi
manager nhận và kiểm tra; hàng hỏng/mất được theo dõi riêng.

## Nhiệm vụ giao nhận

delivery_tasks.kind:

- outbound: giao đơn đến khách; attempt_number chỉ là 1 hoặc 2, có thể thu COD.
- return_pickup: lấy hàng khách trả về cửa hàng; không thu COD và không tự áp
  dụng giới hạn hai lần của giao đi.
- redelivery: giao lại hàng cho khách sau nhánh trả hàng bị từ chối; không thu
  COD lần hai.

delivery_tasks.status có các giá trị pending_assignment, assigned, accepted,
in_transit, delivered, failed, returned_to_store, cancelled,
manager_action_required. Chỉ một nhiệm vụ giao đi đang hoạt động trên mỗi đơn
và chỉ một nhiệm vụ lấy/giao lại đang hoạt động trên mỗi yêu cầu trả; các
nhiệm vụ kết thúc vẫn được giữ để truy vết.

Mỗi nhiệm vụ giao đi có tối đa một bản ghi delivery_attempts và mỗi đơn
không có quá một bản ghi cho cùng số lần giao. result là success hoặc failed;
lần thất bại phải có lý do. Sự cố shipper có kind là damaged, lost hoặc other,
kèm task_id, actor_id là shipper đang tạo sự cố, subject_type là
`delivery_task`, subject_id trùng task_id và request_id chống ghi lặp trong
business_events. Sau P01.1 chỉ manager đọc raw events; shipper không đọc
raw sự cố hoặc report bàn giao, kể cả trên task của mình.

## P00.1 — Hợp đồng chuyển trạng thái giao nhận (23/10/2026)

### Căn cứ, mức xác nhận và giới hạn

- **DB**: đối chiếu `../supabase/migrations/20261006034251_sports_store_schema.sql`
  (enum, bảng và unique index), `20261006034259_sports_store_access.sql`
  (grants/RLS) và `20261006040019_simplify_sports_store.sql` (sự cố trong
  `business_events`). Đây là bằng chứng mã nguồn, không phải kiểm tra cloud hôm nay.
- **NV**: quy tắc nghiệp vụ v3.0 được ghi lại trong `../AGENTS.md` và các mục
  Đơn hàng, COD, Yêu cầu trả hàng ở tài liệu này. Chưa có bản báo cáo gốc v3.0
  để kiểm tra trực tiếp số mục/NT; không khẳng định đã đối chiếu toàn văn báo cáo.
- **KH**: `minh_duc_implementation_plan.md`, Phase 0, 2, 4, 5 là kế hoạch và
  đề xuất tích hợp, không phải bằng chứng nhóm đã đồng ý. File đính kèm
  `01_P00_1.md` không có tại đường dẫn được cung cấp khi thực hiện P00.1.
- **ĐX**: các bảng dưới là đặc tả đề xuất P00.1 dùng đúng enum DB. Các hàng
  có mã D cần người sở hữu xác nhận trước khi triển khai; không có xác nhận
  stakeholder nào được ghi nhận trong lần thay đổi này. Không thêm enum/RPC.
  RPC giao nhận/COD vẫn chưa tồn tại trong các migration đã kiểm tra;
  xem [phạm vi API hiện có](api_contracts.md).

### Các mốc độc lập và quy tắc chung (ĐX, KH)

`assigned` chỉ là manager phân công, không chứng minh shipper đã nhận việc
hoặc đang giữ hàng. DB không có mốc riêng cho shipper xác nhận nhận việc;
nếu cần phải chốt D1, không dùng `accepted_at` cho hai nghĩa.
`accepted`/`accepted_at` dành cho **thực nhận hàng**: tại cửa hàng với outbound
và redelivery, tại khách với return_pickup. `in_transit`/`started_at` là
bắt đầu vận chuyển sau thực nhận. Nhận hàng trả và bắt đầu vận chuyển về
có thể là hai hành động liên tiếp; không suy ra đã đi từ việc được phân công.

Shipper báo bàn giao cửa hàng là sự kiện, chưa phải `returned_to_store`.
Đề xuất lưu trong `business_events` với actor, task, request ID, giờ server,
trạng thái trước/sau giữ nguyên; không gán `incident_kind` cho bàn giao bình thường.
DB chưa có cột mốc bàn giao/custody hoặc cơ chế idempotency tổng quát cho mọi
action; cần thiết kế cách lưu payload/đối chiếu retry ở phase API (D2).
Ở baseline P00.1 shipper chỉ đọc sự cố do mình tạo trên task được phân công;
sau P01.1 raw events chỉ manager đọc. Cách trả
kết quả/retry hoặc projection bàn giao cần hợp đồng server riêng, không
gán giả `incident_kind` hay mở rộng policy trong P00.1.
Chỉ manager thực nhận mới đổi task thành `returned_to_store`; kết luận chất
lượng và nhập tồn phải có kết quả kiểm tra riêng, không suy ra từ trạng thái task.

Mỗi hàng chuyển trạng thái bên dưới cần transaction server kiểm tra role,
phân công hiện tại, liên kết order/request/task, trạng thái và khóa các bản ghi
liên quan theo cùng quy ước với owner. Giờ lấy từ server. Ghi event và thông
báo đúng người theo `(recipient_id, event_id)` trong cùng transaction khi có
thông báo; danh sách recipient phải chốt với Bảo (D7). Retry cùng request ID
và payload trả kết quả cũ; payload khác bị từ chối; hai kết quả đối nghịch chỉ
một được commit. Đây là yêu cầu tương lai, constraint nền chưa thực thi đủ.

### Giao đi — `outbound`

Trong bảng: O = `orders.status`, T = `delivery_tasks.status`.
Mỗi dòng nêu trạng thái đích của cùng task trừ khi ghi rõ tạo task mới.

| ID / căn cứ | Actor, hành động | Tiền điều kiện | Chuyển trạng thái | Tác dụng phụ / quyết định còn mở |
| --- | --- | --- | --- | --- |
| O1 / DB, KH | Manager chuẩn bị và phân công MH09 | O=`preparing`; snapshot hợp lệ; shipper hợp lệ; không có outbound active; count < 2 | T mới `pending_assignment` → `assigned`; O → `awaiting_pickup` | Gán số dự kiến count + 1; chưa tăng count, chưa xuất tồn, chưa có attempt result. Thời điểm chuyển O khi tạo task chưa phân công cần Bảo chốt D1. |
| O2 / KH | Manager đổi người trước nhận hàng | T=`assigned`; chưa `accepted_at`/`started_at`; không có custody | T giữ `assigned`, thay phân công | Lưu lịch sử người cũ/mới; không đổi số lần. Sau thực nhận bị chặn cho đến khi có hợp đồng D3. |
| O3 / KH, NV | Shipper thực nhận hàng tại cửa hàng MH11 | Đúng người; T=`assigned`; O=`awaiting_pickup`; chưa hủy; đủ hàng | T → `accepted`; O giữ `awaiting_pickup` | Ghi `accepted_at`, custody và dispatch tồn đúng một lần trong transaction. Chưa tăng count. Khóa cạnh tranh với hủy; manager không hủy ngoại lệ sau mốc này. D1, D4. |
| O4 / KH | Shipper bắt đầu giao MH11 | T=`accepted`; có custody; O hợp lệ; số dự kiến = count + 1 ≤ 2 | T → `in_transit`; O → `delivering` | Ghi `started_at`, tăng count đúng một lần; chưa ghi `delivery_attempts`. Không dispatch lại. |
| O5 / NV, DB, KH | Shipper giao thành công | T=`in_transit`; khách nhận toàn bộ; thu đủ tổng COD từ server | T → `delivered`; O → `delivered` | Một transaction ghi attempt `success`, thời điểm kết quả, COD `uncollected` → `collected` và người thu. Không chấp nhận thu thiếu. |
| O6 / NV, KH | Shipper báo thất bại lần 1 | T=`in_transit`; count=1; lý do không rỗng; chưa có kết quả | T → `failed`; O → `awaiting_redelivery` | Ghi attempt `failed`, lý do, shipper và giờ server; không ghi thu COD, không nhập tồn. Chờ quyết định manager. |
| O7 / NV, KH | Manager cho giao lần 2 MH09 | O=`awaiting_redelivery`; kết quả lần 1 thất bại; count=1 | Giữ task cũ `failed`; tạo T mới `pending_assignment` → `assigned`, số 2; O → `awaiting_pickup` (ĐX) | Thực nhận/custody phải xác minh lại rồi mới start; không dispatch cùng hàng lần hai. Không tái mở task lần 1. D1, D3, D4 chặn tích hợp. |
| O8 / NV, KH | Manager yêu cầu hoàn sớm | O=`awaiting_redelivery`, kết quả lần 1 thất bại; không task mới đang vận chuyển | T cũ giữ `failed`; O → `awaiting_store_return` | Ghi quyết định hoàn; không tạo lần 2, không hoàn tồn. Nếu đã tạo task 2 nhưng chưa start cần xử lý custody/hủy theo D3, D5. |
| O9 / NV, KH | Shipper báo thất bại lần 2 | T=`in_transit`; count=2; lý do hợp lệ | T → `failed`; O → `awaiting_store_return` | Ghi attempt `failed`; từ chối lần 3 dù đổi shipper/task; không thu COD hoặc tự restock. |
| O10 / KH | Shipper báo bàn giao hàng về | O=`awaiting_store_return`; T=`failed`; shipper đang giữ hàng, bàn giao thực tế | T giữ `failed`; O giữ nguyên | Chỉ event báo bàn giao, không coi cửa hàng đã nhận/kiểm tra; D2. |
| O11 / NV, KH | Manager nhận hàng rồi kiểm tra MH09 | Có hàng thực tế và đối chiếu bàn giao; đúng nhánh hoàn thất bại | Khi nhận: T `failed` → `returned_to_store`, O giữ `awaiting_store_return`; khi kiểm tra xong: O → `undeliverable_returned` | Hai mốc nghiệp vụ tách biệt; chỉ lượng đạt kiểm tra mới restock một lần; hỏng/mất xử lý riêng. Cách lưu receipt/inspection và transaction tồn cần Bảo + Văn Đức chốt D4, D5. |
| O12 / NV, KH | Manager hủy ngoại lệ / khách hủy trước xác nhận | Khách chỉ O=`pending_confirmation`; manager trước thực nhận, theo hợp đồng orders | Task chưa nhận (nếu có) → `cancelled`; O → `cancelled` | Không tăng count/ghi attempt nếu chưa start. Giải phóng tồn giữ một lần theo owner; tranh chấp với O3 chỉ một thắng. D1, D4. |

### Số lần giao, kết quả và retry (ĐX dựa DB, KH)

Các hàng gộp O1/P1/R1 ở trên biểu diễn chuỗi tạo rồi phân công, không bắt
buộc một thao tác nguyên tử. Đặc tả từng mốc thay thế như sau (ĐX):

| ID | Actor và tiền điều kiện | Chuyển trạng thái | Tác dụng phụ / điểm mở |
| --- | --- | --- | --- |
| O1a | Manager; điều kiện O1 | Chưa có task → `pending_assignment`; O giữ `preparing` | Gán số dự kiến; `amount_to_collect_vnd = orders.total_cod_vnd`; chưa gán người hoặc tăng count. D1 chốt thời điểm O. |
| O1b | Manager; T=`pending_assignment`, shipper hợp lệ | T → `assigned`; O → `awaiting_pickup` | Ghi `assigned_shipper_id`, `assigned_by`, `assigned_at`; không custody/dispatch. |
| P1a | Manager duyệt lấy; điều kiện P1 | T mới `pending_assignment`; R → `awaiting_return_pickup` | Chưa phân công; amount=0, số=1; chưa thực nhận. D8. |
| P1b | Manager; T=`pending_assignment`, shipper hợp lệ | T → `assigned`; R giữ nguyên | Ghi người được phân công/người phân công/giờ server. D8. |
| R1a | Manager quyết định sau kiểm tra; điều kiện R1 | T mới `pending_assignment`; R → `awaiting_redelivery` | amount=0, số=1; chưa phân công. D9. |
| R1b | Manager; T=`pending_assignment`, shipper hợp lệ | T → `assigned`; R giữ nguyên | Ghi người được phân công/người phân công/giờ server. D9. |
| O11a | Manager; có hàng thực tế, O=`awaiting_store_return`, T=`failed`; đối chiếu người đang giữ hàng | T → `returned_to_store`; O giữ nguyên | Ghi receipt, chưa restock/kết luận chất lượng. Báo bàn giao của shipper không thay bằng chứng thực nhận. D2/D5. |
| O11b | Manager; đã có receipt O11a, hoàn tất kiểm tra số lượng/chất lượng | T giữ `returned_to_store`; O → `undeliverable_returned` | Ghi inspection riêng; restock chỉ lượng đạt, xử lý hỏng/mất theo D4/D5. |

O11a/O11b thay hàng tổng quan O11; không gọi một action client để ngầm hoàn
tất cả hai mốc. Khi tạo outbound, nghĩa vụ COD dự kiến phải bằng tổng đơn;
O5 kiểm tra đồng thời task amount, `cod_collections.expected_amount_vnd`
và `orders.total_cod_vnd` bằng nhau. Thời điểm tạo khoản `uncollected` cần
chốt với owner đơn hàng, không giả định đã có khoản trong DB.

- `delivery_tasks.attempt_number` là số **dự kiến cố định của task**, được gán
  khi tạo outbound bằng `orders.delivery_attempt_count + 1`; không tăng tại
  accept/start và không sửa task cũ từ 1 thành 2. Chính **count của order**
  tăng tại O4 (`accepted` → `in_transit`) trong cùng transaction, tối đa 2.
- `delivery_attempts` chỉ được INSERT khi O5/O6/O9 có kết quả; DB chỉ có
  result `success`/`failed`, không có bản ghi “đang giao”. Trong lúc vận
  chuyển count có thể lớn hơn số dòng kết quả; đây không phải mất dữ liệu.
  Unique `task_id`, `(order_id, attempt_number)` và FK bốn cột bảo vệ quan hệ;
  server vẫn phải kiểm tra count, trạng thái và shipper.
- Timeout/bấm lặp start, success, fail hoặc đổi người không phải lần mới.
  Request mới cũng không được start lại task đang đi hoặc ghi kết quả thứ hai.
  Lần mới chỉ do manager cho phép sau kết quả thất bại lần 1, tạo task số 2;
  giữ nguyên task/attempt lịch sử và shipper đã thực hiện kết quả.
- Task bị hủy trước start không tiêu thụ lần giao, không ghi result. Task
  thay thế có thể dùng cùng số dự kiến chưa dùng; DB không unique số dự kiến
  giữa các task, nhưng chỉ cho một outbound active. Sau start không reset
  count/hủy để né giới hạn; sự cố không có kết quả giao rõ ràng chờ D6.
- `return_pickup`/`redelivery` luôn `attempt_number=1` theo CHECK DB, count
  outbound giữ nguyên và không ghi `delivery_attempts`. Số 1 không phải hạn
  mức số lần lấy/giao lại; không tự suy ra chính sách retry vật lý cho hai loại này.

### Thu hồi — `return_pickup`

R = `return_requests.status`. O đã `delivered` luôn giữ nguyên; COD đã thu
vẫn phải nộp đủ dù hàng đang trả hoặc đã hoàn tiền. Tất cả task loại này có
`amount_to_collect_vnd=0`, cùng order với request, không dispatch hàng của đơn.

| ID / căn cứ | Actor, hành động | Tiền điều kiện | Chuyển trạng thái | Tác dụng phụ / quyết định còn mở |
| --- | --- | --- | --- | --- |
| P1 / NV, DB, KH | Manager duyệt lấy/phân công MH15 | R=`pending_review` hợp lệ; duyệt thu hồi; chưa có task return active | R → `awaiting_return_pickup`; T mới `pending_assignment` → `assigned` | Snapshot hàng thực tế cần lấy và điểm khách; không duyệt hoàn tiền. Sơn chốt số lượng D8. |
| P2 / KH | Shipper thực nhận tại khách MH11 | T=`assigned`; R=`awaiting_return_pickup`; xác nhận hàng/số lượng thực nhận | T → `accepted`; R → `returning_to_store` | Ghi `accepted_at`, custody và hàng thực nhận; R biểu thị hàng đã ở shipper, chưa khẳng định task bắt đầu chạy. Chưa nhập tồn; D8. |
| P3 / KH | Shipper bắt đầu vận chuyển về | T=`accepted`; đã nhận hàng thực tế | T → `in_transit`; R giữ `returning_to_store` | Ghi `started_at`; không thay count hoặc COD. Việc gộp P2/P3 thành một transaction là lựa chọn cần Sơn chốt D8. |
| P4 / KH | Shipper lấy không thành công | T=`assigned`, chưa nhận hàng; lý do hợp lệ | T → `failed`; R giữ `awaiting_return_pickup` (ĐX) | Báo manager; không có attempt outbound; manager quyết định hẹn/phân công task mới. D8; không tự áp trần hai lần. |
| P5 / KH | Shipper báo bàn giao tại cửa hàng | T=`in_transit`; có hàng bàn giao | T giữ `in_transit`; R giữ `returning_to_store` | Chỉ event bàn giao D2; không đặt `delivered`, không tự restock/hoàn tiền. |
| P6 / NV, KH | Manager nhận hàng MH15 | Có hàng thực tế; kiểm tra số lượng bàn giao; T=`in_transit` | T → `returned_to_store`; R → `under_inspection` | Cùng transaction receipt/task/request; chưa kết luận chất lượng, không tự restock. Kiểm tra/nhập tồn/hoàn tiền là bước riêng của Sơn + inventory D4, D8. |
| P7 / NV, KH | Shipper báo hỏng/mất/sai lệch sau nhận | T=`accepted` hoặc `in_transit`; lý do/sự cố và custody rõ | Đề xuất T → `manager_action_required`; R → `manager_action_required` | Không coi là lấy thất bại trước nhận, không xóa custody; manager giải quyết D6, D8. |

### Giao lại miễn phí sau kiểm tra — `redelivery`

Phân biệt với outbound lần 2: đây là hàng của yêu cầu trả bị từ chối sau kiểm
tra. O giữ `delivered`; COD/count outbound giữ nguyên; số tiền task bằng 0.

| ID / căn cứ | Actor, hành động | Tiền điều kiện | Chuyển trạng thái | Tác dụng phụ / quyết định còn mở |
| --- | --- | --- | --- | --- |
| R1 / NV, DB, KH | Manager quyết định từ chối sau kiểm tra, phân công MH15 | R=`under_inspection`; có kết luận; không task return active | R → `awaiting_redelivery`; T mới `pending_assignment` → `assigned` | Chưa dùng R=`rejected_after_inspection` để đóng trước giao lại; lưu quyết định qua event; D9. |
| R2 / KH | Shipper nhận hàng tại cửa hàng | T=`assigned`; đúng hàng/custody của request | T → `accepted`; R giữ `awaiting_redelivery` | Ghi `accepted_at`, custody; không xuất lại stock outbound, không COD. D4, D8. |
| R3 / KH | Shipper bắt đầu giao lại | T=`accepted`, thực nhận đủ hàng | T → `in_transit`; R giữ `awaiting_redelivery` | Ghi `started_at`; không tăng count, không ghi `delivery_attempts`. |
| R4 / NV, KH | Shipper giao lại thành công | T=`in_transit`; khách nhận đủ hàng giao lại | T → `delivered`; R → `rejected_after_inspection` | Ghi kết quả và đóng yêu cầu cùng transaction; không thu COD mới/không giảm COD cũ. D9. |
| R5 / NV, KH | Shipper giao lại thất bại | T=`in_transit`; R=`awaiting_redelivery`; lý do và custody hợp lệ | T → `manager_action_required`; R → `manager_action_required` | Người dùng chốt D9 ngày 28/10/2026; giữ custody, completed_at/closed_at null, không đóng request hoặc tự tạo lần tiếp theo. Chưa có production proof/writer của Sơn. |
| R6 / KH | Shipper báo bàn giao sau thất bại; manager nhận | R5 đã xảy ra; có hàng thực tế | Báo: giữ nguyên trạng thái; nhận: ĐX T → `returned_to_store`, R giữ `manager_action_required` | Không hoàn tất kết quả từ chối; không tự restock. Manager quyết định xử lý/giao lại; D2, D9. |

### Ngoại lệ và quyết định cần phối hợp

R6 ở bảng tổng quan phải tách thành hai chuyển độc lập (ĐX, D2/D9):

| ID | Actor và tiền điều kiện | Chuyển trạng thái | Tác dụng phụ |
| --- | --- | --- | --- |
| R6a | Shipper đang giữ hàng; đã R5; bàn giao thực tế | T/R giữ `manager_action_required` theo mapping đề xuất R5 | Chỉ ghi report event/giờ server; không receipt, không restock. |
| R6b | Manager; có hàng thực tế, đối chiếu custody và số lượng sau R5 | T → `returned_to_store`; R giữ `manager_action_required` | Ghi receipt độc lập; kiểm tra/xử lý tiếp theo D9, không tự đóng yêu cầu. Report không đủ để chứng minh receipt. |

Quy tắc trường lifecycle đề xuất áp dụng cho tất cả bảng trên (cần owner
xác nhận cùng D1/D2/D8/D9): tạo pending để `assigned_*`, `accepted_at`,
`started_at`, `completed_at` rỗng; phân công ghi `assigned_*`; đổi người
trước custody ghi đè `assigned_at` bằng giờ phân công mới, lịch sử cũ phải
được lưu riêng theo D2. `accepted_at` chỉ ghi một lần tại thực nhận;
`started_at` chỉ ghi một lần tại start. `delivered`, `failed`, `cancelled`
ghi `completed_at` khi có kết quả; `failed` ghi `failure_reason`, `cancelled`
ghi `cancel_reason` không rỗng. Không dùng `completed_at` làm receipt:
task `failed` về `returned_to_store` giữ giờ kết quả thất bại, receipt có
mốc riêng D2. Pickup từ `in_transit` về `returned_to_store` ghi `completed_at`
tại receipt. `manager_action_required` chưa là hoàn tất nên giữ
`completed_at` rỗng và ghi lý do trong event; nếu R6b kết thúc task thì ghi
`completed_at` tại receipt. Các lý do đã ghi không bị xóa bởi bàn giao/retry.
Không có mốc inspection trên task hiện tại; D2 phải chốt cách lưu riêng.

Không có chuyển trạng thái ngầm ngoài các hàng trên. Với pickup/redelivery,
đổi người khi T=`assigned` và chưa custody có thể dùng quy tắc O2; hủy trước
nhận, thu hồi phân công, đổi người sau nhận, phục hồi `manager_action_required`
và tình huống thiếu/hỏng/mất không được tự áp quy tắc outbound. Giữ nguyên
dữ liệu, báo manager và chờ hợp đồng tương ứng; không mở quyền RLS để đi vòng.

| Mã | Cần người sở hữu | Quyết định chưa có xác nhận / điều kiện mở tích hợp |
| --- | --- | --- |
| D1 | Bảo + Minh Đức | Xác nhận O1–O4/O12: thời điểm `awaiting_pickup`, ý nghĩa thực nhận của `accepted_at`, mốc chặn hủy, precondition/khóa chung; có cần mốc nhận việc riêng hay không. |
| D2 | Bảo, Sơn + Minh Đức | Cách lưu receipt, inspection, custody, handover event, payload chống trùng, lịch sử shipper cũ/mới và bằng chứng thực nhận; DB chưa có mốc/payload chuyên biệt. Không coi report của shipper là receipt của manager. |
| D3 | Bảo + Minh Đức | Lần 2 giữ hàng ở shipper cũ, chuyển trực tiếp hay bắt buộc qua cửa hàng; ai xác nhận giao/nhận và khi nào được đổi người. Chặn tự động đổi sau custody khi chưa chốt. |
| D4 | Văn Đức + Bảo/Sơn | Dispatch tại O3, hợp đồng tồn/idempotency, khóa đồng nhất; cách ghi nhận hàng lần 2/redelivery không xuất hai lần; receipt khác inspection và chỉ restock lượng đạt. |
| D5 | Bảo | Xác nhận O8/O11, cách lưu nhận trước kiểm tra, hàng thiếu/hỏng/mất và khi nào O kết thúc; hủy task 2 đã tạo nhưng chưa bắt đầu không làm mất custody. |
| D6 | Bảo, Sơn + Minh Đức | Sự cố trước/sau start, hủy sau thực nhận, task đang đi bị gián đoạn: có được ghi result `failed` hay cần chờ manager; không giả lập kết quả khách từ chối để lấp chỗ trống. Count đã start không giảm. |
| D7 | Bảo | Event/recipient/thời điểm thông báo ở từng hàng, mở deep link kiểm tra lại quyền; không nhúng dữ liệu riêng tư. |
| D8 | Sơn + Minh Đức; Văn Đức cho phần tồn | Chốt P1–P7: hàng/số lượng thực nhận, thiếu/sai món, start riêng hay gộp nhận hàng, pickup thất bại/hẹn lại, receipt/inspection, đổi người/hủy trước nhận và cách giữ custody. Không bắt khách trả món chưa nhận. |
| D9 | Sơn + Minh Đức | Người dùng đã chốt mapping R4/R5 và giao bổ sung primitive: T/R manager_action_required khi thất bại, active slot/custody giữ nguyên; thành công mới rejected_after_inspection/closed_at. Receipt/inspection/release plan/accept/start đã production theo báo cáo mới; manager resolution/mở lại task sau failure và UI MH15 còn riêng, không suy ra agreement của Sơn. |
| D10 | Nhóm / người giữ báo cáo | Cung cấp báo cáo v3.0 và file đính kèm còn thiếu để kiểm tra trực tiếp quy tắc/mã NT; không ghi nhận stakeholder agreement chỉ từ kế hoạch. |

Lưu ý DB: unique active outbound chỉ bao gồm `pending_assignment`, `assigned`,
`accepted`, `in_transit`; unique active return còn bao gồm
`manager_action_required`. `failed` không giữ slot active, nên DB có thể cho
tạo task mới dù custody cũ chưa giải quyết. R5 theo đề xuất giữ slot return;
API tương lai phải chặn tạo mới đến khi manager xử lý và kết thúc task cũ.
Constraint không tự bảo vệ thứ tự chuyển trạng thái hoặc lịch sử bàn giao.

P00.1 đã có bảng đặc tả để review; **chưa là hợp đồng được các owner thống
nhất** và chưa xác minh trực tiếp báo cáo gốc. Không đánh dấu Phase 0 tổng
thể hoặc tích hợp live hoàn tất. Các phase API, migration, UI, map và test
runtime nằm ngoài thay đổi tài liệu này.

## P02.1 — Nhóm trạng thái truy vấn MH10

Mapping dưới đây chỉ phục vụ bộ lọc/count của API đọc danh sách; không đổi
enum, lifecycle, custody hoặc kết luận nghiệp vụ của order/return request.
Đây là quyết định triển khai query trong P02.1, không ghi nhận Bảo/Sơn/Văn Đức
đã duyệt các chuyển trạng thái còn mở tại P00.1.

| Nhóm query | Task status được bao gồm | Ý nghĩa giới hạn |
| --- | --- | --- |
| `waiting` — Chờ | `assigned`, `accepted` | Đã phân công, chưa bắt đầu vận chuyển; accepted không bị đồng nhất với assigned về custody. |
| `in_transit` — Đang đi | `in_transit` | Task đang vận chuyển. |
| `completed` — Hoàn tất | `delivered`, `returned_to_store` | Task đã giao xong hoặc đã được ghi nhận về cửa hàng; không suy ra inspection/refund/restock đã xong. |
| Không thuộc ba nhóm (`ungrouped` trong counts) | `pending_assignment`, `failed`, `cancelled`, `manager_action_required` | Vẫn xuất hiện khi không lọc nhóm; không tự coi thất bại/hủy/chờ xử lý là hoàn tất. |

Không lọc nhóm nghĩa là toàn bộ task projection được phép đọc, bao gồm
history/restricted tối thiểu của P01.1. Không suy quyền lịch sử từ task từng
được phân công: đổi cùng task sang shipper khác/null thu hồi row người cũ.
Snapshot history không chứa mã UUID đơn hoặc tên người nhận để tìm kiếm;
search không được dùng dữ liệu ẩn để làm lộ quan hệ qua counts/kết quả.

## COD

cod_collections.status tách khỏi trạng thái đơn:

uncollected → collected → received

expected_amount_vnd là toàn bộ orders.total_cod_vnd. Khi chuyển sang collected,
số tiền thu phải đúng toàn bộ số dự kiến; khi chuyển sang received, số tiền cửa
hàng nhận cũng phải đúng toàn bộ. Schema không có trạng thái bàn giao một phần
và việc hoàn tiền không làm giảm nghĩa vụ COD. received_by là người quản lý
xác nhận cửa hàng đã nhận đủ tiền.

## Yêu cầu trả hàng

return_requests.reason chỉ nhận wrong_item, missing_items hoặc defective.
video_object_path bắt buộc có ngay trên yêu cầu.

return_requests.status mô tả các mốc:

| Giá trị | Ý nghĩa |
| --- | --- |
| pending_review | Khách đã gửi yêu cầu, lý do, mô tả, video và thông tin nhận hoàn; chờ manager xem xét. |
| initially_rejected | Từ chối ban đầu, hàng vẫn ở khách và yêu cầu kết thúc nhánh này. |
| awaiting_return_pickup | Manager đồng ý tổ chức thu hồi, chưa kết luận hoàn tiền. |
| returning_to_store | Shipper đã nhận hàng thực tế và đang đưa về cửa hàng. |
| under_inspection | Manager đã nhận hàng và đang đối chiếu số lượng, tình trạng, video và yêu cầu. |
| awaiting_refund | Hàng phù hợp, chờ manager chuyển khoản ngoài ứng dụng và lưu bằng chứng. |
| refunded | Đã ghi nhận hoàn đủ tiền hàng và phí giao ban đầu. |
| rejected_after_inspection | Kết quả từ chối sau kiểm tra, chỉ ghi nhận như trạng thái kết thúc sau khi khách đã nhận lại hàng qua redelivery miễn phí. Trong thời gian chờ giao lại dùng awaiting_redelivery; nếu giao lại thất bại dùng manager_action_required. |
| awaiting_redelivery | Đang chờ giao lại miễn phí cho khách, không thu COD lần hai. |
| redelivery_failed | Enum có trong schema nhưng không được chọn cho nhánh P08.3; mapping D9 người dùng chốt dùng manager_action_required. |
| manager_action_required | Có vấn đề cần manager xử lý tiếp, không tự đóng yêu cầu. |

Mỗi đơn chỉ có một yêu cầu trả đang hoạt động. return_items luôn gắn với cùng
order_id của return_request; order_item_id và variant_id có thể rỗng để ghi
nhận hàng thực tế giao sai hoặc hàng thiếu không cần khách trả lại. Chỉ hàng
thực tế thu được mới được chia thành sellable_quantity và damaged_quantity;
không coi việc duyệt lấy hàng là duyệt hoàn tiền.

return_requests giữ video ban đầu trong video_object_path, video bổ sung trong
additional_video_paths và bằng chứng kiểm tra trong
inspection_evidence_paths. Các mảng không được chứa phần tử rỗng.

Thông tin ngân hàng nằm trực tiếp trên return_requests. bank_name,
account_number và account_holder có thể cùng rỗng trước khi hoàn tiền hoặc
phải cùng đầy đủ. refund_amount_vnd, refunded_by, refunded_at,
transfer_evidence_path và refund_request_id cũng có thể cùng rỗng trước khi
hoàn tiền; khi đã ghi hoàn, cả gói bắt buộc đầy đủ, số tiền dương và
refund_request_id duy nhất. Số tiền hoàn dự kiến là toàn bộ tiền hàng cộng phí
giao ban đầu; policy đọc bằng chứng phải giới hạn cho manager và khách của đơn.

## Sự kiện và thông báo

business_events lưu đối tượng, trạng thái trước/sau, actor, lý do và thời điểm.
Sự cố giao hàng dùng cùng bảng với incident_kind, task_id và request_id duy
nhất. Một event sự cố bắt buộc có task, actor, request_id và lý do không rỗng.
Manager đọc toàn bộ event; sau P01.1 shipper không đọc raw event sự cố hay
bàn giao. ACK/replay cần contract response/projection an toàn riêng.
notifications tham chiếu sự kiện và có khóa duy nhất (recipient_id, event_id),
nên một sự kiện xử lý lại không tạo thông báo trùng cho cùng người nhận.
read_at thuộc từng notification/người nhận.

Mở một notification vẫn phải kiểm tra quyền hiện tại trên đối tượng liên quan;
RLS không được thay bằng kiểm tra ở giao diện.

## Chat

Mỗi customer có nhiều nhất một conversations. Chat chỉ giữa customer và
manager; shipper không tham gia. messages.body không được rỗng và
(sender_id, client_message_id) là khóa chống gửi trùng khi mất kết nối. Danh
sách tin có thứ tự xác định bằng (conversation_id, created_at, id).

conversations.read_at_by_user là JSON object với khóa là UUID người đọc. Chỉ
customer của conversation hoặc manager được cấp quyền update riêng cột này;
không có quyền insert read marker. Trigger invoker bỏ qua JSON client gửi lên,
dùng giá trị cũ và jsonb_set tại khóa auth.uid() với clock_timestamp() của
server, giữ nguyên các khóa của người dùng khác. Cập nhật chỉ marker không làm
đổi updated_at của conversation; các cập nhật nghiệp vụ thật vẫn dùng trigger
updated_at chung.

## Cửa hàng và tọa độ

store_settings là bảng singleton với khóa boolean phải là true. Tên là dữ
liệu bắt buộc nhưng chưa seed cửa hàng, địa chỉ, tọa độ hoặc
approved_service_area_geojson. Tọa độ giao/điểm cửa hàng luôn phải đi theo cặp
latitude/longitude và nằm trong miền hợp lệ. Việc xác minh vị trí thuộc Hà Nội
và vùng phục vụ được thực hiện phía server khi đặt đơn; migration nền không tự
tạo tọa độ hoặc boundary giả.

## Orders/Notifications owned design revision1.2 — chưa triển khai

Owner Bảo đã ủy quyền chốt kỹ thuật phạm vi MH07/08/09/17. [Main Specification](technical_specification_mh07_mh08_mh09_mh17.md), [Data/API normative](technical_specification_mh07_mh08_mh09_mh17_data_api.md), [Final Decisions](Final_Technical_Decisions.md), [Cross Contracts](Cross_Module_Integration_Contracts.md) và [Readiness](Implementation_Readiness_v1.2.md). Owned shapes/RPC/receipt/metadata/query/UI design OWNER DECIDED — PROPOSED IMPLEMENTATION; không ghi tables/RPC mới là existing, không thay enum hay grants hiện tại. FullUUID/no humanordercode, snapshotplaceholder, safeCustomerprojection không mở rawtasks/events RLS; main4role routes proposed centralrouter. CIN01–09 external contractoffers NOT ACCEPTED/NOT IMPLEMENTED; recommendedtask2samecustody/inspection cần ownerDelivery/Inventory xác nhận. Businesslost/partialclosure/transferafterpickup/7dayedge chưa quyết. Nội dung baseline của module khác giữ nguyên; currentowned definitions ở revision1.2, schema/runtime baseline vẫn three existingmigrations.

## P03.3 — Quyết định phạm vi phân công outbound đầu tiên (24/10/2026)

Người dùng trực tiếp chốt trong phiên triển khai: phân công lần đầu từ
`preparing` sang `awaiting_pickup` đồng thời là manager xác nhận hàng sẵn sàng;
chỉ đổi shipper trước nhận hàng; chỉ tạo/cập nhật COD sạch ở `uncollected`;
chặn lần giao hai và đổi người sau nhận hàng. Đây là quyết định của người dùng,
không ghi nhận Bảo, Sơn hoặc Văn Đức đã xác nhận.

Quyết định này thay phần còn mở của D1 cho O1/O1b trong phạm vi outbound đầu
tiên và phần S3 về khởi tạo nghĩa vụ COD. Không thay O3/O4: phân công chưa là
thực nhận, start, xuất tồn hay tăng delivery_attempt_count. Không ghi
delivery_attempts khi phân công hoặc đổi người. Task có attempt_number=1;
count vẫn 0. D3 về custody/lần hai, D4 inventory, các hợp đồng nhận/start,
hủy và notification vẫn cần owner liên quan quyết định/triển khai.

| Actor / thao tác | Điều kiện server | Chuyển trạng thái / tác động |
| --- | --- | --- |
| Manager tạo và phân công | Order preparing, count=0; chưa có attempt/custody; không outbound active; target shipper hợp lệ | Tạo outbound assigned số 1, O awaiting_pickup; snapshot điểm nhận từ order; task amount=COD expected=order total; COD uncollected |
| Manager phân công task pending đã có | Order preparing, exact expected task pending_assignment chưa có người/custody | Task assigned, O awaiting_pickup; đồng bộ COD sạch; không tạo task thứ hai |
| Manager đổi người | Order awaiting_pickup, exact expected task và expected shipper; task assigned chưa nhận/start/kết quả; COD sạch | Giữ task/số lần, đổi assigned_shipper_id và COD shipper; audit old/new; người cũ mất quyền current ở lần fetch tiếp theo |
| Manager gửi lại cùng request | Actor vẫn manager, toàn bộ payload giống request thành công | Trả kết quả lệnh đã lưu, không thêm task/audit hay đổi assignment; kết quả replay không là snapshot quyền hiện tại |
| Nhận hàng/lần hai/COD đã thu | Có custody/attempt hoặc COD không sạch | Từ chối; không sửa lịch sử, count, tài chính hoặc dispatch để hợp thức hóa dữ liệu |

Hai manager tạo đồng thời chỉ một lệnh tạo thành công. Reassignment phải gửi
expected task/shipper để phát hiện thao tác cũ; không dùng last-write-wins.
Không mở lịch sử PII cho shipper từ audit manager này.

## P04.1 — O3/O4 chưa có transaction tích hợp

Yêu cầu phase hiện tại xác định accept là thực nhận + dispatch và start mới
tăng count; không phải bằng chứng các RPC/primitive đã tồn tại. Người dùng
xác nhận dependency inventory/cancel chưa có (24/10/2026). O3/O4 vẫn là target
contract, chưa live. Không chuyển assigned→accepted hoặc accepted→in_transit
bằng fixture; không tạo attempt result trước khi kết thúc.

D2 custody proof, D3 custody lần hai, D4 inventory transaction và S2/S4 ledger/
version vẫn mở. Không tự suy task số 2 được accept từ việc nó assigned hoặc
không có active task khác. P03.3 chỉ phân công đầu tiên trước custody vẫn giữ.
Bộ fixture P04.1 fail-closed không chốt phương án các owner và không chứng minh
race hủy/nhận hoặc exactly-once dispatch đã được thực thi.

Demo cô lập bổ sung theo yêu cầu người dùng chỉ minh họa O3/O4/O12; role,
custody/dispatch proof và cùng holder lần hai là dữ liệu/logic mô phỏng trong
p041_demo. Không là quyết định D2/D3/D4 hoặc transaction thật của các owner.
Xem [hướng dẫn demo](demos/p041_outbound_demo.md); trạng thái live vẫn bị chặn.

## P04.2 — Không thêm transition live

Command/eligibility draft và action harness chỉ phục vụ kiểm thử thứ tự O3/O4,
không thay trạng thái hay custody của database. Scope fixture chỉ outbound lần
đầu; không suy D3 lần hai đã chốt từ demo P04.1. RPC O3/O4 vẫn chưa tồn tại,
không dispatch/start/attempt result mới trong phase này. Xem handoff P04.2 ở
api_contracts.md; không ghi nhận stakeholder agreement mới.

## P05.1 — O5 còn bị chặn live

O5 yêu cầu task/order delivered + một success attempt + COD collected và event/
notification nguyên tử, count không tăng ở completion. SQL fixture P05.1 chỉ
kiểm tra mô hình này với custody/recipient giả định test; không là transaction
live hoặc agreement D4/D7/S2/S3. Actor/amount lấy từ server fixture, không tin
shipper/order total caller; thu thiếu không được coi collected.

Contender failed-result test chỉ kiểm tra loại trừ success/failed cho cùng
attempt, không định nghĩa quy tắc thất bại hoặc triển khai O6/O9. Không tự suy
P04.1/P04.2 đã hoàn tất từ fixture. Chi tiết ở api_contracts.md P05.1.

## P05.2 — Không thêm transition live

Confirmation UI fixture không thay O5/task/order/COD; backend amount vẫn là
nguồn chuẩn, received-full là xác nhận chứ không chứng minh server đã ghi.
Không tăng attempt, dispatch, thu COD hoặc ghi delivered từ local state.
Không thay quyết định D7 hoặc các dependency P05.1; live vẫn bị chặn.

## P06.1 — COD list không tạo chuyển trạng thái

Read MH12 giữ uncollected → collected → received. Outstanding chỉ gồm khoản
collected, với nguyên collected_amount_vnd chưa received; uncollected không
là tiền đang giữ, received không còn outstanding. Tổng độc lập status tab và
pagination, nhưng tuân scope role/shipper/order. Returns/refunds không trừ
khoản này, không đổi status hoặc collector. Không có RPC confirm receipt hoặc
completion được thêm ở phase đọc; các dependency write trước đó vẫn còn.

## P06.3 — Manager thực nhận đủ COD

Người dùng chốt receipt contract ngày 25/10/2026; không là approval của owner
khác. Chỉ manager hiện tại xác nhận collected sạch, đủ expected=collected=
amount thực nhận. Chuyển COD collected → received, received_amount đủ nguyên,
received_by=manager auth và received_at=handed_over_at giờ server. Không đổi
order/task/return state, không giảm collected/expected hoặc offset refund.

Một receipt/order. Same manager/request/payload trả lại kết quả; mismatch hoặc
request mới sau receipt bị conflict. Event/notification chỉ holder và ledger
receipt atomic. Shipper không tự xác nhận, kể cả gọi RPC trực tiếp. Chưa áp
dụng transition này vào UI manager hoặc coi completion live đã có.

## P07.1 — Outbound failure dependency boundary (26/10/2026)

Audit chín migration: chưa có public `fail_delivery_task`, accept/start hoặc
`complete_outbound_delivery`. P04.1/P05.1 chỉ fixture cô lập; không dùng dữ
liệu in_transit seed làm bằng chứng custody/dispatch thật. Theo stop rule,
chỉ thêm interface SQL temporary fail-closed và dependency tests; không đổi
migration, enum, RLS/grants, API runtime hoặc UI MH11.

Mapping mục tiêu O6/O9 giữ đúng enum: outbound `in_transit` → `failed`;
order `delivering` → `awaiting_redelivery` ở lần 1, → `awaiting_store_return`
ở lần 2. Chỉ khi có kết quả mới ghi một `delivery_attempts.failed`, giữ count,
không thu COD/restock/nhận hoàn. Chưa thực thi các chuyển này trong P07.1.

Lý do draft: unreachable/reschedule/bad_address/refusal/other; other cần mô tả.
Cách lưu code/description vào text reason, ledger/version và response/error
live còn cần chốt. Bảo cần chốt recipient/event thất bại D7; quyết định P06.3
chỉ áp dụng COD receipt, không là approval cho failure. Văn Đức/Bảo cần
custody/dispatch P04.1 và D3 lần hai; success/failure cần cùng khóa và ledger
để nghiệm thu race thật. Không triển khai return_pickup/redelivery failure.

[Manifest, contract mục tiêu, kiểm tra và blockers](demos/p071_outbound_failure_boundary.md).
P07.1 **chưa hoàn tất / live BLOCKED**; dependency fixture không trả success
và không thay thế acceptance tests của RPC thật.
## P07.2 — Manager retry/reassignment/custody: live BLOCKED (26/10/2026)

Đã audit chín migration và contracts: `assign_delivery_task` P03.3 có thật,
chỉ outbound đầu tiên và đổi trước nhận hàng, chặn count>0/lịch sử attempt/
custody. Không nới API này. `decide_outbound_retry` và custody transfer vẫn
chưa có; P07.1 failure và P04.1 dispatch/start thật cũng chưa có.

Theo stop rule chỉ thêm hai pg_temp interfaces test-only, luôn
DEPENDENCY_NOT_READY sau validation; không có success, mutation hay manager/
custody enforcement runtime. Bổ sung regression gọi RPC assignment hiện có
khi count=2 bằng hai manager/shipper/request khác nhau: phải ATTEMPT_LIMIT,
không sửa lịch sử/số lần/tồn. Đây không là nghiệm thu retry/start lần hai.

Manager có hai lựa chọn mục tiêu sau failed lần 1: tạo task mới số 2 hoặc
order awaiting_store_return để hoàn sớm. Count chỉ tăng tại start, giữ task/
attempt/dispatch cũ; assignment không xác nhận physical receipt. D3 còn chờ
Bảo/Minh Đức chọn giữ hàng/chuyển trực tiếp/qua cửa hàng và proof của Văn Đức;
D5 xử lý task 2 đã tạo nhưng chưa start; ledger/version/custody và D7 chưa
được chốt cho retry. Không tự coi demo là approval hoặc live integration.

[Manifest, contract mục tiêu và kiểm tra P07.2](demos/p072_outbound_retry_boundary.md).
Không migration/RPC public/RLS/UI/router mới; P07.2 **chưa hoàn tất**.
## P07.4 — Store handover/incident dependency boundary (26/10/2026)

Chín migration hiện có chưa có report_store_handover/report_delivery_incident.
Actual enum incident là damaged/lost/other; lưu trong business_events, không
còn bảng delivery_incidents. Sau P01.1 chỉ manager đọc raw events; không mở
RLS shipper để giải quyết retry. Unique event request_id toàn bảng không là
ledger đối chiếu actor/operation/payload/result.

Theo stop rule chỉ thêm hai pg_temp interfaces test-only luôn lỗi
DEPENDENCY_NOT_READY sau validation/auth. Handover signature draft chưa có
items/proof và không bao giờ success; không phải API nhận bàn giao finalized.
Bổ sung test schema/RLS thật bằng privileged event seeds: loại incident,
required actor/task/request/reason, subject match, không ghi result thất bại
hoặc đổi task/order/COD/return/tồn; report chung không giả incident.

Mục tiêu report giữ trạng thái, không manager receipt/inspection/restock hoặc
bồi thường tự động. Outbound O10, pickup P5 và redelivery R6a cần D2/D5/D8/D9
custody/items/allowed-state contracts; incident D6 cần ma trận theo kind/state.
Bảo cần chốt manager recipient/deep link D7; S2 cần ledger/event payload/replay
an toàn. Quyết định COD P06.3 không chốt các dependency này. Không tự chọn
all managers hoặc coi assignment là physical custody.

[Manifest, contract mục tiêu, lệnh/kết quả và blockers P07.4](demos/p074_delivery_reporting_boundary.md).
Không migration/public API/grant/RLS/UI mới; P07.4 **live BLOCKED, chưa hoàn tất**.
## P04.1 — Production accept/start, bổ sung ngày 26/10/2026

Người dùng đã chốt triển khai primitive xuất kho/custody cùng hai RPC; lần hai
chỉ cùng shipper còn giữ đủ hàng, chặn đổi người sau nhận. Đây là quyết định
người dùng, không tự ghi teammate approval. Phần P04.1 BLOCKED/demo ở trên là
lịch sử trước implementation này; không dùng fixture làm backend live.

Migration mới `20261026055651_accept_start_outbound_delivery.sql` định nghĩa
public.accept_delivery_task(p_task_id uuid,p_request_id uuid) và
public.start_delivery_task(p_task_id uuid,p_request_id uuid), returns jsonb.
Accept thực nhận/dispatch/proof nguyên tử, count chưa tăng; start xác minh
proof rồi tăng count tối đa 2, không xuất lại hoặc ghi result attempt.

Reservation phải có movement chứng minh của chính đơn, khớp toàn bộ server
order_items; thiếu evidence bị từ chối. Private immutable dispatch/custody và
request ledger riêng; role/assignment recheck cả replay. Không client write
permission mới. DB guard chống hủy sau custody, không giả có RPC hủy của Bảo.
Second accept/start không tạo task2; P07.2 manager retry và P07.1 failure vẫn
chưa có production endpoint. Không notification D7 chưa chốt hoặc UI P04.2.

[Contract, schema, kiểm thử và trạng thái deploy P04.1 production](demos/p041_production_accept_start.md).
Implementation repository không đồng nghĩa đã deploy/Auth/PostgREST/cloud;
không tự đánh dấu toàn bộ MH11 hoặc luồng giao→COD hoàn tất.
### P04.1 — Kết quả deploy cloud 26/10/2026

Sau khi người dùng duyệt project `bqoyfytmrtvjwrpshuhh` và đăng nhập CLI,
đã deploy các migration pending và hai RPC accept/start production. Đã thêm
migration `20261026062903_secure_internal_auth_identity_bridge.sql` sửa đặc
thù managed Auth schema bằng helper private chỉ trả auth.uid cho internal
roles; không grant quyền client/bảng Auth hoặc membership authenticated.

11 migration local/remote khớp. Native 13 SQL suites +3 nhóm concurrency PASS;
8 scoped SQL suites cloud PASS, gồm accept/start, read, assignment và COD.
HTTP PostgREST hai RPC từ chối caller không đăng nhập bằng 401/42501. Mọi SQL
fixture cloud rollback; profile/order/private proof/request/test Auth users
không tồn dư. Không reset/xóa catalog cloud để ép baseline test PASS.

Hai RPC backend đã có và đã test cloud; chưa positive JWT/UI end-to-end,
không tự bật P04.2 MH11. P05/P07 write APIs còn thiếu vẫn không được coi hoàn
tất. Chi tiết tệp/lệnh/kết quả/giới hạn tại
[demos/p041_production_accept_start.md](demos/p041_production_accept_start.md).
## P04.2 — Presentation production (26/10/2026)

MH11 đã bật xác nhận thủ công assigned → accepted và accepted → in_transit cho outbound current theo P04.1. UI không tự chuyển state; chỉ hiển thị kết quả đọc lại server. Attempt hai vẫn phải qua custody/stock guards ở server. Các mục P04.2 chưa bật live phía trên là lịch sử trước adapter production.

Chi tiết phạm vi, retry, kiểm thử và giới hạn live: [P04.2 production](demos/p042_production_outbound_actions.md).

## P05.1/P05.2 — O5 production đã triển khai (26/10/2026)

Thay kết luận P05 fixture-only trước đây. O5 chỉ shipper đang giữ đầy đủ hàng và được gán task outbound in_transit, order delivering, accepted/start/count/attempt/proof đúng, chưa có result; khách nhận đủ và thu đủ server COD. Một transaction ghi task/order delivered + một delivery_attempts success + COD collected + event delivery_completed và thông báo khách/các manager hiện tại. Count đã tăng ở start, không tăng ở completion; không xuất lại tồn, không ghi store receipt. Hỏng/mất/proof sai chặn completion.

User đã chốt ledger/notification cho completion, không phải stakeholder agreement được suy diễn. Return/refund sau này không xóa COD obligation. MH11 production hai checkbox và refetch authoritative; failure/retry/return mutations P07 vẫn ngoài phạm vi. [Contract và kết quả live](demos/p051_p052_production_outbound_completion.md).

## P06.1–P06.4 — Nghiệm thu live 27/10/2026

Các ghi chú P06 trước đây “chưa deploy/chưa nghiệm thu cloud” là mốc lịch sử. Đã nghiệm thu real Auth/JWT + CodRoutePage shipper/manager + production repositories/RPC trên project bqoyfytmrtvjwrpshuhh: phân trang hơn100 records, own-only/manager UUID filters, full receipt550.000, lost-ACK retry giữ key, simultaneous managers chỉ một receipt, COD không offset refund, và account-switch cache cleanup. Hai cloud SQL suites P06 PASS/ROLLBACK. Sửa one-shot latch dialog chống double pop; không migration/RLS/API mới.

Cleanup xác nhận không còn fixture accounts/orders/COD/returns/receipts/notifications; giữ3products có sẵn. Live là Flutter widget runner nối cloud, chưa điện thoại vật lý/MH17 renderer. Phạm vi/lệnh/manifest, fixture phân trang có nhãn và kết quả chi tiết: [P06 live acceptance](demos/p06_live_acceptance.md).

## P07.1 — Outbound failed result (27/10/2026)

O6/O9 dùng đúng bộ đếm đã tăng tại start: current shipper + outbound in_transit/order delivering + custody/proof + sạch COD uncollected. Ghi một failed result, task failed/completed_at. Lần1 order awaiting_redelivery chờ chủ cửa hàng; lần2 awaiting_store_return. Không tăng/reset count, thu tiền, tạo task2, xuất/nhập tồn hoặc coi cửa hàng đã nhận hàng. Mã lý do riêng, other cần mô tả; event delivery_failed và thông báo chung chỉ chủ cửa hàng có role manager (người dùng làm rõ manager là store owner), không gửi khách. Không suy ra stakeholder approval.

P07.2 quyết định retry/return, P07.3 dialog và P07.4 handover/incident vẫn riêng; tests task2 có nhãn fixture không chứng minh luồng retry đã tích hợp. [Bản production và nghiệm thu](demos/p071_production_outbound_failure.md) là mốc mới thay blocker P04/P05 cũ trong mục P07.1.

## P07.2 — O7/O8 và D5 (27/10/2026)

Người dùng chốt: sau failed1, chủ cửa hàng chọn retry sẽ tạo task2 assigned cùng holder và order awaiting_pickup. Assignment không tự tạo accepted_at/custody; shipper phải xác nhận tiếp tục giữ đủ hàng bằng accept rồi mới start. Count chỉ tăng1→2 ở start, dispatch không lặp. Hoàn sớm trực tiếp giữ task1 failed/custody; đổi retry sang hoàn chỉ trước start, kể cả task2 accepted: task2 cancelled, giữ custody/accepted_at và lịch sử, order awaiting_store_return; không ghi attempt2 nếu chưa start. Sau start2 không đổi quyết định; không lần3/đổi shipper sau nhận hàng.

Đây là quyết định người dùng, không suy ra approval của Bảo/Văn Đức. Manager receipt/inspection/restock D5 còn riêng; không coi quyết định hoàn là đã nhận hàng. [Bảng transition và nghiệm thu P07.2](demos/p072_production_outbound_retry.md) là mốc mới cho O7/O8 và phần D3/D5 đã chốt; pickup/redelivery không áp dụng giới hạn outbound này.

## P07.4 — Report khác receipt (27/10/2026)

Người dùng chốt outbound report: failed hoặc task2 cancelled do hoàn sớm + order awaiting_store_return mới báo bàn giao full goods; vẫn giữ task/order và custody ledger. Manager receipt/inspection/restock là riêng, chưa thực hiện bởi report. Incident sau custody ở accepted/in_transit/failed hoặc cancelled task2 đang chờ hoàn; ghi damaged/lost/other và lý do, không delivery_attempts failed/COD/compensation. Thông báo chỉ chủ cửa hàng. Damage đủ số lượng không cản báo bàn giao; lost không thể khai đã bàn giao toàn bộ đến khi có xử lý manager riêng. Pickup/redelivery chưa có custody contract nên từ chối, không suy ra D8/D9. [Bảng transition và kiểm thử](demos/p074_production_delivery_reporting.md).
