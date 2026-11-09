# BÁO CÁO TỔNG KẾT PRM393 — MH07, MH08, MH09, MH17

**Dự án:** Sports Store
**Phần phụ trách:** Lê Gia Bảo — Orders và Notifications
**Môi trường trình bày:** Flutter full-app local trên Android Emulator Pixel_5
**Entrypoint:** `lib/main_dev.dart`
**Ngày kiểm tra sau cleanup:** 08–09/11/2026

## 1. Tổng quan dự án

Sports Store là ứng dụng môn PRM393 phục vụ mua sắm sản phẩm thể thao, quản lý đơn hàng và giao nhận tại một cửa hàng. Hệ thống có ba vai trò Customer, Manager và Shipper. Source của nhóm có 20 màn nghiệp vụ, bao gồm xác thực, danh mục sản phẩm, giỏ hàng, Checkout, Orders, giao hàng, COD, Returns, Notifications và Chat.

Bản dùng để trình bày là ứng dụng local đầy đủ, không phải Preview riêng cho bốn màn. Người dùng bắt đầu từ Login, vào giao diện đúng vai trò, sử dụng các tab có tên chức năng và đổi tài khoản bằng logout/login. Các màn đã duyệt được tái sử dụng, không thay bằng giao diện minh họa mới.

Báo cáo này tập trung vào MH07/MH08/MH09/MH17. Những module khác chỉ được đề cập khi cần giải thích điều hướng, nguồn dữ liệu hoặc giới hạn tích hợp. Kết quả local không được diễn giải thành xác thực, phân quyền hay ghi PostgreSQL trên Supabase Cloud.

## 2. Phạm vi bốn màn hình

| Màn | Chức năng chính | Người dùng | Source UI chính |
|---|---|---|---|
| MH07 | Danh sách, chi tiết và hủy đơn của mình | Customer | `CustomerOrdersPage`, `CustomerOrderDetailsPage` |
| MH08 | Theo dõi danh sách đơn, bộ lọc, KPI và xử lý đơn chờ | Manager | `ManagerOrdersPage` |
| MH09 | Chi tiết đơn, timeline, projections và actions hợp lệ | Manager | `ManagerOrderDetailsPage` |
| MH17 | Hộp thông báo cá nhân, số chưa đọc và đánh dấu đã đọc | Customer/Manager/Shipper | `NotificationsScreen` |

Phần thực hiện gồm domain models, repository interfaces/adapters, Riverpod reads/actions, UI và tích hợp router/session. Màn hình nhận business ID qua route hoặc callback; không dùng số thứ tự màn hình làm nhãn navigation. Chức năng không có dữ liệu hoặc capability hợp lệ phải hiển thị trạng thái tương ứng, không tự tạo dữ liệu hay báo thành công.

## 3. Kiến trúc và thành phần sử dụng

Ứng dụng theo feature-first MVVM: View nhận state và chuyển thao tác đến ViewModel; ViewModel phối hợp repository; repository xử lý dữ liệu. Domain không phụ thuộc widget hay Supabase SDK. Riverpod quản lý dependency injection và state; go_router quản lý navigation; theme và localization dùng chung của Sports Store.

Các phần chính liên quan đến báo cáo:

- `lib/features/orders/`: models, DTO/adapters, repository contract, providers, pages và business dialogs.
- `lib/features/notifications/`: notification models, repository, read/interactions, inbox, badge và target resolver.
- `lib/core/state/`: `SessionScope`, epoch cache, snapshots và read/retry infrastructure.
- `lib/app/dev/`: full-app local composition, router, local Auth, Commerce và các adapters phục vụ module liên quan.
- `lib/app/demo/data/local_demo_store.dart`: nguồn Orders/Notifications chung trong RAM, được full-app sử dụng trực tiếp.

`OrderRepository` cung cấp customer/manager list, detail, confirm, reject, customer cancel, manager cancel và operation lookup. `NotificationRepository` cung cấp page, exact unread count và canonical markRead acknowledgement. Các màn phụ thuộc interfaces qua providers; không gọi Cloud trực tiếp từ widgets.

Models tách order, delivery, COD và return request. Giá trị VND là số nguyên. `OrderDetails` kiểm tra ownership của items, subtotal, buyer, COD relation và timeline. Capabilities là dữ liệu nghiệp vụ được repository cấp lại theo trạng thái hiện tại, không chỉ là điều kiện ẩn/hiện nút trên UI.

Production entrypoint `lib/main.dart` và các Supabase adapters được giữ. Full-app local override repositories/session trong scope riêng, không thay repository production bằng fixture một cách âm thầm.

## 4. MH07 — Đơn hàng của tôi

### 4.1. Truy cập và hiển thị

Customer mở tab **Đơn hàng**, tương ứng `/customer/orders`. Repository chỉ trả các đơn có `customerId` thuộc session hiện tại. Detail được kiểm ownership lại, nên biết UUID của tài khoản khác không đủ để đọc nội dung.

Danh sách hiển thị sản phẩm/biến thể snapshot, trạng thái, số lượng và tổng thanh toán. Các trạng thái dùng enum chung; hoàn thành giao hàng là `delivered`, không tự thêm trạng thái `completed`. Tổng tiền lấy từ canonical order, gồm merchandise và delivery fee; không cộng lại từ các dòng chỉ được tải một phần của danh sách.

Màn hỗ trợ search, lọc theo trạng thái, refresh và cursor pagination. Đổi query/filter làm thay đổi namespace trang, tránh ghép cursor của truy vấn cũ vào danh sách mới. Các trạng thái loading, error, unavailable, empty và data có cách hiển thị riêng.

### 4.2. Chi tiết và hủy đơn

Trong full-app, nút xem chi tiết mở nested route `/customer/orders/:orderId`, dùng lại nội dung detail đã duyệt. Nội dung gồm người nhận, items, thanh toán, lịch sử và các liên kết Returns khi đủ điều kiện. Các callers cũ của `CustomerOrdersPage` vẫn có thể dùng detail sheet mặc định.

Customer chỉ hủy own order ở `pending_confirmation` và khi capability cho phép. Dialog yêu cầu xác nhận; command mang request ID ổn định. Repository kiểm quyền/trạng thái lại trước khi cập nhật. Đơn preparing, đã giao hoặc không thuộc Customer không được hủy bằng cách gọi lại action cũ.

Sau ACK, danh sách/detail được tải lại từ nguồn chung. Trạng thái thay đổi đồng thời ở MH08/MH09 và customer notification được tạo theo event. Trong local mode, reservation của đơn Checkout được release đúng một lần khi hủy; replay cùng command không release hay tạo event thêm lần nữa.

## 5. MH08 — Quản lý đơn hàng

### 5.1. Danh sách, tìm kiếm và KPI

Manager vào `/manager/orders`. Customer và Shipper không được mở màn này bằng menu hay deep navigation. Màn sử dụng cùng repository/order UUID với MH07, không có danh sách mock độc lập cho Manager.

Manager có search, status filters, số lượng/KPI và pagination. Counts lấy từ aggregate trả về thay vì đếm số cards đang thấy trên màn. Refresh, thay filter và back từ detail phải giữ danh sách ở trạng thái hợp lệ, đồng thời đọc lại các thay đổi vừa thực hiện.

Mỗi card có thông tin khách, items snapshot, số tiền, trạng thái và các actions được cấp. Callback xem chi tiết đưa đúng UUID sang MH09. Loading, empty và failure không bị trình bày như một danh sách thành công giả.

### 5.2. Confirm và Reject

Confirm chỉ áp dụng cho pending order. Sau ACK, trạng thái chuyển sang `preparing`; không tự gán Shipper hay tự đánh dấu giao hàng. Reservation vẫn còn, không giữ hàng lần thứ hai.

Reject áp dụng cho pending order và yêu cầu reason hợp lệ. Reason được đưa vào command/timeline. Sau reject, order thành `rejected`, reservation được giải phóng đúng một lần đối với đơn local Checkout có reservation.

UI khóa thao tác trong lúc xử lý và sử dụng canonical receipt. Repository có request fingerprint, replay và state checks, nên thao tác lặp không tạo hai kết quả nghiệp vụ. Nếu chưa có ACK đáng tin cậy, client không được giữ trạng thái optimistic như thể operation đã thành công.

## 6. MH09 — Chi tiết đơn hàng

### 6.1. Dữ liệu và navigation

MH09 ở `/manager/orders/:orderId`, nhận full UUID từ MH08. Màn hiển thị order status, buyer/recipient, địa chỉ, items, unit price, số lượng, merchandise subtotal, delivery fee và tổng COD dự kiến. Nhấn Back trở về danh sách; refresh đọc lại chính order đang mở.

Items và giá là snapshot lúc đặt đơn, không bị thay đổi khi Manager chỉnh catalog sau đó. Timeline hiển thị milestones/events có trong dữ liệu. `historyComplete=false` được giữ khi seed chỉ có snapshot milestones; không tự dựng event để biến lịch sử thiếu thành lịch sử đầy đủ.

Delivery/COD/Returns chỉ hiện projection thực sự có. Đơn chưa có COD record hiển thị thiếu dữ liệu COD; tổng tiền cần thanh toán không được gọi là tiền đã thu. Một return sau giao thành công không biến delivered order thành cancelled hay xóa nghĩa vụ COD.

### 6.2. Các actions

| Action | Điều kiện local chính | Kết quả |
|---|---|---|
| Confirm | Manager, pending, capability hợp lệ | `preparing`, event/receipt, thông báo Customer |
| Reject | Manager, pending, có reason | `rejected`, release một lần, event/receipt |
| Manager Cancel | Manager, trạng thái cho phép và chứng minh NEVER assigned | `cancelled`, reason, release một lần |
| Action sai trạng thái/quyền | Không đủ capability hoặc ownership/role | Bị chặn, không tạo success receipt |

Manager Cancel không phải quyền hủy mọi đơn. Đơn đã từng assigned/có custody hoặc đã giao không được xử lý bằng shortcut. Những action về phân công, bàn giao, thu tiền và Returns nâng cao chưa có transaction local đầy đủ vẫn unavailable.

Mutation không dùng raw status update từ Flutter. State, timeline, notifications và receipt trong local store được cập nhật theo operation; callers đọc lại canonical detail/list. Loading/disabled state và thông báo lỗi được giữ trong UI đã duyệt.

## 7. MH17 — Thông báo

### 7.1. Inbox và trạng thái đã đọc

MH17 là màn dùng chung, mở qua chuông hoặc mục **Thông báo** trong Tài khoản. Repository suy recipient từ session, không nhận một recipient ID tùy ý từ UI. Customer, Manager và Shipper chỉ đọc inbox của chính mình.

Màn có All/Unread, refresh, cursor pagination và exact unread count. Badge phản ánh count của repository, không suy từ số rows của trang đầu. Empty inbox là trạng thái hợp lệ, nhưng không chứng minh pagination hay markRead đã được thực thi với dữ liệu.

MarkRead chỉ đổi presentation sau khi nhận canonical row có đúng notification ID, recipient và timestamp. Refresh xác nhận row vẫn đã đọc; row còn trong All và không còn trong Unread. Gọi lại markRead giữ nguyên read timestamp, không giảm count thêm lần nữa.

### 7.2. Business events và target resolution

Trong local app, Checkout thêm order vào nguồn chung và tạo notification cho Manager. Các confirm/reject/cancel tạo event cùng notification cho Customer. Event/recipient được deduplicate; replay cùng request không sinh thông báo lặp.

Mở notification sử dụng typed target decision sau khi kiểm tra quyền hiện tại. Router chỉ chọn các destination đã có trong ứng dụng. Không đoán route từ title/body và không chạy một URL tùy ý lấy từ payload. Target không tồn tại, không thuộc quyền hoặc chưa được hỗ trợ phải fail-closed.

Logout và account switch hủy UI/private state cũ, kể cả modal/context đang mở. Inbox và count được đọc trong namespace mới, tránh một frame hiển thị notification của tài khoản trước.

## 8. Điều hướng và tích hợp ứng dụng chung

Full-app dùng StatefulShellRoute.indexedStack để giữ state từng tab. Customer có Trang chủ, Sản phẩm, Giỏ hàng, Đơn hàng và Tài khoản; Manager có Đơn hàng, Sản phẩm, Trả hàng và Tài khoản; Shipper có Giao hàng, Thu hộ COD và Tài khoản. Notifications/Chat/COD có đường truy cập phù hợp theo role, không nhồi toàn bộ vào bottom navigation.

Luồng minh họa chính:

1. Customer chọn product/variant, thêm giỏ, nhập người nhận và vị trí, đặt đơn qua Checkout local.
2. Checkout trả một order UUID; MH07 đọc đúng order đó, hiển thị items/tổng tiền/detail.
3. Logout Customer, login Manager; MH08 tìm được cùng UUID và mở MH09.
4. Manager confirm hoặc reject/cancel theo capability. Back/refresh phản ánh trạng thái mới.
5. Customer login lại, đọc cùng order đã cập nhật và nhận notification phù hợp.
6. Customer khác không xem được order/inbox riêng của tài khoản đầu.

Không cần tạo đơn mới để kiểm tra tất cả terminal transitions trong một record. Confirm, reject và cancel được trình bày trên các seed phù hợp; một đơn không thể vừa bị reject vừa được xử lý như pending để hủy tiếp.

## 9. Quản lý state, session và dữ liệu local

Business state nằm trong các repositories/store chung, phía trên session-bound widget tree. Logout/login giữ các đơn và thay đổi nghiệp vụ trong cùng process, nhưng tạo provider/navigator tree mới theo epoch. Session generation chặn late reads/responses của tài khoản cũ. Local repository scope bị suspend khi logout, không chỉ ẩn màn hình bằng router.

Local Auth là mô phỏng trên thiết bị, không được gọi là Supabase-authenticated. Role đến từ mapping tài khoản local có kiểm soát; Register chỉ tạo Customer có UUID riêng. Production Auth vẫn thuộc entrypoint và repository của nhóm.

Seed có pending, preparing, assigned/delivering, delivered, cancelled và rejected orders; read/unread notifications được chia theo recipient. Seed Customer A có 9 orders, Customer C có 2; Manager đọc 11. Khi Checkout tạo thêm đơn, cả hai phía dùng cùng state mới. Seed nhỏ hơn page limit nên runtime không tự chứng minh pagination; trường hợp này được kiểm bằng automated tests.

`main_dev.dart` không khởi tạo Supabase. Client provider ném lỗi nếu bị nối nhầm và HTTP override chặn Dart HTTP trước request. Business commands, pending storage và uploads của bản local không ghi secure store hay Cloud. Dữ liệu chỉ ở RAM: restart/reset đưa về seed, không cam kết persistence qua khởi động lại.

## 10. Kết quả kiểm thử sau cleanup

Phần này chỉ ghi kết quả của lần kiểm tra sau khi xóa artifact. Các log/checkpoint lịch sử không được dùng thay cho kết quả mới.

| Kiểm tra | Kết quả sau cleanup |
|---|---|
| `flutter pub get --offline` | PASS, dependencies được resolve từ cache |
| `flutter analyze --no-pub` | PASS, No issues found; lượt cuối 23,2 giây |
| Orders/Notifications và các selected tests liên quan | PASS, 854 tests; lượt cuối khoảng 49 giây |
| Navigation/session/privacy regressions | PASS trong cùng bộ 854 tests, không cộng trùng |
| Android debug build `main_dev.dart` | PASS, lượt cuối assembleDebug 20,5 giây; APK đã cài và launch thành công |
| Pixel_5 runtime MH07/MH08/MH09/MH17 | PASS trong phạm vi local đã thao tác; chi tiết và ngoại lệ ở bảng bên dưới |
| `git diff --check` | PASS; chỉ có cảnh báo chuyển LF/CRLF của Git |

Automated tests gồm domain/DTO, role/ownership, invalid transitions, cursor/count, canonical ACK, command replay/fingerprint, late response/session isolation và liên kết giữa screens. Tests dùng fixture/MockClient hoặc repositories RAM không được gọi là Cloud verification.

Bộ selected đã chạy gồm `test/features/orders`, `test/features/notifications`, `test/app/dev`, `test/app/demo`, các tests four-screen/customer-notification navigation, production composition và Auth→feature scope. Không bật capture flags để sinh thêm screenshots/evidence trong repository.

Trong kiểm tra runtime phát hiện header customer detail và trang Shipper không có AppBar chạm status bar. Đã bổ sung SafeArea cho customer detail và local navigation shell, không đổi business widgets/policies. Regression test tại viewport điện thoại đo vị trí tiêu đề so với Android status inset và kiểm system Back; bộ 854 tests được chạy lại sau thay đổi này.

Trên APK cuối đã login Customer, mở MH07/detail và xác minh tiêu đề/nút đóng nằm dưới status bar, đóng trở về danh sách rồi Home. Không có error Flutter trong process đang chạy. Việc cài lại APK khởi tạo RAM seed mới như thiết kế; trạng thái mutation ở lượt kiểm tra trước không được gọi là persistence qua restart.

Runtime kiểm tra riêng list/detail/actions, search/filter, count, refresh, back navigation, account switching và rendering trên Pixel_5. Pagination cần số rows vượt limit; nếu seed không tạo nút tải thêm thì ghi NOT EXERCISED thay vì suy PASS từ danh sách ngắn.

Kết quả thao tác sau cleanup:

| Phạm vi | Thao tác thực tế | Kết quả |
|---|---|---|
| MH07 | Login Customer → Home → Đơn hàng; search `Giày`, lọc pending, mở UUID001; hủy và refresh | Own list9;001 thành cancelled, không còn nút hủy; tổng480.000đ khớp450.000đ+30.000đ |
| MH08 | Manager thấy cùng001 cancelled; filter pending; search full UUID002; Back từ MH09 | Manager list11; pending KPI3→2→1 theo operations; search002 trả đúng một cancelled order530.000đ |
| MH09 | Mở002; confirm→preparing; cancel NEVER assigned có reason; mở003 reject | Canonical state/amount/timeline đúng; reject trống reason bị chặn; gửi reason hợp lệ thành rejected; terminal actions biến mất |
| MH09 projections | Đọc payment, Delivery/COD/Returns và timeline sau refresh | Không fabricate projections; các mục chưa có dữ liệu hiển thị rõ; timeline ghi actor/reason/transition |
| MH17 Customer | Notification từ cancel001; All/Unread; markRead; refresh; mở target | Count4→5 sau event,5→4 sau markRead; row đã đọc còn trong All; target đúng own001, Android Back về inbox |
| Đồng bộ hai role | Customer login lại sau Manager operations | Đọc001/002 cancelled và003 rejected; cùng IDs/số tiền; badge7 sau các event mới |
| Privacy C | Logout A → login C → Orders/inbox | Chỉ2 own orders; search cũ được reset;2 notifications của C/unread1; không còn inbox A |
| Manager/Shipper | Mở inbox Manager; login Shipper → Giao hàng/COD/Account/MH17 | Manager unread6 độc lập; Shipper đọc4 tasks và COD, inbox All/Unread rỗng; không có menu quản lý/customer |
| Pagination | Automated cursor/query/ownership cases; runtime seed dưới limit | Automated PASS; runtime NOT EXERCISED, không tạo thêm records chỉ để đổi kết quả |

Emulator từng báo System UI không phản hồi khi tải snapshot cũ; cold boot không wipe dữ liệu đã khôi phục việc kiểm tra. Đây là sự cố môi trường được ghi nhận, không dùng nó làm lý do bỏ qua runtime. APK local không khởi tạo Supabase và không gửi Cloud business writes trong phiên kiểm tra.

Không tuyên bố full automated suite PASS từ selected tests. Chín Auth I1 findings ngoài phạm vi không bị sửa, xóa hoặc skip để làm đẹp kết quả. Bản cleanup giữ các tests quan trọng và source fixtures được import; chỉ loại bỏ evidence, snapshots, logs và công cụ audit cũ không còn dependency cần thiết.

Cleanup loại 27.037 file artifact với tổng 1.669.504.108 bytes (khoảng 1,55 GiB), đã sao lưu và đối chiếu SHA256 ngoài repository trước khi xóa. Domain snapshots/fixtures không bị xóa. Giữ main.dart/main_dev.dart, shared router/stores/providers, assets khai báo, tests, Android configuration, migrations và contracts nhóm. Code harness/Preview hoặc Cloud utilities còn được tests sử dụng vẫn giữ; chúng không phải entrypoint trình bày. Manifest/logs khôi phục nằm ngoài repository, không tạo báo cáo audit bổ sung. Các liên kết lịch sử còn giữ đã được sửa sang báo cáo tổng kết; không còn Markdown link trỏ tới artifact đã xóa. Cache Flutter/Android đang dùng và outputs được tái tạo khi verification vẫn nằm trong các thư mục gitignored, không phải source bàn giao.

## 11. Giới hạn và hướng dẫn chạy

### 11.1. Giới hạn hiện tại

- Đây là bản trình bày local; kết quả không xác nhận Supabase runtime/RLS hay production readiness.
- RAM state mất khi restart. Không có scheduler local để giả tự động xác nhận sau một giờ.
- Manager Cancel chỉ hỗ trợ NEVER assigned; không bỏ qua custody/inventory/COD.
- Transactions giao nhận/COD và Returns nâng cao chưa có implementation local đầy đủ; không có success fallback.
- Returns cần video được người dùng chọn để submit; xem video/evidence local còn giới hạn. Không fabricate dữ liệu cho projections thiếu.
- Pagination runtime tùy số lượng seed; kết quả automated và runtime được ghi riêng.

### 11.2. Chạy trên máy dev

Mở repository bằng Flutter SDK đã cấu hình, bật AVD **Pixel_5** và xác nhận emulator có ID `emulator-5554`. Từ project root chạy:

```powershell
flutter run -d emulator-5554 -t lib/main_dev.dart --no-dds
```

Không cần Supabase URL/key hoặc QA credentials Cloud. Ở Login, nút **Thông tin đăng nhập trên thiết bị** cung cấp các tài khoản local Customer/Manager/Shipper và mật khẩu mẫu. Chúng chỉ dùng trên thiết bị, không phải tài khoản thật. Đổi role bằng Tài khoản → Đăng xuất → Login.

Để lặp lại buổi trình bày, restart ứng dụng hoặc dùng reset trong Cài đặt phát triển ẩn bằng nhấn giữ dòng Sports Store ở cuối Tài khoản. Không có toolbar đổi role/reset nổi bật trong giao diện chính. `lib/main.dart` vẫn được giữ cho chế độ Production; lệnh trình bày chính thức ở trên không chạy entrypoint đó.

## 12. Kết luận

Bốn màn Orders/Notifications được tổ chức theo cùng kiến trúc và interfaces của ứng dụng nhóm, dùng chung order identity, business state và session boundary. Trọng tâm là hiển thị đúng dữ liệu, chỉ cho phép actions hợp lệ, nhận canonical ACK và đọc lại state, thay vì các nút chỉ hiện thông báo thành công.

Sau cleanup, MH07, MH08, MH09 và MH17 đạt PASS trong phạm vi chức năng local đã kiểm tra bằng 854 selected tests và các thao tác thực tế trên Pixel_5. Pagination runtime chưa thực thi vì seed dưới page limit; các case cursor/count/ownership có automated coverage. Các giới hạn về RAM, NEVER assigned và transactions nâng cao được giữ rõ ràng, không thay bằng thành công giả.

Báo cáo này là tài liệu tổng kết duy nhất cho phần MH07/MH08/MH09/MH17; tài liệu contracts, source, assets và tests cần thiết vẫn được giữ phục vụ bảo trì và tích hợp nhóm. Ứng dụng trình bày tiếp tục chạy bằng main_dev.dart; không cần triển khai Cloud và không thay đổi source nghiệp vụ của các thành viên khác trong lần cleanup này.
