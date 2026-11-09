# Minh Đức · Hướng dẫn demo và đọc code MH10, MH11, MH18, MH12

**Một câu để mở đầu:** “Em sẽ theo một đơn từ lúc shipper thấy nhiệm vụ, mở điểm giao, giao đủ hàng và thu tiền, đến lúc quản lý xác nhận tiền đã về cửa hàng.”

Đối chiếu mã nguồn ngày 09/11/2026, commit `54a71af`. Các liên kết dẫn tới file trong repo. Số sau ký hiệu **L** là dòng tại commit này. Trong VS Code, mở file rồi nhấn **Ctrl+G** và nhập số dòng. Nếu code đã thay đổi, dùng **Ctrl+F** tìm tên hàm ghi cạnh liên kết.

## 1. Chuẩn bị và thứ tự bấm

Để demo cả thao tác ghi, chạy bản kết nối Supabase bằng `flutter run -t lib/main.dart`. Chuẩn bị một tài khoản shipper, một tài khoản quản lý và một đơn demo **đã phân công cho chính shipper, đang chờ nhận, có tọa độ**. Giữ lại mã đơn và nhìn số COD hiển thị thực tế. RPC phải có trên backend của môi trường demo. Nên tập trên một đơn khác vì hoàn thành nhiệm vụ sẽ thay đổi dữ liệu.

| Màn | Thao tác | Chi tiết nên chỉ cho cô |
|---|---|---|
| MH10 · Nhiệm vụ | Đăng nhập shipper → **Nhiệm vụ → Chờ** → chọn một nhiệm vụ giao đi. | Dòng danh sách là nhiệm vụ được phân công. Ghi nhớ mã đơn để đối chiếu ở MH12. |
| MH11 · Chi tiết | Xem người nhận, hàng và COD → **Nhận hàng** → xác nhận. | Một lần xác nhận vừa nhận hàng vừa bắt đầu giao. Task chuyển sang đang giao. |
| MH18 · Bản đồ | Từ MH11 bấm **Mở bản đồ** → xem ghim và địa chỉ → **Chỉ đường tới điểm này** → quay lại ứng dụng. | Ghim là điểm đến lưu cho nhiệm vụ. Nền bản đồ trong app và dịch vụ tìm đường bên ngoài là hai phần riêng. |
| MH11 · Kết quả giao | **Giao thành công** → tích khách đã nhận đủ hàng và đã thu đủ số tiền hiển thị → **Xác nhận**. | Đơn đã giao, còn số COD đang do shipper giữ. |
| MH12 · Tiền thu hộ | Shipper mở **Tiền thu hộ** và tìm đơn. Chuyển sang quản lý, mở đối soát, chọn cùng đơn → **Xác nhận nhận đủ tiền** → tích đã kiểm đếm → **Xác nhận**. | Chỉ quản lý được xác nhận cửa hàng đã nhận đủ tiền của đơn đó. |

**Khi trình chiếu bằng bản local:** `lib/main_dev.dart` dùng dữ liệu trong RAM. Tài khoản mẫu `shipper@local.test` và `manager@local.test` dùng mật khẩu `sports123`. Có thể xem danh sách, chi tiết, tọa độ và khoản COD có sẵn. Các adapter ghi giao hàng và nhận COD ở bản này trả trạng thái chưa khả dụng. MH18 dùng ghim và tọa độ thay cho nền bản đồ mạng. Xem [cấu hình local](../lib/app/dev/dev_app.dart#L178) và [bản đồ offline](../lib/app/dev/dev_app.dart#L239).

## 2. MH10 và MH11 lấy dữ liệu từ đâu?

**Theo một lần bấm bộ lọc ở MH10:** giao diện chuyển lựa chọn cho ViewModel → ViewModel tạo truy vấn → repository gửi RPC qua Supabase → PostgreSQL trả trang kết quả → ViewModel cập nhật danh sách. Khi tìm kiếm hoặc chuyển nhóm, ứng dụng truy vấn lại. Khi tải thêm, truy vấn mang theo con trỏ trang tiếp theo.

| Mở code theo thứ tự | Điều cần nhìn |
|---|---|
| [Router · L385](../lib/app/router/app_router.dart#L385) | Ba route lồng nhau là danh sách, chi tiết theo `:taskId` và `map`. MH12 có route riêng `/cod`. |
| [DeliveryTaskListViewModel · L231](../lib/features/deliveries/presentation/view_models/delivery_task_list_view_model.dart#L231) → [queryTasks · L72](../lib/features/deliveries/data/repositories/supabase_delivery_repository.dart#L72) | ViewModel gọi `queryTasks`; repository biến bộ lọc thành tham số cho `list_my_delivery_tasks`. SQL gốc nằm ở [migration danh sách](../supabase/migrations/20261023153729_list_my_delivery_tasks.sql#L6). |
| [OperationalReadAccess.run · L136](../lib/features/deliveries/data/repositories/operational_read_access.dart#L136) | Kiểm tra phiên hiện tại, đọc role từ `profiles`, so với role được phép. Khi phiên đổi trong lúc chờ phản hồi, kết quả cũ không được dùng cho người mới. |
| [getTaskDetails và getMapTaskDetails · L151](../lib/features/deliveries/data/repositories/supabase_delivery_repository.dart#L151) | **MH11** gọi `get_my_delivery_task_history` để đọc cả lịch sử được phép. **MH18** gọi `get_my_delivery_task` để đọc điểm đến đang được giao. Có quyền xem lịch sử không đồng nghĩa có quyền mở bản đồ hay sửa nhiệm vụ đã kết thúc. |
| [_readTaskDetails · L120](../lib/features/deliveries/data/repositories/supabase_delivery_repository.dart#L120) | Gửi `p_task_id`, kiểm tra phiên sau khi nhận kết quả và đổi JSON qua DTO thành model Dart. Lỗi SQL `P0002` ở hai RPC chi tiết được ánh xạ sang nhiệm vụ không còn thuộc phạm vi được giao. |

Để xem phía SQL của hai màn chi tiết, mở [RPC đọc nhiệm vụ và lịch sử cho MH11](../supabase/migrations/20261102133026_shipper_history_detail_projection.sql#L61) và [RPC đọc điểm đến của nhiệm vụ cho MH18](../supabase/migrations/20261024010714_get_my_delivery_task.sql#L5).

**Phân biệt các ID:** MH11/MH18 mở bằng **taskId**, vì một đơn có thể có nhiều nhiệm vụ hoặc lần giao. MH12 đối soát theo **orderId**, vì khoản tiền gắn với đơn. **requestId** là ID của *một lần yêu cầu nghiệp vụ*, dùng để nhận biết yêu cầu gửi lại khi mạng chập chờn.

## 3. Backend Supabase xử lý ba nút quan trọng

Trong luồng production, repository gọi `client.rpc(...)` qua Data API bằng phiên Supabase Auth. PostgreSQL lấy danh tính từ `auth.uid()`. Ví dụ, hàm gộp nhận và bắt đầu giao dùng SECURITY INVOKER (chạy với quyền người gọi). Hàm xác nhận COD dùng SECURITY DEFINER (chạy với quyền chủ sở hữu hàm). Chủ hàm COD là một role ghi riêng có NOBYPASSRLS và chịu các policy dành cho role này. Quyền EXECUTE cho phép gọi hàm; bản thân hàm vẫn phải kiểm tra danh tính, vai trò và điều kiện nghiệp vụ. Xem [role ghi COD](../supabase/migrations/20261025121908_confirm_cod_received.sql#L17), [policy của role](../supabase/migrations/20261025121908_confirm_cod_received.sql#L150) và [gán chủ sở hữu hàm](../supabase/migrations/20261025121908_confirm_cod_received.sql#L429). Biết UUID, có publishable key hay nhìn thấy nút trên Flutter đều chưa đủ để ghi. Các bảng và phép kiểm được xử lý theo từng lệnh như sau.

### MH11 · Nhận hàng

1. Nút **Nhận hàng** gửi `taskId` và `requestId`. Xem [widget thao tác · L137](../lib/features/deliveries/presentation/widgets/outbound_task_actions.dart#L137) và [repository chọn RPC · L111](../lib/features/deliveries/data/repositories/supabase_outbound_task_command_repository.dart#L111).
2. Mở [accept_and_start_delivery_task · L6](../supabase/migrations/20261102035050_accept_and_start_delivery_task.sql#L6). Hàm xác thực người gọi, tạo hai khóa con cố định từ cùng `requestId`, lấy khóa theo thứ tự ổn định rồi gọi `accept_delivery_task` và `start_delivery_task` trong **cùng một giao dịch PostgreSQL**.
3. Nhận hàng ghi nhận trách nhiệm giữ hàng và xuất kho lần đầu. Bắt đầu giao tăng bộ đếm lần giao của đơn. Nếu bước bắt đầu thất bại, bước nhận và xuất kho trong giao dịch đó cũng bị hoàn tác. Gửi lại cùng yêu cầu sử dụng cùng khóa con, tránh xuất hàng hoặc tăng bộ đếm hai lần. [SQL xử lý nhận và bắt đầu](../supabase/migrations/20261026055651_accept_start_outbound_delivery.sql).

### MH11 · Giao thành công hoặc thất bại

Khi shipper tích đủ hai ô, [hộp xác nhận · L199](../lib/features/deliveries/presentation/widgets/outbound_completion_action.dart#L199) chuyển ý định sang ViewModel. [Repository · L33](../lib/features/deliveries/data/repositories/supabase_outbound_completion_repository.dart#L33) gọi `complete_outbound_delivery`. Hãy mở [thân RPC · L211](../supabase/migrations/20261027060030_fail_outbound_delivery.sql#L211) rồi đến [khối ghi · L407](../supabase/migrations/20261027060030_fail_outbound_delivery.sql#L407). Máy chủ khóa bản ghi đơn, nhiệm vụ và COD, kiểm tra shipper, trạng thái và tiền phải thu trước khi ghi đồng thời:

| Dữ liệu | Sau khi giao thành công |
|---|---|
| `delivery_attempts` | Lưu kết quả lần giao thành công. |
| `delivery_tasks`, `orders` | Nhiệm vụ và đơn đều chuyển sang `delivered`. |
| `cod_collections` | Chuyển sang `collected` (shipper đã thu). Cửa hàng chưa xác nhận nhận tiền. |
| Sự kiện và thông báo | Ghi nhận sự kiện và thông báo trong cùng giao dịch. |

Nếu giao không được, shipper báo lý do qua [fail_delivery_task · L768](../supabase/migrations/20261027060030_fail_outbound_delivery.sql#L768). Lần đầu, đơn chờ quyết định giao lại hoặc hoàn sớm. Cùng shipper đang giữ hàng có thể yêu cầu tạo task lần hai; task mới giữ nguyên lịch sử và không xuất hàng lần nữa. Sau hai lần giao thất bại, đơn chờ hoàn về cửa hàng. Báo bàn giao hàng chưa làm tăng tồn bán. [RPC yêu cầu giao lần hai](../supabase/migrations/20261101095549_shipper_retry_outbound_failure.sql).

MH11 cũng dùng cho **lấy hàng trả** và **giao lại hàng trả sau kiểm tra**. Loại nhiệm vụ quyết định bộ nút hiện ra. Lấy hàng trả căn cứ vào hàng khách thực nhận. Giao lại do từ chối trả sau kiểm tra là miễn phí và không thu COD lần nữa. Xem [thao tác lấy hàng trả](../lib/features/deliveries/presentation/widgets/return_pickup_action.dart) và [thao tác giao lại](../lib/features/deliveries/presentation/widgets/redelivery_action.dart).

### MH12 · Quản lý nhận đủ tiền

[CodRoutePage · L15](../lib/features/cod/presentation/pages/cod_route_page.dart#L15) chọn giao diện theo vai trò. RPC [list_cod_collections](../supabase/migrations/20261025064829_list_cod_collections.sql) trả khoản thu trong phạm vi được phép. Shipper xem khoản của mình. Quản lý có thể xem theo đơn hoặc shipper và xác nhận tiền thực nhận.

Từ [hộp xác nhận của quản lý · L159](../lib/features/cod/presentation/widgets/manager_cod_panel.dart#L159), theo [ManagerCodViewModel · L517](../lib/features/cod/presentation/view_models/manager_cod_view_model.dart#L517) → [repository · L35](../lib/features/cod/data/repositories/supabase_cod_receipt_repository.dart#L35) → [confirm_cod_received · L215](../supabase/migrations/20261025121908_confirm_cod_received.sql#L215). RPC nhận mã đơn, số tiền được xác nhận và mã yêu cầu. Máy chủ kiểm tra quyền quản lý, khóa dữ liệu liên quan, kiểm tra trạng thái đã thu và số tiền đủ cho đơn trước khi ghi `received`. Biên nhận lưu theo người gọi và mã yêu cầu để phát hiện gửi lặp. ViewModel đọc lại dữ liệu sau phản hồi.

**Ví dụ khi cô hỏi về tiền:** đơn 520.000đ cộng phí giao 30.000đ. Khi shipper giao thành công, khoản 550.000đ ở trạng thái đã thu. Chỉ khi quản lý nhận đủ 550.000đ thì mới đối soát xong. Nếu khách trả hàng sau đó, khoản hoàn cho khách được ghi riêng.

## 4. MH18 · Bản đồ trong app và chỉ đường qua Google Maps

### Trong app: từ taskId đến ghim bản đồ

1. **Mở đúng điểm giao.** [Nút Mở bản đồ · L481](../lib/features/deliveries/presentation/pages/delivery_task_detail_page.dart#L481) dẫn tới `/shipper/tasks/:taskId/map`. [DeliveryTaskMapViewModel · L35](../lib/features/deliveries/presentation/view_models/delivery_task_map_view_model.dart#L35) đọc lại task theo phiên shipper. Repository lấy dữ liệu điểm đến từ RPC. Với nhiệm vụ giao đi, đây là địa chỉ và tọa độ đã lưu cho đơn khi khách đặt ở MH16.
2. **Vẽ nền và ghim.** [Page · L197](../lib/features/deliveries/presentation/pages/delivery_task_map_page.dart#L197) gọi `mapDisplayAdapterProvider`; [provider production · L12](../lib/core/maps/map_providers.dart#L12) cấp `RasterMapDisplayAdapter`. [SavedDestinationMap · L81](../lib/core/maps/saved_destination_map.dart#L81) đổi vĩ độ/kinh độ sang vị trí trên lưới **Web Mercator**, lấy cụm **3 × 3 ảnh bản đồ** quanh điểm đến tại mức zoom nguồn 14. Mỗi ảnh là một phần nhỏ của bản đồ. Flutter ghép các ảnh và vẽ ghim tại tọa độ đã lưu.
3. **Tải ảnh nền.** [MapTileSource · L53](../lib/core/maps/map_tile_source.dart#L53) tạo URL dạng `https://tile.openstreetmap.org/{z}/{x}/{y}.png`. Nguồn ảnh có bộ nhớ đệm để dùng lại ảnh còn hạn. Khi kéo bản đồ, người dùng thay đổi vùng nhìn. Nút đưa bản đồ về điểm đến căn giữa lại ghim. MH18 không cập nhật địa chỉ đơn hoặc theo dõi vị trí trực tiếp của shipper.
4. **Khi dữ liệu thiếu.** Nếu còn quyền và có địa chỉ nhưng thiếu tọa độ, MH18 giữ thông tin dạng chữ và cho sao chép địa chỉ. Nút chỉ đường cần tọa độ hợp lệ. Lỗi tải ảnh nền khác với mất quyền đọc nhiệm vụ. [Các trạng thái UI](../lib/features/deliveries/presentation/pages/delivery_task_map_page.dart#L197).

### Khi bấm “Chỉ đường tới điểm này”

| Bước | Code cần mở | Điều xảy ra |
|---|---|---|
| 1. Nhận thao tác | [_openDirections · L350](../lib/features/deliveries/presentation/pages/delivery_task_map_page.dart#L350) | Trang chặn bấm lặp khi đang xử lý, giữ thông tin phiên và yêu cầu ViewModel mở chỉ đường cho đúng task đang hiển thị. |
| 2. Kiểm tra lại quyền | [recheckAuthorizedDetails · L95](../lib/features/deliveries/presentation/view_models/delivery_task_map_view_model.dart#L95) và [openDirections · L154](../lib/features/deliveries/presentation/view_models/delivery_task_map_view_model.dart#L154) | Đọc mới từ server. Chỉ đi tiếp nếu task vẫn thuộc phạm vi hiện tại, điểm đến không đổi, phiên vẫn đúng, trang còn hiển thị và tọa độ hợp lệ. Nếu vừa bị đổi phân công, ứng dụng dừng trước khi gửi tọa độ ra ngoài. |
| 3. Tạo đường dẫn | [GoogleMapsDirectionsLauncher.locationUri · L35](../lib/core/maps/map_directions.dart#L35) | Tạo HTTPS URL với hai tham số: `api=1` và `destination=vĩ_độ,kinh_độ`. Không có tên khách, điện thoại, mã đơn hay địa chỉ chữ trong URL. |
| 4. Giao cho thiết bị mở | [openLocation · L55](../lib/core/maps/map_directions.dart#L55) | `url_launcher` gọi `launchUrl` với `LaunchMode.externalApplication`; trên web đặt `webOnlyWindowName: '_self'`. Tùy thiết bị, URL mở ứng dụng Google Maps hoặc trang web. Google Maps xử lý điểm xuất phát và tìm đường. |
| 5. Nhận kết quả | [Xử lý kết quả · L424](../lib/features/deliveries/presentation/pages/delivery_task_map_page.dart#L424) | `opened` là đã gửi được yêu cầu mở. Nếu thiết bị không mở được hoặc gặp lỗi, màn hình cho thử lại hoặc sao chép địa chỉ. Mở Google Maps không hoàn thành nhiệm vụ hay ghi nhận giao thành công. |

Ví dụ minh họa với tọa độ giả định: `https://www.google.com/maps/dir/?api=1&destination=21.0285%2C105.8542`. Ký hiệu `%2C` là dấu phẩy đã mã hóa trong URL. Cơ chế này chỉ mở một liên kết chỉ đường nên không cần Google Maps API key. **Supabase cấp dữ liệu và kiểm tra quyền; OpenStreetMap cung cấp ảnh nền; Google Maps nhận tọa độ để chỉ đường.**

## 5. Nếu chỉ có một phút để chỉ code

Mở sẵn ba tab: [SQL nhận và bắt đầu giao](../supabase/migrations/20261102035050_accept_and_start_delivery_task.sql#L65), [SQL xác nhận tiền](../supabase/migrations/20261025121908_confirm_cod_received.sql#L376), [Dart tạo URL và mở Google Maps](../lib/core/maps/map_directions.dart#L35). Ở mỗi tab chỉ một hành vi: hai thao tác kho/giao cùng thành công hoặc cùng hoàn tác; tiền chỉ về trạng thái cửa hàng đã nhận sau xác nhận của quản lý; điện thoại chỉ gửi tọa độ điểm đến cho Google Maps.

Tài liệu đối chiếu source của bản production và bản local. Lượt soạn này không chạy demo bằng tài khoản thật hay kiểm tra trạng thái triển khai Supabase.
