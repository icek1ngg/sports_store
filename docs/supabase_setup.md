# Cấu hình Supabase cho base project

## Project dùng chung

- Project ref: `bqoyfytmrtvjwrpshuhh`.
- URL: `https://bqoyfytmrtvjwrpshuhh.supabase.co`.
- Cấu hình client: `config/supabase.json`, chứa `SUPABASE_URL` và `SUPABASE_PUBLISHABLE_KEY`.
- Dependencies trực tiếp được cố định trong `pubspec.yaml`; commit `pubspec.lock` để cả nhóm dùng cùng phiên bản đã giải quyết.

## Khởi tạo và dependency injection

`lib/main.dart` dùng `loadSupabaseConfig`: nếu có biến biên dịch Supabase thì đọc toàn bộ cấu hình từ `--dart-define-from-file`; nếu không có, đọc asset `config/supabase.json`. Cấu hình riêng thiếu/sai không được trộn với cấu hình mặc định. Sau khi kiểm tra URL/key, ứng dụng gọi `Supabase.initialize` trước khi chạy `ProviderScope`. Chỉ file cấu hình public dùng chung được đóng gói; không thêm file local hoặc secret key vào assets. Session được quản lý bởi Supabase Flutter SDK. Khởi tạo SDK không tự chứng minh kết nối mạng hay quyền truy cập vào bảng.

`lib/core/supabase/supabase_providers.dart` cung cấp `supabaseClientProvider` trỏ tới `Supabase.instance.client`. Repository thuộc tầng Data nhận client qua constructor; provider của repository lấy client bằng `ref.watch(supabaseClientProvider)`. ViewModel nhận repository qua Riverpod. Widget không gọi Supabase trực tiếp.

Chỉ khởi tạo một client cho ứng dụng. Router dùng chung nằm ở `lib/app/router/app_router.dart`; theme nằm ở `lib/app/theme/app_theme.dart`. Route `/` hiện là shell tạm, chưa phải màn hình nghiệp vụ. Khi triển khai Auth, phải thống nhất nguồn role do backend quản lý và invalidation cache khi đổi tài khoản.

Android manifest chính đã khai báo `android.permission.INTERNET` để truy cập backend khi build release.

## Phạm vi hiện tại

Base đã có cấu hình và SDK để kết nối project. Schema nền tảng, migration, RLS và Storage được mô tả tại [database.md](database.md); kết quả áp dụng cloud và kiểm tra database được ghi trong tài liệu đó. Màn hình Auth và Google OAuth dùng chung repository, còn tài khoản manager/shipper và RPC giao dịch nghiệp vụ thuộc các phần triển khai riêng.

Repository dùng tên bảng/cột theo migration và [api_contracts.md](api_contracts.md). Các thao tác tồn kho, đặt/hủy đơn, giao nhận, COD và trả/hoàn hàng cần RPC phía server; quyền client hiện chặn ghi trực tiếp các bảng này. Vai trò trong app lấy từ `profiles.role`, chỉ được quản trị qua công cụ server đáng tin cậy.

### Xác nhận email đăng ký trên Web

Ứng dụng gửi `emailRedirectTo` về `/auth/confirm-email` trên origin hiện tại.
Trong Supabase Dashboard → Authentication → URL Configuration, thêm URL
callback của môi trường chạy vào **Redirect URLs**, ví dụ
`http://localhost:57604/auth/confirm-email`. Khi phát triển với cổng động có thể
dùng `http://localhost:*/**`; production nên khai báo URL chính xác. Web hosting
cần phục vụ Flutter `index.html` cho đường dẫn `/auth/confirm-email`.
Xem [hướng dẫn redirect của Supabase](https://supabase.com/docs/guides/auth/redirect-urls).

`main.dart` chụp URL đầu vào trước khi khởi tạo SDK; Supabase Flutter 2.18.0
tự đổi code/token thành session và xóa tham số auth khi thành công. App chỉ
hiển thị **Xác nhận email thành công!** khi SDK đã tạo phiên còn hạn với
`emailConfirmedAt`. Không đổi code lần hai. Link cũ trả về `/` với query/fragment
auth cũng được nhận diện, tránh để hash router hiểu token hoặc lỗi thành route.
Kết quả chỉ giữ trong bộ nhớ của lần khởi động (`persistSession: false`);
mở callback trống hoặc truyền `success=true` không chứng minh đã xác nhận.

`otp_expired` hiển thị link hết hạn/đã sử dụng, không báo thành công giả. Người
dùng đã xác nhận có thể quay về đăng nhập; người chưa xác nhận cần email/link
còn hiệu lực. Không vô hiệu hóa yêu cầu xác nhận email. Chưa thay đổi cấu hình
dashboard hoặc gửi email thật trong bản sửa này.

### Google OAuth trên Flutter Web và Android

Google OAuth dùng Web OAuth client cho luồng trình duyệt. Trong Google Auth
Platform, đặt **Authorized JavaScript origins** là `http://localhost:57604`
cho Web local và domain Web production nếu có. Đặt **Authorized redirect URI**
là `https://bqoyfytmrtvjwrpshuhh.supabase.co/auth/v1/callback`; đây là callback
Google → Supabase, không phải deep link của app. Client ID và Client Secret chỉ
được lưu trong Authentication → Providers → Google của Supabase.

Trong Supabase Authentication → URL Configuration, dùng `http://localhost:57604`
cho Site URL khi phát triển Web (đổi sang domain production khi phát hành), và
thêm các Redirect URLs:

```text
http://localhost:57604/**
com.example.sportsstore://login-callback
https://<domain-production-của-bạn>/**
```

Flutter gọi `signInWithOAuth(OAuthProvider.google)`, dùng `Uri.base.origin` cho
Web và `com.example.sportsstore://login-callback` cho Android. Scheme này không
dùng dấu gạch dưới vì URI scheme không cho phép ký tự đó. Android manifest
đăng ký scheme/host này để mở lại app. OAuth qua trình duyệt không cần Android
OAuth client riêng; Android client ID và SHA-1 chỉ cần nếu thay bằng Google
Sign-In native lấy ID token. Application ID hiện tại còn là
`com.example.sports_store` (giá trị mẫu), cần đổi sang ID chính thức trước khi
phát hành; scheme deep link phải nhất quán giữa Supabase, code và manifest.

Activity đặt `flutter_deeplinking_enabled=false` để `app_links` của Supabase
nhận callback, tránh Flutter Router xử lý cùng URI lần nữa. Theo hướng dẫn
[Flutter app links](https://docs.flutter.dev/cookbook/navigation/set-up-app-links)
và [Supabase OAuth](https://supabase.com/docs/reference/dart/auth-signinwithoauth).
Khi callback Google có lỗi, app mở `/login` với thông báo cố định, không hiển
thị nội dung `error_description` từ provider hoặc coi đó là xác nhận email.
Callback thành công vẫn do SDK trao đổi PKCE và session/profile server quyết
định điều hướng. Để giữ đúng origin local đã allowlist, có thể chạy
`flutter run -d chrome --web-port=57604`.

Kiểm tra bằng HTTP/SDK/widget fixture không thay thế nghiệm thu Google consent
và deep link trên thiết bị thật. Chưa xác minh cấu hình provider/redirect URLs
trên Supabase cloud trong lượt rà soát này.

Rà soát 09/11/2026: 145 test Auth/Catalog/Chat/router và shell đăng xuất đã
PASS bằng fixture. Bao phủ Google PKCE không bị nhận nhầm xác nhận email,
callback lỗi quay về login, không lộ diagnostics, xác nhận email hết hạn,
điều hướng theo role, đổi tài khoản/đăng xuất, sản phẩm và lịch sử chat.

## Kiểm tra kết nối

Từ thư mục gốc:

```powershell
dart run tool/check_supabase_connection.dart
```

Kết quả thành công có HTTP 200 ở `/auth/v1/settings`. Data API được gọi qua `/rest/v1/__connection_probe__?select=*&limit=0`: HTTP 404 với mã `PGRST205` (bảng probe không tồn tại) chứng minh key đã được chấp nhận và request tới PostgREST. Nếu bảng đó tồn tại, script chỉ chấp nhận HTTP 200 với danh sách rỗng. Không cần tạo bảng probe. Endpoint OpenAPI gốc `/rest/v1/` không dành cho publishable key và không được dùng trong phép kiểm tra này.

Script chỉ in trạng thái, không in key, token, dữ liệu người dùng hay nội dung response; không đọc bản ghi hoặc ghi database. Với cấu hình riêng:

```powershell
dart run tool/check_supabase_connection.dart config/supabase.local.json
```

Nếu ứng dụng báo lỗi khởi động, kiểm tra hai trường cấu hình và tham số `--dart-define-from-file`. Nếu script kết nối thất bại, kiểm tra mạng, trạng thái project và publishable key đang bật trong dashboard; sau đó chạy lại script.

## Kết quả xác minh base

Ngày 06/10/2026: `flutter pub get`, `flutter analyze`, 7 bài test cấu hình và build Web với `config/supabase.json` đã đạt. Probe client thực tế nhận Auth HTTP 200 và Data API HTTP 404/PGRST205 như mong đợi. Truy vấn chỉ đọc `select current_database(), current_timestamp` qua connector Supabase cũng thành công; đây là kiểm tra quản trị riêng, không xác nhận quyền của client với bảng nghiệp vụ.

Chưa xác minh build Android: `flutter doctor` báo máy thiếu Android SDK command-line tools và chưa xác định được trạng thái license. Cần hoàn thiện Android toolchain trước khi kiểm tra APK.

## Tài liệu chính thức

- [Khởi tạo Supabase Flutter](https://supabase.com/docs/reference/dart/initializing).
- [API keys và publishable keys](https://supabase.com/docs/guides/api/api-keys).
- [Riverpod providers](https://riverpod.dev/docs/concepts2/providers).
