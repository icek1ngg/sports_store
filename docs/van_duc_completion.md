# Bàn giao phần Văn Đức — MH04, MH05, MH06, MH16

Ngày cập nhật: 27/10/2026. Tên ứng dụng **Sports Store**, giao diện tiếng Việt.
Tài liệu này cập nhật trạng thái sau kế hoạch ngày 24/10; không xem các ghi chú
“MH16 chưa triển khai” trong lịch sử kế hoạch là trạng thái hiện hành.

## Phạm vi

| Màn hình | Route | Chức năng |
| --- | --- | --- |
| MH04 | `/customer/products` | Danh sách, tìm tên, lọc danh mục, phân trang |
| MH05 | `/customer/products/:productId` | Chi tiết, biến thể, giá/tồn, thêm giỏ |
| MH06 | `/customer/cart` | Đọc/sửa/xóa giỏ riêng, tạm tính, mở MH16 |
| MH16 | `/customer/checkout` | Người nhận, điện thoại, địa chỉ, chọn vị trí, đặt COD, biên nhận |

Chỉ customer được mở các route trên. Dùng router, theme, Supabase client và
session provider chung. Không thêm MH21 hoặc sửa MH18 thành chọn địa chỉ khách.
Model `Order`/`OrderItem` được tích hợp từ nền Orders của Bảo tại
`origin/feature/orders-notifications-phase2`; chỉ lấy model nền và mapper cần cho
biên nhận. Màn MH07–MH09 và tác vụ tự xác nhận vẫn thuộc Orders.

## Đặt hàng và khôi phục

Máy chủ lấy customer từ phiên, giá và tồn từ catalog; phí giao cố định 30.000đ.
Một giao dịch tạo đơn/snapshot, giữ tồn tất cả biến thể, ghi ledger, sự kiện
`order_placed` và thông báo cho các manager. Thêm giỏ không giữ tồn; đặt đơn
không giảm `on_hand` (xuất hàng do luồng giao hàng thực hiện).

`place_order` nhận mã yêu cầu và ý định mua hàng; cùng customer/mã/payload trả
lại cùng đơn. Đổi payload dưới cùng mã bị từ chối. Hai customer có thể dùng
cùng UUID yêu cầu mà không truy cập hoặc xung đột dữ liệu của nhau.

Ứng dụng lưu yêu cầu chờ trong kho mã hóa của thiết bị trước khi gửi RPC.
Timeout giữ nguyên mã và payload. Khi mở lại, tra `get_placement_result` trước
khi cho phép tiếp tục; `not_found` không chứng minh lần trước đã rollback.
Đổi tài khoản loại dữ liệu khỏi bộ nhớ, và không hiển thị kết quả đến muộn của
phiên trước. Lỗi đọc kho khôi phục không được tự xóa yêu cầu rồi đặt mới.

Giỏ được giữ sau khi đặt để không xóa thay đổi phát sinh trên thiết bị khác.
Biên nhận MH16 hiển thị mã đơn, trạng thái hiện tại và tổng COD máy chủ chốt.
Giá/tồn cuối cùng được kiểm tra trên máy chủ khi đặt; màn hình thông báo rõ
quy tắc này. Không báo đặt thành công nếu API hoặc kiểm tra biên nhận thất bại.

## Vùng giao Hà Nội

Máy chủ kiểm tra tọa độ với polygon Hà Nội, không chỉ chữ “Hà Nội” hay bounding
box. Hỗ trợ Polygon/MultiPolygon, loại vùng lỗ; thiếu hoặc sai cấu hình thì từ
chối đặt. Địa chỉ chi tiết và tọa độ đều bắt buộc. Bộ chọn vị trí nằm trong MH16,
có bản đồ OpenStreetMap và ghi nguồn; không thu thập GPS shipper.

Nguồn dữ liệu ranh giới: Government of Viet Nam / HDX, năm 2020, phân phối qua
[geoBoundaries gbHumanitarian VNM ADM1](https://www.geoboundaries.org/api/current/gbHumanitarian/VNM/ADM1/),
commit `9469f09`, giấy phép CC BY 3.0 IGO. Feature gốc, 4.664 điểm, lưu tại
[`assets/data/hanoi_boundary_source.geojson`](../assets/data/hanoi_boundary_source.geojson).
SHA-256: `67610162580e31e5d4af72c05741f6b72328b3da037bd57e393ea1aab9a78128`.
Đây là phiên bản dữ liệu hành chính được dùng cho dự án, không phải dịch vụ
geocoding hoặc cam kết tự cập nhật địa giới. Migration cấu hình chỉ điền khi
vùng giao chưa có, giữ nguyên cấu hình đã có của cửa hàng.

## Chạy thử

```powershell
flutter pub get
flutter run -d emulator-5554 -t tool/catalog_live/main.dart --dart-define-from-file=config/supabase.json
```

Đây là entry point thử phần Văn Đức bằng Auth/Supabase thật, không thay MH01
do An sở hữu. Cần customer đã xác nhận email và catalog thật. Dữ liệu DEMO có
trong `supabase/seed_catalog_demo.sql`; không reset giá/tồn của dữ liệu đã tồn tại.

Kiểm tra tự động toàn luồng trên Android với transport fixture tách biệt:

```powershell
flutter test integration_test/van_duc_purchase_test.dart -d emulator-5554
```

Kiểm tra này dùng giao diện/router/ViewModel/repository thật, nhưng HTTP fixture
rõ ràng, không đăng nhập hoặc tạo đơn trên Supabase cloud. Unit/widget tests
chạy bằng `flutter test test`. Database fixture dùng PostgreSQL 17 trong
`supabase/.temp/`, có Auth/Storage stub và không thay đổi database cloud.

Nghiệm thu Auth/RLS/catalog/giỏ thật và nhập thông tin thử được hướng dẫn trong
[`van_duc_mh04_mh06_acceptance.md`](van_duc_mh04_mh06_acceptance.md).
Không gửi mật khẩu qua chat hoặc đưa vào `dart-define`/APK/source.

## Kết quả xác minh

| Kiểm tra | Kết quả | Phạm vi |
| --- | --- | --- |
| `flutter analyze --no-pub` | Không có lỗi | Code chung và bốn màn của Văn Đức |
| `flutter test --no-pub test` | 217 test qua | Catalog/cart/checkout, điều hướng, ngôn ngữ, hồi quy delivery/COD |
| Android `integration_test/van_duc_purchase_test.dart` | 2 test qua trên Pixel_5 API 33 | Luồng bốn màn với HTTP fixture và đọc/ghi kho mã hóa Android thật |
| PostgreSQL 17.10 `checkout_placement.sql` | Qua, rollback | Thiếu hàng, tranh món cuối, replay, payload khác, toàn bộ đơn, quyền, polygon, kiểm tra ý định đầy đủ kể cả hash trùng |
| `database_security.sql`, `delivery_read_security.sql`, seed catalog lặp | Qua, rollback dữ liệu test | Không nới RLS; seed không reset stock đã có |
| Supabase `checkout_cloud_smoke.sql` | Qua, rollback | Tạo đơn, tổng COD, giữ tồn, replay/conflict, ngoài Hà Nội, customer khác, notification và validator tồn thật của delivery |
| APK debug `tool/catalog_live/main.dart` | Build thành công | `build/van_duc/sports-store-debug.apk`; dùng publishable config, không nhúng mật khẩu |

APK đã được cài trên `emulator-5554`; kiểm tra tiến trình ứng dụng đang chạy,
Supabase SDK khởi tạo xong và Activity trả trạng thái `ok`. Đây là kiểm tra
khởi động, không thay kiểm tra đăng nhập thật hoặc kiểm tra trực quan bằng tay.

Ba migration đã áp dụng lên project `bqoyfytmrtvjwrpshuhh`:

- `20261027005254_checkout_placement.sql`
- `20261027005305_hanoi_service_area.sql`
- `20261027010030_checkout_exact_intent.sql`

Các file được tạo bằng CLI Supabase thật; sau khi triển khai, timestamp file
được đồng bộ với version trả về trong migration history của cloud. Migration
cuối đối chiếu cả JSON ý định chuẩn hóa, không chỉ dựa vào fingerprint hash.

Cloud đã có dữ liệu và đang được các phần khác thử cùng lúc. Test của Văn Đức
chỉ tạo tài khoản SQL tạm không có password/identity/session và dữ liệu có
prefix riêng trong transaction; cuối test rollback toàn bộ. Không dùng số đếm
tổng đơn của cả project để suy ra số đơn do checkout tạo. Không xóa/reset đơn
hoặc tồn do nhóm đã tạo trước.

Log test và build nằm trong `build/`, được Git bỏ qua. Runner PostgreSQL yêu
cầu runtime PG17 và module Node `pg` trong `supabase/.temp/catalog_pg_runtime`,
server loopback `127.0.0.1:55441`, data directory chính xác
`supabase/.temp/catalog_pg_data`. Runner từ chối server ngoài đường dẫn đó,
và từ chối tái sử dụng database fixture đã có. Runtime này là dụng cụ tại máy,
không phải dependency của Flutter hoặc thành phần cloud.

Nghiệm thu Auth/Storage/UI qua mạng thật chưa chạy: đã có user trên project
nhưng chưa nhập thông tin đăng nhập riêng vào
`config/catalog_acceptance.local.json`. File đó phải được tạo qua
`tool/set_catalog_acceptance_credentials.ps1`, không ghi mật khẩu vào chat.
Hai test Android nêu trên không thay bằng chứng đăng nhập qua Supabase Auth.

Advisors đã được kiểm tra. INFO “RLS enabled no policy” trên metadata private
là chủ ý: client không có quyền đọc/ghi. Cảnh báo public SECURITY DEFINER cần
được đọc theo mục đích wrapper đã kiểm tra quyền/transaction, không khắc phục
bằng mở quyền trực tiếp. Xem
[hướng dẫn advisor của Supabase](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
Auth còn cảnh báo cấu hình chống mật khẩu bị lộ, thuộc phần quản trị Auth:
[hướng dẫn cấu hình](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

Màn MH07, thao tác xác nhận đơn và job tự xác nhận sau một giờ vẫn do Bảo sở
hữu; checkout tạo đúng `pending_confirmation`, không tự chuyển đơn hoặc gán
shipper. API phân công hiện có của delivery chịu trách nhiệm tạo COD
`uncollected` khi phân công. Tích hợp toàn bộ mã Orders của nhánh Bảo cần giữ
canonical model/DTO đã dùng chung, không tạo một bộ model mới.

Code được giữ trên nhánh `v-duc`, đã gộp nền `origin/main` tại `69dfe6b`;
chưa commit/push trong lượt triển khai này.

## Sửa P1 — làm mới phiên trong MH16, ngày 28/10/2026

Đã xử lý trường hợp go_router kiểm tra quyền ở URI nền MH04 khi đang mở chồng
MH06/MH16. Bốn route customer hợp lệ chia sẻ kết quả kiểm tra role trong cùng
phiên hiện tại; UUID sai và route ngoài phạm vi không được dùng kết quả này.
Các repository vẫn kiểm tra quyền và dữ liệu riêng trên máy chủ.

Navigator của customer được giữ khi kiểm tra lại quyền cho cùng tài khoản,
đồng thời ẩn giao diện và chặn nhập liệu. Form người nhận, địa chỉ và tọa độ
được giữ; lỗi mạng có nút thử lại. Dialog chọn vị trí thuộc Navigator được bảo
vệ nên cũng được ẩn khi kiểm tra quyền. Đăng xuất/đổi tài khoản xóa cả màn và
dialog cũ; thay đổi role được kiểm tra lại và có thể chặn checkout.

Kiểm thử hồi quy nằm trong `test/app/router/customer_session_refresh_test.dart`:
giữ form/tọa độ rồi đặt đúng một đơn, kiểm tra quyền chậm, lỗi mạng và thử lại,
quay về giỏ/danh mục, dialog đang mở, đổi tài khoản, đăng xuất và thu hồi quyền.
Đây là widget tests dùng router/ViewModel/repository thật với HTTP fixture,
không thay nghiệm thu Auth/Storage/UI qua Supabase thật.

Kết quả xác minh lượt P1: `dart format` đạt, `flutter analyze --no-pub` không
có vấn đề; toàn bộ 225 test đạt. Tám ca hồi quy P1 cũng đạt khi chạy riêng,
bao gồm đăng xuất/đổi tài khoản trong lúc dialog vị trí đang mở. Log nằm tại
`build/p1_full_tests.log` và `build/p1_regression_tests.log`, được Git bỏ qua.

Phạm vi lượt 28/10 chỉ P1; P2 được xử lý ở mốc tiếp theo bên dưới. Không thay
database, RPC, dependency hoặc commit/push trong lượt P1.

## Sửa P2 — giữ thao tác giỏ khi phiên làm mới, ngày 29/10/2026

CartViewModel giữ nguyên target tuyệt đối khi token làm mới cùng customer.
Ví dụ giỏ có 2, thêm 3 đã ghi thành 5 nhưng mất phản hồi: refresh và thử lại
vẫn đặt target 5, không cộng thành 8. Thao tác xóa chưa xác nhận cũng giữ đúng
variant và lặp lại cùng lệnh xóa.

Mỗi customer có lock cho request đang chạy; token refresh không mở ghi mới
song song. Phản hồi ở epoch cũ không ghi đè snapshot hiện tại hoặc báo thành
công. Nếu A chuyển sang B rồi quay lại A trong lúc request A còn chạy, A chỉ
khôi phục command của chính mình; B không thấy snapshot/intent của A. Khi
đăng xuất/đổi tài khoản sau request đã kết thúc, intent hiển thị cũ được bỏ.

Lỗi auth sau ghi vẫn giữ target vì server có thể đã commit. Khi dựng lại giỏ
sau token refresh gặp lỗi mạng/backend và cùng customer đang có pending, UI giữ snapshot đã biết,
hiện cảnh báo và khóa checkout/ghi mới; người dùng thử lại đúng command cũ.
Ở lượt dựng lại này, lỗi quyền/dữ liệu không dùng snapshot dự phòng.

Kiểm thử bổ sung trong `test/features/cart/cart_session_refresh_test.dart`
và `test/features/cart/cart_retry_flow_test.dart`, gồm refresh nhiều lần,
timeout sau commit, xóa lặp, request còn chạy, lỗi đọc/auth, khóa checkout/
thêm giỏ, đăng xuất/đổi tài khoản và A → B → A. Các test dùng fixture rõ ràng,
không là bằng chứng Auth/Storage/UI qua Supabase thật.

Kết quả kiểm tra cuối ngày 29/10/2026:

| Kiểm tra | Kết quả |
| --- | --- |
| `dart format --output=none --set-exit-if-changed lib test integration_test tool test_driver` | 128 file, không cần sửa định dạng |
| `flutter analyze --no-pub` | Không có vấn đề |
| `flutter test --no-pub test` | 237 test qua, gồm cả tám ca P1 và 12 ca P2 mới |
| Hai file hồi quy giỏ P2 chạy riêng | 13 test qua, gồm một ca giỏ cũ |
| `flutter build apk --debug --no-pub -t tool/catalog_live/main.dart --dart-define-from-file=config/supabase.json` | Build thành công |
| Script kết nối Supabase chỉ đọc | Auth settings HTTP 200; Data API probe HTTP 404 đúng kỳ vọng |

APK mới ở `build/app/outputs/flutter-apk/app-debug.apk`. Log kiểm tra cuối:
`build/p2_full_tests.log`, `build/p2_regression_tests.log`, `build/p2_apk_build.log`;
đều được Git bỏ qua. Không thay database, RPC hoặc dependency trong lượt P2.
Rà độc lập không phát hiện lỗi P1/P2 mới trong mã sửa; P1 và P2 đã được đóng
theo phạm vi fixture/biên dịch trên. Tại thời điểm kết thúc lượt P2 chưa commit
hoặc push nhánh `v-duc`.

`config/catalog_acceptance.local.json` vẫn chưa có, nên chưa chạy nghiệm thu
đăng nhập, ảnh Storage và UI qua Supabase thật. Kiểm tra kết nối chỉ chứng
minh endpoint phản hồi; không thay bằng chứng đọc/ghi bằng tài khoản thật.

## Kiểm tra trước khi commit — 29/10/2026

Kiểm tra lại trên nền `v-duc` tại `69dfe6b` cùng phần thay đổi MH04–MH06/MH16:
định dạng 128 file đạt, phân tích không có lỗi, toàn bộ 237 test qua và
`git diff --check` đạt. Log ở `build/prepush_analyze.log` và
`build/prepush_tests.log`, không đưa vào Git.

Đã fetch và đối chiếu `origin/main` tại `b818f1b`; bản main này chưa được gộp
vào snapshot kiểm thử trên. Model đơn hàng và SQL checkout tương thích.
Khi tích hợp cần giữ DTO đơn hàng đầy đủ và màn COD đã triển khai của main,
đồng thời hợp nhất dependencies/assets/fonts và tài liệu hai phía. Các màn
Auth/quản lý sản phẩm preview và phần Orders chưa nối backend của nhóm không
được xem là luồng production hoàn chỉnh chỉ vì đã có trên main.
