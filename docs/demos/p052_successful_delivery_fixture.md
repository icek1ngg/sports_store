# P05.2 — Successful delivery UI harness, live BLOCKED

Ngày 25/10/2026, P05.1 vẫn chỉ có SQL contract fixture; không có completion
RPC public hoặc adapter production. Theo stop rule, P05.2 chỉ thêm domain
interfaces và harness provider/widget dưới `test/`. MH11 production vẫn chỉ
đọc; không nối schema p051_fixture vào app hoặc báo backend success giả.

## Chạy kiểm thử

```powershell
flutter test --no-pub test/features/deliveries/outbound_completion_fixture_test.dart test/features/deliveries/outbound_completion_panel_fixture_test.dart test/features/deliveries/outbound_completion_cache_fixture_test.dart
```

Panel không được route trong app, luôn có nhãn P05.2 TEST-ONLY. Nó dùng theme
Nike hiện có và dữ liệu đọc/transport/request-ID factory/session được inject
rõ ràng bởi test. Scripted repository không phải Supabase adapter hay API thật.

## Các ràng buộc của harness

- Chỉ current outbound in_transit với amount dương mới có thể xác nhận.
  Hiển thị nguyên `amountToCollectVnd` từ snapshot, gồm phí nếu backend đã
  tính; không cộng thêm 30.000 hoặc suy tổng từ item lines. Không TextField
  cho số tiền và không tạo fee breakdown khi API không cung cấp.
- Dialog có hai checkbox độc lập: khách nhận đủ toàn bộ hàng và đã thu đủ
  COD. Chỉ bật confirm khi cả hai được chọn; mở dialog hoặc hủy không gửi lệnh.
- Gắn số tiền và session revision tại lúc mở dialog; snapshot thay đổi amount
  hoặc session A→B→A thì không lặng lẽ gửi một confirmation cũ cho scope mới.
- Command draft chỉ task/request UUID, receivedAllItems và reported cash amount
  lấy từ snapshot đã xác nhận. `receivedFullCod` là guard UI, không tự thêm vào
  payload. Không gửi actor/shipper/order total/fee/recipient. Version/schema và
  RPC payload cuối vẫn phải chốt với P05.1 live.
- Timeout/network giữ nguyên command, ID và số tiền; khóa action xung đột.
  Manual refresh không sinh command mới. ACK chỉ kích hoạt đọc lại, không đổi
  local task thành delivered. Chỉ snapshot delivered mới xác nhận trạng thái;
  history bị mask không giữ lại COD/contact cũ.
- Sau ACK và read xác nhận delivered, refresh hai cache seam MH10/COD độc lập.
  Callback nào lỗi thì retry callback đó cùng thao tác đọc, không gửi lại write
  đã ACK. Lỗi session/permission/assignment/dependency khóa action và ngăn
  callback account cũ; terminal denial phải ưu tiên hơn lỗi mạng trước đó.
  Riêng sessionExpired hoặc session revision đổi thì dừng callback tiếp theo;
  lỗi permission/assignment/dependency của MH10 vẫn cho COD đọc scope riêng.
- Dialer draft chỉ nhận URI `tel:` với số điện thoại plain hợp lệ, mở trình
  quay số qua seam được inject; không tự đặt cuộc gọi, không liên quan completion.
  Outcomes opened/unavailable/failed được phân biệt; không nói đã gọi thành công.
  History/missing/USSD-like number không được mở dialer từ harness.

Cache tests sử dụng FutureProviders **fixture** để kiểm tra dữ liệu cache được
đọc lại sau invalidate, không chỉ tăng counter callback. Chúng không phải
runtime `deliveryTasksProvider` hoặc `codCollectionsProvider` wiring. Không
dùng callback test để tuyên bố MH10/MH12 live đã cập nhật sau completion.

Pending command hiện chỉ ở bộ nhớ test provider; chưa có khôi phục qua provider
teardown, navigation hoặc app restart. Request UUID generator và platform dialer
implementation thật chưa được thêm. Dialer của MH11 production vẫn chưa khả dụng
như P03.2, không thêm plugin để mở rộng scope khi live integration còn bị chặn.

## Blockers

Cần completion RPC P05.1 cùng custody/dispatch P04.1, shared ledger/version,
event/notification D7 và payload đã finalized; sau đó mới thêm Supabase adapter,
runtime session guards/provider invalidation, UUID persistence và dialer platform
implementation theo dependencies chung. P05.2 **chưa hoàn thành live**. Không
triển khai failure actions, COD receipt hoặc phase tiếp theo.

## Tệp và kết quả kiểm tra 25/10/2026

- Domain draft: `lib/features/deliveries/domain/models/outbound_completion_command.dart`,
  `lib/features/deliveries/domain/repositories/outbound_completion_repository.dart`,
  `lib/features/deliveries/domain/repositories/delivery_phone_dialer.dart`.
- Harness: `test/features/deliveries/fixtures/outbound_completion_fixture.dart`,
  `completion_panel_fixture.dart`, `completion_harness_fixture.dart`.
- Tests: `test/features/deliveries/outbound_completion_fixture_test.dart`,
  `outbound_completion_panel_fixture_test.dart`, `outbound_completion_cache_fixture_test.dart`.
- Docs: hướng dẫn này và phần P05.2 trong `docs/api_contracts.md`,
  `docs/business_states.md`, `docs/database.md`, `docs/screen_mapping.md`.

Lệnh targeted ở trên: **33 tests PASS**. `flutter test --no-pub`: **197 tests PASS**.
`flutter analyze --no-pub`: **No issues found**. `dart format` cho các tệp Dart
P05.2: thành công. `git diff --check`: exit 0, chỉ cảnh báo chuẩn hóa LF→CRLF.
Kiểm tra `rg -n "fixtures/|p051_fixture|p041_demo" lib`: không có kết quả.

P05.2 không thêm/sửa migration, public RPC, RLS, dependency, router hay runtime
MH11/MH10/COD providers. Không chạy SQL/cloud deploy trong phase UI này.
