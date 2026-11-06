# P08.4 — MH10/MH11 giao lại miễn phí

Ngày 28/10/2026. Rà riêng P08.4 sau khi backend và frontend redelivery đã được
triển khai trong yêu cầu bổ sung primitive trước đó. Không làm phase tiếp theo,
không migration/RLS/API signature mới, không router/dependency/theme/client mới.

## Hành vi và nguồn dữ liệu

- MH10 dùng nhãn `GIAO LẠI MIỄN PHÍ`, `Không thu COD`; badge lần giao `/2` chỉ
  outbound. MH11 dùng một task-detail screen, hero/khối chi phí ghi giao lại
  miễn phí, không thu COD lần hai, không áp hạn mức outbound.
- Điểm đến và actual item/variant/quantity đọc từ P08.3 authorized task plan.
  Legacy redelivery chưa có plan vẫn unavailable, không tự dùng hàng toàn đơn.
- Assigned có accept full-goods, accepted có start, in_transit có success/fail;
  history/restricted hoặc chưa có plan/session hợp lệ không được submit.
- Dialog thủ công, full-goods checkbox cho accept/start/complete; failure Other
  bắt buộc mô tả. Cancel không gửi request. Không thu hoặc sửa số tiền COD.
- ViewModel/repository đã có nối `accept_redelivery_task`, `start_redelivery_task`,
  `complete_redelivery`, `fail_redelivery_task` thật của P08.3. Giữ UUID/payload
  sau timeout, chống tap kép/outcome xung đột, xử lý lỗi typed và không fake ACK.
  Sau ACK phải reload detail rồi reload MH10 mới xác nhận. Request state do
  server cập nhật nguyên tử cùng task; shipper không đọc bảng return request.
- Success trả delivered/rejected_after_inspection, failure giữ
  manager_action_required/custody/open, không tự đóng hoặc lên lịch giao lại.
  Đổi tài khoản/xóa session không khôi phục PII hoặc pending của người trước.

## File thay đổi trong lượt P08.4 này

- `lib/features/deliveries/presentation/widgets/delivery_task_card.dart`:
  nhãn kind/chi phí giao lại rõ miễn phí.
- `lib/features/deliveries/presentation/pages/delivery_task_detail_page.dart`:
  hero/tiêu đề chi phí và lời nhắc không COD lần hai.
- `test/features/deliveries/redelivery_widget_test.dart`: bảy cases widget với
  repository/read fixtures có nhãn, dùng production VM/action widget.
- Expectations nhãn trong `delivery_task_detail_page_test.dart` và
  `delivery_task_list_page_test.dart`, `return_pickup_widget_test.dart`, cùng
  tài liệu này/screen mapping.

Giữ nguyên code P08.3/P08.4 đã có từ lượt trước: redelivery domain/DTO/repository/
providers/VM/action widget và backend migration. Không tạo bản song song hoặc
ghi đè các thay đổi chưa commit khác trong workspace.

## Kiểm chứng

- `flutter test --no-pub test/features/deliveries/redelivery_widget_test.dart
  test/features/deliveries/delivery_task_detail_page_test.dart
  test/features/deliveries/delivery_task_list_page_test.dart`: **28 PASS**.
  Bao phủ assigned/accepted xác nhận disabled→enabled, cancel không write;
  terminal/restricted không nút; success/failure với plan thật, Other validation,
  một write → detail reload → list refresh, chưa confirmed khi một read còn chờ;
  zero-COD/no-cap và tương thích các kind cũ.
- `dart format` các Dart file thay đổi: PASS.
- `flutter analyze --no-pub`: No issues found.
- `flutter test --no-pub --concurrency=1 --reporter expanded`: **493 PASS,
  4 opt-in live skipped**. Lượt đầu phát hiện một expectation nhãn cũ trong
  pickup compatibility test; đã cập nhật đúng nhãn mới, giữ assertion không
  có pickup actions trên redelivery và chạy lại full suite PASS.
- `git diff --check`: exit 0, chỉ cảnh báo LF/CRLF.
- Review độc lập không còn finding P08.4 sau đủ bảy widget cases.

Nghiệm thu Auth/JWT/UI live cả success/failure đã PASS trong lượt trước, được
ghi ở [P08.3 production](p083_production_redelivery.md). Lượt này chỉ đổi nhãn và
bổ sung kiểm thử frontend, không cần ghi thêm dữ liệu cloud để chứng minh lại
RPC không thay đổi. Fixtures widget không phải backend live hoặc fallback app.

Không còn blocker P08.4 trong scope; UI MH15/refund/restock và manager resolution
sau failure là ranh giới owner/nghiệp vụ riêng. Không claim teammate agreement.
