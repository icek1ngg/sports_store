# MH06 — giỏ hàng STRIDE

Giỏ hàng dùng bố cục ảnh tham khảo và bốn mục điều hướng đã chốt: Sản phẩm,
Đơn hàng, Giỏ hàng, Tài khoản. Dòng hàng có checkbox, ảnh, tên, màu/cỡ,
đơn giá, tăng/giảm, thành tiền, xóa và cảnh báo tồn thấp từ dữ liệu thực.
Thanh tiền hàng/nút đặt nằm cố định trên thanh điều hướng.

Không thêm Saved/Pass, voucher hoặc miễn phí giao hàng. Nội dung vận chuyển
giữ đúng COD tại Hà Nội, phí 30.000 đồng mỗi đơn. MH06 ghi rõ tiền hàng chưa
gồm phí; MH16 cộng phí và server xác nhận tổng cuối cùng.

## Luồng sử dụng

1. Từ MH04/MH05 thêm sản phẩm, mở Giỏ hàng. Mặc định chọn mọi dòng.
2. Bỏ chọn từng món hoặc chọn/bỏ chọn tất cả. Tiền hàng và số dòng đặt cập
   nhật ngay; checkbox không ghi database và không giữ tồn.
3. Tăng/giảm cập nhật giỏ Supabase; xóa bỏ dòng của khách hiện tại. Dòng
   không còn bán vẫn hiện để xóa hoặc bỏ chọn. Nếu số lượng vượt tồn, giảm
   sẽ đưa về tồn khả dụng; hết tồn thì không tăng/giảm để tạo kết quả giả.
4. Bấm Đặt hàng chỉ chuyển các UUID đã chọn sang MH16. Dòng bỏ chọn giữ trong
   giỏ sau khi đặt; giỏ chỉ trừ số lượng mua khi `place_order` commit.

Lựa chọn cục bộ được giữ khi làm mới cùng tài khoản; ID bị xóa được bỏ khỏi
lựa chọn; đổi tài khoản hoặc hủy màn hình thì reset. Route checkout nhận
snapshot ID để việc đổi checkbox bên ngoài không thay yêu cầu đang gửi.
Mã lạ, dòng đã mất hoặc lựa chọn rỗng không tự mở rộng thành toàn bộ giỏ.

Giữ luồng chống lặp có sẵn: quantity là đích tuyệt đối, lỗi chưa rõ kết quả
giữ lệnh để thử lại; trong lúc đó khóa sửa/xóa/chọn và đặt hàng. Yêu cầu đặt
đã lưu trong secure store luôn được lookup/thử lại với ID và nội dung cũ,
kể cả khi giỏ đã bị trừ. Không tự gửi một đơn mới khi mất phản hồi.

## Supabase và phạm vi

Không cần tạo bảng hoặc migration cho lựa chọn checkbox. Dùng `cart_items`,
catalog và RPC `place_order` hiện có. Đã đọc lại policy cloud của
`cart_items`: customer chỉ đọc/thêm/sửa/xóa giỏ có `customer_id = auth.uid()`;
giá và tồn không được ghi từ giỏ. Không tạo giỏ hoặc đơn thử trên tài khoản
thật khi kiểm thử lượt này.

Ảnh riêng của biến thể được ưu tiên; nếu thiếu thì dùng ảnh sản phẩm.
Các sản phẩm STRIDE thêm trước đó vẫn là dữ liệu demo.

## Kiểm tra

Bộ liên quan catalog/cart/checkout/router đã đạt **201 ca**, 3 ca capture
opt-in bỏ qua trong bộ mặc định. `flutter analyze --no-pub` không có lỗi.
Review độc lập đã kiểm tra lựa chọn, scope route, phiên và khôi phục lệnh;
lỗi số lượng dài được sửa và thêm kiểm thử hồi quy.
Capture riêng đã đạt ở 390×1200, 390×844, 320×800 và 1024×900, đã xem ảnh.
Build web `--no-pub --no-wasm-dry-run` thành công; còn cảnh báo font
CupertinoIcons có từ trước, không chặn biên dịch.

Các ca cần đạt: chọn/bỏ chọn cả hàng không còn bán; tiền đúng tập chọn;
URL chỉ mang ID đã chọn; scope checkout giữa hai lựa chọn tách biệt; rỗng/ID
lạ bị chặn; pending request giữ nội dung cũ; từ chối chắc chắn trở về lựa
chọn route cho lần đặt mới; đổi tài khoản xóa lựa chọn; giỏ mất mạng vẫn có
nút thử lại; 320px/cỡ chữ 2 và số lượng dài không tràn.

Ảnh ở `build/cart_storefront_*.png` được render từ UI/font thật và ảnh catalog
cache, không phải bằng chứng đăng nhập cloud trên Chrome. Logs nằm trong
`build/cart_redesign_regression_tests.log`, `build/cart_redesign_analyze.log`,
`build/cart_storefront_visual_test.log`, `build/cart_redesign_web_build.log`.

Chạy `flutter run -d chrome`, đăng nhập khách, thêm các biến thể có màu/cỡ
ở MH05, rồi thử luồng trên. Code lượt này chưa commit/push Git.
