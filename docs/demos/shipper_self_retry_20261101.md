# Giao lại lần hai do shipper chủ động — 01/11/2026

## Yêu cầu mới

Shipper ghi lý do giao thất bại trực tiếp, không cần quản lý duyệt lý do.
Sau lần đầu thất bại, chính người đang giữ hàng được yêu cầu giao lần hai.
Quyết định này thay quy tắc cũ bắt buộc quản lý chọn retry trong P07.2.

## Hợp đồng

- `fail_delivery_task` giữ nguyên chữ ký và biên nhận: task lần một thành
  `failed`, order `awaiting_redelivery`; không tự xuất kho, thu COD hoặc tạo
  kết quả lần hai.
- `retry_outbound_delivery_task(p_task_id uuid, p_request_id uuid)` chỉ dành
  cho shipper đang được phân công task outbound thất bại lần một. Server suy
  ra order, kiểm tra role hiện tại và người giữ hàng, rồi dùng giao dịch
  `decide_outbound_retry(..., 'retry', ...)` hiện có.
- Kết quả là task mới lần hai `assigned`, cùng shipper, order `awaiting_pickup`.
  Biên nhận JSON theo hợp đồng `decide_outbound_retry`, gồm `task_id`,
  `failed_task_id`, `retry_task_id`, `order_id`, `operation`, `decision`,
  trạng thái task/order, số lần dự kiến/thực tế, holder, timestamps, event và
  request ID. Client xác minh biên nhận và đọc lại dữ liệu trước khi dùng.
- `request_id` phải giữ nguyên khi kết quả mạng chưa rõ. Khóa order và ledger
  đảm bảo chỉ có một task lần hai dù bấm lặp/cạnh tranh với quản lý.
- Nhận hàng lần hai xác nhận tiếp tục giữ hàng; không xuất tồn lần nữa.
  `start_delivery_task` mới tăng bộ đếm từ một lên hai. Không có lần thứ ba.
- Shipper không được chọn hoàn về cửa hàng hay sửa người nhận/người giữ hàng.
  Quản lý vẫn có thể chọn hoàn sớm trước khi lần hai bắt đầu. Báo cáo mất/hỏng
  hàng vẫn chặn giao lại; không coi lý do giao thất bại là bằng chứng mất hàng.
- MH10 hỗ trợ `p_state_group = 'failed'`. `counts.failed` là phần con của
  `counts.ungrouped`; giữ nguyên tổng `waiting + in_transit + completed +
  ungrouped` để bản app cũ không mất số lượng nhiệm vụ. Sau khi báo thất bại,
  client bỏ bộ lọc/từ khóa cũ để nhiệm vụ vẫn xuất hiện trong danh sách.

## Dữ liệu demo đã kiểm tra

“DEMO giao hàng 1” có bằng chứng nhận/xuất hàng hợp lệ, nhưng có hai sự kiện
`lost` ngày 30/10/2026. Lỗi `CUSTODY_UNRESOLVED` là kiểm tra đúng của server.
Không xóa các sự kiện hoặc làm giả bằng chứng giữ hàng để cho phép giao.
“DEMO giao hàng 2” và “DEMO giao hàng 4” đã thất bại lần một, có thể dùng luồng
giao lại mới nếu vẫn đáp ứng kiểm tra server tại thời điểm thao tác.

## Kiểm chứng và triển khai

- `flutter analyze`: không có lỗi.
- `flutter build apk --debug --no-pub --dart-define-from-file=config/supabase.json`:
  thành công; APK tại `build/app/outputs/flutter-apk/app-debug.apk`.
- `flutter test test/features/deliveries test/app/router`: 499 tests đạt.
  Sau đó bổ sung và chạy lại bộ retry riêng: 4 tests đạt, gồm đổi tài khoản
  A → B trong lúc chờ đọc và điều hướng đúng một lần sau recovery.
- Adapter Supabase: 3 tests đạt cho RPC/params/receipt thực, từ chối receipt
  lệch request/task và ánh xạ lỗi custody; không chỉ dùng repository giả.
- `supabase/tests/run_outbound_retry_dependencies.ps1`: exit 0; migration,
  quyền đọc/ghi, wrapper dưới role authenticated, replay, nhận/bắt đầu lần
  hai, cạnh tranh shipper với manager và các regression SQL đều đạt trên
  PostgreSQL 17 cục bộ với Auth/Storage fixture.
- Hai assertion SQL cũ được đồng bộ với migration ảnh đã tồn tại: projection
  item có `image_url` (10 trường), delivery reader có 34 column grants.
- Đã triển khai riêng migration `shipper_retry_outbound_failure` lên project
  `bqoyfytmrtvjwrpshuhh` ngày 01/11/2026. File CLI cục bộ có version
  `20261101095549`; công cụ triển khai ghi cloud version `20261101144354`.
  Không chạy `db push` hàng loạt vì lịch sử migration đã có chênh lệch cũ.
- Kiểm tra cloud sau triển khai: anon không có quyền gọi wrapper/decision;
  writer chỉ có quyền cần thiết để gọi decision. Đọc nhóm failed dưới role
  authenticated của shipper trả 2 nhiệm vụ, `failed=2`, `ungrouped=2`, tổng
  vẫn bằng 5. Không đổi trạng thái các đơn demo để kiểm tra.
- Security advisors: giữ 2 INFO private RLS và 1 cảnh báo bảo vệ mật khẩu cũ;
  cảnh báo authenticated SECURITY DEFINER tăng 29 → 30 do RPC mới có chủ đích.
  Wrapper kiểm tra role/assignment, owner không login/bypass RLS, search_path
  rỗng. [Giải thích advisor](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

## Thử trên app

1. Đăng nhập shipper, mở một nhiệm vụ đang giao, báo thất bại và chọn lý do.
2. Quay về MH10: nhiệm vụ vẫn có trong danh sách, có thể lọc **Thất bại**.
3. Mở nhiệm vụ thất bại lần một và chọn **Giao lại lần 2**. App đọc task mới
   từ server; xác nhận tiếp tục giữ hàng rồi bắt đầu giao. Không cần manager
   duyệt lý do hoặc tạo lần giao thứ hai.
4. Mở bản đồ từ chi tiết, quay lại rồi bấm bắt đầu: nút hoạt động sau khi
   dữ liệu được xác minh lại, không gửi trùng lệnh.
5. Nếu thất bại lần hai, không có lần giao thứ ba; thực hiện luồng hoàn hàng
   về cửa hàng. Không tự cộng tồn hoặc xóa nghĩa vụ COD.
