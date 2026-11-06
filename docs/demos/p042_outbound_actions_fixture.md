# P04.2 — Interface và harness kiểm thử, live còn bị chặn

Ngày 25/10/2026 repository vẫn chưa có RPC accept/start live. P04.1 chỉ có
demo SQL cô lập; inventory/cancellation/custody contracts của các owner chưa
được cung cấp. Theo stop rule, P04.2 chỉ bổ sung interface và test fixtures.
Không nối demo SQL vào app, không bật nút MH11 production hoặc sửa router.

## Chạy harness kiểm thử

```powershell
flutter test --no-pub test/features/deliveries/outbound_action_fixture_test.dart test/features/deliveries/outbound_action_panel_fixture_test.dart
```

Đây là provider/widget tests, không phải màn demo được route trong app.
Panel hiện nhãn `DEMO TEST-ONLY — chưa kết nối RPC live`, dùng AppTheme hiện có.
Repository/read/session/request-ID generator đều được test inject rõ ràng;
không có Supabase client hoặc fake adapter được production import. Scripted
read DTO biểu thị response của fixture, không phải dữ liệu backend thật.

## Contract draft

`OutboundTaskCommand` gồm task UUID, request UUID và action acceptGoods hoặc
startDelivery. `OutboundTaskCommandRepository.execute` chỉ xác nhận lệnh;
không trả một task để ViewModel tự đổi status. Hai kiểu này là seam draft,
chưa là signature RPC, payload/version hay SQLSTATE được owner duyệt.
Không có Supabase implementation hoặc runtime provider cho interface này.

Eligibility chỉ dùng để trình bày: outbound, scope current, attempt 1,
assigned để accept và accepted để start. Nó không chứng minh phân quyền,
đủ hàng, custody hoặc dispatch. Attempt 2 chưa được mở bằng helper này.
Không thêm Order model; tiếp tục dùng DeliveryTaskDetails/Snapshot hiện có.

## Hành vi được kiểm tra trong fixture

| Trường hợp | Hành vi |
| --- | --- |
| Mở chi tiết / hủy dialog | Chỉ đọc; không gửi command. Confirm riêng cho nhận hàng và start. |
| Gửi lệnh | Sinh ID qua factory được inject đúng một lần; khóa các action/refresh retry xung đột đến khi lệnh và các lần đọc hoàn tất. |
| Timeout/network chưa rõ kết quả | Giữ nguyên command/request ID qua retry và manual refresh; không cho chuyển sang action khác dù read fixture đã trả accepted. |
| ACK | Đọc lại task và gọi callback reload danh sách, không tự sửa status hoặc counts. Read cũ không tiến triển sau ACK bị staleState; không bật lại action cũ với key mới. |
| ACK nhưng lỗi đọc/list | Retry chỉ đọc lại, bao gồm callback list còn thất bại; không gửi lại write đã ACK. |
| Permission/session/assignment/dependency bị từ chối | Hiện lỗi typed, khóa write; hết phiên xóa details và không tiếp tục private reads. Chỉ session revision/fixture mới mở gate lại. |
| Account đổi / logout / dispose / response đến muộn | Bỏ dữ liệu và pending command của epoch cũ; không publish PII cũ hoặc reload list account cũ. Kiểm tra cả A→B→A cùng user/epoch label. |
| Trả sai task ID | InvalidData, không render task khác hoặc bật action. |

Request IDs của harness là UUID test được inject, không phải generator production.
Pending state chỉ sống trong fixture provider, chưa có phục hồi qua app restart,
navigation teardown hoặc storage. Không dùng harness thay thiết kế retry durable
của backend/client thật. Không tự auto-retry hoặc gọi success khi transport lỗi.

## Phần chưa thể nghiệm thu live

MH11 thật vẫn read-only theo P03.2. Không có xác nhận accept/start từ RPC thật,
thay đổi counts MH10 thật sau write hoặc navigation action mới. Callback reload
list trong harness chỉ là seam kiểm thử; các kiểm thử router/read-refresh sẵn có
không chứng minh write integration. Complete-success vẫn dành cho P05.2.

Cần P04.1 live với inventory/cancel/custody/idempotency/version được chốt, rồi
mới thêm Supabase adapter dùng client/session chung, request-ID generator thật,
provider wiring và action UI MH11. P04.2 **chưa hoàn thành live**.

## Tệp riêng của P04.2

- `lib/features/deliveries/domain/models/outbound_task_command.dart`
- `lib/features/deliveries/domain/repositories/outbound_task_command_repository.dart`
- `test/features/deliveries/fixtures/outbound_action_fixture.dart`
- `test/features/deliveries/fixtures/outbound_action_panel_fixture.dart`
- `test/features/deliveries/outbound_action_fixture_test.dart`
- `test/features/deliveries/outbound_action_panel_fixture_test.dart`
- `docs/demos/p042_outbound_actions_fixture.md`
- Bổ sung mục P04.2 trong `api_contracts.md`, `screen_mapping.md`,
  `business_states.md`, `database.md`.

Không thêm migration/API/RLS/dependency và không sửa UI/router/client runtime.
Diff P03.3/P04.1 chưa commit được giữ nguyên, `outputs/` không thuộc phase này.

## Kiểm chứng cuối ngày 25/10/2026

- `dart format --output=none --set-exit-if-changed lib/features/deliveries/domain/models/outbound_task_command.dart lib/features/deliveries/domain/repositories/outbound_task_command_repository.dart test/features/deliveries/fixtures/outbound_action_fixture.dart test/features/deliveries/fixtures/outbound_action_panel_fixture.dart test/features/deliveries/outbound_action_fixture_test.dart test/features/deliveries/outbound_action_panel_fixture_test.dart`:
  6 files, 0 changed.
- `flutter analyze --no-pub`: No issues found.
- `flutter test --no-pub`: **164 tests passed**; gồm 33 test P04.2 mới
  (22 provider/model-boundary và 11 widget) cùng 131 test hồi quy sẵn có.
- `flutter test --no-pub test/features/deliveries/outbound_action_fixture_test.dart test/features/deliveries/outbound_action_panel_fixture_test.dart`:
  31 tests passed ở vòng targeted; hai test terminal-error cuối được bổ sung
  sau đó và chạy trong full suite 164 tests phía trên.
- `git diff --check`: PASS, chỉ warning LF/CRLF theo cấu hình repository.

Các vòng đầu bắt được fixture return DTO không đúng kind/return_request và
lỗi compiler/lint từ phần worker đang dở; đã sửa và giữ assertions thật.
Review còn phát hiện read sai task, ACK read cũ, retry mất key, lỗi list refresh
và terminal auth che bởi timeout; đã bổ sung regression tests cho các lỗi đó.
Worker Luna chạm usage limit giữa lượt triển khai; coordinator hoàn thiện phần
còn dở, reviewer Sol thực hiện review độc lập cuối, không còn finding trong
phạm vi test fixtures. Không coi hạn chế live là test đã đạt.

Không chạy SQL/cloud deploy vì P04.2 không sửa database và không có RPC live
để kiểm chứng. Không thêm package/pub get, không build màn success hoặc P05.2.
Phase này hoàn tất phần interface/test harness được stop rule cho phép;
**P04.2 live chưa hoàn thành**. Thay đổi vẫn chưa commit/push.
