# Chạy migration Dung An trong Supabase SQL Editor

1. Mở project ứng dụng `bqoyfytmrtvjwrpshuhh` trên Supabase, vào **SQL Editor**,
   tạo truy vấn mới và dùng role quản trị mặc định `postgres`.
2. Mở [dung_an_management.sql](dung_an_management.sql), sao chép **toàn bộ** nội
   dung, dán vào editor và bấm **Run**. Chạy một lần trên schema Sports Store
   hiện có. File đã chứa `BEGIN`/`COMMIT`, nên lỗi ở bất kỳ bước nào sẽ hủy toàn
   bộ lần chạy, không để trạng thái cài đặt dở dang.
3. Thành công sẽ trả dòng `Dung An migration committed. Run
   verify_dung_an_management.sql next.`
4. Chạy toàn bộ [verify_dung_an_management.sql](verify_dung_an_management.sql).
   Đây là truy vấn chỉ đọc, không lấy dữ liệu khách hàng. Kết quả mong đợi:
   - 5 RPC: `installed=true`, `authenticated_can_execute=true`,
     `anon_can_execute=false`.
   - 8 bảng: `installed=true`, `rls_enabled=true`.
   - 2 trigger: `installed=true`, `enabled=true`.
5. Từ thư mục `sports_store`, kiểm tra API và chạy ứng dụng:

   ```powershell
   dart run tool/check_dung_an_backend.dart
   flutter run -d chrome --dart-define-from-file=config/supabase.json
   ```

   Probe API phải in `OK` cho cả năm RPC: hàm đã có và từ chối caller chưa đăng
   nhập. Sau đó đăng nhập ứng dụng để thử thêm/sửa/ngừng bán sản phẩm và nhắn tin.

Nếu báo thiếu schema nền tảng hoặc đối tượng đã tồn tại, giữ nguyên thông báo
lỗi để kiểm tra; không chạy reset hay replay migration nền tảng trên cloud có
dữ liệu. Trong SQL Editor, nếu đã chạy riêng từng đoạn rồi gặp lỗi, chạy
`ROLLBACK;` trước khi chạy lại toàn bộ script.

**Vai trò ứng dụng:** Owner của tài khoản Supabase là quyền quản trị nền tảng.
Để mở MH03, tài khoản đăng nhập **trong ứng dụng** cần có
`public.profiles.role='manager'`. Đăng ký bằng MH02 luôn tạo `customer`;
quản trị viên cấp quyền manager cho đúng ID người dùng trong bảng `profiles`.

**Nguồn migration:** bản SQL Editor được xuất từ
`supabase/migrations/20261029041230_dung_an_management_integration.sql`.
Nếu sửa migration nguồn, chạy `./tool/export_dung_an_sql.ps1` để xuất lại.
SQL Editor không tự ghi lịch sử migration cho Supabase CLI; khi sử dụng CLI
về sau cần đối chiếu lịch sử để không áp dụng lại migration này.

File đã được kiểm thử bằng PostgreSQL nhúng với schema nền tảng và fixture
Auth/Storage. Sau khi bạn báo đã chạy trên cloud, probe ngày 29/10/2026 xác
nhận cả năm RPC đã có và chặn anon đúng quyền; Auth/Data API kết nối được.
Chưa kiểm thử thao tác ghi bằng tài khoản ứng dụng thật trên cloud. Xem
[kết quả kiểm tra](../../docs/features/dung_an_supabase.md).
