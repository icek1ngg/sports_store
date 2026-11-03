# Xem lại chi tiết nhiệm vụ của shipper

## Yêu cầu ngày 02/11/2026

Shipper vẫn được xem thông tin nhiệm vụ đang thuộc mình sau khi giao xong
hoặc thất bại: mã đơn, người nhận, địa chỉ, hàng hóa, thời điểm và COD.
Không coi nhiệm vụ đã kết thúc là lý do để xóa toàn bộ dữ liệu trên MH11.
Quyền xem lịch sử không đồng nghĩa quyền nhận hàng hay giao thêm lần nữa.

## Ranh giới

- Backend kiểm tra role shipper và phân công hiện tại. Không có quyền thì
  từ chối toàn bộ chi tiết, không trả dữ liệu khách khác.
- Dùng snapshot đã lưu của nhiệm vụ/hàng, không dựng lại địa chỉ hoặc giá
  từ hồ sơ khách/catalog hiện tại.
- COD đọc từ ledger theo đơn và người giữ tiền, không suy đoán thu tiền từ
  trạng thái nhiệm vụ. Hai lần giao cùng đơn không tạo hai nghĩa vụ COD.
- Lấy hàng trả và giao lại hàng trả không thu COD lần nữa.
- Không có dữ liệu ghi chú trong schema thì hiển thị chưa có ghi chú;
  không gán nhầm thành dữ liệu bị giới hạn.
- Bản đồ và các lệnh giao hàng vẫn giữ kiểm tra trạng thái/quyền hiện có.
- Không thêm lại báo sự cố, điểm cửa hàng hoặc đổi shipper; người dùng đã
  loại các chức năng này khỏi yêu cầu hiện tại.

## Hợp đồng và kiểm chứng

- API bổ sung `get_my_delivery_task_history(p_task_id uuid)` cho MH11,
  giữ nguyên các API list/read/detail cũ để không làm lỗi bản app cũ.
- Task hoạt động dùng scope `current`; lịch sử được phép xem đầy đủ dùng
  scope `history` trong API mới. Adapter bật chế độ `allowReadableHistory`
  chỉ khi đọc API mới. API cũ vẫn kiểm tra `history` bị che như hợp đồng cũ,
  không đánh đồng hai cách đọc. Nhiệm vụ chờ quản lý xử lý sau giao lại cũng
  được đọc như lịch sử, không mở quyền thao tác; chưa phân công thì từ chối.
- Response bổ sung `cod` (trạng thái, số tiền dự kiến/đã thu/đã nhận và
  timestamps từ ledger) và `capabilities.can_retry` do server tính.
- Chỉ hiện giao lần hai khi server cho phép; task lần một đã có lần hai
  hoặc đã chuyển hoàn sớm không hiện nút giao lại trên chi tiết lịch sử.

## Kiểm chứng ngày 03/11/2026

- `flutter analyze`: không có vấn đề.
- `flutter test test/features/deliveries test/features/cod test/app`: 589 test đạt,
  gồm điều hướng bản đồ, thay đổi quyền, lịch sử và giao lại.
- Toàn bộ SQL fixture và concurrency regression đạt trên PostgreSQL 17 cục bộ;
  cleanup xác nhận 52 bảng không còn dữ liệu fixture sau rollback.
- Review độc lập không phát hiện lỗi phân quyền nghiêm trọng. Đã sửa thông báo
  lịch sử để không mâu thuẫn với quyền giao lần hai và thêm test capability ở MH11.
- `flutter build apk --debug --no-pub --dart-define-from-file=config/supabase.json`:
  đạt; APK tại `build/app/outputs/flutter-apk/app-debug.apk`.
- Kiểm tra hosted phát hiện role đọc không có quyền schema `auth`. Bản sửa dùng
  lại `private.delivery_request_user_id()` có sẵn; không mở quyền bảng Auth.
- Đã triển khai riêng hai migration lên `bqoyfytmrtvjwrpshuhh`:
  `20261102133026_shipper_history_detail_projection.sql` → cloud `20261103022045`;
  `20261103022144_shipper_history_detail_auth_acl.sql` → cloud `20261103022454`.
- Kiểm tra đúng nhiệm vụ trong ảnh bằng role authenticated của shipper:
  trạng thái failed/history, có người nhận và địa chỉ, 2 dòng hàng, COD dự kiến
  1.285.000 VND, chưa thu/chưa nhận tiền, không còn quyền giao lần ba.
  API cũ vẫn che lịch sử như trước. Không đổi trạng thái dữ liệu demo để kiểm tra.
- Kiểm thử SQL bổ sung đã thu hồi quyền schema auth của reader để mô phỏng hosted;
  toàn bộ regression vẫn đạt. Review độc lập corrective migration không có finding.
- Security advisor: 2 INFO private RLS và 1 cảnh báo bảo vệ mật khẩu không đổi;
  cảnh báo authenticated SECURITY DEFINER tăng 40 → 41 do API mới có chủ đích.
  RPC dùng owner NOLOGIN/NOBYPASSRLS, search_path rỗng, kiểm tra role/phân công;
  anon/service_role không có EXECUTE, authenticated có EXECUTE.
  [Giải thích advisor](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
