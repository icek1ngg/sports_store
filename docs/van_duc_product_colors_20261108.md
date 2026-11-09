# MH05 — chọn màu và cỡ, 08/11/2026

MH05 đã đổi sang bố cục STRIDE theo ảnh tham khảo: ảnh lớn/gallery, tên và
giá, màu dạng pill, cỡ riêng theo màu, tồn khả dụng, số lượng và nút thêm giỏ
cố định dưới màn hình. Gallery chỉ hiện chỉ báo nếu có nhiều ảnh thực sự.
Không thêm đánh giá, giá gạch bỏ hoặc chính sách giao/đổi hàng không có trong
báo cáo. Phí COD tại Hà Nội giữ 30.000 đồng.

## Dữ liệu đã áp dụng

Project `bqoyfytmrtvjwrpshuhh`, seed
`supabase/seeds/stride_color_expansion_20261108.sql` và manifest JSON cùng tên.

| Loại | Sản phẩm | Màu/mẫu | Cỡ | Biến thể |
| --- | ---: | ---: | --- | ---: |
| Giày | 5 | 4 | 36–44 | 180 |
| Quần áo | 8 | 4 | S, M, L, XL, XXL | 160 |

Đây là bộ dữ liệu demo, không xác nhận phối màu thực tế của hãng. Thêm 215
biến thể/215 ledger khởi tạo tồn; 125 biến thể cũ giữ nguyên giá, on_hand,
reserved, damaged và is_active, đối chiếu hash trước/sau. Tổng catalog cùng
10 dụng cụ có sẵn: 23 sản phẩm, 350 biến thể.

Mỗi biến thể có UUID/SKU riêng; giỏ/checkout tiếp tục dùng UUID, không dùng
tên màu làm khóa. Đổi màu giữ cỡ nếu cỡ đó tồn tại; cỡ hết hàng vẫn xem được
nhưng không thêm giỏ. Phiên bản cũ không có màu vẫn chọn được. Refresh giữ
UUID nếu còn và giới hạn lại số lượng theo tồn mới. Thêm giỏ không giữ tồn.

## Xem dữ liệu trên Supabase

1. Mở đúng project `sports_store` → **Table Editor** → `products`. Các sản
   phẩm mẫu có mô tả bắt đầu `[DEMO STRIDE 20261108]`.
2. Sao chép `id` sản phẩm → mở `product_variants`, lọc `product_id` bằng ID
   đó. Giày có 36 dòng, quần áo có 20 dòng.
3. `attributes.color`, `attributes.size`, `attributes.color_hex` điều khiển
   lựa chọn màu/cỡ và chấm màu. `price_vnd` là giá của đúng biến thể;
   `available_quantity` là tồn khả dụng do server tính từ tồn và lượng giữ.
4. Khi thay dữ liệu danh mục, dùng nút làm mới ở MH05. Giá và tồn được kiểm
   tra lại trên server khi đặt đơn.

Ngày 09/11/2026 đã bổ sung đủ 52 ảnh cho 13 mẫu × 4 màu. Bấm màu tại MH05
đổi ảnh theo biến thể; xem [bản cập nhật ảnh màu](van_duc_color_images_20261109.md).
Ảnh do AI phối màu có chú thích riêng. HTTPS và object path trong bucket
private `product-images` vẫn được hỗ trợ. Không sửa tồn/reserved trực tiếp
để mô phỏng đặt đơn; nghiệp vụ giữ hàng dùng RPC giao dịch hiện có.

## Kiểm chứng

- PostgreSQL 17 fixture: đủ ma trận 4 màu, chạy lặp không reset dữ liệu hoặc
  nhân movement; giữ giá/giữ hàng/metadata; SKU sai rollback toàn giao dịch;
  customer đọc được nhưng không sửa tồn, shipper không đọc catalog.
- 142 kiểm thử catalog/cart/router đạt; 2 visual opt-in bỏ qua trong bộ này.
  Capture MH05 chạy riêng đạt với ảnh cache ở 390×1400, 390×844, 320×800 cho
  cả giày và áo. Đây là render fixture, không phải đăng nhập cloud trên trình
  duyệt. Kiểm thử bổ sung gồm đường chọn legacy, 50 ảnh/320px/cỡ chữ 2,
  thứ tự cỡ, chọn màu giữ cỡ, hết hàng và đúng UUID/số lượng gửi vào giỏ.
- `flutter analyze --no-pub`: không lỗi; build web đạt. Build vẫn có cảnh báo
  font CupertinoIcons có sẵn từ trước, không chặn biên dịch.
- Log: `build/mh05_color_regression_tests.log`,
  `build/details_color_analyze.log`, `build/stride_color_fixture_verified.log`,
  `build/product_details_visual_test.log`, `build/mh05_color_web_build.log`.

Code lượt này chưa commit/push; dữ liệu seed đã ghi lên Supabase.
