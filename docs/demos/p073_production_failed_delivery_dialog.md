# P07.3 — MH11 dialog báo giao outbound thất bại

Ngày 27/10/2026. **Đã nối production MH11 → ViewModel → Supabase repository →
fail_delivery_task P07.1**. Thay kết luận fixture-only trong
`p073_failed_delivery_dialog_fixture.md`; giữ fixtures có nhãn để audit.
Không thêm migration/RPC/RLS/router/client/theme/dependency.

## Hành vi và contract

Chỉ current outbound in_transit, attempt1/2, có accepted/start timestamps mới
có nút báo thất bại. Backend vẫn kiểm tra assignment/custody/order/COD;
timestamps UI không thay proof physical receipt. History/restricted,
pickup/redelivery, assigned/accepted và attempt3 không được submit.

Mở dialog không ghi. Lý do: không liên hệ được, khách hẹn lại, sai địa chỉ,
từ chối nhận, khác. Other cần mô tả không chỉ whitespace; các lý do chuẩn có
mô tả tùy chọn. Không gộp hỏng/mất thành lý do thường. Xác nhận có one-shot
latch; bấm hai lần không pop hai route hoặc ghi hai lần. Call action giữ
nguyên phone composer P05, không tự gọi.

RPC chỉ gửi p_task_id/p_request_id/p_reason_code/p_description. Không gửi
actor, tiền, count, lịch hẹn hay status. ACK DTO kiểm tra whitelist, UUID/key/
task, attempt/count, reason/description, failed_at và order mapping:
attempt1 awaiting_redelivery; attempt2 awaiting_store_return.

Sau ACK phải refetch MH11 có outbound failed, đúng attempt, completed_at và
scope restricted/current hợp lệ. Failed projection P01 là restricted, không
ép đọc lại PII/order/items để có current scope. Chỉ sau read đạt mới hiển thị
“Chờ quản lý quyết định” hoặc “Chờ hoàn về cửa hàng”, rồi refresh MH10 giữ
filters. Không khẳng định đã thu COD/nhập tồn/manager nhận hàng; không cho
shipper lên lịch lần hai.

## Retry, xung đột và session

- UUIDv4 tạo một lần; timeout/network/5xx/malformed ACK giữ nguyên command/key/
  reason/description. Tắt retry tự động Supabase, không fixture fallback.
- ACK đạt nhưng read lỗi: retry chỉ đọc, không gửi write đã ACK lần nữa.
- Lỗi business typed có thông điệp an toàn; không lộ raw PostgREST text hoặc
  mô tả trong logs/error UI. Denied/session/assignment không fake success.
- Shared result gate theo task chặn completion/failure đồng thời và khi mất
  ACK; SQL locks vẫn là bảo vệ thật. Recovery UI không mở opposite action từ
  snapshot in_transit cũ sau khi parent chuyển failed/delivered.
- Account switch/logout xóa pending envelope, bỏ response cũ, đóng/redact
  dialog. Cùng user token refresh giữ key/ACK và hiện read retry khi cần.
  Controller sống qua loading/restricted để hoàn tất reconciliation.
- Pending chỉ trong memory, không durable qua process restart. Khi mở lại
  cần đọc server trước thao tác mới.

## Manifest

Mới trong deliveries: data/models/outbound_failure_ack_dto.dart;
data/repositories/supabase_outbound_failure_repository.dart;
presentation/view_models/outbound_failure_providers.dart,
outbound_failure_view_model.dart, outbound_result_gate.dart;
presentation/widgets/outbound_failure_action.dart.

Cập nhật domain failure command/repository từ draft sang P07.1; detail page
nối action/giữ controller; completion VM/action dùng gate chung, token-refresh
recovery và route disposal an toàn. Không đổi completion business/API P05.
Tests mới outbound_failure_repository_test.dart (21),
outbound_failure_production_test.dart (11); cập nhật detail/action page tests.
Docs api_contracts/screen_mapping nối tiếp; diff các phase trước giữ nguyên.

## Kiểm thử và giới hạn

```powershell
flutter test --no-pub test/features/deliveries/outbound_failure_production_test.dart test/features/deliveries/outbound_failure_repository_test.dart
flutter test --no-pub --reporter expanded
flutter analyze --no-pub
dart format lib/features/deliveries test/features/deliveries/outbound_failure_production_test.dart test/features/deliveries/outbound_failure_repository_test.dart
git diff --check
```

Targeted **32 PASS**; full **390 PASS, 2 opt-in live skipped**; analyze **No
issues found**; format/diff check PASS, Git cảnh báo LF/CRLF. Tests chạy actual
production classes với transport/read override test: first/second failed
restricted read, reason validation, timeout stable-key, ACK read-only retry,
token refresh/account switch/inflight, denied/stale/malformed ACK, double-submit
dialog, và hai production providers completion/failure chỉ một dispatch.

Review độc lập đã phát hiện scope failed, token-refresh recovery, opposite
stale button và disposal; đã sửa trước full run. Tests cũ kỳ vọng failure
disabled đã cập nhật; fixtures P07.3 cũ vẫn không được import vào runtime.

**Hoàn tất implementation và acceptance tự động P07.3.** Chưa chạy app với
JWT thật hoặc điện thoại vật lý cho flow này; hai live tests skipped không
phải nghiệm thu P07.3. P07.1/P07.2 đã deploy ở lượt trước; không schema/deploy
mới. P07.4/receipt/inspection ngoài phạm vi. Chưa commit/push; giữ nguyên
thay đổi P06/P07.1/P07.2 và outputs không liên quan.
