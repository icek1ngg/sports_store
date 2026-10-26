# P07.3 — MH11 failure dialog: test-only, live BLOCKED

Kiểm tra ngày 26/10/2026: trước thay đổi này P07.3 chưa có dialog hoạt động.
MH11 production chỉ hiển thị nút “Báo giao thất bại” disabled cùng thông báo
màn chỉ đọc. P07.1 mới có temporary SQL interface luôn DEPENDENCY_NOT_READY,
không có public fail_delivery_task, adapter hoặc finalized write response.

Đã đọc AGENTS.md, kế hoạch Minh Đức, bốn docs contract, chín migration và
MH11/tests hiện có. Báo cáo gốc v3.0 chưa có để đối chiếu trực tiếp; không
tuyên bố đã kiểm tra toàn văn báo cáo. Không coi tên RPC trong plan là API có sẵn.

Theo stop rule, chỉ thêm domain draft interfaces và provider/widget fixture
trong test/, không nối SQL fixture vào Flutter hoặc bật nút MH11 production.
Fixture có nhãn rõ, dùng AppTheme/Nike đang có; không có router/client/theme
hoặc dependency mới. Không sửa màn orders/inventory/returns của teammates.

## Hành vi được kiểm thử

- Năm lý do theo yêu cầu: không liên hệ được, khách hẹn lại, sai địa chỉ,
  từ chối nhận, khác. “Khác” cần mô tả không chỉ whitespace; mô tả được trim.
  Không dùng hỏng/mất hàng như lý do giao thất bại; đó là incident P07.4.
- Chỉ mở cho current outbound in_transit, số lần 1/2, có accepted/start
  timestamps, session shipper hợp lệ và không pending/busy. Đây là guard
  presentation draft, timestamps không chứng minh custody hoặc quyền server.
  Return pickup/redelivery, restricted/history và trạng thái khác bị chặn.
- Mở/hủy không ghi. Dialog xác nhận thủ công; khóa nhấn lặp và các action
  xung đột trong lúc đang gửi hoặc chưa xác định kết quả.
- Request ID do test inject; timeout/network giữ nguyên command/key/lý do/
  mô tả, không tạo ID mới khi retry. Không nhận amount, shipper ID, schedule,
  stock hay actor từ người dùng. Số lần trong command chỉ là snapshot guard
  cục bộ, server tương lai phải tự xác định từ order/task đã khóa.
- ACK draft phải khớp task/request/attempt và disposition; ACK không tự đổi
  local task. Chỉ sau authorized read xác nhận failed task cùng lần mới hiển
  thị kết quả và gọi callback refresh MH10. Read sau ACK lỗi thì retry đọc,
  không gửi lại write đã ACK. Scripted repository/read là fixture rõ ràng.
- Hiển thị “Chờ quản lý quyết định” hoặc “Chờ hoàn về cửa hàng” dựa ACK đã
  xác minh và snapshot failed; không ghi stock returned, không cho shipper
  hẹn/giao lần hai, không checkbox hoặc thông điệp đã thu COD.
- Session/permission/assignment thay đổi phải xóa/redact state, đóng dialog
  và bỏ kết quả inflight của account/epoch cũ. Không trả server text/description
  nhạy cảm qua error message hoặc log; lỗi typed hiển thị tiếng Việt an toàn.

Disposition managerDecision/storeReturnPending là draft acknowledgement cho
test, không enum mới DB hoặc field hiện có trong get_my_delivery_task. API
read hiện tại chưa cung cấp order state; không tự suy production order status
từ nhãn failed của task. Cần finalized P07.1 response trước integration.

## Phạm vi và dependency còn thiếu

P07.1 RPC/authorization/transaction/notification/ledger production chưa có.
P04.1 custody/dispatch/start, D3 lần hai, D7 recipient và payload/version/error
contract còn mở. Không tự chốt phần của Bảo/Văn Đức/Sơn. P07.3 **chưa hoàn
tất live**; widget/provider PASS chỉ nghiệm thu harness, không backend thật.

Không mutation migration/API/RLS/grant được thêm. Chưa deploy hoặc nghiệm thu
Supabase/Auth/PostgREST. Không commit/push. Pending request trong fixture chỉ
giữ khi harness sống, không durable qua dispose/logout/restart.

## Manifest và chạy lại

- `lib/features/deliveries/domain/models/outbound_failure_command.dart`:
  reason/command/ACK draft transport-neutral, không Supabase SDK.
- `lib/features/deliveries/domain/repositories/outbound_failure_repository.dart`:
  draft seam, không implementation production.
- `test/features/deliveries/fixtures/outbound_failure_fixture.dart`:
  dependencies/session và ViewModel test-only.
- `test/features/deliveries/fixtures/failure_panel_fixture.dart`:
  dialog/layout chỉ test, luôn có nhãn fixture.
- `test/features/deliveries/fixtures/failure_harness_fixture.dart`:
  bridge View → ViewModel, capture session revision và chỉ hiện kết quả sau read.
- `test/features/deliveries/outbound_failure_fixture_test.dart`:
  domain/provider/scripted repository checks.
- `test/features/deliveries/outbound_failure_panel_fixture_test.dart`:
  widget checks.
- `test/features/deliveries/outbound_failure_harness_fixture_test.dart`:
  dialog/provider integration với scripted transport/read, stable timeout retry,
  ACK/read retry riêng, hai disposition và permission denial.
- Tài liệu này, api_contracts.md và screen_mapping.md được cập nhật nối tiếp.

```powershell
flutter test --no-pub test/features/deliveries/outbound_failure_fixture_test.dart test/features/deliveries/outbound_failure_panel_fixture_test.dart test/features/deliveries/outbound_failure_harness_fixture_test.dart
flutter analyze --no-pub
git diff --check
```

Không đổi SQL nên không chạy lại migration suites; kết quả SQL của P07.1/
P07.4 không được dùng thay acceptance P07.3 hoặc claim backend đã hoạt động.

## Kết quả kiểm tra 26/10/2026

- Lệnh targeted ba tệp ở trên: **33 PASS**, gồm 18 domain/provider tests,
  12 panel widget tests và 3 provider/dialog integration tests.
- `flutter test --no-pub`: **289 PASS**, exit 0; gồm hồi quy MH11 read-only,
  navigation, MH10 và COD. Không suy ra backend production đã hoạt động.
- `flutter analyze --no-pub`: exit 0, `No issues found!`.
- Format verification:

```powershell
dart format --output=none --set-exit-if-changed lib/features/deliveries/domain/models/outbound_failure_command.dart lib/features/deliveries/domain/repositories/outbound_failure_repository.dart test/features/deliveries/fixtures/outbound_failure_fixture.dart test/features/deliveries/fixtures/failure_panel_fixture.dart test/features/deliveries/fixtures/failure_harness_fixture.dart test/features/deliveries/outbound_failure_fixture_test.dart test/features/deliveries/outbound_failure_panel_fixture_test.dart test/features/deliveries/outbound_failure_harness_fixture_test.dart
```

Kết quả: 8 files, 0 changed, exit 0. `git diff --check`: exit 0, chỉ cảnh
báo LF/CRLF của Git. Không thay lockfile/dependencies, không chạy pub get.

Review độc lập phát hiện và đã sửa: account mới đọc nhầm task cũ; malformed/
unknown post-dispatch errors làm mất retry key; callback-only retry giữ busy
vĩnh viễn. Đã có regression tests cho các lỗi này. Lỗi compile/lint test-helper
ban đầu đã sửa trước toàn bộ checks cuối; review cuối không còn finding đáng kể.

Không có production `fail_delivery_task` hoặc Supabase adapter được thêm.
API/schema/migrations/quyền không thay đổi; scope mutation/UI live của P07.3
vẫn **BLOCKED, chưa hoàn tất**. Tất cả diff các phase trước được giữ nguyên.
