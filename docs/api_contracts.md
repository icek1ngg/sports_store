# Hợp đồng truy cập database

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
