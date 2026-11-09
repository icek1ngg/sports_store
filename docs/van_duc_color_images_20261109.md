# Ảnh theo màu MH05 — 09/11/2026

Đã bổ sung 52 ảnh cho 13 sản phẩm demo: 5 giày và 8 mẫu quần áo, mỗi mẫu
4 màu. Mỗi màu có ảnh riêng; chọn màu giữ cỡ nếu có và đổi gallery theo
biến thể đang chọn. 12 ảnh tham khảo giữ nguyên; 40 ảnh phối màu bằng AI
có dòng “Ảnh phối màu minh họa bằng AI.”. Đây là dữ liệu demo, không xác
nhận bảng màu thương mại của nhà sản xuất. Riêng S02-C1 được tạo lại vì
ảnh tham khảo ban đầu không khớp nhãn Đen trắng.

## Dữ liệu và cách triển khai

- Bản Git chỉ chứa code và metadata. 52 ảnh nguồn tại
  `assets/images/stride_color_20261109_*` được giữ riêng trên máy và gitignore.
  Runtime dùng object path `demo/stride-colors-20261109/<file>` trong bucket
  private `product-images`, qua signed-URL provider có kiểm tra quyền.
- Manifest: `supabase/seeds/stride_color_images_20261109.json`.
- Seed: `supabase/seeds/stride_color_images_20261109.sql`. Bản Storage chỉ
  được chạy trên project `bqoyfytmrtvjwrpshuhh` sau khi đủ 52 object thực.
  Chỉ cập nhật metadata ảnh của 340 biến thể demo đã tồn tại và câu mô tả
  ảnh cũ; không thêm biến thể/giữ hàng. `local_source` chỉ phục vụ upload,
  không đưa vào attributes runtime.
- Bốn trường `attributes.image_path`, `image_paths`, `image_source`,
  `image_color` xác định ảnh; các thuộc tính còn lại được giữ nguyên.
- Dùng `tool/upload_stride_color_images.ps1` để upload và tải lại xác minh
  SHA-256 trước khi chạy seed. Seed từ chối thiếu object hoặc bucket public.
  Chạy lại không thay timestamp khi dữ liệu đã đúng. Không sửa schema, RLS,
  RPC hay migration history. Xem [hướng dẫn Storage](storage_color_images_20261109.md).

Bản seed ảnh asset ban đầu đã có 13 sản phẩm, 340 biến thể, 52 đường dẫn,
không có ánh xạ màu sai. Hash giá/tồn/trạng thái trước và sau lần đó đều là
`1dc713f548b492ef960db45b8dd72626`.

## Kiểm chứng

- `flutter analyze --no-pub`: không lỗi.
- 222 bài catalog/cart/checkout/router đạt; 5 bài opt-in bỏ qua.
- Chạy riêng `color_assets_manifest_test.dart` với
  `--dart-define=STRIDE_COLOR_ASSETS_READY=true`: cả 52 file nguồn upload giải mã được;
  mỗi sản phẩm có 4 ảnh với dữ liệu pixel khác nhau; 40 AI/12 tham khảo.
- Fixture PostgreSQL 17 với `STRIDE_COLOR_ASSETS_READY=1`: đủ 340 ánh xạ,
  chạy lặp không thay dữ liệu/timestamp, giữ giá/tồn/reservation/ledger,
  collision rollback; khách đọc được nhưng không sửa metadata, shipper
  không đọc danh mục. Đây là kiểm thử quyền trên fixture cục bộ.
- Log: `build/color_assets_decode.log`, `build/color_images_regression.log`,
  `build/color_images_analyze.log`, `build/stride_color_images_assets_fixture.log`.
- Bản APK debug trước lần chuyển Storage đã đạt. Bản cài cục bộ:
  `build/releases/sports-store-color-images-20261109-debug.apk`. Log build:
  `build/color_images_android_build.log`.

Trong Supabase Table Editor, lọc `product_variants.sku` bắt đầu
`DEMO-STRIDE-20261108-`; xem `attributes.image_color` và `image_path`.
Object path private không phải URL công khai; app ký URL theo quyền đọc.
Muốn dùng ảnh chụp thật, thay metadata bằng URL HTTPS hoặc đường dẫn Storage
đúng phối màu và đổi `image_source` khỏi `ai_color_preview`.
