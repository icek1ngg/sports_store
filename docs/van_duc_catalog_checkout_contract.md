# Hợp đồng catalog đặt hàng và tồn kho của Văn Đức

> Phiên bản triển khai 27/10/2026: xem [bàn giao MH04–MH16](van_duc_completion.md)
> và mục MH16 trong `api_contracts.md`. Phần đề xuất bên dưới là lịch sử thiết kế;
> không diễn giải thành xác nhận đồng thuận từ chủ sở hữu Orders/Delivery.

Ngày 24/10/2026. Phần catalog là hợp đồng triển khai MH04/MH05 trong thay đổi
này. Phần checkout/tồn kho là quyết định thiết kế phía Văn Đức để bàn giao;
RPC chưa được triển khai và chưa được Bảo/Minh Đức xác nhận tích hợp.
Không suy diễn tài liệu hợp đồng thành endpoint đã có trên cloud.

## Cơ sở đối chiếu

- `origin/main` tại `c0a5100`: schema 18 bảng và projection giao hàng đã được gộp.
- Nhánh Bảo `feature/orders-notifications-phase2` tại `9d7e746`:
  `docs/Cross_Module_Integration_Contracts.md`, CIN-02, CIN-04, CIN-07, CIN-09;
  model `Order`, `OrderItem` và `OrderRepository` trong feature orders.
- `docs/api_contracts.md`: hợp đồng giao hàng/COD, thứ tự khóa L và ledger bridge.
- Báo cáo nhóm: BR-COM-04–11, BR-COM-36; phần mua hàng 2.10.

## Catalog đã triển khai

| Thành phần | Hợp đồng |
| --- | --- |
| Model sở hữu bởi catalog | `Category`, `Product`, `ProductVariant`, `CatalogQuery`, `CatalogPage` |
| Repository | `CatalogRepository.getCategories()`, `getProducts(query)`, `getProduct(id)`, `getImageUrl(path)` |
| Route MH04 | `/customer/products` |
| Route MH05 | `/customer/products/:productId`; UUID đầy đủ, không hardcode |
| Quyền màn hình | Customer, kiểm tra `profiles.role` từ server; shipper/manager không mở route khách |
| Quyền repository | Customer/manager đọc theo RLS; hỗ trợ An tái sử dụng catalog data contract |
| Dữ liệu | `categories`, `products`, `product_variants`; lọc active rõ ràng |
| Ảnh | `products.image_path` là object path trong private bucket `product-images`; signed URL ngắn hạn |
| Giá | `int` VND theo biến thể; giá nhỏ nhất của biến thể active trên danh sách; null nếu chưa có biến thể |
| Tồn | `available_quantity` server = `on_hand - reserved`; số lượng xem không giữ tồn |
| Tìm kiếm | Từ khóa literal theo tên, không coi `%`, `_` do người dùng nhập là wildcard |
| Phân trang | 20 sản phẩm/trang, thứ tự name + UUID; có trang tiếp theo nếu đọc được dòng thứ 21 |
| Phiên | Dùng data contract `OperationalReadAccess` hiện có trong main; đổi/thoát/hết phiên hủy dữ liệu cũ |

Domain không phụ thuộc Flutter/Supabase. View gọi ViewModel; data repository
dùng client chung. Catalog không truy cập ViewModel của delivery/orders.
Vị trí hiện tại của access helper do nền main quy định; khi Auth của An cung cấp
contract chung, thay provider ở điểm tích hợp, không xây một client thứ hai.

An mở rộng cùng Product/Variant khi làm MH03, không tạo bản model khác trong
auth hoặc manager tree. Bảo có thể mở route MH05 bằng `product_id` trong snapshot;
catalog không được ghi đè tên/giá lịch sử của `OrderItem`.

MH06 được nối ở mốc tiếp theo ngày 24/10/2026: `/customer/cart`,
CartRepository đọc/sửa/xóa giỏ riêng và MH05 gọi CartViewModel để thêm thật.
Contract đầy đủ nằm tại [API MH06](api_contracts.md). Giỏ chưa đặt/giữ tồn;
MH16 vẫn chưa triển khai.
MH01 chưa thuộc mốc này: `tool/catalog_live/` chỉ cung cấp cách đăng nhập thật để thử.

## Checkout phía Văn Đức chọn bám CIN-02 của Bảo

Tên và chữ ký dưới đây là đề xuất để đối chiếu với consumer của Bảo; cần Bảo xác nhận trước khi triển khai MH16:

```text
place_order(
  p_request_id uuid,
  p_items jsonb,
  p_recipient_name text,
  p_recipient_phone text,
  p_address_detail text,
  p_latitude numeric,
  p_longitude numeric
)

p_items = [{variant_id: UUID, quantity: positive integer}, ...]
```

Khách phải đăng nhập. Server lấy customer ID từ `auth.uid()`, kiểm tra role
server-managed; không nhận customer ID, giá, tổng tiền hoặc phí từ client.
Mảng hàng không rỗng, không trùng variant; chuẩn hóa thứ tự variant trước khi
tính fingerprint. Lưu request ID/payload ổn định khi retry, kể cả sau timeout.

Kết quả thành công dự kiến dùng envelope `{ok:true,data:{order,items,event_id,replayed}}`:

- `order` dùng đúng `OrderDto` của orders, `items` dùng `OrderItemDto[]` của Bảo.
  Phía checkout không tạo bản Order thứ hai. Model chính thức được tích hợp khi
  code orders được review/gộp; tài liệu này chưa copy model vào nhánh hiện tại.
- `event_id` là event `order_placed` chuẩn, `replayed` xác định retry cùng kết quả.
- Trạng thái ban đầu `pending_confirmation`; tiền VND nguyên; thời gian server.
- Điều hướng MH07 bằng `order.id`; yêu cầu tải lại list/detail từ repository.
  Route MH07 chính thức vẫn do Bảo và router owner thống nhất.

Lỗi dự kiến map theo CIN-02: `invalid_argument`, `insufficient_stock`,
`outside_service_area`, `idempotency_conflict`, `forbidden_or_unavailable`,
`external_dependency_unavailable`. Network/timeout là kết quả chưa biết, không
hiển thị thành công và không đổi request ID. Transport/envelope lỗi cần Bảo
xác nhận cùng adapter trước khi triển khai RPC.

`get_placement_result(p_request_id uuid)` dự kiến chỉ tra kết quả thuộc khách
hiện tại. `committed` trả order/items/event; `not_found` không chứng minh request
trước đã rollback. Cùng ID khác payload bị từ chối. Quyền phải kiểm tra lại
trước khi replay kết quả; không trả dữ liệu của tài khoản trước.

## Transaction đặt hàng

1. Xác thực và claim khóa idempotency theo customer/request ID, đối chiếu payload.
2. Kiểm tra người nhận, địa chỉ chi tiết và tọa độ nằm trong vùng Hà Nội đã được
   nhóm xác nhận. Thiếu dữ liệu vùng giao thì từ chối; không dùng bounding box
   rộng hoặc chữ “Hà Nội” làm bằng chứng duy nhất.
3. Khóa các variant theo UUID tăng dần; kiểm tra active, giá và đủ tồn mọi món.
4. Trong cùng transaction: tạo order/items snapshot, tăng reserved, ghi ledger,
   event và thông báo cho manager theo CIN-09, lưu kết quả idempotency.
5. Một món không đủ tồn hoặc ghi event/notification lỗi thì rollback toàn bộ.

Giữ phí giao 30.000 VND. Snapshot chứa tên sản phẩm/biến thể, thuộc tính, giá,
số lượng, người nhận và địa chỉ/tọa độ. Catalog đổi sau đó không làm đổi đơn cũ.
Giá trên UI là giá tham khảo hiện tại; quy tắc xác nhận lại nếu giá đổi cần được
chốt cùng UX checkout, không thêm tham số giá client vào nguồn giá server.

## Tồn kho dùng chung

Phía Văn Đức chọn một primitive nội bộ theo CIN-04:

```text
private.apply_order_inventory_event(
  p_order_id uuid, p_event_id uuid, p_effect text,
  p_items jsonb, p_actor_id uuid, p_reason text
) -> {event_id, order_id, movements:[
  {variant_id, on_hand_delta, reserved_delta, damaged_delta}
]}
```

Hàm chỉ được gọi trong transaction server đã kiểm tra role/đối tượng. Actor
phải do wrapper đáng tin cậy truyền vào, không lấy tùy ý từ Flutter. Không cấp
EXECUTE trực tiếp cho client. Internal exceptions được wrapper map sang lỗi
consumer; không trộn mã uppercase proposal delivery với lowercase orders ở UI.

| Tác động | Khi gọi | Thay đổi |
| --- | --- | --- |
| reserve | Đặt đơn | reserved +q, on_hand giữ nguyên; ghi ledger trong checkout |
| release | Hủy/từ chối trước xuất hàng | reserved -q đúng một lần |
| dispatch | Bàn giao vật lý lần đầu cho shipper | on_hand -q và reserved -q đúng một lần |
| inspect_undelivered | Manager nhận và kiểm tra hàng giao thất bại | Cộng on_hand phần bán được, damaged phần hỏng; không tự nhập hàng mất |

`reserve` là phần nội bộ của transaction checkout; không tự thêm vào enum
effect của CIN-04 trước khi đồng bộ signature với Bảo. Event + variant là khóa
ledger hiện có. Ngoài unique constraint, phải đối chiếu fingerprint để không
coi cùng event/khác payload là retry thành công. Order giữ lịch sử reservation
và dispatch để event ID mới cũng không xuất/giải phóng tồn lần thứ hai.

Thứ tự khóa bám L: request key → order → return request nếu có → delivery task
→ COD → variants theo UUID → items. Placement tạo order mới có thể khóa variants
sau claim request; order mới chưa lộ ra ngoài transaction. Không giữ khóa qua
network, Storage upload hoặc cuộc gọi RPC thứ hai từ Flutter.

## Điểm cần xác nhận với Bảo và Minh Đức

| Điểm | Quyết định phía Văn Đức / trạng thái |
| --- | --- |
| CIN-02 / CIN-07 | Bám tên place_order, shape đầu vào và model orders; customer catalog routes ở trên đã triển khai |
| CIN-04 | Chọn shared internal inventory primitive; cần xác nhận wrapper gọi và lưu fingerprint |
| CIN-09 | Bảo sở hữu producer thông báo; checkout cần event/notification trong cùng transaction; chưa có helper thực thi |
| Số lần giao | Tài liệu Bảo mô tả tăng khi có kết quả; đề xuất delivery trên main mô tả tăng lúc start. Chưa thống nhất; không dùng số lần giao để quyết định xuất tồn |
| Giao lần hai | Dispatch chỉ tại bàn giao vật lý lần đầu; giữ hàng giao lại không dispatch lần nữa; owner delivery chốt custody |
| Lỗi/receipt | Chốt envelope, error mapping và lookup result bằng fixture chung trước MH16 |

Đây là bàn giao bằng tài liệu, không phải bằng chứng Bảo đã đồng ý hay RPC đã
deploy. Không gửi thông điệp cho thành viên khác hoặc sửa code nhánh của họ
trong thay đổi catalog này.

## Tiêu chí nghiệm thu trước MH16

- Hai khách tranh món cuối: đúng một đơn giữ tồn thành công; không âm tồn.
- Một món thiếu trong giỏ nhiều món: không có order/items/reservation một phần.
- Retry cùng request: cùng order/event, không thêm ledger/notification; payload khác bị từ chối.
- Hủy/xác nhận/shipper nhận hàng tranh chấp: cùng order lock và precondition.
- Hủy hoặc dispatch lặp, kể cả request mới: không lặp cập nhật tồn.
- Đổi tài khoản giữa request và response: không trả/hiển thị dữ liệu tài khoản trước.
- Ngoài Hà Nội, tọa độ thiếu và vùng giao chưa xác thực: không tạo đơn.
- API lỗi/timeout: không hiện đơn thành công giả; có recovery cùng request ID.
