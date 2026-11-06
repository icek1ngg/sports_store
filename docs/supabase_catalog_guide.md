# Dùng Supabase để chạy MH04, MH05 và MH06

> Cập nhật 27/10/2026: MH16 và RPC đặt hàng đã triển khai. Trạng thái, APK và
> kết quả thử bốn màn hình xem [bàn giao hiện hành](van_duc_completion.md).
> Các số đếm dữ liệu và nhận xét ngày 24–25/10 bên dưới là lịch sử kiểm tra.

Cập nhật 25/10/2026: đã kết nối được connector quản trị đúng project và thêm
3 sản phẩm/5 biến thể DEMO trên cloud. Tài khoản Auth và nghiệm thu live còn
chờ hoàn tất; xem [hướng dẫn nghiệm thu mới](van_duc_mh04_mh06_acceptance.md).
Các kết quả và giới hạn ngày 24/10 bên dưới được giữ làm lịch sử kiểm tra.

Hướng dẫn dành cho Văn Đức, ngày 24/10/2026. Ứng dụng truy vấn Supabase thật;
nếu database rỗng, giao diện báo rỗng. Dữ liệu có nhãn `[DEMO]` chỉ xuất hiện
nếu bạn chủ động chạy file seed mẫu vào database.

Giao diện dùng tiếng Việt, kể cả nút/menu mặc định của Flutter khi máy đang
đặt ngôn ngữ khác. Trang chạy thử có tiêu đề “Chạy thử cửa hàng”; tên ứng dụng
trên web và Android là “Sports Store”. Cấu hình ngôn ngữ dùng chung tại
`lib/app/localization/app_localization.dart`, theo
[hướng dẫn Flutter](https://docs.flutter.dev/ui/internationalization).
Sau thay đổi ngôn ngữ, toàn bộ 117 kiểm thử đạt và phân tích mã không có lỗi.

**Trạng thái xác minh 24/10/2026:** cấu hình hiện tại gọi được Auth (HTTP 200)
và Data API (probe bảng không tồn tại trả HTTP 404/PGRST205). Việc này xác nhận
URL/public key, chưa xác nhận đăng nhập customer và đọc catalog. Connector
quản trị đang dùng tài khoản không có quyền project `bqoyfytmrtvjwrpshuhh`;
cần kết nối lại tài khoản có project PRM trước khi kiểm tra dữ liệu cloud.
Chưa seed hoặc sửa schema/RLS trên cloud trong thay đổi này.

## 1. Mở đúng project

Mở [Supabase Dashboard](https://supabase.com/dashboard/project/bqoyfytmrtvjwrpshuhh).
Đăng nhập bằng tài khoản được mời vào project của nhóm. Nếu không thấy project,
nhờ người quản trị mời tài khoản Supabase của bạn vào organization/project.
Tài khoản Dashboard quản trị khác với tài khoản khách mua hàng của ứng dụng.

Project ref dùng chung là `bqoyfytmrtvjwrpshuhh`. Cấu hình Flutter đã có tại
`config/supabase.json`; không cần tạo project mới hoặc đổi key để bắt đầu.
Flutter chỉ dùng publishable key; quyền đọc dữ liệu do phiên người dùng và
RLS quyết định. Không tắt RLS để xử lý lỗi đăng nhập.

## 2. Nhận biết các mục cần dùng

| Mục trong Dashboard | Dùng để làm gì trong bài này |
| --- | --- |
| Table Editor | Xem bảng `categories`, `products`, `product_variants`, `profiles` |
| Authentication → Users | Tạo tài khoản khách để đăng nhập công cụ chạy thử |
| Storage → product-images | Upload ảnh sản phẩm; bucket giữ private |
| SQL Editor | Chạy truy vấn kiểm tra và file seed mẫu khi cần |

Ở Table Editor, chọn schema `public`. Sản phẩm nằm ở `products`, còn giá và
số lượng nằm ở `product_variants`. Mỗi biến thể có `product_id` trỏ tới sản phẩm.
`available_quantity = on_hand - reserved` là cột tự tính; không nhập trực tiếp.
Ba danh mục chuẩn là `apparel`, `shoes`, `equipment`.

## 3. Tạo một tài khoản customer để thử

1. Vào **Authentication → Users**, chọn **Add user / Create new user**
   (tên nút có thể thay đổi theo giao diện Dashboard).
2. Nhập email bạn quản lý và mật khẩu riêng. Với tài khoản thử do quản trị tạo,
   chọn xác nhận email nếu Dashboard cung cấp lựa chọn đó; nếu không, hoàn tất
   bước xác nhận email trước khi đăng nhập.
3. Mở Table Editor → `profiles`, tìm dòng có `id` bằng User UID vừa tạo.
   Trigger của dự án phải tạo dòng này với `role = customer`.
4. Giữ role `customer` cho tài khoản thử catalog. Không cần sửa thành manager.
   Nếu thiếu profile, báo người quản trị kiểm tra migration/trigger trước.

Nhập email và mật khẩu trực tiếp trong công cụ chạy thử; không ghi mật khẩu vào
Git, file cấu hình, ảnh chụp hoặc chat. Công cụ không tạo tài khoản tự động.

## 4. Có dữ liệu để xem

Trước hết xem `products` và `product_variants` đã có dữ liệu dùng chung chưa.
Nếu đã có, dùng dữ liệu đó. Catalog chỉ hiện sản phẩm/danh mục đang hoạt động;
các biến thể đang hoạt động quyết định giá và tồn hiển thị.

Nếu chưa có dữ liệu, mở `supabase/seed_catalog_demo.sql`, đọc nội dung, sau đó
dán nguyên file vào **SQL Editor → New query → Run** trên đúng project thử/nhóm.
File thêm **3 sản phẩm và 5 biến thể có nhãn DEMO**, kèm lịch sử khởi tạo tồn.
Chạy lại không đặt lại tồn, giá, số lượng giữ hoặc ảnh của bản ghi đã tồn tại.
File không tạo tài khoản, đơn hàng, nhiệm vụ, hoặc thay đổi schema/RLS.

Đây là dữ liệu lưu thật trong Supabase nhưng là dữ liệu mẫu phục vụ học/demo.
File không tự chạy khi khởi động ứng dụng. SQL Editor có quyền quản trị, nên
kết quả nhìn thấy ở đó chưa chứng minh tài khoản customer đọc được trong app.

Kiểm tra chỉ đọc:

```sql
select p.id, p.name, p.is_active, c.name as category,
       v.sku, v.label, v.price_vnd, v.available_quantity
from public.products p
join public.categories c on c.id = p.category_id
left join public.product_variants v on v.product_id = p.id
order by p.name, v.sku;
```

## 5. Thêm ảnh sản phẩm

1. Mở **Storage → product-images**. Bucket hiện có phải giữ **private**.
2. Upload ảnh bạn có quyền sử dụng, ví dụ `catalog/daily-run.jpg`.
3. Trong Table Editor → `products`, đặt `image_path` của sản phẩm thành
   `catalog/daily-run.jpg`, đúng tên và chữ hoa/thường của file.
4. Lưu rồi làm mới màn sản phẩm. App xin signed URL bằng phiên đang đăng nhập.

`image_path` chỉ chứa đường dẫn bên trong bucket: không thêm `product-images/`,
không dùng URL public hay dán signed URL sắp hết hạn. Có thể để NULL để hiện
khung chưa có ảnh. Ảnh lỗi không biến toàn bộ danh mục thành dữ liệu giả.
Khi thử lại ảnh hoặc tải lại màn hình, ứng dụng yêu cầu signed URL mới.

## 6. Chạy trên máy

Từ thư mục gốc của dự án:

```powershell
flutter pub get
dart run tool/check_supabase_connection.dart
flutter run -d chrome -t tool/catalog_live/main.dart --dart-define-from-file=config/supabase.json
```

Trang đầu ghi **Chạy thử cửa hàng**. Đăng nhập bằng tài khoản
customer ở bước 3. Công cụ dùng cùng client, repository, guard và router của app;
không bỏ qua RLS. Phiên chỉ lưu trong bộ nhớ, tải lại trình duyệt cần đăng nhập
lại. MH01 chính thức vẫn do An phụ trách; công cụ nằm trong `tool/`.

Nếu dùng Android, chạy `flutter devices` và thay `chrome` bằng device ID.
Ví dụ với máy ảo đang mở:

```powershell
flutter run -d emulator-5554 -t tool/catalog_live/main.dart --dart-define-from-file=config/supabase.json
```

`android/gradle.properties` tắt biên dịch tăng dần của Kotlin để tránh lỗi cache
`this and base files have different roots` trên Windows khi thư viện và dự án
ở hai ổ đĩa khác nhau. Cách này có thể làm biên dịch Kotlin chậm hơn; không đổi
nghiệp vụ hay phiên bản thư viện. Tham chiếu
[tùy chọn biên dịch Kotlin](https://kotlinlang.org/docs/gradle-compilation-and-caches.html).

Đã xác nhận ngày 24/10/2026: biên dịch APK debug thành công, cài và khởi chạy
trên `emulator-5554` (Android 13, API 33, x86_64). Nhật ký báo Flutter đã chạy
và Supabase SDK khởi tạo xong. Chưa đăng nhập/thử giỏ bằng tài khoản thật và
chưa xác minh trực quan vì công cụ quan sát chưa được cấp quyền với máy ảo.
Main production vẫn chạy bằng `flutter run --dart-define-from-file=config/supabase.json`;
khi Auth chưa tích hợp, dùng entry point công cụ ở trên để kiểm tra tài khoản thật.

## 7. Thử luồng MH04 → MH05 → MH06

1. MH04: xem lưới sản phẩm, nhập từ khóa và bấm tìm/Enter, lọc danh mục.
2. Mở sản phẩm: URL mang UUID thật sang `/customer/products/:productId`.
3. MH05: đổi biến thể để thấy giá/tồn thay đổi; số lượng nằm trong tồn khả dụng.
4. Thử biến thể hết hàng, tên tìm kiếm không có kết quả, và làm mới dữ liệu.
5. MH05: thêm hàng, chỉ nhận thông báo thành công sau khi ghi/đọc lại giỏ được xác nhận.
6. Mở biểu tượng giỏ: `/customer/cart`. Tăng/giảm số lượng, xóa, làm mới;
   đối chiếu `cart_items` của user hiện tại trong Dashboard. Cùng biến thể gộp
   số lượng; giỏ không giữ tồn và không ghi thay đổi giá.
7. Thử hàng ngừng bán/hết tồn: dòng giỏ có cảnh báo và còn xóa được. Khi tồn
   giảm dưới số lượng, nút giảm đưa về lượng hiện còn; hết tồn thì dùng nút xóa.
8. Lỗi kết nối trong lúc ghi không báo thành công; retry thao tác đang chờ
   dùng lại target số lượng. Nút đặt hàng bị khóa vì MH16 chưa được tích hợp.
9. Trở về trang công cụ để đăng xuất/đổi tài khoản. Giỏ và dữ liệu phiên trước
   phải biến mất; tài khoản sau chỉ thấy giỏ của chính mình.

Mốc MH06 nối thêm/sửa/xóa giỏ với Supabase adapter. Chưa có thao tác đặt
hàng hoặc giữ tồn; cần nghiệm thu CRUD bằng tài khoản thật theo các bước trên.
Giá/tồn khi xem chỉ là hiện tại; MH16 sẽ kiểm tra lại ở server lúc đặt đơn.

## 8. Xử lý lỗi thường gặp

| Hiện tượng | Cách kiểm tra |
| --- | --- |
| Không thấy project | Đúng tài khoản Dashboard và lời mời của nhóm chưa? |
| Email/mật khẩu không đúng | Tài khoản phải ở Authentication của đúng project, không dùng mật khẩu Dashboard |
| Email chưa xác nhận | Kiểm tra trạng thái email của user trong Authentication |
| Không có quyền | `profiles.id` khớp UID và `role = customer`; RLS vẫn bật |
| Danh mục rỗng | Có sản phẩm active trong danh mục active chưa? Bộ lọc/từ khóa có phù hợp không? |
| Giá chưa có / hết hàng | Kiểm tra biến thể active, `price_vnd` và `available_quantity` |
| Ảnh không tải | Kiểm tra bucket private, `image_path`, file tồn tại và phiên còn hạn |
| Không thể kết nối | Chạy lại script kiểm tra; kiểm tra mạng và project có bị pause không |

## Kết quả kiểm tra MH06 ngày 24/10/2026

- `dart format` đã chạy cho Dart thay đổi; `flutter analyze --no-pub`: không có issue.
- `flutter test --no-pub`: **115 test đạt**, gồm toàn bộ regression catalog,
  delivery/COD, route guard, repository/ViewModel giỏ, retry sau mất response,
  account switch và UI 320px/text scale 2 (kể cả ảnh lỗi).
- Build web entry point `tool/catalog_live/main.dart` với cấu hình project đã
  thành công (`build/web`), gồm Wasm dry run. Compiler còn in cảnh báo font
  `CupertinoIcons`; analyzer không có issue.
- Luồng MH05 thêm → MH06 sửa/xóa/refresh được kiểm tra qua ViewModel và
  Supabase repository thật với HTTP transport fixture. Đây không phải CRUD cloud.
- PostgreSQL 17.10 cô lập: bốn migration, `database_security.sql`,
  `delivery_read_security.sql`, seed lặp và bảo toàn reservation đều đạt.
  Auth/Storage là SQL stub; server fixture đã dừng sau kiểm tra.
- Không thêm package/migration và không ghi lên database cloud. Chưa nghiệm
  thu đăng nhập/CRUD giỏ/ảnh bằng tài khoản customer thật trong lượt MH06.
- Review độc lập đã hoàn tất; các lỗi pending retry, input không hợp lệ,
  thao tác khi hết tồn và thumbnail nhỏ đã được sửa kèm regression tests.

## Kết quả catalog trước MH06 (lịch sử)

- `dart format` cho các file thay đổi; `flutter analyze --no-pub`: không có lỗi/cảnh báo.
- `flutter test --no-pub`: 82 test đạt, gồm catalog, router và regression giao hàng/COD.
- Web entry point `tool/catalog_live/main.dart` đã build thành công.
- PostgreSQL 17.10 cô lập: bốn migration, `database_security.sql`,
  `delivery_read_security.sql` và seed chạy lặp đều đạt. Đây là fixture cục bộ.
- Chưa kiểm tra đăng nhập customer/đọc catalog/ảnh trên cloud vì connector
  chưa có quyền vào project PRM. Chưa gửi code lên Git và chưa deploy database.

## Tài liệu Supabase chính thức

- [Quản lý bảng và dữ liệu](https://supabase.com/docs/guides/database/tables).
- [Quản lý người dùng](https://supabase.com/docs/guides/auth/managing-user-data).
- [Đăng nhập bằng mật khẩu trong Flutter](https://supabase.com/docs/reference/dart/auth-signinwithpassword).
- [Signed URL cho ảnh private](https://supabase.com/docs/reference/dart/storage-from-createsignedurl).
