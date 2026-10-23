# Ánh xạ màn hình Sports Store

Phạm vi chính gồm đúng 20 màn hình (MH01–MH20). Hộp thoại thêm/sửa sản phẩm,
biến thể và bộ chọn vị trí trong màn đặt hàng là thành phần của màn hình tương
ứng, không tạo thêm mã màn hình.

| Mã | Màn hình | Role | Chủ sở hữu | Use case chính |
| --- | --- | --- | --- | --- |
| MH01 | Đăng nhập | Khách, Manager, Shipper | Dung An | Đăng nhập, đăng xuất và điều hướng theo role |
| MH02 | Đăng ký | Khách chưa có tài khoản | Dung An | Đăng ký tài khoản khách với quyền customer |
| MH03 | Quản lý sản phẩm | Manager | Dung An | Thêm/sửa/ngừng bán sản phẩm, biến thể và tồn kho bằng hộp thoại |
| MH04 | Danh sách sản phẩm | Khách | Văn Đức | Xem, tìm kiếm và lọc theo danh mục |
| MH05 | Chi tiết sản phẩm | Khách | Văn Đức | Xem thông tin, chọn biến thể và số lượng |
| MH06 | Giỏ hàng | Khách | Văn Đức | Xem, sửa, xóa món và chuyển sang đặt hàng |
| MH07 | Đơn hàng của khách | Khách | Bảo | Xem đơn, chi tiết, hủy trước khi xác nhận và mở yêu cầu trả |
| MH08 | Danh sách đơn của manager | Manager | Bảo | Lọc trạng thái, xem đơn mới và cảnh báo giao thất bại |
| MH09 | Chi tiết đơn của manager | Manager | Bảo | Xác nhận/từ chối, phân công, giao lại, hoàn và nhận hàng trả |
| MH10 | Danh sách nhiệm vụ shipper | Shipper | Minh Đức | Xem các nhiệm vụ giao đi, lấy hàng trả và giao lại được phân công |
| MH11 | Chi tiết nhiệm vụ | Shipper | Minh Đức | Nhận/bàn giao hàng, cập nhật kết quả, thu COD và báo sự cố |
| MH12 | Đối soát COD | Shipper, Manager | Minh Đức | Shipper xem khoản của mình; manager xác nhận đã nhận đủ tiền |
| MH13 | Tạo yêu cầu trả | Khách | Sơn | Gửi yêu cầu trong hạn, chọn lý do và tải video bằng chứng |
| MH14 | Theo dõi yêu cầu trả của khách | Khách | Sơn | Xem tiến độ, bổ sung bằng chứng và xem kết quả hoàn tiền |
| MH15 | Quản lý yêu cầu trả | Manager | Sơn | Duyệt/từ chối, chỉ định lấy hàng, kiểm tra và ghi hoàn tiền |
| MH16 | Đặt hàng | Khách | Văn Đức | Nhập người nhận, chọn vị trí Hà Nội, tính phí 30.000 VND và đặt COD |
| MH17 | Thông báo | Khách, Manager, Shipper | Bảo | Xem thông báo theo người nhận, lọc chưa đọc và đánh dấu đã đọc |
| MH18 | Bản đồ điểm đến nhiệm vụ | Shipper | Minh Đức | Xem điểm đến đã lưu của nhiệm vụ được phân công; không bắt buộc pin cửa hàng |
| MH19 | Danh sách hội thoại | Khách, Manager | Dung An | Khách mở hội thoại; manager xem danh sách và tin chưa đọc |
| MH20 | Chi tiết hội thoại | Khách, Manager | Sơn | Đọc lịch sử, gửi/nhận tin văn bản và cập nhật đã đọc |

## Điều hướng chính

- Khách: MH01/MH02 → MH04 → MH05 → MH06 → MH16 → MH07.
- Khách trả hàng: MH07 → MH13 → MH14; hỗ trợ: MH19 → MH20.
- Manager: MH08 → MH09; truy cập MH03, MH12, MH15 và MH19 → MH20.
- Shipper: MH10 → MH11 → MH18; MH12 chỉ hiển thị COD của shipper đó.
- MH17 là màn dùng chung theo quyền. Khi mở liên kết từ thông báo, server phải
  kiểm tra lại quyền với đơn, nhiệm vụ, yêu cầu trả hoặc hội thoại.

## P00.1 — Điểm thao tác theo hợp đồng trạng thái

Tham chiếu [bảng chuyển trạng thái P00.1](business_states.md#p001--hợp-đồng-chuyển-trạng-thái-giao-nhận-23102026).
Các mã O/P/R và D bên dưới trỏ tới hàng chuyển trạng thái và quyết định còn mở
trong tài liệu đó. Đây là mapping đề xuất để review, chưa có xác nhận của
Bảo/Sơn/Văn Đức. Không thay đổi số lượng MH01–MH20 hoặc triển khai route.

| Màn / owner | Mốc và hành động | Ranh giới cần giữ |
| --- | --- | --- |
| MH09 / Bảo | O1/O2 phân công; O7 giao đi lần 2; O8 hoàn sớm; O11 nhận hàng thất bại rồi kiểm tra; O12 hủy hợp lệ | Phân công không phải thực nhận; manager nhận/kiểm tra khác shipper báo bàn giao. D1–D5. |
| MH10 / Minh Đức | Hiển thị ba kind và trạng thái task đúng enum; mở MH11 | Không gọi mọi trạng thái ngoài đang giao là hoàn tất. `manager_action_required` cần xử lý; `failed` có thể còn hàng cần hoàn. Không suy ra custody từ nhóm UI. |
| MH11 / Minh Đức | O3/O4 thực nhận tại cửa hàng rồi start; O5/O6/O9 kết quả; O10 báo bàn giao. P2 nhận tại khách, P3 vận chuyển về, P4 thất bại lấy, P5 báo bàn giao. R2/R3 nhận/start, R4/R5 kết quả, R6 báo bàn giao | Một màn theo kind; không có nút shipper xác nhận manager đã nhận/kiểm tra; pickup không kết thúc khi vừa lấy từ khách; redelivery không thu COD. D2/D3/D6/D8/D9. |
| MH15 / Sơn | P1 duyệt thu hồi/phân công, P6 thực nhận tại cửa hàng và mở kiểm tra; R1 quyết định giao lại, R6 nhận hàng giao lại thất bại và giải quyết tiếp | Duyệt lấy không phải duyệt hoàn tiền; thất bại giao lại không đóng request. Chốt mapping enum với Sơn D8/D9. |
| MH07 / Bảo, MH14 / Sơn | Đọc trạng thái order và return tương ứng | Order đã `delivered` không chuyển thành cancelled vì trả hàng; hiển thị chờ manager ở nhánh chưa có kết quả cuối. |
| MH12 / Minh Đức | Shipper xem COD đã thu; manager xác nhận thực nhận đủ từng đơn | Tách bàn giao tiền khỏi bàn giao hàng; trả/hoàn tiền không xóa hoặc bù trừ nghĩa vụ COD. |
| MH16 / Văn Đức | Snapshot đơn và hợp đồng giữ/xuất/nhận tồn hỗ trợ O3/O11/P6 | D4 là phụ thuộc transaction, không chuyển thao tác nhận/kiểm tra của manager sang checkout UI. |
| MH17 / Bảo | Nhận event giao thất bại, bàn giao và các mốc được chốt ở D7 | Recipient và deep link theo quyền hiện tại; nội dung không lộ dữ liệu riêng tư. |

Tại thời điểm P00.1, router chỉ có `/` trong `lib/app/router/app_router.dart`.
Các hàng gộp trong bảng trên chỉ là mô tả màn hình: tạo/phân công phải đọc
riêng O1a/O1b, P1a/P1b, R1a/R1b; MH09 nhận hàng theo O11a rồi kiểm tra
theo O11b; MH11 báo bàn giao theo R6a và MH15 nhận hàng theo R6b. Các mốc
này có actor, tiền điều kiện và tác dụng độc lập trong hợp đồng trạng thái.
Route đề xuất trong kế hoạch (`/shipper/tasks`, `/shipper/tasks/:taskId`,
`/shipper/tasks/:taskId/map`, `/cod`) chưa được đăng ký trong P00.1; mục P01.3
bên dưới ghi trạng thái mới sau tích hợp router.
P00.2 bên dưới xác định phạm vi MH18 theo yêu cầu hiện tại; provider bản đồ
vẫn chưa chọn và không được coi đã chốt qua bảng trạng thái P00.1.
