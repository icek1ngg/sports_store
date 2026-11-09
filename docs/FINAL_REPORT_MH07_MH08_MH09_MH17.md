# BÁO CÁO TỔNG KẾT PRM393 — MH07, MH08, MH09, MH17

**Dự án:** Sports Store
**Phần phụ trách:** Lê Gia Bảo — Orders và Notifications
**Ứng dụng chính thức:** Flutter trên Android Emulator, sử dụng Supabase
**Entrypoint:** `lib/main.dart`
**Cập nhật cấu trúc:** 09/11/2026

## 1. Tổng quan dự án

Sports Store là ứng dụng môn PRM393 phục vụ mua sắm sản phẩm thể thao, quản lý đơn hàng và giao nhận tại một cửa hàng. Source của nhóm có 20 màn nghiệp vụ, ba vai trò Customer, Manager và Shipper, dùng chung Auth, router, models và repository contracts.

Ứng dụng chính thức bắt đầu từ Supabase Login, xác định vai trò qua hồ sơ server và mở navigation tương ứng. Không có local accounts, thanh đổi vai trò, app composition dùng RAM hoặc cơ chế thay backend lỗi bằng fixture. Các màn hình đã duyệt được tái sử dụng, không thay bằng UI minh họa.

Báo cáo tập trung vào MH07/MH08/MH09/MH17. Có source adapter hoặc migration không đồng nghĩa backend đã được deploy hoặc operation đã được chạy thành công trên Cloud. Automated transport fixtures cũng không phải bằng chứng Cloud read/write.

## 2. Phạm vi bốn màn hình

| Màn | Chức năng | Vai trò | UI chính |
|---|---|---|---|
| MH07 | Danh sách, chi tiết và hủy đơn của mình | Customer | `CustomerOrdersPage`, `CustomerOrderDetailsPage` |
| MH08 | Danh sách đơn, tìm kiếm, bộ lọc, KPI, actions | Manager | `ManagerOrdersPage` |
| MH09 | Chi tiết, timeline, projections và actions | Manager | `ManagerOrderDetailsPage` |
| MH17 | Inbox, unread count và markRead | Theo recipient của phiên | `NotificationsScreen` |

Source gồm domain models, DTO/adapters, repository contracts, Riverpod reads/actions, UI và route/session integration. Business IDs đi qua route/callback. Loading, empty, error và dependency unavailable được phân biệt rõ; thiếu backend không được coi là thành công.

## 3. Kiến trúc Flutter

Ứng dụng dùng feature-first MVVM, Riverpod và go_router. View hiển thị state và chuyển thao tác đến ViewModel/coordinator; repository xử lý data mapping và Supabase transport. Domain không phụ thuộc Flutter widgets hoặc Supabase SDK.

- `lib/main.dart`: khởi tạo SDK, giữ email-confirmation callback và production composition.
- `lib/app/router`: canonical application router, route guards và session boundary.
- `lib/app/shells`: navigation theo role; không tạo MaterialApp hoặc Auth riêng trong pages.
- `lib/app/integration`: binding Orders/Notifications và lifecycle theo Auth hiện có.
- `lib/core/state`: session generation, epoch cache và snapshots.
- `lib/features/orders`: order contracts, Supabase adapter, receipts/recovery và UI.
- `lib/features/notifications`: recipient-scoped inbox, markRead và target authorization.

`SupabaseOrderRepository` và `SupabaseNotificationRepository` là data adapters của runtime chính. Những repositories của Catalog, Cart, Checkout, Chat, Deliveries, COD và Returns tiếp tục theo các provider/contracts của nhóm. Không tạo repository Auth thứ hai.

## 4. MH07 — Đơn hàng của tôi

Customer truy cập `/customer/orders` qua tab Đơn hàng. Danh sách và chi tiết được đọc qua aggregate Orders, với ownership được kiểm tra theo authenticated identity. Biết UUID không thay thế quyền truy cập.

Danh sách có search, status filters, refresh và cursor pagination. Query/filter tạo namespace phù hợp, không ghép cursor cũ vào truy vấn mới. Cards hiển thị snapshot sản phẩm/biến thể, số lượng, trạng thái và tổng COD theo canonical data. Giá trị VND dùng số nguyên.

Customer details dùng `/customer/orders/:orderId`; Back trở về danh sách trong cùng hệ thống navigation. Links Returns chỉ khả dụng theo capabilities và quyền hiện tại. Các caller dùng detail sheet cũ vẫn phải giữ session boundary.

Customer cancel chỉ được gửi khi capability cho phép. Command có stable request ID, kết quả phải là canonical server acknowledgement. Không raw UPDATE `orders.status`, không sửa trạng thái RAM để che backend lỗi. Khi outcome chưa rõ, client giữ pending/recovery flow thay vì báo thành công hoặc gửi request mới tùy ý.

## 5. MH08 — Quản lý đơn hàng

Manager vào `/manager/orders`. Customer/Shipper không được cấp Manager UI chỉ bằng URL hoặc metadata tự chỉnh. UI guards bổ sung trải nghiệm; backend vẫn phải kiểm quyền.

List/search/filter/KPI/pagination đọc canonical aggregate. Counts không suy ra bằng số cards trong trang đầu. Detail callback truyền đúng UUID sang MH09; Back/refresh phải đọc lại thay đổi hợp lệ mà không tạo shell hoặc Auth session mới.

Confirm/Reject chỉ enabled khi capabilities hợp lệ. Reject yêu cầu reason. Sau ACK, UI invalidates/reloads list/detail; không giữ optimistic business status nếu server chưa xác nhận. RPC thiếu, receipt không hợp lệ hoặc session đổi phải có failure/unavailable tương ứng.

## 6. MH09 — Chi tiết đơn hàng

Route `/manager/orders/:orderId` nhận order UUID. Nội dung gồm buyer/recipient, địa chỉ, items, snapshot prices, delivery fee, total COD, order state, timeline và các projections hiện có.

Order, Delivery, COD và Return states được tách riêng. Thiếu Delivery/COD/Returns projection hiển thị thiếu dữ liệu; không fabricate lifecycle hoặc đổi tổng tiền phải thu thành tiền đã thu. Lịch sử chưa đầy đủ giữ semantics `historyComplete=false`.

Các operations trong contract gồm Confirm, Reject và Manager Cancel. Manager Cancel không phải quyền hủy mọi đơn; source B2 giới hạn NEVER assigned khi cần chứng minh chưa có dispatch/custody. Client chỉ gọi canonical RPC, xác thực receipt và đọc lại. Inventory reservation/release, COD và delivery invariants thuộc transaction backend; không tự mô phỏng bằng nhiều Flutter updates.

Receipt lookup phục vụ recovery khi timeout/unknown outcome. Same-key replay phải giữ kết quả canonical; cùng request ID khác fingerprint bị từ chối. OP-O04–08 chỉ được gọi thành công khi deployed contract, grants, quyền identity và QA scope thực tế đều đáp ứng.

## 7. MH17 — Thông báo

MH17 mở qua chuông hoặc menu Tài khoản. Recipient được suy từ authenticated session, không nhận tùy ý một user ID từ màn hình. Customer/Manager/Shipper chỉ được đọc inbox thuộc quyền của mình.

Màn có All/Unread, refresh, pagination và exact unread count. Badge dùng count của repository, không suy từ trang đầu. Inbox rỗng là read result hợp lệ nhưng không chứng minh pagination hoặc markRead đã được thực thi.

MarkRead chỉ chấp nhận canonical row có ID/recipient/timestamp phù hợp. Read-back mới có thể xác nhận persistence trên server. Row đã đọc vẫn ở All và rời Unread; repeated call phải giữ semantics idempotent. UI không được fake success từ SnackBar hoặc optimistic cache.

Notification targets dùng typed decision sau khi recheck quyền. Không đoán route từ title/body hoặc mở arbitrary payload URL. Target chưa hỗ trợ, revoked hoặc malformed phải fail-closed. Business notifications do backend producer tạo, không seed hoặc INSERT admin trong runtime Flutter.

## 8. Điều hướng và tích hợp toàn ứng dụng

Một runtime chính, một Supabase Auth và canonical router phục vụ toàn bộ màn hình nhóm. Role navigation dùng tên chức năng:

- Customer: Trang chủ, Sản phẩm, Giỏ hàng, Đơn hàng, Tài khoản.
- Manager: Đơn hàng, Sản phẩm, Trả hàng, Tài khoản; COD/Chat/Notifications qua menu phù hợp.
- Shipper: Giao hàng, Thu hộ COD, Tài khoản.

Checkout success phải dùng canonical Customer Orders route trong cùng app; không push MaterialApp hoặc shell khác. Order UUID hiển thị phải đến từ receipt đã được Supabase xác nhận. Customer/Manager đọc cùng dữ liệu server, không có hai danh sách RAM tách rời.

Detail screens và notification pushes giữ Back/navigation nhất quán. Tab state và deep links phải được kiểm bằng regression tests; không suy rằng thay tên file đã bảo đảm các hành vi này.

## 9. Phân quyền, session và fixture tests

Production Auth dùng `SupabaseAuthRepository`, server-managed profile và trusted feature scope. Không lấy role từ user-editable metadata. Email callback, token lifecycle và chính sách `persistSession` hiện có phải được giữ khi tổ chức source.

Account/logout/expiry invalidates private caches và dialogs theo session generation. Late response từ phiên cũ không được phục hồi dữ liệu. Route guard không thay RLS; reads/writes cần quyền phía server.

RAM Orders/Notifications contract fixture được giữ riêng dưới `test/support/fixtures`; runtime không import fixture này. Nó phục vụ tests về receipts, invalid transitions, same-key replay, ownership và notifications, không phải local authentication hoặc fallback backend.

Các app variants/local entrypoints cũ đã được loại khỏi application source. Tests chỉ kiểm implementation đã nghỉ được loại cùng implementation; business regression tests phù hợp với repository contracts tiếp tục được giữ ở test tree.

## 10. Trạng thái xác minh

Đợt kiểm tra ngày 09/11/2026 được chạy sau khi hoàn tất cleanup và hợp nhất
runtime. Các kết quả local demo cũ không được dùng thay kết quả refactor mới.

| Kiểm tra | Kết quả thực tế |
| --- | --- |
| Full Flutter suite sau refactor | 1.882 PASS, 9 FAIL thuộc Auth I1 lịch sử, 9 skip có sẵn; không phải full-suite PASS |
| Checkout và navigation sau chuyển utility test khỏi `lib/` | 39 PASS, 5 case live Cloud không bật trong lượt offline |
| Checkout ACK → Orders | Widget regression bấm nút thật trên CheckoutPage với transport cô lập; giữ cùng MaterialApp/router/shell và đúng tab Đơn hàng |
| Analyzer | PASS; không còn diagnostics ở lượt kiểm tra mới |
| Android debug build `lib/main.dart` | PASS |
| Cold launch production APK | Supabase khởi tạo và mở Login; không có app local hoặc navigation mode thứ hai |
| Customer A / Manager B | Supabase login, server profile/SessionScope, Orders list/detail và nội dung detail UI PASS trên Pixel_5 |
| MH17 Customer A / Manager B | Cloud All/Unread/count, pagination và filter UI PASS; logout xóa private scope |
| Customer C | Cloud login và inbox/orders rỗng hợp lệ; order detail/pagination thiếu dữ liệu không được coi là PASS |
| Cross-account READ | Customer C bị từ chối đọc order của A; authenticated SELECT không trả notification của A |
| Checkout/Orders/markRead WRITE mới | NOT VERIFIED; không gửi business mutation trong đợt refactor |

Chín Auth I1 findings được giữ nguyên. Chúng liên quan server identity
revalidation, expiry không giới hạn, stream completion, periodic role check,
coalescing và timeout/late response; cần Auth owner thống nhất contract,
không được xóa/skip hoặc thay production Auth chỉ để đổi kết quả tests.

Tài khoản QA dự kiến dùng cho Shipper được server trả role `customer` trong
lượt runtime. Client giữ nguyên trusted role; không gán quyền theo email.
Shipper navigation có regression coverage nhưng Cloud runtime Giao hàng/COD
còn BLOCKED cho đến khi có QA identity thực sự được cấp role shipper.

Orders pagination chưa được thực thi trong lượt Cloud này. Notification target
resolver production chưa có accepted binding nên fail-closed. SQL trong source
không chứng minh OP-O04–08 đã deployed/callable; chưa thực hiện controlled
mutation nên không kết luận B2 Cloud WRITE hoặc receipt persistence PASS.

## 11. Giới hạn và hướng dẫn chạy

Cần AVD Pixel_5, Flutter SDK phù hợp `pubspec.yaml`, Internet, Supabase client config hợp lệ và tài khoản ứng dụng có role được server cấp. Không dùng các tài khoản local cũ.

```powershell
flutter run -d emulator-5554 -t lib/main.dart --no-dds
```

Entrypoint đọc cấu hình client mặc định hoặc build overrides theo hướng dẫn README. Không đưa password/token/service-role key vào source, logs hoặc cấu hình mobile. Đổi tài khoản qua Logout/Login bằng Supabase Auth.

RPC/migration có trong Git chưa chứng minh đã deployed. Operations chưa đủ contract/grants/data hoặc ngoài QA scope phải báo BLOCKED/NOT VERIFIED. Không tự deploy SQL, thay RLS hoặc tạo thêm orders trên Cloud chung để hoàn thành demo.

Không có reset dữ liệu nghiệp vụ RAM, local account switcher hay offline business success fallback. Mất mạng/backend lỗi hiển thị failure/unavailable trung thực. Những thay đổi irreversible chỉ được kiểm bằng exact approved QA records.

## 12. Kết luận

Phần MH07/MH08/MH09/MH17 giữ cùng domain contracts, canonical acknowledgement, session isolation và navigation của ứng dụng nhóm. Ứng dụng chính thức chạy từ `lib/main.dart` với Supabase làm business source of truth; fixture chỉ phục vụ automated tests.

Đã kiểm client sau cleanup và kiểm authenticated Cloud READ trên Pixel_5.
Ứng dụng giữ Supabase làm nguồn dữ liệu nghiệp vụ duy nhất. Full suite còn
chín Auth I1 findings; Shipper Cloud runtime và business WRITE chưa hoàn tất
xác minh. Không gán nhãn production-ready hoặc Cloud WRITE PASS từ kết quả
fixture, source SQL hay navigation tests.
