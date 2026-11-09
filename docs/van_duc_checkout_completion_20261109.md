# MH16 — checkout và biên nhận đơn COD

Cập nhật 09/11/2026: đã sửa tải bản đồ/ghim địa chỉ và DNS riêng giả lập;
xem [chẩn đoán địa chỉ giao hàng](van_duc_checkout_address_20261109.md).

## Đã làm

MH16 theo bố cục STRIDE: người nhận, vị trí giao hàng trên bản đồ, địa chỉ
chi tiết, tóm tắt đúng các dòng đã chọn, tiền hàng, phí Hà Nội 30.000 đồng,
COD và nút đặt cố định. Trạng thái thành công nằm trong MH16, không thêm
màn hình nghiệp vụ thứ 21.

Biên nhận dùng `PlacementResult` đã đối chiếu với request và tài khoản:
UUID đầy đủ có nút sao chép, trạng thái thực, thời gian server hiển thị theo
Hà Nội, sản phẩm/biến thể/giá/số lượng snapshot, người nhận, địa chỉ, phí và
tổng COD server. Có Xem đơn hàng, Tiếp tục mua sắm và Quay lại giỏ hàng.
Không dựng hãng vận chuyển, giờ giao, đánh giá hoặc trạng thái xác nhận giả.
Ảnh chỉ dùng metadata snapshot nếu có; thiếu ảnh thì dùng placeholder.

## Lỗi và kết quả chẩn đoán

1. Người dùng xác nhận lỗi **không lưu được yêu cầu trên Android**. Đây là
   bước trước RPC; chưa có lệnh tạo đơn được gửi từ lần bấm đó. Store nay
   dùng Android `resetOnError: false`, `migrateWithBackup: true`, kiểm tra
   ghi–đọc lại đúng payload trước RPC, thông báo phân biệt plugin chưa nạp và
   lỗi native. Không đổi sang lưu plaintext, không tự xóa kho bảo mật. Nếu
   lưu cục bộ thất bại, ViewModel không xóa journal chưa rõ nguồn gốc.
2. Cloud thiếu hàm/trigger trừ giỏ sau đơn thành công. Đã áp dụng nguyên SQL
   trong `20261103152927_consume_purchased_cart_items.sql`. Đặt hàng chỉ trừ
   số lượng mua của đúng khách; giữ món bỏ chọn và lượng còn dư; replay
   không trừ lần hai.
3. RPC `place_order`, `get_placement_result`, tham số Dart và envelope khớp;
   quyền gọi customer và vùng Hà Nội hoạt động. Supabase không phải đang
   hoàn toàn mất kết nối như suy đoán ban đầu.

Probe Android chạy APK mới trên AVD API 33 **riêng**, không dùng/xóa dữ liệu
Pixel_5 cũ: plugin mặc định và store production đều ghi/đọc/xóa được, instance
mới khôi phục đúng payload, user khác không đọc được. Đạt 2/2 ca native.
Không có thiết bị đang gặp lỗi được kết nối, nên chưa xác định được chính
xác exception cũ trên máy người dùng. Kết quả không chứng minh lỗi do nhóm
trưởng chặn quyền, cũng không chứng minh chắc chắn là lỗi hot reload.

## Cách thử trên Android

1. Dừng hẳn tiến trình app đang chạy. Chạy lại `flutter run -d <device-id>`
   hoặc cài chồng APK ứng dụng mới; hot reload không đăng ký plugin native
   mới. **Không gỡ app/xóa dữ liệu** nếu đang có đơn chưa rõ kết quả.
2. Đăng nhập tài khoản khách. Vào MH05 chọn màu/cỡ còn tồn, thêm giỏ và chọn
   món cần mua. Không chọn cỡ demo hết tồn.
3. Tại MH16 nhập tên (2–200 ký tự), điện thoại (7–30 ký tự, có ít nhất 7 chữ
   số; chỉ số và `+(). -`), địa chỉ (5–500 ký tự); ghim đúng vị trí Hà Nội.
   Tọa độ được server kiểm tra theo vùng giao được duyệt, không chỉ theo
   chữ Hà Nội trong địa chỉ.
4. Đặt COD. Chỉ khi nhận/khôi phục biên nhận hợp lệ mới hiện thành công.
   Nếu mất phản hồi, dùng nút xác minh/thử lại yêu cầu cũ, không tạo request
   ID mới. Món bỏ chọn vẫn ở trong giỏ.

## Kiểm chứng backend

- `flutter analyze --no-pub`: không lỗi. Bộ catalog/cart/checkout/router đạt
  **210 ca**, 4 capture opt-in bỏ qua; capture checkout/success chạy riêng đạt
  ở 390px và 320px. Các ca làm mới phiên, đổi tài khoản và logout vẫn xác
  nhận dữ liệu người nhận cũ không xuất hiện ở tài khoản mới.
- APK ứng dụng thường đã build thành công từ **`lib/main.dart`**, không dùng
  entry point integration test. Bản cài:
  `build/releases/sports-store-checkout-20261109-debug.apk`.
  Log: `build/checkout_app_apk_build.log`. Đây là APK debug để nhóm thử,
  không phải bản phát hành cửa hàng.
- Ảnh render fixture: `build/checkout_form_390x1900.png`,
  `build/checkout_success_390x1400.png` và các bản 390×844/320×800. Ảnh map
  bị tắt trong capture offline; app thật dùng OSM và picker hiện có. Dữ liệu
  người nhận/đơn trong ảnh là fixture, không phải một giao dịch đã tạo thật.

- `build/checkout_redesign_sql_fixture.log`: PostgreSQL 17 cô lập, toàn bộ
  migration; tranh mua món cuối chỉ một đơn thành công, giữ tồn một lần,
  kiểm thử giao dịch/phân quyền/trừ giỏ PASS, không để dữ liệu nghiệp vụ thử.
- `supabase/tests/checkout_cloud_smoke.sql`: chạy trực tiếp trên project
  `bqoyfytmrtvjwrpshuhh`, trong transaction **ROLLBACK**; đặt/replay,
  khác payload, ngoài Hà Nội, đọc chéo khách, ledger/thông báo, trừ giỏ một
  phần, xóa dòng mua hết, giữ món bỏ chọn và giỏ khách khác đều PASS.
  Kiểm tra sau rollback còn 8 đơn thật, 0 user/product/cart fixture.
- Native log:
  `build/checkout_storage_probe/20261108_223304_5b864ad4/checkout-storage-test.log`.
  Chạy lại bằng `tool/run_checkout_storage_probe.ps1`; helper chỉ cài vào AVD
  tạm có danh tính và userdata trong workspace, rồi dừng AVD riêng.

## Lịch sử migration và phần phối hợp

MCP đăng ký migration trừ giỏ ở cloud với version **20261108153641**, tên
`consume_purchased_cart_items`; nguồn SQL tương ứng file local version
**20261103152927** đã có từ trước. Bộ duyệt tự động từ chối cập nhật trực
tiếp metadata để đổi version vì không cần thiết cho chức năng. Lịch sử cloud
được giữ nguyên; không thử lại bằng đường khác. Khi đồng bộ migration bằng
CLI cho nhóm, cần đối chiếu hai version này trước, không áp lại `CREATE
FUNCTION/TRIGGER` trùng. Không sửa hoặc đánh dấu giả các migration khác.

Chẩn đoán còn thấy auto-confirm sau một giờ chưa được chứng minh/triển khai
trên cloud (chưa có pg_cron/hàm phù hợp; có 3 đơn chờ quá một giờ tại lúc
kiểm tra). Đây là phần phối hợp Orders của Bảo, không chặn tạo đơn; lượt này
không tự sửa trạng thái các đơn cũ hoặc nhận là đã hoàn tất scheduler.

Code chưa commit/push Git. `.metadata` và `pubspec.lock` có thay đổi từ trước
được giữ nguyên. APK integration test không phải APK để sử dụng app thường;
chỉ giao APK build bằng target `lib/main.dart`.
