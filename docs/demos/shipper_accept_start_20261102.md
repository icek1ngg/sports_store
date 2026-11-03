# Nhận hàng bắt đầu giao và phân nhóm giao lại — 02/11/2026

## Hành vi

- MH11: shipper bấm **Nhận hàng**, xác nhận một lần; nhận hàng và bắt đầu
  giao trong cùng giao dịch server. Thành công thì nhiệm vụ là `in_transit`.
  Không cần bấm thêm **Bắt đầu giao hàng**. Áp dụng cho outbound lần một và
  lần hai; task `accepted` từ phiên bản cũ vẫn có thao tác bắt đầu để tiếp tục.
- Không tăng số lần giao hai lần, không xuất tồn lần nữa khi giao lại và
  không bỏ qua kiểm tra người giữ hàng, phân công, mất/hỏng hàng hay COD.
- MH10: outbound lần một không thành công nằm trong **Giao lại**. Sau khi có
  task lần hai, task lần một không còn được tính trong nhóm này. Outbound
  lần hai không thành công mới vào **Thất bại**; các loại task thất bại khác
  giữ hành vi hiện có.
- Trạng thái database `failed` của từng lần giao và lịch sử sự kiện vẫn giữ
  nguyên. Nhãn lịch sử lần một là **Lần 1 chưa giao được**, không phải thất
  bại cuối cùng; nhóm **Giao lại** chỉ chứa lần một chưa có lần hai.
- Các nhóm mới là phần con của `ungrouped`; tổng danh sách giữ công thức cũ.
  Không mở rộng thông tin người nhận trong các projection đã bị giới hạn.

## Hợp đồng

- `accept_and_start_delivery_task(p_task_id uuid, p_request_id uuid)` ghép
  các RPC accept/start hiện hữu trong một transaction. Request UUID được
  giữ nguyên khi retry; hai lệnh con có UUID riêng được suy ra ổn định để
  không ghi lặp bằng chứng nhận hàng hoặc tăng số lần giao.
- Receipt theo shape `start_delivery_task`, nhưng `operation` là
  `accept_and_start` và `request_id` là UUID yêu cầu ngoài. Client kiểm tra
  receipt rồi đọc lại chi tiết; không coi ACK là projection của nhiệm vụ.
- Bộ lọc `retry`: outbound `failed`, attempt 1, chưa có task outbound
  attempt 2 cùng order và order còn `awaiting_redelivery`; đã chọn hoàn sớm
  thì không thuộc nhóm này. Bộ lọc `failed`: các task `failed` trừ outbound
  attempt 1. `counts.retry` và `counts.failed` không cộng thêm vào total.
- `raw_order_id` chỉ phục vụ phép kiểm tra nội bộ, không xuất ra response
  của task bị giới hạn quyền. Task lần một đã có lần hai vẫn giữ trong
  lịch sử/tổng `ungrouped`, không được tính vào hai nhóm trên.

## Kiểm chứng và triển khai

- Migration CLI: `20261102035050_accept_and_start_delivery_task.sql`.
  Đã triển khai riêng lên project `bqoyfytmrtvjwrpshuhh`, cloud version
  `20261102040118`; không đẩy các migration không liên quan.
- `flutter analyze`: không có lỗi. Bộ delivery tests đạt; reviewer chạy lại
  83 test trọng tâm và coordinator chạy 47 test router, đều đạt.
- SQL: `run_delivery_read_fixture.mjs` và
  `run_outbound_retry_production.mjs` đạt trên PostgreSQL 17 cục bộ,
  gồm replay, rollback lỗi muộn, ACL, phân nhóm và các concurrency regression.
- Kiểm tra cloud bằng role authenticated của shipper: `retry=1`, `failed=1`,
  `ungrouped=3`, tổng 7 nhiệm vụ; hai nhóm trả đúng filtered_total tương ứng.
  Không thay đổi trạng thái đơn demo để kiểm tra.
- Security advisors không tăng so với trước triển khai: 2 INFO private RLS,
  32 cảnh báo RPC SECURITY DEFINER hiện hữu, 1 cảnh báo bảo vệ mật khẩu cũ.
  RPC mới là SECURITY INVOKER; helper boolean nằm trong private và không
  cho authenticated gọi trực tiếp.
- Build thành công: `flutter build apk --debug --no-pub
  --dart-define-from-file=config/supabase.json`; APK tại
  `build/app/outputs/flutter-apk/app-debug.apk`.
