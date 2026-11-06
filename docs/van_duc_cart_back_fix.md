# Sửa quay lại và lỗi dữ liệu giỏ hàng — 02/11/2026

## Lỗi và bản sửa

Sau khi mở giỏ bằng `push`, nút quay lại mặc định dùng
`Navigator.maybePop()`. Observer kiểm tra quyền gọi `router.refresh()` khi
route information vẫn chứa stack trước khi pop, khiến giỏ được dựng trở lại.
Trong go_router 18.0.2, `GoRouter.pop()` tự đồng bộ stack nhưng nút mặc định
không đi qua phương thức này.

Router chung hiện dùng `router.restore(router.routerDelegate.currentConfiguration)`
trong callback sau pop. Vẫn kiểm tra lại quyền của trang vừa hiện; không đổi
route, mô hình quyền, dữ liệu giỏ hoặc hành vi URL chung. Đóng dialog không
kích hoạt kiểm tra pop của trang.

## Kiểm chứng

`test/app/router/customer_cart_back_test.dart` dùng hồ sơ customer đầy đủ,
router, màn hình và repository thật cùng HTTP fixture cô lập. Hai ca AppBar
Back thất bại trước bản sửa và đạt sau bản sửa:

- Giỏ → chi tiết → danh sách sau khi cập nhật số lượng.
- Giỏ → danh sách khi phản hồi cập nhật không xác nhận đúng số lượng;
  nút thử lại vẫn dùng được sau khi request kết thúc.

Ca thứ ba mô phỏng khôi phục lịch sử trình duyệt qua `RouteInformation` khi
giỏ có lỗi. Đây là kiểm thử mô phỏng, không phải thao tác trực tiếp trên Chrome
với tài khoản cloud.

Bộ 30 ca điều hướng liên quan đạt, gồm ba ca mới, refresh phiên customer,
checkout, delivery, COD và bắt đầu giao hàng. `flutter analyze --no-pub`
không có vấn đề. Log trong `build/van_duc_cart_back_fix.log` và
`build/van_duc_cart_back_analyze.log`, được Git bỏ qua.

Sau bản sửa, `flutter test --no-pub --reporter expanded test` đạt 1.635 ca,
bỏ qua 4 ca; log `build/van_duc_cart_back_full_tests.log`. Định dạng ba file
Dart thay đổi và `git diff --check` đều đạt. Rà soát độc lập không phát hiện
lỗi mới trong bản sửa. Không commit hoặc push trong lượt này.

## Lỗi dữ liệu trong ảnh — đã xác định và sửa

Sau khi người dùng cung cấp ba tài khoản thử, nghiệm thu qua Supabase Auth
và repository Flutter thật tái hiện `CartFailure(invalidData)` trên giỏ có
hai dòng. HTTP trả `order=variant_id.desc.nullslast`, trong khi con trỏ dùng
`gt` và kiểm tra UUID tăng dần. `postgrest` 2.9.1 mặc định `ascending=false`.

Repository hiện chỉ định `.order('variant_id', ascending: true)`. Không đổi
dữ liệu giỏ hoặc RLS. Đã bỏ log chẩn đoán tạm sau khi tìm được nguyên nhân.
Hai ca hồi quy với giới hạn API 1/2 dòng kiểm tra cả bỏ sót dòng và lỗi cursor.
Bộ giỏ/router liên quan đạt 16 ca trong `build/van_duc_cart_cursor_regression.log`.

Truy vấn giỏ diện rộng ở lượt đầu bị xét duyệt từ chối và không thực hiện.
Lượt nghiệm thu sau dùng JWT của đúng ba tài khoản thử được cung cấp, chỉ đọc
giỏ customer đã chỉ định; không dùng service-role hoặc quyền quản trị Auth.

## Nghiệm thu có dữ liệu thật

`test/live/van_duc_supabase_acceptance_test.dart` đạt 5 ca:

- Customer đăng nhập, kiểm tra role máy chủ, đọc danh mục/chi tiết/giỏ,
  ghi lại cùng số lượng và xác nhận kết quả.
- Manager và shipper đăng nhập đúng role; repository chặn thao tác giỏ,
  RLS trả rỗng khi đọc giỏ của customer thử đã chỉ định.
- Server từ chối tọa độ ngoài Hà Nội; tra mã yêu cầu xác nhận chưa tạo đơn.
- Widget thật mở MH04 → MH05 → MH06 → MH16, chọn vị trí và quay lại ba lần.

Log đạt: `build/van_duc_supabase_acceptance_pass.log`. Đây là widget runner
trên máy tính với API thật. Pending store được cô lập trong bộ nhớ và tắt
tile bản đồ; không xác nhận ảnh Storage, bản đồ tile hoặc kho mã hóa trên
Chrome. Không bấm đặt đơn hợp lệ, không tạo đơn/reservation/notification thử.
Nhánh hiện chưa có adapter hủy đơn production để dọn một đơn thử trọn luồng.

Chạy lại bằng mật khẩu nhập tại runtime, không ghi vào source/define/log:

```powershell
$securePassword = Read-Host 'Mật khẩu của ba tài khoản thử' -AsSecureString
$env:SPORTS_ACCEPTANCE_PASSWORD = [System.Net.NetworkCredential]::new('', $securePassword).Password
$env:SPORTS_LIVE_ACCEPTANCE = '1'
$env:SPORTS_TEST_CUSTOMER_ID = Read-Host 'UUID của customer thử'
try {
    flutter test --no-pub --reporter expanded test/live/van_duc_supabase_acceptance_test.dart
} finally {
    Remove-Item Env:SPORTS_ACCEPTANCE_PASSWORD, Env:SPORTS_LIVE_ACCEPTANCE, Env:SPORTS_TEST_CUSTOMER_ID
}
```

Mặc định năm ca live được bỏ qua khi không bật cờ và không cung cấp mật khẩu.
Client chỉ dùng publishable key và kiểm tra đúng hostname project. Mỗi phiên
test đăng xuất local rồi giải phóng client/transport. Transport test dùng
HTTPS xác thực bình thường, không giữ HTTP keep-alive trong fake clock.

Helper Node dùng chung đã sửa phản hồi 204/205/304 thành body `null`; trước đó
logout 204 gây lỗi constructor. Sáu ca `live_https_transport_test.mjs` đạt.

Kết quả cuối: `flutter analyze --no-pub` không có vấn đề; toàn bộ test mặc định
đạt 1.637 ca, bỏ qua 9 ca (gồm 5 ca live opt-in), log
`build/van_duc_live_final_full_tests.log`. Định dạng và `git diff --check` đạt.

Web đã hot restart bản sửa tại `http://127.0.0.1:7357`, SDK khởi tạo xong.
Hai lần chạy suite Chrome riêng trước đó bị kẹt khi tải và đã dừng; không tính
chúng là kiểm thử đạt.

## Workspace thống nhất trên máy

Theo yêu cầu mới nhất của người dùng, thư mục duy nhất để chỉnh sửa, kiểm thử,
chạy web và thao tác Git là **`E:\sports_store`**. Project/chat Codex đã ở đây;
GitHub Desktop được thêm/chọn bằng đúng đường dẫn này. Nhánh hiện tại là `main`,
remote `origin` giữ nguyên.

Đã đối chiếu đủ 10 file thay đổi của `sports_storea` bằng SHA-256: tất cả đã
có trong workspace chính và khớp nội dung. `main` được fast-forward từ
`14053c8` lên merge commit `7861a8f` của bản đối chiếu; hai commit có cùng tree
nên không đổi nội dung nguồn. 203 file đang thay đổi, gồm cả ảnh nghiệm thu
MH09 có sẵn, được kiểm tra hash và giữ nguyên trước/sau fast-forward.

Đã gỡ chỉ dẫn cục bộ từng chuyển thao tác sang `sports_storea`. Bản
`E:\sports_storea` được giữ để đối chiếu, có chỉ dẫn cục bộ chuyển người làm
việc về workspace chính; không tiếp tục đồng bộ hai chiều. Không xóa hai repo,
không tạo commit mới hoặc push trong bước thống nhất này.

Bản sao diff, chỉ dẫn cũ và manifest hash trước thống nhất nằm trong
`build/workspace_unify_20261102_194418/` của workspace chính. Bản sao trước lần
đồng bộ ban đầu vẫn ở `build/git_sync_backup_20261102_191527/`.

Sau thống nhất, đã kiểm tra lại ngay trong `E:\sports_store`: phân tích mã sạch,
115 test danh mục/giỏ/checkout/điều hướng và 6 test HTTP Node đều đạt. Log tại
`build/workspace_unified_analyze.log` và `build/workspace_unified_tests.log`.
`git diff --check` đạt; `main` khớp `origin/main` sau fetch, các thay đổi vẫn
chưa commit. GitHub Desktop đã hiển thị các file thay đổi của workspace chính.

Đã dừng phiên web từ bản đối chiếu và khởi động lại từ workspace chính tại
`http://127.0.0.1:7357`: HTTP 200, Supabase SDK khởi tạo thành công. Project/chat
Codex tiếp tục có thư mục làm việc mặc định `E:\sports_store`.
