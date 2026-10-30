# Kết nối Supabase cho các màn Dung An

## Cập nhật sửa lỗi và tích hợp — 30/10/2026

- MH01/MH02 sau khi có session và profile hợp lệ chuyển customer tới
  `/customer/products`, manager tới `/manager/orders`, shipper tới
  `/shipper/tasks`; không cần bấm thêm nút mở nhiệm vụ. Deep link hợp lệ được
  giữ nguyên. Trang theo role từ chối tài khoản khác quyền.
- MH04 chưa có implementation trong repository. Route customer nhận
  `customerCatalogRouteBuilderProvider`; mặc định hiển thị chưa tích hợp,
  không dùng inbox làm trang mua hàng. MH08 đã có UI; route dùng
  `ManagerOrdersPage` khi owner cung cấp `orderRepositoryProvider`, còn mặc
  định thông báo thiếu dịch vụ đơn hàng. Hai dependency này chưa hoàn tất.
- `lib/main.dart` nối `featureSessionScopeProvider` ở root ProviderScope với
  `trustedFeatureSessionProvider` từ session/profile server; mỗi lần thay đổi
  tạo generation mới để provider dùng chung không đọc cache của phiên trước.
- Navigation khách có Sản phẩm/Hội thoại; manager có Đơn hàng/Sản phẩm/Hội
  thoại/COD. COD manager có nút về quản lý đơn hàng.
- MH20 poll/manual refresh ghép dữ liệu mới vào lịch sử đã tải, giữ cursor,
  thứ tự `(created_at,id)` và không nhân đôi. Backfill tới mốc head liên tục
  đã đọc, kể cả khi có ACK gửi tin mới hơn khoảng lịch sử chưa tải. Gửi/tải
  lịch sử/refresh không chạy chồng; lỗi quyền xóa dữ liệu đang hiển thị, lỗi
  mạng giữ lịch sử. MH19 được tải lại sau head read và khi quay về từ MH20.
- MH03 chọn ảnh từ thiết bị qua `file_selector` 1.1.0. Chỉ nhận chữ ký file
  PNG/JPEG/WebP, tối đa 5 MiB. ViewModel gọi repository kiểm tra manager rồi
  upload vào bucket private `product-images`, object path
  `<manager UUID>/<request UUID>.<extension>`, `upsert=false`. Preview dùng
  signed URL; chỉ object path được lưu vào sản phẩm. UI chặn lưu/đóng trong
  lúc chọn/upload, bỏ kết quả của tài khoản cũ, không báo thành công giả.
- Upload Storage và lưu sản phẩm là hai thao tác riêng. Đóng biểu mẫu sau khi
  upload có thể để lại ảnh private chưa được tham chiếu; không tự xóa ảnh
  đang có hoặc đổi quyền bucket. Chưa nghiệm thu picker trên điện thoại thật.
- Sửa helper `_hasText` và assertion root cũ của test điều hướng dùng chung.

Không thay schema/RLS/RPC trong lượt này. Các kết quả ngày 29/10 bên dưới là
lịch sử. Nghiệm thu ghi bằng tài khoản cloud thật vẫn chưa thực hiện: connector
không có quyền project `bqoyfytmrtvjwrpshuhh`, CLI không có access token và
không có tài khoản test được cấu hình trong environment. Không tạo tài khoản
hoặc thay đổi dữ liệu cloud để vượt qua giới hạn này.

Kết quả kiểm tra 30/10: `flutter analyze --no-pub` không có issue;
72 test Auth/Catalog/Chat/toàn bộ router PASS, gồm giữ lịch sử chat khi poll,
backfill khoảng trống sau ACK gửi tin, upload/đổi phiên, bridge Auth ở root
và manager quay về từ COD. Runner PostgreSQL cô lập PASS 34 kiểm tra. Đây
không phải bằng chứng thao tác ghi bằng tài khoản cloud thật.

Lệnh kiểm tra thay đổi:

```powershell
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 test/features/auth test/features/catalog test/features/chat test/app/router --reporter expanded
flutter build web --no-pub --dart-define-from-file=config/supabase.json
node supabase/tests/run_dung_an_integration.mjs
dart run tool/check_dung_an_backend.dart
```

Ứng dụng chính dùng cùng client được khởi tạo trong `lib/main.dart`, Riverpod,
go_router và repository thật. `tool/ui_preview/prm_main.dart` chuyển vào cùng
entrypoint; không còn bộ sản phẩm/hội thoại demo trong các màn này.

| Màn | Route | Chức năng |
| --- | --- | --- |
| MH01 | `/`, `/login` khi chưa đăng nhập | Email/mật khẩu, báo lỗi Auth, khôi phục phiên, đọc vai trò từ `profiles`, đăng xuất |
| MH02 | `/register` | Đăng ký khách, lưu họ tên/điện thoại qua trigger, hướng dẫn xác nhận email khi server yêu cầu |
| MH03 | `/manager/products` | Đọc/tìm/lọc/phân trang sản phẩm; thêm/sửa/ngừng bán; quản lý SKU, thuộc tính, giá và tồn từng biến thể; chọn/upload ảnh |
| MH19 | `/chat` | Hội thoại thật, tìm nội dung/tên, lọc chưa đọc/chờ trả lời, tải lại; khách mở hội thoại riêng |
| MH20 dùng chung | `/chat/:conversationId` | Mở theo ID, đọc/gửi văn bản, tải tin cũ và lưu mốc đã đọc |

Manager có thanh điều hướng sản phẩm/hội thoại. Customer không mở được quản lý
sản phẩm; shipper được dẫn tới luồng nhiệm vụ đã có. Khi đổi tài khoản, UI và
provider không được giữ dữ liệu riêng của phiên cũ. Backend tiếp tục kiểm tra
RLS/quyền thực tế; metadata do người dùng sửa không cấp quyền manager/shipper.

## Hợp đồng ghi sản phẩm

`save_managed_product(p_request_id, p_product_id, p_expected_updated_at, p_name,
p_category_id, p_description, p_image_path, p_is_active, p_variants)` trả UUID
sản phẩm. Tạo mới dùng ID/thời điểm kỳ vọng null. Mỗi biến thể gồm `id`, `sku`,
`label`, `price_vnd`, `on_hand`, `expected_on_hand`, `is_active`, `attributes`.

RPC chỉ cho manager: khóa sản phẩm và biến thể theo thứ tự, kiểm tra bản đọc cũ,
không cho tồn thấp hơn lượng đã giữ, giữ nguyên `reserved`/`damaged`, ghi ledger
điều chỉnh và receipt trong cùng transaction. Không bỏ biến thể cũ khỏi payload;
ngừng bán bằng `is_active=false` để giữ liên kết đơn hàng. Retry cùng request ID
và payload trả kết quả cũ; đổi payload với cùng ID bị từ chối. Không xóa cứng
sản phẩm đã được tham chiếu. Ảnh dùng URL HTTPS hoặc object path đã có trong
bucket `product-images`; đã có bộ chọn/tải ảnh từ thiết bị như cập nhật 30/10.

Hàm public là SECURITY INVOKER, chuyển vào hàm private kiểm tra manager do
inventory/ledger không có quyền ghi trực tiếp từ client. Bảng receipt private
bật RLS, không cấp quyền đọc/ghi cho client; hàm không cấp EXECUTE cho anon.

## Hợp đồng hội thoại

- `list_chat_conversations()` trả JSON summaries theo hoạt động tin nhắn mới
  nhất, gồm customer, nội dung cuối và số chưa đọc của người gọi.
- `ensure_customer_conversation()` tạo/đọc một hội thoại duy nhất của khách hiện
  tại. Không nhận customer ID từ client.
- `get_chat_messages(p_conversation_id, p_before_message_id default null)` trả
  tối đa 100 tin, `has_more`, ID hội thoại. Cursor dùng `(created_at,id)` ổn định.
  Lần đọc đầu cập nhật mốc đọc theo snapshot trả về.
- `send_chat_message(p_conversation_id,p_client_message_id,p_body)` trả tin
  canonical. Nội dung 1–4000 ký tự; cùng sender/client ID không tạo tin trùng.

Các RPC chat dùng SECURITY INVOKER và RLS hiện có. Trigger mốc đọc chỉ thay key
của `auth.uid()`, giữ key người khác, không lùi mốc và chặn thời gian tương lai.
Trigger ghi tin nhắn và RPC đọc khóa cùng hàng hội thoại. Tin nhắn nhận giờ
server sau khi lấy khóa, tăng đơn điệu trong hội thoại; transaction bắt đầu
sớm nhưng commit muộn không đẩy tin chưa xem ra sau mốc đã đọc. Mở trang mới
nhất đánh dấu hội thoại đã đọc tới tin mới nhất trả về, gồm lịch sử trước đó;
100 tin đầu là phần hiển thị ban đầu và có thể tải các trang cũ hơn.
Danh sách tải lại định kỳ khi đang mở; chi tiết có nút tải tin mới và tin cũ.
Không có trạng thái hoàn tất hội thoại tự đặt, OAuth hay realtime giả lập.

## Áp dụng và xác minh

Bạn tự chạy trên Supabase SQL Editor theo
[bộ SQL và hướng dẫn chạy thủ công](../../supabase/manual/README.md):
`dung_an_management.sql` là bản có transaction để dán chạy toàn bộ;
`verify_dung_an_management.sql` kiểm tra năm RPC, RLS và trigger sau khi cài.

Migration CLI đã tạo:
`supabase/migrations/20261029041230_dung_an_management_integration.sql`.
Không sửa/replay migration nền tảng trên database đã có dữ liệu. Quản trị viên
cần kiểm tra lịch sử migration của đúng project `bqoyfytmrtvjwrpshuhh`, sau đó
áp dụng migration mới bằng Supabase CLI hoặc SQL Editor. Không chạy reset.

Kiểm tra lại ngày 29/10/2026 sau khi người dùng chạy migration: Auth settings
HTTP 200, Data API nhận key hợp lệ. Cả năm RPC đã được nhận diện trên cloud và
trả `42501`/HTTP 401 hoặc 403 cho caller chưa đăng nhập đúng như yêu cầu; lỗi
`PGRST202` trước khi triển khai đã hết. Kết nối quản trị của phiên vẫn chưa có
quyền project, nên chưa đọc được định nghĩa hàm, RLS/trigger hay chạy SQL kiểm
chứng trực tiếp trên cloud.

Chạy từ thư mục `sports_store`:

```powershell
flutter run -d chrome --dart-define-from-file=config/supabase.json
dart run tool/check_supabase_connection.dart
dart run tool/check_dung_an_backend.dart
flutter analyze
flutter test
```

Probe backend dùng anon, không tạo tài khoản hoặc ghi dữ liệu: RPC đã cài phải
trả `42501`, chặn anon; hàm thiếu trả `PGRST202`. Probe không thay thế kiểm thử
đăng nhập/giao dịch bằng tài khoản thật.

Kiểm thử SQL cô lập bằng PostgreSQL nhúng (Auth/Storage là SQL fixture, không
phải dịch vụ Supabase) không tác động cloud:

```powershell
npm install --prefix build/dung_an_db_test --no-save --package-lock=false @electric-sql/pglite@0.3.14
node supabase/tests/run_dung_an_integration.mjs
```

Runner đã qua 34 kiểm tra database, gồm quyền cho phép/từ chối theo vai trò,
trigger đăng ký không nhận role metadata, rollback toàn bộ khi tồn kho sai,
giữ lượng reserved, chống retry trùng, từ chối bản sửa cũ, quyền chat và phân
trang lịch sử. Đây là PostgreSQL nhúng một kết nối, chưa phải kiểm thử nhiều
transaction đồng thời hoặc nghiệm thu dịch vụ Supabase cloud.

Muốn thử quản lý cần tài khoản có `profiles.role='manager'` do quản trị viên
cấp. Đăng ký trong ứng dụng luôn tạo `customer`; không tự nâng quyền để demo.

## Kết quả kiểm tra mã nguồn

- `flutter analyze --no-pub`: không có issue.
- `flutter test --no-pub`: 1.276 test thành công; 1 test có sẵn bị bỏ qua.
- `flutter build web --no-pub --dart-define-from-file=config/supabase.json`:
  thành công. Có cảnh báo font Cupertino từ dependency; các màn mới dùng
  Material icons. Bản build không xác nhận RPC cloud đã triển khai.
- `node supabase/tests/run_dung_an_integration.mjs`: 34 kiểm tra thành công.
- `dart run tool/check_supabase_connection.dart`: Auth và Data API kết nối được.
- `dart run tool/check_dung_an_backend.dart`: cả năm hàm cloud trả `OK`, nhận
  diện được và chặn caller chưa đăng nhập bằng `42501`.

## Kiểm tra lại sau migration cloud — 29/10/2026

Theo lựa chọn của người dùng, phạm vi lượt này là API và bộ kiểm thử hiện có;
không đăng nhập hay tạo dữ liệu thử trên cloud.

| Kiểm tra | Kết quả | Phạm vi bằng chứng |
| --- | --- | --- |
| Auth settings / Data API | PASS | Kết nối thật tới `bqoyfytmrtvjwrpshuhh`; key client được chấp nhận |
| 5 RPC catalog/chat | PASS | Chữ ký RPC đã có; anon bị từ chối; không còn lỗi thiếu hàm |
| Auth, sản phẩm, chat, router | 30 test PASS | Flutter/SDK qua HTTP fixture; không phải thao tác bằng JWT cloud thật |
| SQL bản chạy thủ công | 37 kiểm tra PASS | PostgreSQL nhúng với fixture Auth/Storage; giao dịch, quyền, retry, tồn kho, mốc đọc, phân trang |
| Lưu sản phẩm / nhắn tin bằng tài khoản thật | Chưa kiểm thử | Không có phiên đăng nhập ứng dụng; người dùng chọn chỉ kiểm tra API và test hiện có |

Lệnh kiểm tra lại chức năng:

```powershell
flutter test --no-pub test/features/auth test/features/catalog test/features/chat test/app/router/dung_an_navigation_test.dart --reporter expanded
node supabase/tests/run_dung_an_integration.mjs --manual
```

Kết quả test Flutter của lượt này: `build/dung_an_post_migration_tests.log`.
Không thay đổi quyền, schema hay bản ghi nghiệp vụ trên cloud trong lượt kiểm tra.
