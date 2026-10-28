# Database Sports Store

**Cập nhật production 28/10/2026:** migration
`20261028062908_p083_redelivery_production.sql` đã deploy, hiện 22 migrations.
Thêm private append-only/FORCE RLS redelivery_requests, redelivery_return_receipts,
redelivery_inspection_results, redelivery_release_plan_items, redelivery_task_items,
redelivery_acceptances, redelivery_custody, redelivery_starts, redelivery_outcomes.
Reuse restricted writer/reader, không base-table grant shipper, không đổi COD,
inventory hoặc delivery_attempts. [Schema/API/tests hiện tại](demos/p083_production_redelivery.md)
thay kết luận chưa migration của mốc P08.3 fixture bên dưới.

Mốc fixture P08.3 trước khi bổ sung primitive không thêm migration/schema/RLS production. Enum hiện hữu đủ biểu diễn
redelivery miễn phí và D9 mới chốt; schema chưa có proof manager receipt +
inspection release/item plan/custody redelivery. Chỉ có SQL fixture rollback
trong native test database, không deploy; không tái dùng pickup handover report
làm manager receipt. [Chi tiết](demos/p083_redelivery_backend_contract.md).

Pickup handover bổ sung: migration `20261028011128_return_pickup_store_handover.sql`
đã deploy, thêm ledger private append-only/RLS FORCE và hai RPC hẹp. Không đổi
bảng trạng thái, stock/COD hoặc quyền đọc base tables client.
[Chi tiết](demos/p082_pickup_handover_acceptance.md).

P08.1: hợp đồng pickup exact-full/combined collect-start đã được người dùng
chốt. `return_items` là kế hoạch hàng thực tế đã duyệt, không thay bằng toàn bộ
order_items. Thu hồi không dispatch/restock, không ghi outbound attempts hoặc
sửa COD/refund. Schema/API mới và chứng cứ kiểm thử được ghi tại
[P08.1](demos/p081_return_pickup_backend.md); approval/manager receive của Sơn
vẫn là dependency độc lập, không có chỉ vì enum/cột đã tồn tại.
Migration P08.1 `20261027142031_return_pickup_tasks.sql` đã qua 20-migration local
regression và đã áp dụng lên cloud ngày 28/10/2026 sau khi bật VPN. Có snapshot/custody/ledger
private, không mở thêm client base-table reads.

P07.5 thêm migration `20261027140241_delivery_reporting_context.sql` cho một
RPC đọc hẹp phục vụ báo cáo MH11: reuse constrained reporting owner/validator,
không table/schema/enum mới, không nới grants/RLS client. Chỉ latest outbound
task của holder hợp lệ nhận flags/item snapshot; không PII/order UUID/giá.
Chi tiết [P07.5](demos/p075_production_reporting_interfaces.md).

Mô tả baseline/P00.2 bên dưới là lịch sử thiết kế. P01.1 cuối file ghi thay
đổi read projection và policy mới; không dùng predicate shipper của baseline
như quyền hiện hành sau khi áp dụng migration P01.1.

Schema nền tảng gọn gồm 18 bảng cho báo cáo nghiệp vụ v3.0 ngày 29/09/2026, giữ đủ phạm vi 20 màn hình và một cửa hàng ở Hà Nội. Project Supabase dùng chung có ref `bqoyfytmrtvjwrpshuhh`.

## Quy ước dữ liệu

- ID nghiệp vụ là UUID do database sinh; ID người dùng trùng `auth.users.id`.
- Vai trò `customer`, `manager`, `shipper` lấy từ `profiles.role` do server quản lý. Đăng ký luôn tạo khách, không lấy quyền từ `user_metadata`.
- Giá và số tiền là số nguyên VND (`bigint`); Flutter dùng `int`. Thời gian là `timestamptz`, do server ghi và lưu nhất quán.
- Sản phẩm/biến thể ngừng bán bằng `is_active`; giữ nguyên snapshot trong đơn cũ.
- RLS được bật cho mọi bảng `public`. Cấp quyền Data API tường minh; schema `private` chứa helper nội bộ và không được expose.
- Các bảng tồn kho, đơn, nhiệm vụ, COD, trả hàng, hoàn tiền và lịch sử chưa nhận INSERT/UPDATE/DELETE trực tiếp từ `authenticated`. Cần RPC giao dịch có kiểm tra quyền khi triển khai các luồng tương ứng.

## Nhóm bảng

| Nhóm | Bảng | Nội dung chính |
|---|---|---|
| Tài khoản | `profiles` | Liên kết Supabase Auth; vai trò do server quản lý |
| Danh mục | `categories` | Danh mục tạo sẵn: quần áo, giày, dụng cụ |
| Sản phẩm/tồn | `products`, `product_variants` | Thông tin sản phẩm; SKU, thuộc tính, giá và các lượng tồn từng biến thể |
| Lịch sử kho | `inventory_movements` | Biến động tồn theo sự kiện, chống ghi trùng |
| Giỏ | `cart_items` | Khóa `(customer_id, variant_id)`; không cần bảng giỏ riêng; không giữ tồn |
| Đơn | `orders`, `order_items` | Người nhận/địa chỉ/tọa độ; snapshot hàng, giá; trạng thái; tổng COD |
| Giao nhận | `delivery_tasks`, `delivery_attempts` | Phân công, địa điểm nhiệm vụ và từng lần giao đi; sự cố lưu trong lịch sử sự kiện |
| COD | `cod_collections` | Một khoản theo đơn; thu và nhận đủ tiền, độc lập trả hàng |
| Trả/hoàn hàng | `return_requests`, `return_items` | Yêu cầu, hàng thực tế cần thu hồi; video, bằng chứng kiểm tra, ngân hàng và hoàn tiền nằm trong yêu cầu |
| Lịch sử | `business_events` | Đối tượng, trước/sau, người thực hiện, lý do, thời điểm và sự cố giao nhận |
| Thông báo | `notifications` | Người nhận, sự kiện chống trùng, đối tượng liên quan, mốc đã đọc |
| Chat | `conversations`, `messages` | Một hội thoại mỗi khách; văn bản, chống gửi trùng; mốc đã đọc lưu theo user trong hội thoại |
| Cửa hàng | `store_settings` | Một cấu hình cửa hàng; địa chỉ/tọa độ và vùng giao được xác nhận |

## Constraint quan trọng

- Tồn không âm; lượng giữ không vượt tồn; `available_quantity = on_hand - reserved`.
- Phí giao của đơn là 30.000 VND; tổng COD tính từ tiền hàng và phí. Dòng hàng lưu giá và số lượng lúc đặt.
- Số lần giao đi không vượt hai; nhiệm vụ lấy hàng trả/giao lại không thu COD mới.
- Một yêu cầu trả đang xử lý cho mỗi đơn; hàng thu hồi có thể là hàng thực tế nhận khác snapshot, không bắt trả món chưa được giao.
- Số tiền COD ghi nhận phải đầy đủ, không ghi một phần; một bản ghi hoàn tiền cho mỗi yêu cầu.
- Mã yêu cầu đặt đơn, sự kiện kho, tin nhắn và thông báo có unique constraint để tránh bản sao.
- Nội dung tin nhắn không được rỗng. Bank details nằm trong `return_requests`; shipper không được đọc bảng này, chỉ đọc danh sách hàng qua `return_items`.

Constraint không thay thế quy trình giao dịch. Ví dụ unique request ID ngăn tạo hai bản ghi nhưng RPC đặt đơn vẫn phải trả cùng kết quả khi retry, kiểm tra giá/tồn và khóa biến thể trong một transaction. Chưa có RPC đó trong schema nền.

## Quyền truy cập

| Dữ liệu | Khách | Manager | Shipper |
|---|---|---|---|
| Profile | Xem của mình | Xem để xử lý nghiệp vụ | Xem của mình |
| Catalog/tồn có thể bán | Xem hàng đang bán | Xem; sửa sản phẩm/biến thể | Không |
| Giỏ | CRUD giỏ của mình | Không | Không |
| Đơn | Xem đơn của mình | Xem các đơn | Không đọc nguyên bảng đơn; dùng snapshot nhiệm vụ |
| Dòng hàng | Xem của mình | Xem | Xem qua nhiệm vụ được phân công |
| Nhiệm vụ | Xem trạng thái đơn | Xem | Xem nhiệm vụ được phân công |
| COD | Xem theo đơn của mình | Xem | Xem khoản của mình, kể cả sau khi đơn trả |
| Yêu cầu/bằng chứng trả | Xem của mình | Xem | Chỉ danh sách hàng qua nhiệm vụ thu hồi |
| Bank details/hoàn tiền | Xem của mình | Xem | Không |
| Thông báo | Xem/đánh dấu của mình | Xem/đánh dấu của mình | Xem/đánh dấu của mình |
| Chat | Hội thoại của mình | Hỗ trợ khách | Không |
| Cấu hình cửa hàng | Không | Xem | Xem |

Người chưa đăng nhập (`anon`) không được truy cập bảng nghiệp vụ trong baseline này. Quyền Supabase Dashboard/MCP của thành viên nhóm là một hệ quyền khác với vai trò trong app.

## Storage

Các bucket `product-images`, `return-videos`, `inspection-evidence`, `refund-evidence` đều private. Dùng SDK/signed URL theo quyền; không lưu bằng chứng hoàn tiền bằng URL public.

- Video trả hàng: `<customer_uuid>/<return_uuid>/<file>`. Khách upload vào thư mục của mình; manager đọc khi video nằm trong `video_object_path` hoặc `additional_video_paths` của yêu cầu. Không cho client sửa/xóa video đã upload.
- Bằng chứng kiểm tra và chuyển tiền: `<return_uuid>/<file>`. Manager upload; khách đọc đường dẫn đã liên kết trong `inspection_evidence_paths` hoặc `transfer_evidence_path` của yêu cầu của mình. Shipper không đọc.
- Ảnh sản phẩm: khách/manager đọc; manager quản lý.

Dung lượng và định dạng file chưa được chốt trong báo cáo; cần đặc tả kỹ thuật riêng. Việc video tồn tại trong Storage và nằm đúng yêu cầu phải được RPC gửi yêu cầu trả kiểm tra.

## Phạm vi đã thiết kế và phần triển khai tiếp theo

Schema cung cấp bảng, FK/index, constraint, RLS/grants, trigger tạo profile khách và lưu mốc đọc theo giờ server. `conversations.read_at_by_user` là JSON object ánh xạ user UUID sang timestamp; trigger chỉ cập nhật mốc của session hiện tại và giữ nguyên mốc của người khác. Các chính sách 7 ngày, địa chỉ Hà Nội, giữ/xuất/nhập tồn, chuyển trạng thái, thông báo theo sự kiện và hoàn tiền cần được thực thi thêm trong RPC/tác vụ server của từng feature.

Chưa có địa chỉ/tọa độ cửa hàng hoặc polygon Hà Nội được phê duyệt trong báo cáo. `store_settings` không được điền bằng vị trí suy đoán. RPC checkout phải từ chối đặt khi chưa xác thực được địa chỉ/phạm vi; không dùng riêng nhãn `Hà Nội` làm kiểm tra tọa độ.

Manager/shipper được provision bằng Supabase Auth administration và cập nhật vai trò qua công cụ server đáng tin cậy. Không có màn quản lý tài khoản hoặc RPC cho khách tự cấp vai trò.

Trạng thái chuẩn: [business_states.md](business_states.md). Hợp đồng Data API và RPC cần triển khai: [api_contracts.md](api_contracts.md). Mapping 20 màn hình: [screen_mapping.md](screen_mapping.md).

## Migration và kiểm tra

Các migration được tạo bằng Supabase CLI 2.119.0. Tên/version trong repo phải khớp lịch sử migration cloud sau khi áp dụng. Không chạy `db reset --linked` trên project dùng chung.

Ngày 06/10/2026 đã áp dụng nguyên văn lên project `bqoyfytmrtvjwrpshuhh`:

- `20261006034251_sports_store_schema.sql`.
- `20261006034259_sports_store_access.sql`.

Hai migration đầu tạo schema chi tiết 25 bảng. Sau khi người dùng chọn giữ đủ 20 màn hình và gộp bảng phụ, đã áp dụng thêm `20261006040019_simplify_sports_store.sql`. Migration khóa các bảng liên quan, kiểm tra chúng còn rỗng và dùng `DROP ... RESTRICT`; nếu có dữ liệu nghiệp vụ thì dừng trước khi thay đổi.

Lịch sử cloud xác nhận cả ba version. Truy vấn sau migration cuối xác nhận **18/18 bảng `public` bật RLS**, 3 danh mục, 0 tài khoản Auth và 4 bucket đều private. PostgreSQL cloud là 17.11. Security advisors không có finding; performance advisors chỉ có 42 mục `unused_index` mức INFO khi database mới chưa có dữ liệu nghiệp vụ. Giữ index hỗ trợ FK/RLS và đánh giá lại với workload thực tế. Khi dựng database mới, áp dụng đầy đủ ba migration theo thứ tự, không chạy riêng schema đầu.

`supabase/tests/database_security.sql` dùng fixture trong transaction và kết thúc bằng ROLLBACK. Chạy bằng SQL Editor/công cụ quản trị có quyền phù hợp, hoặc thực thi bản nguyên vẹn qua MCP. Không cắt bỏ ROLLBACK và không sử dụng các fixture làm dữ liệu demo.

Ngày 06/10/2026 đã chạy nguyên file bằng MCP trên cloud và nhận `database_security.sql: PASS`: 83 kiểm tra về quyền đọc/ghi được phép và bị chặn, chống tự cấp role, giỏ, chat/mốc đọc, Storage riêng tư, FK liên quan đơn/giao/trả hàng, COD đầy đủ và khóa chống trùng. Đã truy vấn lại sau ROLLBACK: 0 Auth users, 0 Storage objects, 0 dòng nghiệp vụ ngoài 3 danh mục seed; 18/18 bảng vẫn bật RLS. Security advisors sau test không có finding. File test được review độc lập cùng ba migration.

Các test baseline xác minh quyền/constraint, không chứng minh mọi kịch bản NT01–NT30 đã hoàn thành. Các test đặt hàng đồng thời, hủy/xác nhận đua nhau và idempotent workflow chỉ có ý nghĩa sau khi RPC tương ứng được triển khai.

Tham khảo: [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [Storage access control](https://supabase.com/docs/guides/storage/security/access-control), [Auth profiles](https://supabase.com/docs/guides/auth/managing-user-data).

## Orders/Notifications owned design revision1.2 — chưa triển khai

Owner Bảo đã ủy quyền chốt kỹ thuật phạm vi MH07/08/09/17. [Main Specification](technical_specification_mh07_mh08_mh09_mh17.md), [Data/API normative](technical_specification_mh07_mh08_mh09_mh17_data_api.md), [Final Decisions](Final_Technical_Decisions.md), [Cross Contracts](Cross_Module_Integration_Contracts.md) và [Readiness](Implementation_Readiness_v1.2.md). Owned shapes/RPC/receipt/metadata/query/UI design OWNER DECIDED — PROPOSED IMPLEMENTATION; không ghi tables/RPC mới là existing, không thay enum hay grants hiện tại. FullUUID/no humanordercode, snapshotplaceholder, safeCustomerprojection không mở rawtasks/events RLS; main4role routes proposed centralrouter. CIN01–09 external contractoffers NOT ACCEPTED/NOT IMPLEMENTED; recommendedtask2samecustody/inspection cần ownerDelivery/Inventory xác nhận. Businesslost/partialclosure/transferafterpickup/7dayedge chưa quyết. Nội dung baseline của module khác giữ nguyên; currentowned definitions ở revision1.2, schema/runtime baseline vẫn three existingmigrations.

## P00.2 — Kiểm kê schema giao nhận/COD và khoảng trống (23/10/2026)

Phần này đối chiếu trực tiếp ba migration trong repo theo thứ tự
`20261006034251_sports_store_schema.sql`,
`20261006034259_sports_store_access.sql` và
`20261006040019_simplify_sports_store.sql`. “Hiện tại” bên dưới chỉ mô tả
schema/RLS được các migration tạo ra; enum, constraint và policy không phải là
bằng chứng rằng RPC hay tác vụ server đã tồn tại. “Đề xuất” là yêu cầu cho
phase API/migration sau. Các tên bảng/cột đề xuất trong phần đó chỉ là tên gợi
ý, **chưa tồn tại và chưa được deploy**.

### Schema hiện tại của giao nhận

Các enum hiện có là `delivery_task_kind` (`outbound`, `return_pickup`,
`redelivery`), `delivery_task_status` (`pending_assignment`, `assigned`,
`accepted`, `in_transit`, `delivered`, `failed`, `returned_to_store`,
`cancelled`, `manager_action_required`), `delivery_attempt_result`
(`success`, `failed`) và `delivery_incident_kind` (`damaged`, `lost`, `other`).

| Bảng | Cột và ràng buộc đang có |
|---|---|
| `delivery_tasks` | `id`, `order_id`, `return_request_id`, `kind`, `assigned_shipper_id`, `assigned_by`, `status`, `attempt_number`, thông tin điểm đến (`destination_name`, `destination_phone`, `destination_address`, `destination_latitude`, `destination_longitude`), `amount_to_collect_vnd`, các mốc `assigned_at`, `accepted_at`, `started_at`, `completed_at`, `failure_reason`, `cancel_reason`, `created_at`, `updated_at`. Đơn outbound có `attempt_number` từ 1 đến 2; pickup/redelivery bắt buộc là 1. Pickup/redelivery phải có `return_request_id`; outbound không được có. Nhiệm vụ không phải outbound có `amount_to_collect_vnd = 0`. Có FK ghép `(return_request_id, order_id)` về `return_requests` và index chỉ cho một outbound active theo `order_id`, một pickup/redelivery active theo `return_request_id`. |
| `delivery_attempts` | Mỗi task tối đa một dòng nhờ `unique(task_id)`, và mỗi đơn tối đa một dòng cho cùng `attempt_number` nhờ `unique(order_id, attempt_number)`. Có FK ghép `(task_id, order_id, attempt_number, task_kind)` về task, `task_kind` hiện bị CHECK là `outbound`, `result`, `reason`, `occurred_at`, `shipper_id`. Result `failed` bắt buộc có lý do không rỗng. Đây là bản ghi kết quả cuối, không phải lịch sử mọi chuyển trạng thái. |
| `orders` / `order_items` | `orders` giữ snapshot người nhận/địa chỉ/tọa độ, `subtotal_vnd`, phí cố định 30.000 VND, `total_cod_vnd` sinh từ hai khoản và `delivery_attempt_count` trong 0..2. `order_items` giữ `product_name`, `variant_label`, `attributes`, `unit_price_vnd`, `quantity`, `line_total_vnd` tại thời điểm đặt; vẫn giữ FK đến product/variant hiện tại. |
| `return_items` | Gắn với `return_request_id` và `order_id`; `order_item_id` và `variant_id` có thể null để ghi nhận hàng thực tế giao sai hoặc thiếu. Có `actual_item_name`, `quantity_to_collect`, `quantity_collected`, `sellable_quantity`, `damaged_quantity`; chưa có bản ghi custody riêng cho từng lần nhận/bàn giao. |
| `business_events` | Sau simplification, incident không còn bảng riêng. Bảng có `subject_type`, `subject_id`, `from_state`, `to_state`, `reason`, `actor_id`, thêm `task_id`, `incident_kind`, `request_id`. Khi `incident_kind` khác null, CHECK bắt buộc subject là `delivery_task`, `subject_id = task_id`, có actor, request ID và lý do không rỗng; `request_id` unique nhưng nullable. Event trạng thái chung vẫn có thể có các cột incident null. |

Index partial hiện tại chỉ coi các trạng thái `pending_assignment`, `assigned`,
`accepted`, `in_transit` là outbound active. Với pickup/redelivery,
`manager_action_required` cũng giữ slot active; `failed` không giữ slot active.
Vì vậy constraint hiện tại chưa ngăn tạo task mới khi một task thất bại vẫn
có hàng đang được shipper giữ.

### Schema hiện tại của COD

`cod_collections` là một dòng cho mỗi đơn (`order_id` là PK và FK đến
`orders`). Các cột chính là `shipper_id` nullable, `status` gồm
`uncollected`, `collected`, `received`, `expected_amount_vnd`,
`collected_amount_vnd`, `received_amount_vnd`, các mốc và actor
`collected_at`/`collected_by`, `handed_over_at`,
`received_at`/`received_by`, cùng `created_at`/`updated_at`.

Các CHECK hiện tại bảo đảm `expected_amount_vnd > 0`, số tiền không âm,
`received_amount_vnd <= collected_amount_vnd <= expected_amount_vnd`, và
không ghi nhận một phần: `uncollected` phải có collected bằng 0;
`collected`/`received` phải có collected bằng expected; `received` phải có
received bằng expected còn hai trạng thái trước phải có received bằng 0.
Schema chưa có FK/CHECK buộc `expected_amount_vnd` bằng
`orders.total_cod_vnd`, chưa có actor cho `handed_over_at`, chưa có lịch sử
chuyển trạng thái, evidence hoặc request ID cho action COD. Việc hoàn tiền
không được biểu diễn bằng cách giảm nghĩa vụ trong dòng COD.

### RLS và quyền đọc hiện tại

Migration đầu bật RLS cho mọi bảng public còn lại; migration access cấp
`SELECT` trên toàn bộ bảng public cho `authenticated`, sau đó policy giới hạn
dòng. Không có grant `INSERT`/`UPDATE`/`DELETE` cho `authenticated` trên
`delivery_tasks`, `delivery_attempts`, `cod_collections`, `business_events`,
`orders`, `order_items` hoặc `return_items`; các thay đổi phải đi qua cơ chế
server có kiểm tra quyền và transaction. Policy thực tế liên quan giao nhận
và COD là:

| Policy / đối tượng | Predicate thực tế sau migration cuối |
|---|---|
| `tasks_read` / `delivery_tasks` | Manager đọc mọi dòng; shipper đọc khi `assigned_shipper_id = auth.uid()`. Không có điều kiện status. |
| `attempts_read` / `delivery_attempts` | Manager đọc mọi dòng; customer đọc khi task thuộc đơn của mình; shipper đọc khi tồn tại task có `t.id = task_id` và `t.assigned_shipper_id = auth.uid()`. |
| `order_items_read` / `order_items` | Manager đọc mọi dòng; customer đọc dòng thuộc đơn của mình; shipper đọc khi tồn tại bất kỳ task nào của cùng `order_id` đang có `assigned_shipper_id = auth.uid()`. Shipper không có policy đọc `orders`. |
| `return_items_read` / `return_items` | Manager đọc mọi dòng; customer đọc theo `return_requests.customer_id = auth.uid()`; shipper đọc khi tồn tại task có `t.return_request_id = return_items.return_request_id` và `t.assigned_shipper_id = auth.uid()`. Shipper không có policy đọc `return_requests`. |
| `business_events_read` / `business_events` | Manager đọc mọi event. Shipper chỉ đọc khi `incident_kind IS NOT NULL`, `actor_id = auth.uid()` và tồn tại task có `t.id = task_id` cùng `t.assigned_shipper_id = auth.uid()`. Vì vậy đây là quyền đọc **incident do chính shipper tạo trên task đang được gán**, không phải quyền đọc generic state history. |
| `cod_read` / `cod_collections` | Manager đọc mọi dòng; shipper đọc khi `shipper_id = auth.uid()`; customer đọc khi tồn tại order có `o.id = order_id` và `o.customer_id = auth.uid()`. Policy này không kiểm tra `delivery_tasks`, status task, hay trạng thái return. |

Do `tasks_read`, `attempts_read`, `order_items_read` và `return_items_read`
chỉ dựa vào `assigned_shipper_id` và không lọc trạng thái, shipper hiện tại
vẫn đọc được task đã `delivered`, `failed`, `returned_to_store` hoặc `cancelled`
miễn là cột phân công vẫn giữ UUID của họ. Khi task bị gán cho người khác hoặc
bị set null, quyền đọc theo task đó mất đi. Đây là quan hệ **phân công hiện
tại**, chưa phải lịch sử người từng tham gia.

COD có quyền đọc độc lập với quan hệ task nói trên: shipper còn đọc được dòng
COD nếu `cod_collections.shipper_id` vẫn là UUID của họ, kể cả sau khi task
kết thúc, đơn có yêu cầu trả hàng hoặc shipper không còn là người được gán
task hiện tại. Quyền này cũng không cho shipper đọc bank details/return request
và không cấp quyền ghi. Generic `business_events` không được shipper đọc;
Baseline chỉ nhánh incident thỏa predicate trên được đọc; sau P01.1 raw business_events chỉ manager đọc, kể cả incident (xem mục P01.1 bên dưới). `service_role` có grant
riêng trong migration nhưng không được dùng trong Flutter.

### Khoảng trống cần xử lý

- **Idempotency:** `orders.request_id`, `inventory_movements.event_id` theo
  biến thể, `messages.client_message_id` và `notifications(recipient_id,
  event_id)` có chống trùng ở các phạm vi riêng. Delivery action không có
  request ID; `delivery_attempts` chỉ chặn hai bản ghi kết quả cho một task/số
  lần. COD không có request ID. Không có payload hash, kết quả đã commit hoặc
  quy tắc retry cùng key phải trả cùng kết quả.
- **Custody và lịch sử:** Task chỉ có các mốc đơn (`accepted_at`,
  `started_at`, `completed_at`) và các cột phân công có thể bị ghi đè. Chưa có
  actor nhận hàng, holder trước/sau, số lượng thực nhận, receipt của manager,
  handover event, inspection event, hay lịch sử shipper cũ/mới bất biến.
  `business_events` có thể chứa event chung nhưng chưa có CHECK bảo vệ thứ tự
  chuyển trạng thái và shipper không được đọc event chung.
- **Snapshot theo task/assignment:** `orders` và `order_items` có snapshot đặt
  hàng; `delivery_tasks` có bản sao destination/amount tại task. Tuy nhiên
  chưa có item snapshot riêng cho task, snapshot hàng thực tế của pickup,
  version/immutable marker theo assignment, hoặc liên kết snapshot với người
  giữ hàng. RLS hiện tại còn cho shipper đọc toàn bộ `order_items` của đơn khi
  có bất kỳ task nào của họ, dựa trên task mutable.
- **Transaction và giới hạn lần giao:** Constraint không tự thực hiện các
  bước nhận hàng, dispatch, start, tăng `delivery_attempt_count`, thu đủ COD,
  nhận hàng về kho, inspection hay restock. Không có khóa/transition guard
  cho race giữa hủy, phân công, nhận và đổi người. Task return `failed` có thể
  rơi khỏi partial unique index dù custody cũ chưa giải quyết.
- **COD:** Các CHECK bảo vệ hình dạng số tiền nhưng chưa bảo vệ action chỉ do
  shipper/manager hợp lệ thực hiện, thứ tự đơn điệu, đối chiếu amount với đơn,
  hoặc việc ghi nhận cùng một lần thu/bàn giao/nhận lại khi retry. Quyền đọc
  trực tiếp theo `shipper_id` cần giữ độc lập với return và task, nhưng cần
  chốt rõ `shipper_id` là người thu ban đầu hay holder hiện tại.
- **Incident và bằng chứng:** Incident đã nhập vào `business_events`, nhưng
  không có bảng/payload chuyên biệt cho ảnh, biên bản bàn giao, số lượng thực
  nhận hoặc bằng chứng manager nhận. Policy cố ý không mở generic history cho
  shipper; dữ liệu lịch sử an toàn cần một projection có phạm vi tối thiểu.

### Yêu cầu schema đề xuất — chưa triển khai

Các yêu cầu sau là đầu vào cho migration/RPC tương lai; không mô tả endpoint đã
có:

1. Mỗi action làm thay đổi task, custody, attempt hoặc COD phải mang một
   `request_id` do caller tạo. Nên có một ledger idempotency (tên ví dụ như
   `operation_requests`, **chưa tồn tại**) lưu operation, subject, actor,
   payload hash, trạng thái xử lý, kết quả/tham chiếu bản ghi và timestamp,
   với unique key phù hợp. Retry cùng key và cùng payload phải trả kết quả đã
   commit; cùng key khác payload phải bị từ chối. Việc ghi ledger, state,
   inventory, COD, event và notification liên quan phải nằm trong cùng
   transaction.
2. Bổ sung lịch sử append-only cho assignment/state/custody (tên ví dụ
   `delivery_task_history` hoặc `delivery_task_assignments`, **chưa tồn tại**).
   Mỗi dòng cần task, order/return request, actor, shipper, holder trước/sau,
   state trước/sau, số lần, thời gian server, `request_id`, payload tối thiểu
   và evidence/tham chiếu nếu có. Phân công lại phải đóng assignment cũ và
   tạo assignment mới, không ghi đè lịch sử. Receipt của manager phải là mốc
   riêng với report bàn giao của shipper; inspection phải là mốc riêng với
   receipt.
3. Tạo snapshot bất biến theo task và assignment (tên ví dụ
   `delivery_task_snapshots`/`delivery_task_item_snapshots`, **chưa tồn tại**)
   cho recipient, destination, amount, item/quantity hoặc return item thực tế
   cần xử lý. Snapshot phải được chốt tại mốc nghiệp vụ đã owner xác nhận và
   không bị thay bởi việc đổi shipper hay cập nhật đơn. Shipper từng tham gia
   chỉ được thấy snapshot tối thiểu gắn với assignment/custody của chính họ;
   dữ liệu recipient/đơn mới không được suy ra từ task mutable hoặc từ
   `order_items` toàn đơn.
4. Giữ `cod_collections` là subject độc lập ở cấp order. Bổ sung ledger sự
   kiện COD bất biến (tên ví dụ `cod_events`, **chưa tồn tại**) cho collect,
   hand-over và manager receive, gồm actor, amount, server time, request ID,
   evidence và kết quả. Server phải đối chiếu expected amount với snapshot
   tổng đơn, chỉ cho chuyển trạng thái khi đủ toàn bộ tiền, không ghi partial,
   không giảm nghĩa vụ do refund, và không cho retry tạo lần thu/bàn giao thứ
   hai. RLS đọc của shipper vẫn dựa trên quyền COD/collector đã được chốt,
   độc lập với RLS task và return; ghi chỉ qua transaction server với manager
   xác nhận nhận đủ.
5. Giữ policy hiện tại cho live task theo assignment hiện tại, nhưng thêm
   đường đọc lịch sử qua assignment/snapshot bất biến với dữ liệu tối thiểu.
   Không dùng một `assigned_shipper_id` có thể đổi để chứng minh custody cũ.
   `business_events` tiếp tục chỉ cho shipper đọc incident của chính họ trong
   phạm vi task được phép; nếu cần xem lịch sử xử lý, dùng projection lịch sử
   được giới hạn, không mở toàn bộ generic event ledger.
6. Transaction server phải khóa đúng order/task/COD theo thứ tự thống nhất,
   kiểm tra precondition và trạng thái trước đó, bảo đảm một outbound active,
   tối đa hai lần giao đi, dispatch/receipt/restock một lần, và chặn task mới
   khi custody cũ chưa được manager giải quyết. Đây là yêu cầu triển khai,
   không phải hành vi hiện có của constraint/RLS.

### Mã dependency P00.2 dùng trong API

Các mã sau gom các yêu cầu đánh số phía trên để tra cứu từ api_contracts.md;
tất cả vẫn là đề xuất chờ duyệt, không là tên migration đã tồn tại:

| Mã | Thay đổi schema/quyền bắt buộc trước triển khai |
| --- | --- |
| S1 — snapshot | Yêu cầu 3: projection/item snapshot theo kind; nguồn note/ảnh còn thiếu; danh sách giao lại thực tế và điểm đến theo task cần Sơn/Văn Đức chốt. Chốt mốc đóng băng snapshot với Bảo/Sơn; không lấy catalog hiện tại để thay lịch sử. |
| S2 — giao dịch và truy vết | Yêu cầu 1/2/6: request ledger unique `(actor_id,request_id)` kèm operation/target/hash/result, receipt/inspection/custody theo item và lịch sử assignment/event_type/payload. Có quantity received/lost hoặc ledger tương đương; không dùng `quantity_collected` thay receipt. Retry/khóa theo L ở api_contracts.md; không tạo bảng trong phase này. |
| S3 — COD | Yêu cầu 4: chốt tạo uncollected, collector/holder và amount đối chiếu đơn; đề xuất shipper_id cố định bằng người thu khi collected, không thay theo task sau đó. Chưa có RPC shipper báo nộp tiền riêng: đề xuất manager confirm ghi handed_over_at cùng received_at nếu thực giao/nhận đồng thời; nếu muốn mốc báo độc lập cần hợp đồng mới, chưa đoán actor/thời gian quá khứ. |
| S4 — history, version và quyền | Yêu cầu 5 và bổ sung version bigint tăng đơn điệu trên order/request/task/COD, chưa có ở schema. History projection chỉ task_id/kind/status/result/attempt_number/completed_at gắn người thực hiện, không PII hoặc quyền vào task mới. Chốt grants/projection để quyền đọc trực tiếp không vượt dữ liệu tối thiểu; không cho shipper đọc orders/return_requests để giải quyết join. |

Chưa chọn cấu trúc vật lý cuối cùng (bảng mới hay mở rộng event ledger),
index/grants/EXECUTE và migration filename; phase triển khai mới dùng CLI
tạo migration thật, review quyền tối thiểu và chạy allowed/denied tests.

Chi tiết bổ sung sau review P00.2: S2 phải phân biệt client request ID theo
actor và event ID. `business_events.request_id` hiện unique toàn cục nên
không thể gán trực tiếp UUID client cho nhiều event hoặc hai actor cùng UUID.
Đề xuất FK operation_request_id về ledger server và event token riêng; cần
đổi constraint/mapping incident qua migration được duyệt, chưa triển khai.
S3 cần review nhánh customer của cod_read: RPC từ chối customer không thu hẹp
quyền SELECT nguyên dòng hiện có. Projection customer tối thiểu không cần UUID
nhân viên/mốc đối soát; chờ owner duyệt cách thu hẹp grants/policy.
S4 đề xuất chuyển task terminal (`delivered/cancelled/returned_to_store`) sang
history tối thiểu, không contact/destination/map; direct Data API phải được
review tương ứng, không chỉ giới hạn DTO. Chi tiết tập vận hành và ma trận
kiểm chứng tương lai nằm trong api_contracts.md; các kiểm chứng đó chưa chạy.

### Xác nhận owner còn thiếu cho P00.2

Các mã dưới đây lấy từ P00.1 và vẫn là câu hỏi mở, chưa được coi là contract:

- **D1 — Bảo + Minh Đức:** thời điểm đơn chuyển `awaiting_pickup`, ý nghĩa
  chính xác của `accepted_at`, ranh giới khóa hủy và có cần mốc nhận việc
  riêng; chốt nhận hàng và bắt đầu giao là hai action hay một.
- **D2 — Bảo, Sơn + Minh Đức:** schema receipt/inspection/custody/handover,
  evidence, request payload chống trùng và lịch sử shipper cũ/mới; report của
  shipper không thay receipt của manager.
- **D3 — Bảo + Minh Đức:** lần giao thứ hai giữ hàng ở shipper cũ, chuyển trực
  tiếp hay qua cửa hàng; khi nào được đổi người sau custody.
- **D4 — Văn Đức + Bảo/Sơn:** transaction dispatch và inventory idempotency;
  cách ngăn dispatch hai lần cho outbound lần hai/redelivery; receipt khác
  inspection và chỉ restock lượng đạt.
- **D5 — Bảo:** cách ghi nhận hàng giao thất bại quay về, hàng thiếu/hỏng/mất,
  thời điểm order kết thúc và xử lý task lần hai đã tạo nhưng chưa start.
- **D6 — Bảo, Sơn + Minh Đức:** sự cố trước/sau start, hủy sau nhận hàng,
  gián đoạn khi đang đi; khi nào được ghi result `failed` và khi nào chỉ ghi
  incident chờ manager.
- **D7 — Bảo:** event/recipient/thời điểm tạo notification và cách deep link
  kiểm tra lại quyền hiện tại.
- **D8 — Sơn + Minh Đức, Văn Đức cho tồn:** item/quantity thực nhận của
  return pickup, start riêng hay gộp với nhận, pickup thất bại/hẹn lại,
  receipt/inspection và đổi người/hủy trước custody.
- **D9 — Sơn + Minh Đức:** P08.3 người dùng chốt failure T/R
  `manager_action_required`, giữ active slot/custody/open; chỉ success mới đóng
  request. Receipt/inspection/release plan/custody primitive đã có production theo
  mốc mới; manager resolution để đóng/mở lại trước task mới và UI MH15 vẫn riêng.
- **COD với owner orders/deliveries:** thời điểm tạo dòng `uncollected`, ý
  nghĩa lâu dài của `cod_collections.shipper_id`, actor của hand-over và
  policy đọc của shipper sau đổi người/return phải khớp với ledger custody.

Cho đến khi các quyết định trên được chốt và migration/RPC tương ứng được
review, không coi các cột hiện tại là bằng chứng của custody, lịch sử bất biến,
idempotency end-to-end hoặc snapshot an toàn theo shipper.

## P01.1 — Migration lớp đọc task/item an toàn

File `supabase/migrations/20261023104903_secure_delivery_read_projections.sql`
được tạo bằng `npx --yes supabase@2.119.0 migration new secure_delivery_read_projections`.
Migration mới, không sửa/xóa ba migration nền, không đổi enum/table/cột nghiệp
vụ hoặc triển khai bất kỳ thao tác phân công, custody, dispatch, COD hay trả hàng.

| Thay đổi | Quyền sau migration |
| --- | --- |
| `tasks_read` | Bảng gốc chỉ manager. Shipper đi qua read_my_delivery_tasks; customer vẫn không đọc task trực tiếp. |
| `order_items_read`, `return_items_read`, `attempts_read` | Giữ manager/customer-own scopes, bỏ nhánh shipper theo bất kỳ task cùng order/request. Không có grant order/return mới cho shipper. |
| `business_events_read` | Manager đọc; bỏ shipper đọc incident/raw reason theo task mutable. Chưa tạo incident projection trong phase này. |
| `cod_read`, Storage và các policy ngoài bảng trên | Giữ nguyên. COD vẫn độc lập nhiệm vụ/returns; không xử lý dependency COD S3 trong read-task phase. |
| `sports_store_delivery_reader` | Role nội bộ NOLOGIN/NOINHERIT/NOBYPASSRLS, không là owner bảng; chỉ SELECT một số cột profiles/tasks/order_items/return_items, không quyền ghi hoặc đọc orders/return_requests/COD. Chỉ postgres được cấp membership để chuyển ownership function; API roles không là member. |
| Bốn policy `delivery_reader_*` | Chỉ áp dụng cho role đọc; profile chỉ own auth.uid; task phải đúng assigned_shipper_id và profiles.role=shipper; item chỉ qua task đúng kind và assigned/accepted/in_transit. |
| Hai read function | Stable SQL, search_path rỗng, SECURITY DEFINER dưới role đọc chịu RLS; EXECUTE chỉ authenticated, không PUBLIC/anon/service_role. Schema public CREATE được cấp tạm để chuyển owner rồi thu hồi. |

Role là cluster-wide nên local reset có thể giữ role sau khi dựng lại database.
Migration chỉ tái sử dụng role có marker của P01.1 và thuộc tính khóa đúng;
gặp role cùng tên không phù hợp thì dừng, không đổi quyền role ngoài ý muốn.
Không disable RLS hay dùng postgres-owned definer để vượt policy.

Projection mask theo status: current (`assigned/accepted/in_transit`) có
destination_* và amount_to_collect_vnd lấy nguyên task; history
(`delivered/cancelled/returned_to_store`) và restricted (các trạng thái còn
lại) chỉ task_id/kind/status/attempt_number/completed_at/scope/item_source,
không order/request ID, tiền, địa chỉ/contact, thời điểm nhận/start hoặc item.
History chỉ là phép chiếu tối thiểu của task còn assigned cho user hiện tại,
không hứa lịch sử assignment bất biến. Đổi cùng task sang người khác/null
thu hồi quyền người cũ; task lịch sử không mở task mới hoặc item theo order.
Đây là quyết định read-layer tối thiểu trong P01.1, không mặc định các hợp
đồng custody/history S2/S4 đã được nhóm chốt.

Nguồn item chỉ outbound/order_items và pickup/return_items đúng task, không
join nguyên orders/return_requests. Không trả quality/bank/video/refund
evidence. Redelivery chưa có plan được Sơn xác nhận: item_source báo
`unavailable_redelivery_plan`, item RPC rỗng; tích hợp item redelivery còn chặn.
Ảnh/note/version và snapshot assignment bất biến chưa triển khai.

Kiểm thử: `supabase/tests/delivery_read_security.sql` dùng fixture trong
transaction và ROLLBACK, kiểm tra role/ownership, mọi nhóm status, các deep
link ngoài quyền, đổi người/cùng order/request, masking lịch sử, base-table
closure và ACL/owner của function. `database_security.sql` được sửa kỳ vọng
shipper sang projection mới; không còn kỳ vọng raw task/item/event access.
Khi chạy SQL trực tiếp phải dùng `psql -v ON_ERROR_STOP=1` để lỗi không bị bỏ
qua và kết quả PASS chỉ xuất sau tất cả assert; không dùng fixture làm demo.

### Kết quả kiểm chứng P01.1 ngày 23/10/2026

- `git diff --check`: PASS.
- `flutter analyze`: `No issues found!`; không sửa dependency/lockfile.
- `node --check supabase/tests/run_delivery_read_fixture.mjs`: PASS.
- `node supabase/tests/run_delivery_read_fixture.mjs p011_read_verified`:
  PASS trên PostgreSQL **17.10 native**, áp dụng đủ bốn migration trong một
  database cô lập mới; cả `database_security.sql` và
  `delivery_read_security.sql` PASS + ROLLBACK. Truy vấn sau test xác nhận
  0 Auth users, orders, tasks và Storage objects. Các fixture không được giữ
  làm dữ liệu nghiệp vụ.
- Lần chạy đầu đã phát hiện assertion catalog so sánh cách Postgres lưu
  search_path chưa đúng (`search_path=""`); sửa assertion và chạy lại trên
  database fixture mới như trên. Không sửa migration để làm yếu kiểm tra.
- `npx --yes supabase@2.119.0 db start`: không hoàn tất môi trường Supabase;
  gặp lỗi bootstrap container `exit 125`, sau đó Docker Desktop engine không
  sẵn sàng/khởi động bị treo. Không có kết quả Supabase/PostgREST hoặc cloud
  được xác nhận trong phase này. Các lệnh khởi tạo bị treo đã được hủy.

`fixtures/p011_auth_storage.sql.fixture` chỉ tạo **SQL stubs tối thiểu** cho
auth.uid, auth.users và Storage để thử PostgreSQL RLS, không phải Supabase
Auth/Storage thật hoặc migration triển khai. Runner chỉ kết nối localhost
port 55439, kiểm tra data_directory đúng `.temp/p011_native_data` của repo,
tạo database mới tên `p011_*` và từ chối tên/database đã có. Không có DROP,
reset, secret/service-role key hoặc kết nối cloud. Đuôi `.sql.fixture` tránh
coi bootstrap là SQL test tự chạy trên database Supabase thật.

Cách dựng lại môi trường fixture (PowerShell, từ project root; runtime/data
trong `.temp` bị gitignore, không là dependency của ứng dụng):

```powershell
npm install --prefix supabase/.temp/p011_pg_runtime --no-save --no-package-lock embedded-postgres@17.10.0-beta.17
$pgBin = Join-Path (Get-Location) 'supabase/.temp/p011_pg_runtime/node_modules/@embedded-postgres/windows-x64/native/bin'
$pgData = Join-Path (Get-Location) 'supabase/.temp/p011_native_data'
# Chỉ initialise khi thư mục data chưa tồn tại; không xóa/reset data cũ.
& (Join-Path $pgBin 'initdb.exe') -D $pgData -U postgres --auth=trust --encoding=UTF8 --locale=C
Start-Process -FilePath (Join-Path $pgBin 'postgres.exe') -ArgumentList @('-D', $pgData, '-p', '55439', '-h', '127.0.0.1') -WindowStyle Hidden
# Chọn tên p011_* mới nếu database fixture tên này đã tồn tại.
node supabase/tests/run_delivery_read_fixture.mjs p011_read_verified
& (Join-Path $pgBin 'pg_ctl.exe') -D $pgData stop -m fast
```

Trong Supabase thật, áp dụng đủ migration bằng workflow migration của nhóm
rồi chạy nguyên hai file SQL test với quyền quản trị trên môi trường test
và ON_ERROR_STOP; không chạy bootstrap fixture. Cần kiểm chứng thêm EXECUTE,
PostgREST/JWT, RLS và Storage với hạ tầng Supabase thực trước nghiệm thu live.
Item redelivery còn chờ plan của Sơn; không đánh dấu S1/S2/S4 toàn bộ hay
P01 foundation tổng thể hoàn tất chỉ vì lớp SQL đọc outbound/pickup đã pass.

Sau kiểm thử đã dừng PostgreSQL native bằng pg_ctl (`server stopped`), giữ
database fixture trong `.temp` để không xóa dữ liệu tự động. Engine Docker
vẫn không phản hồi khi thử dừng container thử `sports_store_p011_test`; lệnh
cleanup CLI đã được hủy sau timeout, không dừng/xóa container hoặc volume của
dự án khác. Khi Docker phục hồi có thể dừng đúng container thử này; không
dùng `db reset --linked` hoặc cleanup diện rộng.

## P01.2 — Dart read adapters và giới hạn tích hợp

P01.2 không thay schema/migration/RLS. Delivery adapter dùng hai read RPC
P01.1 đã có trong repository; COD adapter dùng SELECT cột tường minh trên
cod_collections theo RLS hiện có, không giả định RPC COD đã tồn tại.
Model chỉ chứa snapshot/task/item/COD và UUID tham chiếu, không sao chép Order
hoặc return request chứa thông tin ngân hàng/bằng chứng.

Models/DTO/repository/provider và chi tiết retry/session được ghi ở mục
P01.2 của [api_contracts.md](api_contracts.md). Model money dùng int VND,
timestamp UTC; DTO từ chối tiền vượt integer chính xác trên Flutter web,
không chuyển sang double hoặc thay đơn vị tiền. Pagination client dùng
keyset với filter/order/limit có sẵn, không thêm API ghi hay snapshot version
chưa có; đọc nhiều trang vẫn không là transaction snapshot bất biến.

Kiểm chứng Dart dùng transport MockClient + session/JWT **fixture chỉ trong
test**, không truy cập cloud hoặc tự báo backend thành công. Các adapter
production không import fixture và không có demo fallback. Live integration
vẫn cần xác nhận P01.1 đã áp dụng trên môi trường đích và chạy Auth/RLS thật;
redelivery item plan còn phụ thuộc Sơn (itemsAvailable=false), note/ảnh/
version và các API ghi chưa thuộc phase này. Không chạy lại SQL migration
hoặc thay fixture SQL của P01.1 trong P01.2.

## P02.1 — Task-list query RPC

Migration additive
`supabase/migrations/20261023153729_list_my_delivery_tasks.sql` được tạo bằng
`npx --yes supabase@2.119.0 migration new list_my_delivery_tasks`.
Chỉ thêm `public.list_my_delivery_tasks(delivery_task_kind,text,text,integer,text)`
trả jsonb; chữ ký/kết quả/count/filter/cursor ở [api_contracts.md](api_contracts.md).
Không sửa migration cũ, enum, cột/bảng, trạng thái, inventory/COD, notification
hoặc API ghi. Không thay grants đọc bảng và không thêm/sửa policy RLS.

Owner tiếp tục là sports_store_delivery_reader NOLOGIN/NOINHERIT/NOBYPASSRLS
của P01.1; function stable, search_path rỗng. EXECUTE chỉ authenticated;
PUBLIC/anon/service_role không được cấp. Function kiểm tra auth.uid và role
shipper trong profiles; RLS tiếp tục enforce task assigned đúng user.
Đọc dữ liệu qua read_my_delivery_tasks đã mask, chỉ join delivery_tasks đã
chịu RLS để lấy created_at phục vụ sort `(created_at,id)` giảm dần. Không
đọc orders/return_requests/bank/evidence hoặc hidden recipient để search.
Item JSON giữ nguyên trường của P01.1; created_at chỉ là metadata cursor.

Counts sau kind/search, trước group/cursor/limit; total sau group, trước
cursor/limit. Một snapshot SQL cho page/counts/total; không khóa hàng/ghi
request ledger. Keyset không đóng băng dữ liệu xuyên request. Cùng task đổi
người/null thu hồi quyền shipper cũ, terminal history vẫn mask như P01.1;
không bổ sung assignment archive S4.

Không thêm index: đã có delivery_tasks_assigned_shipper_id_idx cho scope
và primary key cho join ID. Query phải đếm toàn bộ tập được phép sau filter;
sort diễn ra sau projection materialized. Chưa có workload/EXPLAIN chứng minh
index mới giúp phần này; không thêm trigram/index orders cho tìm UUID/tên
hoặc tuyên bố tối ưu lớn khi chưa có dữ liệu thật. Đánh giá lại performance
trên workload thực nếu cần, không đổi quyền để tối ưu.

`supabase/tests/delivery_task_list.sql` là fixture trong BEGIN/ROLLBACK,
được thêm vào runner cô lập hiện có. Bootstrap Auth/Storage chỉ là SQL stub
trên PostgreSQL native, không là Supabase Auth/PostgREST/Storage live. Không
áp dụng migration hoặc reset project cloud trong phase này. Khi nghiệm thu
live cần dùng workflow migration của nhóm và chạy SQL allowed/denied trên
môi trường test Supabase thật, không dùng bootstrap stub trên cloud.

Kiểm chứng cuối: `node supabase/tests/run_delivery_read_fixture.mjs p011_p021_final9`
PASS trên PostgreSQL 17.10 native, đủ 5 migration và ba SQL suites
(database_security.sql, delivery_read_security.sql, delivery_task_list.sql).
Mọi fixture ROLLBACK, xác nhận 0 user/order/task/Storage object còn lại.
Sau kiểm thử đã dừng đúng native server trong `.temp/p011_native_data` bằng
`pg_ctl -D <workspace>/supabase/.temp/p011_native_data stop -m fast` và nhận
`server stopped`; giữ database cô lập, không xóa/reset dữ liệu. Không có
kết quả cloud hoặc PostgREST thật được xác nhận. Lệnh đầy đủ và manifest
Dart/test/docs tại mục bàn giao P02.1 của [api_contracts.md](api_contracts.md).

## P03.1 — Authorized detail projection

Migration additive
`supabase/migrations/20261024010714_get_my_delivery_task.sql` được tạo bằng
`npx --yes supabase@2.119.0 migration new get_my_delivery_task`.
Thêm public.get_my_delivery_task(p_task_id uuid) trả jsonb envelope task/items/
notes/notes_source/as_of. Contract hiện hành ở mục P03.1 api_contracts.md;
get_my_delivery_task ở bảng P00.2 là đề xuất lịch sử trước implementation này.

Không sửa/xóa năm migration trước hoặc thêm bảng/cột/index/enum. Function
stable, search_path rỗng, owner sports_store_delivery_reader NOLOGIN và
NOBYPASSRLS đã có; EXECUTE chỉ authenticated, không PUBLIC/anon/service_role.
Không mở membership cho API roles, không thêm base SELECT grant/policy hoặc
Storage quyền. Task/item nguồn duy nhất là hai read projections P01.1; gate
profiles.role/auth.uid, data và item aggregate trong cùng SQL statement.
Các SELECT bên trong stable function dùng cùng read snapshot, không khóa ghi.

Item projection hạn chế tiếp tục dùng outbound order_items và pickup
return_items theo exact task/kind/current state, không phải mọi item cùng
order theo một assignment cũ. Metadata history/restricted giữ masking P01.1;
đổi người/null thu hồi row, hủy chuyển sang masked history tại lần đọc mới.
FK/PK và index scope/item hiện có đủ cho lookup một task; không có index mới
được thêm khi chưa có bằng chứng workload cần thiết.

Không có schema notes hoặc approved redelivery item plan; API trả explicit
unavailable flags/null như P01.1/P00.2 đã ghi, không backfill dữ liệu đoán.
Không truy vấn raw orders/return_requests/business_events/catalog/Storage;
không có đường đọc bank/refund/video/inspection hoặc cấp signed URL sản phẩm.
Không triển khai write RPC, custody/attempt/COD/inventory/notification.

SQL suite mới `supabase/tests/delivery_task_detail.sql` chạy BEGIN/ROLLBACK
qua runner fixture hiện có; Auth/Storage bootstrap chỉ là SQL stub trên
PostgreSQL native. Khi test Supabase thật dùng suite nguyên vẹn với
ON_ERROR_STOP trên môi trường test, không áp dụng bootstrap stub lên cloud.
Phase này không chạy db push hoặc reset project chung.

Kiểm chứng cuối P03.1: `node supabase/tests/run_delivery_read_fixture.mjs p011_p031_final_20261024g`
PASS trên PostgreSQL 17.10 native fixture. Đủ 6 migration được áp dụng;
4 suites database_security/delivery_read_security/delivery_task_list/
delivery_task_detail PASS và ROLLBACK, xác nhận không còn Auth user/order/
task/Storage object test. Detail suite kiểm tra ACL/owner/STABLE/search_path,
role NOBYPASSRLS, role/task scope, reassignment/cancellation, masking và
aggregate đủ 1001 items. Không ghi là đã chạy Supabase/PostgREST thật.

Native fixture server đã dừng bằng pg_ctl -D <workspace>/supabase/.temp/p011_native_data
stop -m fast (`server stopped`), giữ database trong thư mục ignored để không
xóa dữ liệu. Lệnh, 12 tệp thay đổi và kết quả 107 Flutter tests ở mục bàn giao
P03.1 của [api_contracts.md](api_contracts.md). Notes, redelivery item plan và
asset snapshot/quyền vẫn là dependency chưa có; không thêm schema đoán hoặc
grant đọc orders/returns/Storage để gỡ các dependency đó.

## P03.3 — Outbound assignment write boundary

Migration additive `20261024070151_assign_outbound_delivery_task.sql` bổ sung
RPC assign_delivery_task và hai bảng private.delivery_assignment_requests,
private.delivery_assignment_audits. Không sửa migration cũ/enum/schema order,
không thêm index task khi unique active outbound và index order đã có.
Ledger khóa actor/request lưu payload+response thành công; audit append-only
lưu manager, task/order, old/new shipper và thời điểm server. Không cung cấp
API read/audit history cho shipper từ hai bảng này.

Writer NOLOGIN/NOBYPASSRLS dùng SECURITY DEFINER để thực hiện transaction
nhiều bảng; search_path rỗng, chỉ authenticated có EXECUTE. Internal role
không được cấp cho API roles. Các quyền ghi/cột và RLS riêng chỉ phục vụ
manager assignment; không thêm INSERT/UPDATE cho authenticated và không mở
đọc orders/returns/Storage cho shipper. Read projections P01.1/P03.1 tiếp tục
xác minh assignment hiện tại; audit phân công không tạo quyền đọc task khác.

S3 khởi tạo COD được người dùng chốt: tạo/cập nhật chỉ khi uncollected sạch;
shipper_id theo người được phân công trước nhận hàng; expected bằng order total.
Phần collection/receipt/handed_over và policy customer ngoài scope vẫn mở.
D1 readiness cho lần đầu được chốt như business_states P03.3; D3 custody/lần
hai tiếp tục chặn, không reset count qua task/shipper mới.

Migration chỉ được áp dụng vào database fixture cô lập khi kiểm thử; chưa
khẳng định đã deploy Supabase/PostgREST thật. Không db push/reset cloud.

Đã đối chiếu hướng dẫn Supabase về database functions và RLS:
[Database functions](https://supabase.com/docs/guides/database/functions),
[Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security).
SECURITY DEFINER ở đây phục vụ transaction được giao, có owner không BYPASSRLS,
search_path rỗng và EXECUTE giới hạn; không dùng để bỏ kiểm tra caller.

## P04.1 — Chặn triển khai khi thiếu dispatch/cancel/custody

Người dùng xác nhận ngày 24/10/2026: chưa có primitive xuất kho của Văn Đức
và RPC hủy đơn của Bảo. Bảy migration hiện tại chưa chứa accept/start. Các
cột product_variants.on_hand/reserved/damaged và inventory_movements là dữ
liệu nền, không là transaction dispatch. Unique(event_id,variant_id) không
ngăn cùng order xuất lại với event mới. Chưa có proof custody/dispatch theo
order hoặc contract lần hai D3; accepted_at/assigned_shipper_id không đủ thay.

P04.1 chỉ thêm pg_temp SQL interface fixture + test fail-closed, không migration,
RPC public, schema/quyền runtime hoặc policy mới. Không cấp shipper quyền sửa
product_variants/orders/tasks để gỡ dependency. Chưa có RPC start riêng được
bật cho task accepted seed thủ công, vì không thể chứng minh custody hợp lệ.

Cần owner chốt order-level dispatch key/proof, custody actor/holder/items,
ledger/version và lock order→tasks→variants chung với cancel. Assignment
ledger/audit P03.3 giữ phạm vi riêng. Chi tiết handoff và tiêu chí chưa đạt ở
mục P04.1 api_contracts.md. Không triển khai inventory/cancel thay owner.

Bổ sung theo lựa chọn demo cô lập của người dùng: schema p041_demo chỉ được
cài tạm bởi runner opt-in trong database fixture mới, không phải migration.
Mọi actors/orders/tasks/variants/dispatch/custody/requests mô phỏng tách khỏi
bảng public; dọn schema sau concurrency. Không áp dụng file .sql.fixture lên
Supabase/cloud. Xem [hướng dẫn demo](demos/p041_outbound_demo.md).

## P04.2 — Không thay schema/API database

Hai Dart draft interfaces và test-only action harness không tạo migration,
function, quyền RLS/grants, custody hoặc inventory primitive. P04.1 demo không
được đưa vào repository runtime. Accept/start live vẫn chưa có; contract và
blockers tại [handoff P04.2](demos/p042_outbound_actions_fixture.md).

## P05.1 — Completion chưa có migration/API live

Baseline delivery_attempts unique task và (order_id,attempt_number), COD CHECKs
và notification unique(recipient_id,event_id) chỉ bảo vệ hình dạng/trùng row,
không là transaction complete. Event_type/payload/mapping D7/S2 và custody/
version proof còn thiếu; không tái dùng assignment ledger cho completion ngầm.

Phase này chỉ thêm p051_fixture trong database native test opt-in; không thay
schema public/private, grants/RLS, enum hoặc migrations. Generated total fixture
và full clean COD được kiểm tra cùng một transaction; cấu hình recipients/custody
chỉ seed test. [Handoff P05.1](demos/p051_outbound_completion_fixture.md).
Không deploy cloud hoặc báo complete_outbound_delivery đã tồn tại live.

## P05.2 — Không thay database contracts live

Draft Dart interfaces và UI/provider tests không thêm migration/RPC/schema,
RLS/grants hoặc server event. P05.1 fixture signature không được xem là API đã
deploy. Không tính thêm phí ở client, không ghi COD trực tiếp từ widget.
[Handoff P05.2](demos/p052_successful_delivery_fixture.md).

## P06.1 — COD list projection

Thêm read function list_cod_collections trên cod_collections hiện có; không
thêm bảng tài chính hoặc thay enum/check/amount. Xem contract hiện hành tại
[api_contracts.md](api_contracts.md#p061--role-scoped-cod-list-api-25102026) và
[handoff P06.1](demos/p061_cod_list_api.md) cho tên migration/kết quả local.

Authorization mỗi lần gọi từ auth.uid/profile server. Shipper đọc khoản thuộc
shipper_id của mình, không theo task mới hoặc collected_by do client cung cấp;
manager có scope global/order/shipper. Assignment task thay đổi không tự chuyển
holder COD đã thu. Endpoint không join orders/returns/refunds, không sửa nghĩa
vụ trong các quy trình đó. Policy customer đọc COD baseline vẫn giữ, chưa giải
quyết đề xuất thu hẹp customer S3 và không tuyên bố đã giải quyết privacy đó.

Order code chưa có cột riêng, projection ghi rõ order_uuid. API read không
khóa ghi hoặc tạo event/idempotency ledger; page/count/outstanding dùng cùng
snapshot statement. Không thay RPC assignment/completion/receipt hay RLS ghi.

## P06.3 — Receipt write theo quyết định người dùng

P06.3 thêm function confirm_cod_received và private.cod_receipt_requests riêng,
không dùng assignment ledger. Actor/request PK lưu operation/order/exact amount/
hash/result; unique order bảo vệ một receipt thành công; append-only và không
grant client đọc/ghi ledger. Không đổi cod enum/check hoặc mở quyền ghi COD
trực tiếp cho authenticated. Role write nội bộ NOLOGIN/NOBYPASSRLS với grants
theo cột/policy riêng; SECURITY DEFINER là boundary nghiệp vụ có kiểm tra role,
không là cách bypass RLS. Không tạo global operation/version cho phase khác.

Người dùng đã chốt S3 simultaneous handover/receipt giờ server, D7 notify chỉ
holder và ledger receipt riêng. Không ghi nhận teammate approvals. Collect/
inventory/custody/assignment quyết định khác giữ nguyên; collection P05.1 live
vẫn thiếu. Event dùng business_events hiện có, không giả có event_type mới;
client request được map trong private ledger, business_events.request_id dùng
event UUID server vì unique toàn cục hiện hữu. Notification dedupe theo
(recipient_id,event_id). Receipt không đổi expected/collected/holder hoặc
giảm nghĩa vụ theo refund; mọi side effect rollback khi có lỗi.

Migration/kiểm tra và trạng thái cloud: [P06.3](demos/p063_cod_receipt_api.md).

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
## P04.2 — Client production, không đổi database (26/10/2026)

Adapter MH11 gọi hai RPC accept_delivery_task/start_delivery_task đã deploy ở P04.1; không có migration/grant/RLS mới. Kết luận fixture-only P04.2 phía trên được thay thế cho accept/start. Các mutation completion/failure/reporting chưa được suy ra là production.

Chi tiết phạm vi, retry, kiểm thử và giới hạn live: [P04.2 production](demos/p042_production_outbound_actions.md).

## P05.1 — Schema production và cloud deployment (26/10/2026)

Migration CLI thật `20261026130645_complete_outbound_delivery.sql` đã deploy project bqoyfytmrtvjwrpshuhh, 12 local=12 remote. Thêm private.outbound_completion_requests (PK actor/request, payload/ACK) và private.outbound_completion_results (PK task, unique order/attempt và event/request). Ledgers force RLS/append-only, không client grants. Internal NOLOGIN/NOINHERIT/NOBYPASSRLS completion writer được grant tối thiểu; dùng private identity bridge, search_path rỗng. Không mở general order/item/Auth/Storage reads.

RPC completion atomic trên delivery_attempts/delivery_tasks/orders/cod_collections/business_events/notifications, ghi server amount/by/time; COD chỉ collected, receipt manager là P06.3 riêng. Event reason=delivery_completed, không thêm event_type. P04 proof validator được gọi lại trước tiền. 14 SQL suites+4 concurrency native PASS; 9 scoped SQL cloud suites PASS; real JWT/UI P04→P05 PASS, scoped test rows/accounts cleanup. Các ghi chú P05 fixture-only phía trên là lịch sử đã được thay thế trong phạm vi này. [Schema/manifest/lệnh/giới hạn](demos/p051_p052_production_outbound_completion.md).

## P06.1–P06.4 — Nghiệm thu live 27/10/2026

Các ghi chú P06 trước đây “chưa deploy/chưa nghiệm thu cloud” là mốc lịch sử. Đã nghiệm thu real Auth/JWT + CodRoutePage shipper/manager + production repositories/RPC trên project bqoyfytmrtvjwrpshuhh: phân trang hơn100 records, own-only/manager UUID filters, full receipt550.000, lost-ACK retry giữ key, simultaneous managers chỉ một receipt, COD không offset refund, và account-switch cache cleanup. Hai cloud SQL suites P06 PASS/ROLLBACK. Sửa one-shot latch dialog chống double pop; không migration/RLS/API mới.

Cleanup xác nhận không còn fixture accounts/orders/COD/returns/receipts/notifications; giữ3products có sẵn. Live là Flutter widget runner nối cloud, chưa điện thoại vật lý/MH17 renderer. Phạm vi/lệnh/manifest, fixture phân trang có nhãn và kết quả chi tiết: [P06 live acceptance](demos/p06_live_acceptance.md).

## P07.1 — Failure schema (27/10/2026)

Migration CLI `20261027060030_fail_outbound_delivery.sql` thêm nullable `delivery_attempts.failure_reason_code`/`failure_reason_description`, giữ tương thích result legacy/success; private.outbound_failure_requests/results append-only/force RLS và internal failure writer NOLOGIN/NOINHERIT/NOBYPASSRLS. Không cấp client đọc ledgers hoặc mở general order/item/return/Storage. `business_events.request_id` của failure là UUID do server sinh; client request thuộc ledger actor/key, nên hai shipper dùng trùng client UUID không xung đột event.

RPC ghi result/task/order/event/notification/ledgers trong một transaction; không đổi COD/tồn. Failure writer chỉ có UPDATE(order_id) trên COD để SELECT FOR UPDATE; policy WITH CHECK(false) chặn ghi COD thực tế. Mã/lý do cấu trúc giữ riêng, legacy reason phục vụ tương thích. Đồng bộ ba migration checkout từ đúng SQL đã lưu cloud, không sửa nguồn đồng đội hoặc repair lịch sử. [Manifest, cross-operation idempotency, migration provenance và kiểm thử](demos/p071_production_outbound_failure.md).

## P07.2 — Outbound retry decision schema (27/10/2026)

Migration CLI `20261027062118_decide_outbound_retry.sql` dành cho manager decision; private request/decision ledgers riêng, append-only/force RLS, internal NOLOGIN/NOINHERIT/NOBYPASSRLS writer. Không ghi vào ledger assignment/COD để giả custody. Tạo task2 theo snapshot server và holder hiện giữ hàng; không sửa task1/result1/dispatch/inventory/COD/counter. Task2 custody chỉ được ghi bởi accept thực hiện sau quyết định.

Guard custody chỉ được mở ngoại lệ có bằng chứng decision server để hủy task2 chưa start khi chuyển hoàn, giữ nguyên cấm đổi assigned fields sau nhận hàng. Không tắt RLS/trigger/FK hoặc dùng GUC client để vượt guard. [Schema/ACL/transaction/manifest và kết quả deploy](demos/p072_production_outbound_retry.md).

## P07.4 — Reporting schema production (27/10/2026)

Migration CLI 20261027093919_report_delivery_handover_incidents.sql đã deploy. Thêm private.outbound_reporting_requests (PK actor/request, operation/payload/hash/ACK) dùng chung hai RPC, private.outbound_handover_reports (PK order) và internal sports_store_outbound_reporting_writer NOLOGIN/NOINHERIT/NOBYPASSRLS. Ledgers force RLS/append-only, không client grants. Public wrappers report_store_handover/task+request+items và report_delivery_incident/task+request+enum+reason chạy với writer bị giới hạn; helper private không executable bởi client, search_path rỗng, không Auth schema grant.

Khóa request→shared order advisory→order→outbound tasks UUID→COD; role/assignment/holder recheck trước replay. Chỉ INSERT report/event/notification; các grant UPDATE khóa id/order_id có WITH CHECK(false), không đổi state/COD/tồn/attempt. Historical dispatch validator đọc proof cũ nhưng không coi damaged là thiếu quantity; handover full bị chặn nếu có lost. Không sửa proofvalidator hiện tại của accept/start/fail/complete. Event request_id là UUID server, client key giữ riêng ledger. Notification chỉ profiles role manager, không customer. Pickup/redelivery UNSUPPORTED_TASK_KIND. [Contract/schema/checks/giới hạn](demos/p074_production_delivery_reporting.md).
