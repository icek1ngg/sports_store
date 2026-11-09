# 52 ảnh màu trên Supabase Storage, không đưa ảnh vào Git

Project: `bqoyfytmrtvjwrpshuhh` (`sports_store` / PRM393).
Bucket hiện có: `product-images`, private. Object prefix:
`demo/stride-colors-20261109/`. App dùng đường dẫn object và ký URL theo
quyền customer/manager; không lưu signed URL hết hạn trong database/Git.

## Quy trình upload quản trị

1. Có đủ 52 file nguồn trên máy ở `assets/images/stride_color_20261109_*`.
   Các file này bị gitignore. Manifest JSON có `local_source` để đối chiếu;
   người chỉ chạy app không cần bộ file này.
2. Đăng nhập CLI bằng tài khoản có quyền đúng project:

```powershell
npx --yes supabase@3.0.0 login
./tool/upload_stride_color_images.ps1 -PreflightOnly
./tool/upload_stride_color_images.ps1
```

Script cố định project/bucket/prefix, kiểm tra đủ 52 tên file duy nhất, kích
thước và đường dẫn local nằm trong thư mục ảnh dự án. Mỗi ảnh được upload
qua Storage API với đúng MIME rồi tải lại và so SHA-256. Receipt và log nằm
trong `build/stride_color_storage/<run>/`, không chứa credential.
`-VerifyOnly` chỉ tải và so ảnh đã upload.

3. Chỉ sau khi đủ 52 ảnh đã xác minh, chạy
   `supabase/seeds/stride_color_images_20261109.sql` bằng SQL Editor hoặc MCP
   được cấp quyền. Seed preflight tất cả Storage objects trước mọi UPDATE
   catalog, không ghi giả metadata Storage bằng SQL. Không đổi quyền bucket.
4. Kiểm tra 340 biến thể/52 đường dẫn và giá/tồn trước–sau; mở lại app/làm
   mới MH05 để đọc metadata mới. Các máy khác chỉ cần pull code và đăng nhập.

Manifest giữ đủ 13 mẫu × 4 màu, 40 ảnh phối AI/12 ảnh tham khảo. Bản Storage
không thay chính sách ảnh AI, giá, tồn kho hoặc snapshot đơn cũ. Kiểm thử
fixture local gồm đơn tạo qua RPC trước khi đổi ảnh, RLS đọc/ghi,
idempotency và rollback khi thiếu object. Log:
`build/stride_color_storage_fixture.log`, `build/storage_color_manifest_test.log`.

Sau khi chuyển manifest: 410 bài kiểm thử chức năng/catalog/cart/checkout/
maps/router/Auth/adapter đạt, 5 bài opt-in bỏ qua; analyze sạch. Kiểm tra
hai bài manifest/giải mã local chạy riêng đạt. Log:
`build/no_image_git_regression.log`, `build/no_image_git_analyze.log`.

Bản lưu file nguồn có thể đóng gói riêng; không dùng `git push --all` để
phát hành nhánh checkpoint cục bộ chứa ảnh trước lần chuyển Storage này.
Main được tạo lại trên nền main của nhóm, không cần force-push.

## Tình trạng triển khai

Script/manifest/fixture đã sẵn sàng. Upload thực và đổi metadata live chỉ
hoàn tất sau khi CLI được đăng nhập và receipt đủ 52 file; không coi bản
chuẩn bị này là đã upload thành công.
