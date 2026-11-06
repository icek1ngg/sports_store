# P08.2 — MH10/MH11 thu hồi hàng tại khách

**Cập nhật sau yêu cầu bổ sung của người dùng:** đã triển khai/deploy hai API
pickup handover riêng và nghiệm thu UI/JWT thật PASS. Blocker handover ban đầu
đã được xử lý bởi
[bổ sung RPC và nghiệm thu](p082_pickup_handover_acceptance.md); manager receipt
của Sơn vẫn là thao tác riêng, không tự thực hiện bởi shipper report.

## Phạm vi và backend đã xác minh

P08.1 đã deploy `collect_return_items` và `fail_return_pickup_task` trên project
`bqoyfytmrtvjwrpshuhh` ngày 28/10/2026. P08.2 nối giao diện vào hai RPC này qua
domain/repository/ViewModel, dùng Supabase client, theme và router chung.
Không thêm màn, dependency hoặc viết lại MH15 của Sơn. Kiểm chứng cuối gồm
45 tests pickup PASS, full suite 465 PASS/3 opt-in skipped, analyze sạch và
live MH11 collect → report handover PASS qua Auth/RPC thật.

`report_store_handover` **chỉ hỗ trợ outbound**. Pickup dùng RPC riêng
`report_return_pickup_handover` và đọc marker `get_my_return_pickup_handover`.
Sau thu đủ, shipper xác nhận bàn giao toàn bộ kế hoạch; sau report nút được
thay bằng thông báo đã ghi nhận, cửa hàng chưa xác nhận nhận/kiểm tra. Không tạo
demo success hoặc suy ra nhập tồn. Manager `receive_customer_return` của Sơn
chưa có và không thuộc phase frontend.

## Hành vi giao diện

- MH10 nhận biết loại thu hồi, dùng nhãn trạng thái theo pickup; không hiện
  cảnh báo giới hạn hai lần giao outbound hoặc nút thu tiền.
- MH11 đọc đúng snapshot điểm khách, hàng thực tế và số lượng kế hoạch/thực
  nhận. Notes chưa có trong schema được ghi chưa khả dụng, không lấy mô tả
  return request/video/ngân hàng làm ghi chú thay thế.
- Chỉ current assigned pickup chưa nhận hàng có thể thu đủ hàng hoặc báo lấy
  thất bại. Xác nhận thu là xác nhận thực nhận tại khách, không tự chạy khi mở
  màn hình. Payload chỉ task/key và item UUID/quantity theo kế hoạch server.
- Thu đủ thành công phải đọc lại task `in_transit` và quantity đã nhận; diễn đạt
  “đang hoàn về”, không phải cửa hàng đã nhận/kiểm tra/nhập lại tồn.
- Thất bại dùng các lý do được backend chấp nhận; other bắt buộc mô tả. Task
  failed có projection restricted, không xem đó là dữ liệu lỗi hoặc tự hẹn lại.
- Pending request giữ nguyên UUID/payload sau timeout/malformed ACK. ACK hợp lệ
  chỉ dẫn tới đọc lại MH11/MH10; lỗi phần đọc chỉ retry phần đọc. Đổi tài khoản
  xóa dữ liệu cũ, không để late response khôi phục snapshot/reason của người trước.

Không hiển thị bank details, return video/refund evidence/Storage URL hoặc hàng
của toàn đơn thay cho kế hoạch pickup. Không tạo nghĩa vụ COD mới, không suy
ra hoàn tiền/restock, không triển khai redelivery hoặc backend phase sau.

## API, files và kiểm chứng

Manifest P08.2:

- `lib/features/deliveries/domain/models/return_pickup_command.dart`,
  `domain/repositories/return_pickup_repository.dart`.
- `lib/features/deliveries/data/models/return_pickup_command_dto.dart`,
  `data/repositories/supabase_return_pickup_repository.dart`.
- `lib/features/deliveries/presentation/view_models/return_pickup_providers.dart`,
  `return_pickup_view_model.dart`, `widgets/return_pickup_action.dart`.
- Trang MH11 `presentation/pages/delivery_task_detail_page.dart`, card MH10
  `presentation/widgets/delivery_task_card.dart`.
- `test/features/deliveries/return_pickup_repository_test.dart`,
  `return_pickup_production_test.dart`, `return_pickup_widget_test.dart` và các expectations pickup trong test
  page/list hiện có.
- Tài liệu này cùng business states/API contracts/screen mapping, giữ nguyên
  nội dung P08.1 chưa commit trước lượt này.

`ReturnPickupCommand` giữ order/request UUID như guard ACK local, không gửi chúng
vào RPC. ACK phải đúng task/request/order/key/operation/status và timestamp server;
nullable description vẫn phải có key. Extra private fields bị từ chối. SDK retry
tắt để ViewModel quản lý retry bằng đúng command cũ.

Sau ACK collect, đọc lại đúng item-set returnPlan, quantity và quantityCollected
phải bằng kế hoạch đã xác nhận; không chỉ kiểm tra chữ in_transit. Fail ACK đọc
lại restricted failed projection có ID/contact/amount/items đã bị ẩn; không yêu
cầu các trường private xuất hiện trở lại mới coi là đã đọc xong. Logout/đổi tài
khoản xóa pending/ACK; same-user token epoch giữ envelope chưa chắc kết quả.

## Kiểm chứng ngày 28/10/2026

| Lệnh | Kết quả |
| --- | --- |
| `flutter test --no-pub test/features/deliveries/return_pickup_repository_test.dart --reporter expanded` | 21 PASS |
| `flutter test --no-pub test/features/deliveries/return_pickup_production_test.dart --reporter expanded` | 10 PASS ở lượt đầu; test gating thêm sau đó nằm trong full suite cuối (11 tests) |
| `flutter test --no-pub test/features/deliveries/return_pickup_widget_test.dart --reporter expanded` | 7 PASS |
| `flutter test --no-pub test/features/deliveries/delivery_task_detail_page_test.dart test/features/deliveries/delivery_task_list_page_test.dart --reporter expanded` | 21 PASS |
| `flutter analyze --no-pub` | No issues found |
| `flutter test --no-pub --concurrency=1 --reporter expanded` | **459 PASS, 2 opt-in live skipped** |
| `dart format` trên các Dart files P08.2 trong manifest | PASS |
| `git diff --check` | exit 0, chỉ cảnh báo LF/CRLF |

Lượt full suite song song ban đầu có expectation pickup cũ và một lỗi timing
test COD account-switch không thuộc source đã sửa. Đã cập nhật đúng expectation
pickup, giữ nguyên COD code và chạy full suite tuần tự đạt. Không bỏ test hoặc
đổi permission để ép PASS.

Review đã phát hiện/sửa failed restricted ACK guard, nhả result gate sau thành
công, exact quantity khi đọc lại, không render received-copy cho partial data,
source item theo returnPlan và wording redelivery. Worker chạm usage limit trước
kiểm tra cuối; coordinator sửa các phần còn lại/chạy final suite. Không tuyên bố
có final independent approval sau những sửa cuối.

Tests dùng production repositories/VM/widgets với adapters có nhãn trong test,
không app fallback. Bao phủ guarded collect/Other reason, duplicate submit,
timeout/malformed ACK/same-user epoch, late ACK account switch, ACK read-only
retry, masked failed projection, exact collected plan, gate release, states/kind,
privacy và layout 320px. Bổ sung handover có marker read/retry, exact-full dialog,
chống double submit và không hiển thị trạng thái đã nhập tồn. Kiểm chứng cuối
với JWT/UI thật và migration bổ sung ghi tại
[biên bản handover](p082_pickup_handover_acceptance.md), thay mốc kiểm thử ban đầu
trong bảng trên. Approval MH15/manager receipt của Sơn vẫn cần tích hợp riêng;
fixture kế hoạch đã duyệt không chứng minh upstream đó đã hoàn tất.
Source P08.1/P08.2 chưa commit/push trong lượt này; giữ nguyên `outputs/` ngoài
phạm vi.
