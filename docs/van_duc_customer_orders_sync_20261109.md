# Đồng bộ đơn khách sau checkout — 09/11/2026

MH07 dùng thương hiệu STRIDE, màu/font chung và tổng thanh toán dạng
`380.000 đ`. Danh sách và phần chi tiết dùng chung `OrderItemImage`, ưu tiên
metadata ảnh trong `OrderItem.attributes` đã được chốt khi đặt đơn.

Chẩn đoán hai đơn trong ảnh phản hồi cho thấy cả hai đã lưu đúng ảnh
`stride_color_20261109_A01_C2.png` (áo Kalenji xanh navy, cỡ L); số lượng
lần lượt 1 và 2 là dữ liệu của hai đơn khác nhau. UI trước đó luôn vẽ
placeholder nên không sử dụng metadata ảnh sẵn có. Không sửa số lượng,
giá, tổng tiền hoặc dữ liệu đơn để khớp ảnh minh họa.

Ảnh được chuẩn hóa bằng cùng quy tắc `ProductVariant.imagePaths` như biên
nhận checkout rồi hiển thị qua provider ảnh chung. Không truy vấn catalog
hiện tại để thay ảnh lịch sử; thiếu hoặc sai metadata vẫn có placeholder
trung thực. Không thêm trường DTO/RPC hay sửa schema/RLS trong lần sửa này.

Sau receipt đã đối chiếu đúng request/chủ sở hữu và kiểm tra lại phiên,
checkout invalidates `orders/` và `notifications/` trong EpochCache của đúng
tài khoản. Danh sách/counters đọc lại aggregate server; không chèn receipt
client vào list hoặc cho phản hồi cũ trước checkout ghi đè kết quả mới.
Lookup khôi phục đơn đã thành công cũng dùng cùng đường cập nhật.

Kiểm chứng: 32 bài widget/customer orders đạt; 13 bài CheckoutViewModel đạt,
gồm vô hiệu hóa đọc cũ sau thành công, khôi phục đơn, lỗi lưu local và giữ
nguyên cache của tài khoản khác. Bộ hồi quy liên quan đạt 427 bài, 1 bài
opt-in bỏ qua; chạy tuần tự vì máy thiếu tài nguyên khi tạo nhiều DartWorker.
Analyze toàn dự án không lỗi. Đã build/cài và chạy app trên emulator-5554
với entry `/customer/orders`. Log: `build/mh07_sync_regression_serial.log`,
`build/mh07_sync_analyze.log`, `build/mh07_sync_run.log`.
Các thao tác hủy/trả hàng, lọc, phân trang và guards được giữ nguyên.

Lần chuyển ảnh sang Storage vẫn cần hoàn tất upload riêng trước khi đẩy
main không có ảnh. Hai snapshot mới hiện đang tham chiếu asset cũ; khi
chuyển hosting cần resolver tương thích đường dẫn lịch sử, không sửa lại
snapshot đơn để lấy ảnh catalog mới. Xem [trạng thái Storage](storage_color_images_20261109.md).
