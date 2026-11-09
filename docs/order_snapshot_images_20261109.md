# Ảnh snapshot trong đơn và biên nhận — 09/11/2026

Đơn áo Hà Nội FC có ảnh sản phẩm trong `order_items.product_image_url`,
nhưng hai helper trả item JSON bỏ sót trường này. Attributes của biến thể
chỉ chứa màu/cỡ nên UI không có đường dẫn để hiển thị. Đây là lỗi projection
và hiển thị ảnh; không cần đặt lại đơn hoặc sửa dữ liệu lịch sử.

## Hợp đồng và cách hiển thị

- Danh sách/chi tiết dùng `private.orders_read_items`; checkout placement,
  lookup và replay dùng `private.checkout_items_json`. Cả hai thêm duy nhất
  trường ảnh đã lưu, giữ ACL/configuration/order cũ.
- DTO/model có `productImageUrl` tùy chọn; response cũ hoặc metadata ảnh
  sai vẫn đọc được. Không đổi snapshot sản phẩm, số lượng hay tổng tiền.
- Ảnh chính xác theo màu trong attributes được ưu tiên; thiếu mới lấy ảnh
  sản phẩm của chính đơn. Không đọc catalog hiện tại để thay ảnh quá khứ.
- Card, chi tiết và receipt dùng chung resolver; ảnh chung có mô tả ảnh mẫu,
  không khẳng định đúng màu. Ảnh thiếu hoặc không tải được có placeholder.

Migration local được tạo bằng Supabase CLI 3.0.0, tên
`20261109155043_expose_order_snapshot_product_images.sql`. Áp dụng qua MCP
được cloud ghi version `20261109160242`. Không sửa trực tiếp history.

## Kiểm chứng

- 38 kiểm thử ảnh/DTO/receipt và 63 hồi quy tương thích đạt; log
  `build/order_product_snapshot_fallback_tests.log` và
  `build/order_product_snapshot_regression_tests.log`.
- `flutter analyze` toàn dự án sạch; log
  `build/orders_snapshot_image_global_analyze.log`.
- Fixture PostgreSQL 17 mới chạy 38 migration trước đó: owner/manager nhận
  ảnh, khách khác/shipper/anon bị chặn; legacy null tương thích; đặt hàng,
  lookup, replay và đọc chi tiết cùng ảnh. Catalog sửa sau đó không đổi ảnh
  đơn; migration lặp giữ ACL/OID và hash toàn bộ hàng nghiệp vụ. Log đạt:
  `build/orders_snapshot_image_pg_low_memory_verified.log`.
- Một lượt khởi động fixture trước đó thiếu bộ nhớ Windows; lượt kiểm chứng
  trên dùng shared_buffers 16MB và đã hoàn tất mọi assertion.
- Cloud smoke trong transaction read-only rồi rollback: đúng chủ nhận URL
  đã lưu, khách khác bị từ chối và không đọc được item; hash item không đổi.
- URL ảnh của đơn Hà Nội FC trả HTTP 200, Content-Type image/jpeg.
- Security advisor trước sửa có các cảnh báo RPC SECURITY DEFINER hiện hữu
  và leaked-password protection; hai helper sửa ở đây đều SECURITY INVOKER,
  không thêm grant. Sau sửa các nhóm/số lượng cảnh báo không đổi (46 RPC,
  1 bảng private có RLS không policy, 1 cấu hình mật khẩu). Tham khảo
  [kiểm tra RPC](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)
  và [bảo vệ mật khẩu](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
  Health advisor không có mục cảnh báo.

Sau khi fetch main mới, giữ cả capability mở yêu cầu trả hàng và bản sửa
router session của nhóm; chỉ gộp hai phần tài liệu cùng được thêm ở cuối.
Fixture chạy lại với 39 migration trước đó vẫn đạt toàn bộ assertion; log
`build/orders_snapshot_image_post_merge_pg.log`.

Hồi quy sau merge: 460 bài orders/checkout/router đạt, 1 bài opt-in bỏ qua.
Lệnh đầu chọn thêm nhầm file trợ giúp `test/scenarios/van_duc_purchase_scenario.dart`
không có `main`; lỗi tải test này không phải lỗi ứng dụng. Đã chạy lại đúng
entry `test/van_duc_purchase_flow_test.dart`, thêm 1 bài đạt (tạo đúng một
đơn COD). Analyze toàn dự án sạch sau merge. Log:
`build/order_image_main_merge_tests.log`,
`build/order_image_main_merge_purchase_test.log`,
`build/order_image_main_merge_analyze.log`.

Phần upload 52 ảnh màu lên private Storage là công việc riêng còn chờ CLI
đăng nhập. Không thay các snapshot asset cũ bằng catalog mới; cần resolver
tương thích sau khi upload thật. Xem [trạng thái Storage](storage_color_images_20261109.md).
