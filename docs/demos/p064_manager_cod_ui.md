# P06.4 — Manager COD trong cùng MH12

CodRoutePage `/cod` hiện có chọn shipper hoặc ManagerCodPanel theo role profile
server. Panel manager là widget trong cùng màn/shell, không có route/page/
Supabase client/theme thứ hai. Backend RLS và RPC P06.3 vẫn kiểm tra quyền dù
caller bỏ qua UI; không thêm grant ghi trực tiếp hoặc migration mới.

## Đối chiếu mock

Giữ bố cục Nike alpha đen–trắng: policy banner, nhãn manager, form tìm kiếm,
hai nhóm và thẻ khoản thu, dialog xác nhận. Không dùng NV001/DH001, tên shipper,
ca làm, tổng/số lượng mẫu hoặc DOM-removal success của HTML vào runtime.
P06.1 chưa có mã đơn ngắn/tìm tên nhân viên, nên hai filter là exact UUID đơn/
shipper, cho để trống xem toàn scope manager. Form nói rõ UUID và validate
trước query, submit-driven, không lọc cục bộ loaded rows. Không mở quyền
orders/profiles để tự bù thông tin chưa có trong projection.

Chi tiết khoản thu dùng order_code/source, shipper/collector/receiver UUID,
expected/collected/received amount và timestamps server; không tự nói COD
collected là order vẫn delivered. Không lấy bank/refund/video/contact hoặc
thêm phí 30.000 lần nữa. Cùng formatter VND/UTC của shipper.

## Xác nhận và retry

Chỉ collected hợp lệ mới có hành động. Dialog hiển thị nguyên full amount từ
snapshot và bắt buộc checkbox đã kiểm đếm, thực nhận đủ; không edit amount.
Hủy/chưa nhận đủ không gọi write. Trước submit ViewModel kiểm tra lại row,
amount, session/role revision; dialog redacts/closes khi role/account đổi hoặc
panel bị dispose, không giữ dữ liệu manager trước trên tài khoản mới.

Command chỉ p_order_id, p_received_amount_vnd, p_request_id đúng P06.3. UUIDv4
được sinh bằng Random.secure một lần cho operation; timeout/network giữ frozen
command/request/amount và khóa action xung đột. Không tự retry SDK write hoặc
tạo request mới để ép state conflict. Pending retry được giữ trong scope cùng
account; không coi response không xác định là chưa ghi hoặc success.

ACK không đổi card/totals local. Phải đọc lại exact order qua P06.1 và đối
chiếu received amount/by/at, sau đó refresh list/counts/outstanding manager và
invalidate backing caches legacy/shipper. Read/cache failure sau ACK chỉ đọc
lại, không gửi lại write đã ACK. Remote shipper đang mở UI sẽ thấy cập nhật
qua polling foreground/resume/manual P06.2; không giả Realtime publication.

Business conflicts có thông điệp an toàn; permission/session denial xóa data.
Đổi filter/group/refetch phải chống response cũ; pagination dùng server cursor,
kiểm tra drift/trùng/sort/totals. Không callback tài khoản cũ được publish.

## Giới hạn tích hợp

P06.1/P06.3 đã có migrations trong repository, chưa xác minh deploy cloud.
UI/repository gọi RPC thật, không fixture fallback nếu RPC thiếu/lỗi. P05.1
collection live vẫn còn blocked; P06.4 không tự tạo khoản collected giả để
nghiệm thu. Chỉ cần khoản collected thật/hợp lệ để manager nhận tiền; không
đổi expected hoặc offset refund. Không làm phase tiếp theo hoặc MH17.

## Lifecycle và giới hạn request ID

Manager provider auto-dispose bình thường, không giữ vô hạn từng orderId đã
xem. Chỉ pending write/ACK-read retry được keep-alive, cùng auth/role observers
để xóa dữ liệu khi đổi quyền ngay cả lúc màn bị đóng. Không query COD ẩn;
onResume chỉ tiếp tục đọc, không tự gửi write. Khi operation kết thúc hoặc
auth bị từ chối, observers/keep-alive được giải phóng. Filter đã áp dụng giữ
qua refresh/write cùng màn; account/role epoch đổi xóa draft riêng, optional
orderId từ URL là input mới được guard/backend recheck.

Request ID/pending command hiện chỉ ở bộ nhớ, không lưu qua app restart hoặc
logout/auth epoch thay đổi. Trong cùng epoch, timeout/malformed ACK và navigation
giữ đúng command/request. Sau restart/đổi phiên phải đọc lại server; unique
receipt/order của P06.3 vẫn ngăn double-write nhưng UI không tuyên bố khôi phục
được request ID cũ. Không có durable outbox hoặc storage PII được thêm ngầm.

## Tệp thay đổi trong P06.4

- `lib/features/cod/domain/models/cod_receipt.dart` và
  `lib/features/cod/domain/repositories/cod_receipt_repository.dart`:
  command/result/failures và write contract theo P06.3.
- `lib/features/cod/data/models/cod_receipt_dto.dart`,
  `lib/features/cod/data/repositories/supabase_cod_receipt_repository.dart`:
  strict ACK mapping, manager-only adapter, closed business-error mapping.
- `lib/features/cod/presentation/view_models/manager_cod_view_model.dart`:
  filter/read/write/retry/lifecycle orchestration.
- `lib/features/cod/presentation/view_models/cod_providers.dart`:
  dùng shared client/access, receipt repository và UUID factory.
- `lib/features/cod/presentation/widgets/manager_cod_panel.dart` và
  `lib/features/cod/presentation/pages/cod_route_page.dart`: cùng MH12.
- `lib/features/cod/presentation/widgets/cod_formatters.dart` và
  `lib/features/cod/presentation/pages/shipper_cod_page.dart`: tái sử dụng
  formatter cũ, không đổi hành động/quyền shipper.
- `test/features/cod/cod_receipt_repository_test.dart`,
  `manager_cod_view_model_test.dart`, `manager_cod_panel_test.dart`;
  cập nhật smoke test manager branch cũ trong `shipper_cod_page_test.dart`.
- Hướng dẫn này, phần P06.4 trong `docs/api_contracts.md` và
  `docs/screen_mapping.md`.

Không sửa migration/RLS, public RPC signature P06.1/P06.3, router/shell,
core client/theme, dependency/lockfile hoặc phần việc owner khác. Không chạy
SQL/deploy trong phase Dart/UI này vì backend không đổi.

## Validation ngày 26/10/2026

| Lệnh | Kết quả |
| --- | --- |
| `flutter test --no-pub test/features/cod/manager_cod_view_model_test.dart test/features/cod/manager_cod_panel_test.dart test/features/cod/cod_receipt_repository_test.dart` | 31 tests PASS: VM 15, widget 6, adapter 10 |
| `flutter test --no-pub` | 256 tests PASS |
| `flutter analyze --no-pub` | No issues found |
| `dart format --output=none --set-exit-if-changed lib/features/cod test/features/cod/manager_cod_panel_test.dart test/features/cod/manager_cod_view_model_test.dart test/features/cod/cod_receipt_repository_test.dart test/features/cod/shipper_cod_page_test.dart` | 23 files, 0 changed, exit 0 |
| `git diff --check` | Exit 0; chỉ cảnh báo LF→CRLF |

Fixtures test được inject rõ ràng, không fake adapter runtime. Bao phủ
full amount/checkbox/duplicate tap, exact filters/counts, denied API và role
switch đóng dialog, timeout/malformed ACK cùng ID, ACK đọc lỗi retry chỉ read,
denial ở exact read/final list refresh redact, hidden pending ACK đổi account
giải phóng provider, navigation pending và viewport hẹp/text scale lớn.
Review độc lập cuối không còn finding correctness/security material.

**P06.4 hoàn tất triển khai và kiểm thử local**. Chưa nghiệm thu cloud
Auth/PostgREST hoặc toàn luồng tạo khoản collected qua P05.1. Cần deploy các
migration P06.1/P06.3 theo workflow nhóm và kiểm tra dữ liệu thật trước tuyên
bố live hoàn tất; không biến HTTP fixtures thành bằng chứng stakeholder đã
duyệt hay backend đã deploy.
