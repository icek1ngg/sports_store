# P06.2 — MH12 shipper COD

Giao diện shipper nằm trên route `/cod` hiện có, giữ optional `orderId` của
deep link và guard hiện tại. Dùng Riverpod MVVM, CodRepository.queryCollections
P06.1, shared Supabase client/theme/shell. Không tạo màn manager, router/client
thứ hai hoặc RPC nhận tiền.

## Mock và dữ liệu thật

HTML đính kèm chỉ là tham khảo bố cục: nhãn shipper, hướng dẫn, khối tổng tiền
nền đen, hai tab dạng pill và thẻ nền soft-cloud. Dùng AppColors Nike alpha
hiện có, primary #111111, surface #ffffff, soft-cloud #f5f5f5. Không thêm font,
package hoặc tải ảnh ngoài. Bỏ mock #8842/DH001, tên khách/hàng, tên quản lý/
thủ quỹ, số điện thoại cửa hàng, ca sáng, địa chỉ cửa hàng và demo/error toggles.
API không cung cấp các dữ liệu đó. Không thêm vai trò thủ quỹ ngoài ba role.

Mã đơn là order_code/source của P06.1, hiện ghi rõ UUID. Card chỉ có tiền đã
thu (hoặc received_amount cho nhóm đã nhận) và timestamps server. Không dựng
breakdown 520.000+30.000 khi API không có hai field đó; full COD 550.000 vẫn
hiển thị nguyên dữ liệu server. Thời gian hiển thị UTC rõ ràng, không ghi
"hôm nay" dựa vào ngày mẫu hoặc tự gán giờ thu khi timestamp null.

## Hai nhóm và totals

- Chưa đối soát: query statuses=[collected].
- Đã đối soát: query statuses=[received].
- Uncollected không thuộc hai nhóm tiền đã thu, không bị coi là chưa nộp tiền.
  UI có giải thích tường minh. Counts lấy từ backend, không đếm card đã tải.
- Held total lấy nguyên outstanding_vnd của P06.1, trước status/page và sau
  scope/order filter. Đổi tab không tự đổi tổng thành 0. Khi có orderId, UI
  ghi đang xem theo đơn và tổng cũng chỉ thuộc scope đơn đó.
- ViewModel gửi shipperId đúng session, không nhận filter shipper khác từ UI;
  kiểm tra response đúng chủ/kind nhóm. Backend RLS vẫn là boundary quyết định.
- Không có nút xác nhận receipt, báo nộp, edit amount, bù refund hoặc action
  manager trong shipper UI. Không tự suy collected là order state delivered.

## Refresh và lỗi

Mount/new navigation tải từ đầu; pull-to-refresh/nút làm mới đọc lại thật;
app resume và mỗi 30 giây khi foreground + route hiện tại đọc lại để thấy
manager update. Timer dừng khi dispose, không query lúc paused/route bị che.
Không giả định bảng đã được bật Realtime publication. Không polling khi đang
load/load-more hoặc first-page error; lỗi có retry thủ công.

Hook `refreshCodReadsAfterConfirmedWrite(Ref)` invalidate backing cache legacy
và shipper ViewModel; chỉ được gọi sau ACK/write result thật. Test thay đổi
scripted reads để kiểm chứng cache re-fetch, không fake manager RPC. P05.1 live
và RPC manager receipt chưa có, nên **chưa có call site write live**; không
coi hook là luồng giao thành công/đối soát end-to-end đã hoàn tất.

Refresh/tab/session đổi xóa dữ liệu cũ trước khi đọc; late response không được
publish. Auth/permission failures đóng dữ liệu, network load-more giữ trang
cùng query và có retry. Phân trang dùng cursor server và totals toàn scope,
drift phải đọc từ đầu có giới hạn. Không filter cục bộ trang đầu.

## Phạm vi và dependencies

P06.2 không migration/RLS/API signature/dependency/router/theme mới. Role
manager vẫn là outlet chưa triển khai, shipper page chỉ mount sau server role
check. Thay đổi role/account không được mở scope global của manager vào UI
shipper. P06.1 cần được deploy trước khi dùng trên backend chung; chưa xác
minh cloud Auth/PostgREST hoặc live records. RPC thiếu/lỗi hiện lỗi thật.

## Files và validation ngày 25/10/2026

- `lib/features/cod/presentation/pages/shipper_cod_page.dart`: UI read-only.
- `lib/features/cod/presentation/pages/cod_route_page.dart`: chọn shipper UI/
  manager outlet theo server role, loading/error/retry role.
- `lib/features/cod/presentation/view_models/shipper_cod_view_model.dart`:
  group/query/page/session/error lifecycle.
- `lib/features/cod/presentation/view_models/cod_providers.dart`: role read và
  invalidation backing cache; retry khôi phục cả upstream session failure.
- `lib/features/cod/presentation/view_models/cod_read_refresh.dart`: hook sau
  write ACK thật, chưa có call site live.
- `test/features/cod/shipper_cod_view_model_test.dart`,
  `shipper_cod_page_test.dart`, `cod_read_refresh_test.dart`: fixture được
  inject rõ ràng, không phải dữ liệu/success backend production.
- `test/app/router/operational_navigation_test.dart`: điều chỉnh assertion
  guard cũ vì UI hiện có thêm query read sau khi vào /cod; router không đổi.
- Tài liệu này, phần P06.2 trong `docs/api_contracts.md` và
  `docs/screen_mapping.md`.

| Lệnh | Kết quả |
| --- | --- |
| `flutter test --no-pub test/features/cod/shipper_cod_view_model_test.dart test/features/cod/shipper_cod_page_test.dart test/features/cod/cod_read_refresh_test.dart` | 20 tests PASS |
| `flutter test --no-pub test/features/cod` | 41 tests PASS |
| `flutter test --no-pub test/app/router/operational_navigation_test.dart` | 14 tests PASS |
| `flutter test --no-pub` | 225 tests PASS |
| `flutter analyze --no-pub` | No issues found |
| `dart format lib/features/cod/presentation test/features/cod/cod_read_refresh_test.dart` | Thành công; run cuối 6 files, 0 changed |
| `git diff --check` | Exit 0, chỉ cảnh báo chuẩn hóa LF→CRLF |

Widget tests có actual ViewModel + repository/session fixtures cho grouping/
own scope, state presentation, no manager actions, lifecycle polling/resume
và narrow viewport/text scale. Provider test xác minh cả cache backing legacy
và UI được đọc lại sau hook, không chỉ đếm một callback. Review độc lập không
còn finding correctness/security đáng kể. Không chạy thêm SQL/deploy trong
phase UI vì migration/API/RLS không đổi; kết quả SQL P06.1 ở handoff riêng.

P06.2 hoàn tất UI/read integration và kiểm thử local. **Chưa hoàn tất nghiệm
thu live toàn bộ scope sau write**: P06.1 chưa xác nhận deploy, P05.1/P05.2
live và manager receipt chưa có nên chưa thể nối hook vào write thật hoặc
kiểm tra luồng giao thành công/đối soát live. Không đánh dấu dependencies đó
đã được owner duyệt và không giả thành công để thay thế.
