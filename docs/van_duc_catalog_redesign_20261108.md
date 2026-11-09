# MH04 STRIDE và dữ liệu quần áo/giày — 08/11/2026

## Thiết kế và các thao tác

Theo ảnh tham chiếu của Văn Đức: hai thanh thương hiệu phía trên, tìm kiếm,
bộ lọc, danh mục dạng pill, tiêu đề bộ sưu tập, lưới hai cột trên điện thoại,
thẻ ảnh nền xám, nhãn tồn/đa cỡ và khối giới thiệu cuối danh sách. Máy tính
hiển thị ba/bốn cột; màn nhỏ với chữ lớn chuyển một cột để đọc được nội dung.

Thanh dưới theo lựa chọn của người dùng: **Sản phẩm, Đơn hàng, Giỏ hàng,
Tài khoản**. Tài khoản là bottom sheet chứa hồ sơ hiện tại, liên hệ cửa hàng
và đăng xuất. Không thêm màn chính hay chính sách thành viên mới.

- Tìm kiếm theo tên, Enter/tìm kiếm để gửi truy vấn; có xóa từ khóa.
- Bộ lọc chỉ hiện sản phẩm có ít nhất một biến thể active còn tồn khả dụng.
- Sắp xếp tên A–Z, tên Z–A, mới nhất: áp dụng ở database trước phân trang.
- Bộ đếm là số sản phẩm **trên trang**, không giả làm tổng số toàn catalog.
- Giỏ dùng số lượng thực từ `cartProvider`; mở chi tiết bằng UUID sản phẩm.
- Thẻ giới thiệu giữ quy định COD Hà Nội, phí 30.000 VND; không thêm miễn phí
  giao toàn quốc hoặc khuyến mại như nội dung minh họa trong ảnh tham chiếu.

## Nối Đơn hàng

Route `/customer/orders` mở MH07 hiện có của Bảo, dùng models, DTO v1.2,
ViewModels và repository contract chung. `SupabaseOrderRepository` nối các RPC
đã có trên cloud: `get_customer_orders`, `get_manager_orders`,
`get_order_details`, `confirm_order`, `reject_order`, `cancel_customer_order`,
`cancel_manager_order`, `get_order_operation_result`.

Khi hợp nhất main ngày 09/11/2026, giữ adapter aggregate chính thức của Bảo
với `client/readSession`, nối qua `productionFeatureOverrides` và lifecycle
chung. `/customer/orders` dùng `FourScreenRouteBoundary` ở root, thanh khách
nằm trong boundary này; catalog/cart giữ operational shell hiện có.
Customer chỉ nhận đơn của mình; thay đổi tài khoản vô hiệu hóa kết quả cũ.
Giữ cơ chế journal/khôi phục lệnh của module đơn hàng; không thay bằng adapter
checkout, không giả lập biên nhận khi mất phản hồi.

Giới hạn API hiện tại: chi tiết đơn có thể trả `delivery_summary` và
`cod_summary` null, `history_complete = false`; adapter giữ đúng dữ liệu server.
Không sửa schema/RPC đơn hàng trong lượt giao diện này.

## Dữ liệu đã thêm trên Supabase

Đúng project `bqoyfytmrtvjwrpshuhh`, qua kết nối tài khoản `duc`:

| Danh mục | Sản phẩm | Biến thể |
| --- | ---: | ---: |
| Quần áo | 8 | 80 |
| Giày | 5 | 45 |
| Dụng cụ có sẵn | 10 | 10 |
| Tổng | 23 | 135 |

Seed `supabase/seeds/stride_apparel_shoes_20261108.sql` đã chạy trên cloud.
File JSON cùng tên lưu danh mục sản phẩm, cỡ, màu, giá minh họa và URL ảnh.
Giày có cỡ 36–44; quần áo có S–XXL, hai màu mỗi mẫu. Có 13 biến thể hết hàng
để kiểm tra MH05. 112 biến thể có tồn ban đầu có ledger `adjustment` tương ứng.

Đây là **dữ liệu mẫu**, có marker trong mô tả và SKU `DEMO-STRIDE-20261108-*`.
Giá, chất liệu và tồn minh họa; ảnh có thể không thể hiện tất cả màu biến thể.
Không xác nhận dữ liệu này là danh mục thương mại chính thức của các nhãn hàng.
Không ghi đè 10 sản phẩm dụng cụ hoặc đơn hàng hiện có.

Seed lấy UUID danh mục từ code, tạo UUID sản phẩm/biến thể ở database; dùng SKU
và khóa giao dịch để chống tạo trùng. Chạy lại giữ nguyên giá, tồn, reservation,
ảnh đã chỉnh và ledger; SKU trùng khác sản phẩm bị từ chối. Không thay schema
hoặc RLS nên đây là seed dữ liệu, không phải migration.

Ảnh HTTPS theo contract MH03 hiện có. Đã kiểm tra tải đủ 13 ảnh, HTTP 200 và
CORS `*`. Nguồn: [DummyJSON](https://dummyjson.com/products/category/mens-shoes),
[Decathlon](https://www.decathlon.co.uk/vc/kiprun-shorts),
[tasc](https://www.tascperformance.com/products/carrollton-fitness-t-shirt-11),
[STRT SPLY](https://strtsply.com/products/preloved-nike-dri-fit-miler-1-0-t-shirt-burnt-orange).
URL có thể thay đổi về sau; ảnh lỗi có nút thử lại và không làm giả dữ liệu sản phẩm.

## Kiểm tra và chạy

- `supabase/tests/run_stride_seed_fixture.mjs`: PostgreSQL 17 cô lập, cùng
  toàn bộ migrations; 13 sản phẩm/125 biến thể/112 ledger, chạy lặp không đổi,
  giữ reservation/giá đã sửa, customer đọc được và không sửa tồn, shipper bị
  chặn đọc catalog. Không dùng database cloud để tạo các tài khoản fixture.
- Adapter Orders: kiểm thử envelope, phân quyền, phiên và biên nhận với HTTP
  fixture; không tạo đơn hoặc gọi mutation production khi chạy bộ mặc định.
- `test/features/catalog/storefront_visual_test.dart`: chụp opt-in các màn
  320px, 390px và desktop với UI thật, font thật và ảnh seed cache cục bộ.
  Đây là hình render fixture, không phải bằng chứng đăng nhập cloud trên Chrome.
- Các kết quả kiểm thử cuối và ảnh kiểm chứng nằm trong `build/`, không đưa
  mật khẩu/token hoặc ảnh cache vào source.

Kết quả cuối: `flutter analyze --no-pub` sạch; bộ mặc định đạt **1.756 test**,
bỏ qua 10 ca opt-in/ngoài môi trường; bộ liên quan catalog/router/Orders đạt
70 ca. Visual capture opt-in đạt ở 390×1440, 390×844, 320×800 và 1024×900.
`flutter build web --no-pub --no-wasm-dry-run` đạt. Các file log:
`build/catalog_redesign_full_tests_final.log`, `build/catalog_redesign_analyze.log`,
`build/catalog_storefront_capture.log`, `build/catalog_redesign_web_build.log`,
`build/stride_seed_fixture.log`.

Code của lượt này chưa commit/push. `.metadata` và `pubspec.lock` đã có thay
đổi từ trước lượt này, được giữ nguyên. Dữ liệu seed đã được ghi lên cloud như
bảng số lượng ở trên.

Chạy ứng dụng bằng `flutter run -d chrome`. Cấu hình public Supabase hiện có
được nạp theo entry point production. Đăng nhập tài khoản khách, thử danh mục
Giày/Quần áo, chọn cỡ ở MH05 và thêm giỏ; các thao tác đặt hàng vẫn kiểm tra tồn
và giá lại ở server theo contract checkout chung.
