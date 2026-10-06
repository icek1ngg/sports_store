# Trạng thái nghiệp vụ

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
business_events. Shipper chỉ đọc được sự cố của nhiệm vụ đang được phân công
cho chính mình.

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
| redelivery_failed | Giao lại thất bại, yêu cầu còn chờ quyết định của manager. |
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
Manager đọc toàn bộ event; shipper chỉ đọc event sự cố của nhiệm vụ đang được
phân công.
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
