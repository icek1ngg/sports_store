# Cấu hình Supabase cho base project

## Project dùng chung

- Project ref: `bqoyfytmrtvjwrpshuhh`.
- URL: `https://bqoyfytmrtvjwrpshuhh.supabase.co`.
- Cấu hình client: `config/supabase.json`, chứa `SUPABASE_URL` và `SUPABASE_PUBLISHABLE_KEY`.
- Dependencies trực tiếp được cố định trong `pubspec.yaml`; commit `pubspec.lock` để cả nhóm dùng cùng phiên bản đã giải quyết.

## Khởi tạo và dependency injection

`lib/main.dart` đọc biến biên dịch từ `--dart-define-from-file`, kiểm tra URL/key, rồi gọi `Supabase.initialize` trước khi chạy `ProviderScope`. Session được quản lý bởi Supabase Flutter SDK. Khởi tạo SDK không tự chứng minh kết nối mạng hay quyền truy cập vào bảng.

`lib/core/supabase/supabase_providers.dart` cung cấp `supabaseClientProvider` trỏ tới `Supabase.instance.client`. Repository thuộc tầng Data nhận client qua constructor; provider của repository lấy client bằng `ref.watch(supabaseClientProvider)`. ViewModel nhận repository qua Riverpod. Widget không gọi Supabase trực tiếp.

Chỉ khởi tạo một client cho ứng dụng. Router dùng chung nằm ở `lib/app/router/app_router.dart`; theme nằm ở `lib/app/theme/app_theme.dart`. Route `/` hiện là shell tạm, chưa phải màn hình nghiệp vụ. Khi triển khai Auth, phải thống nhất nguồn role do backend quản lý và invalidation cache khi đổi tài khoản.

Android manifest chính đã khai báo `android.permission.INTERNET` để truy cập backend khi build release.

## Phạm vi hiện tại

Base đã có cấu hình và SDK để kết nối project. Schema nền tảng, migration, RLS và Storage được mô tả tại [database.md](database.md); kết quả áp dụng cloud và kiểm tra database được ghi trong tài liệu đó. Chưa có màn hình đăng nhập, tài khoản manager/shipper hoặc RPC giao dịch nghiệp vụ.

Repository dùng tên bảng/cột theo migration và [api_contracts.md](api_contracts.md). Các thao tác tồn kho, đặt/hủy đơn, giao nhận, COD và trả/hoàn hàng cần RPC phía server; quyền client hiện chặn ghi trực tiếp các bảng này. Vai trò trong app lấy từ `profiles.role`, chỉ được quản trị qua công cụ server đáng tin cậy.

Chưa cấu hình OAuth/magic link hoặc redirect đăng nhập trên dashboard. Khi triển khai các luồng này, cần thiết lập callback theo nền tảng và kiểm tra session thực tế.

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
