# Tạo đơn demo các màn shipper

Script: `supabase/seeds/demo_shipper_screens.sql`.

## Chuẩn bị và chạy

1. Dùng database demo đã áp dụng đầy đủ migrations trong repository.
2. Có tài khoản Auth và bản ghi `profiles` tương ứng cho customer, manager và shipper. Script không tạo tài khoản hoặc đổi quyền.
3. Chạy `supabase/seeds/demo_products_20261030.sql` nếu chưa có sản phẩm demo. Seed sản phẩm yêu cầu danh mục tên `Dụng cụ` đã tồn tại; các biến thể demo cần còn đủ tồn kho và đang hoạt động.
4. Mở script đơn hàng, sửa các email cấu hình cho đúng tài khoản demo.
5. Trong Supabase SQL Editor của database demo, chạy toàn bộ script với quyền `postgres`. Xem bảng kết quả cuối script để lấy mã đơn, nhiệm vụ và trạng thái.
6. Đăng nhập ứng dụng bằng tài khoản shipper đã cấu hình và tải lại danh sách.

Script dùng RPC đặt đơn và giao hàng để tạo snapshot, giữ/trừ tồn, ghi nhận COD và dữ liệu liên quan. Bước xác nhận đơn dùng cập nhật quản trị có ghi business event, giống seed cũ, vì repository chưa có RPC xác nhận đơn. Dữ liệu có nhãn DEMO, địa điểm công cộng tại Hà Nội và số điện thoại minh họa; không dùng để giao thật.

## Kiểm tra trên ứng dụng

| Màn | Nội dung demo |
| --- | --- |
| MH10 | Nhiệm vụ được phân công, đang giao và đã hoàn thành |
| MH11 | Người nhận, địa chỉ, sản phẩm, số tiền COD; thao tác nhận hàng/bắt đầu giao trên nhiệm vụ mới |
| MH12 | COD shipper đã thu nhưng chưa nộp và COD cửa hàng đã nhận |
| MH18 | Mở bản đồ từ nhiệm vụ đang hoạt động có tọa độ Hà Nội |

Chạy lại cùng cấu hình sẽ bỏ qua đơn đã tạo, không đưa đơn đã thao tác về trạng thái ban đầu. Script chạy trong một transaction; lỗi trong phần tạo dữ liệu sẽ rollback phần tạo mới của lần chạy đó. Script có tác động tồn kho demo và tạo nghĩa vụ COD demo; không chạy trên database vận hành thật.

Phạm vi seed là giao hàng đi và đối soát COD; không tạo yêu cầu trả hàng, nhiệm vụ lấy hàng trả hoặc giao lại sau kiểm định.

## Giới hạn kiểm chứng

Đối chiếu SQL với migrations trong repository. Chưa thực thi trên database ở môi trường soạn script do Docker daemon chưa chạy và chưa có PostgreSQL local khả dụng. Sau khi chạy, kiểm tra bảng kết quả và các màn theo bảng trên; không coi kiểm tra tĩnh là bằng chứng đã kết nối backend thành công.
