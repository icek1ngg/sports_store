# Database Sports Store

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
