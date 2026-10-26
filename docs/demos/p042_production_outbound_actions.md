# P04.2 — MH11 nhận hàng và bắt đầu giao production

Cập nhật 26/10/2026. Bản này thay thế kết luận fixture-only của
`p042_outbound_actions_fixture.md` cho riêng accept/start outbound. Không mở
complete/fail/return actions từ các fixture của phase khác.

**Bổ sung nghiệm thu live cùng ngày:** P04.2 đã PASS real Auth/JWT + Flutter
widget/repository/cloud RPC, sửa lỗi self-refetch loop khi loading. Sau đó P05.1/
P05.2 production cũng đã triển khai, deploy và nghiệm thu riêng. Các giới hạn
chưa positive JWT và completion-disabled bên dưới phản ánh mốc bàn giao trước;
xem [kết quả mới nhất](p051_p052_production_outbound_completion.md). Không coi
widget runner là điện thoại vật lý.

## Tích hợp

- MH11 dùng `OutboundTaskActions`, Riverpod `OutboundTaskActionsViewModel` và
  `SupabaseOutboundTaskCommandRepository`; dùng client/theme/router chung.
- Chỉ task outbound current, attempt 1 hoặc 2: assigned cho nhận hàng;
  accepted và có accepted_at cho bắt đầu giao. Backend tiếp tục quyết định
  quyền, tồn kho, custody và điều kiện lần hai; UI không thay thế authorization.
- Dialog yêu cầu xác nhận thực nhận đủ hàng hoặc sẵn sàng vận chuyển. Mở trang,
  đóng dialog hay chọn hủy không gọi mutation. Chặn double tap, xác nhận cũ khi
  snapshot/session thay đổi và thao tác đồng thời.
- Gọi RPC thật `accept_delivery_task` hoặc `start_delivery_task`, chỉ truyền
  `p_task_id`, `p_request_id`. Không gửi shipper, số tiền, attempt hay state.
  SDK retry tự động bị tắt. ACK được kiểm tra ID, operation, state, timestamp,
  event và counter trước khi dùng làm xác nhận server.
- UUID v4 được tạo khi gửi xác nhận hợp lệ. Timeout/network/ACK không xác minh
  được giữ nguyên command và request ID cho retry trong phiên đang chạy.
  Refresh token cùng tài khoản giữ key; logout/account switch xóa key và bỏ qua
  response cũ. Key không lưu bền qua tắt tiến trình; mở lại phải đọc trạng thái
  server. Không tự gửi lại mutation khi mở trang.
- Sau ACK phải đọc lại backing projection của MH11 rồi refresh ViewModel MH10
  hiện có, giữ bộ lọc. Nếu đọc lỗi, retry chỉ đọc, không gửi write lần nữa.
  Không đổi state local để mô phỏng thành công. Không invalidate COD vì hai
  thao tác này chưa thu tiền.
- Khi route bị ẩn, giữ envelope đang chờ nhưng ngừng listener detail; hoãn
  reconciliation đến lúc quay lại. Không giữ snapshot người nhận trong action
  controller khi ẩn. Quyền/session lỗi chặn action và hiển thị lỗi an toàn.

## Tệp chính

- `lib/features/deliveries/data/models/outbound_task_command_ack_dto.dart`
- `lib/features/deliveries/data/repositories/supabase_outbound_task_command_repository.dart`
- `lib/features/deliveries/domain/models/outbound_task_command.dart`
- `lib/features/deliveries/domain/repositories/outbound_task_command_repository.dart`
- `lib/features/deliveries/presentation/view_models/outbound_action_providers.dart`
- `lib/features/deliveries/presentation/view_models/outbound_task_actions_view_model.dart`
- `lib/features/deliveries/presentation/view_models/delivery_providers.dart`
- `lib/features/deliveries/presentation/widgets/outbound_task_actions.dart`
- `lib/features/deliveries/presentation/pages/delivery_task_detail_page.dart`
- Tests `outbound_task_command_repository_test.dart`,
  `outbound_task_actions_view_model_test.dart`, `outbound_task_actions_page_test.dart`
  và cập nhật `delivery_task_detail_page_test.dart` trong `test/features/deliveries/`.

## Kiểm tra và giới hạn

- `dart format` trên 13 tệp Dart liên quan: PASS.
- `flutter analyze --no-pub`: No issues found.
- `flutter test --no-pub`: 335 tests PASS; bao gồm adapter,
  provider và widget với HTTP/repository được kiểm soát, không giả lập thành
  công thay thế adapter trong ứng dụng.
- `git diff --check`: PASS (chỉ cảnh báo chuẩn hóa LF/CRLF của working copy).
- Lần đầu redirect log vào `.temp/` không chạy được do thư mục không tồn tại;
  đã chạy lại test trực tiếp, không tạo thư mục/dữ liệu giả để bỏ qua lỗi.
- Không migration, grants, RLS, dependency hay RPC mới trong P04.2. Hai RPC
  production đã deploy/SQL-test ở P04.1; xem `p041_production_accept_start.md`.
- Chưa nghiệm thu bằng tài khoản shipper đăng nhập thật qua UI trên thiết bị.
  SQL cloud và kiểm thử widget không chứng minh positive JWT/UI E2E. Cần order
  có reservation evidence đúng để chạy accept thật; thiếu evidence phải lỗi.
- Hoàn tất mã tích hợp P04.2 không đồng nghĩa các mutation P05/P07 đã live.
