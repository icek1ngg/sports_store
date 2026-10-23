# Ánh xạ màn hình Sports Store

Phạm vi chính gồm đúng 20 màn hình (MH01–MH20). Hộp thoại thêm/sửa sản phẩm,
biến thể và bộ chọn vị trí trong màn đặt hàng là thành phần của màn hình tương
ứng, không tạo thêm mã màn hình.

| Mã | Màn hình | Role | Chủ sở hữu | Use case chính |
| --- | --- | --- | --- | --- |
| MH01 | Đăng nhập | Khách, Manager, Shipper | Dung An | Đăng nhập, đăng xuất và điều hướng theo role |
| MH02 | Đăng ký | Khách chưa có tài khoản | Dung An | Đăng ký tài khoản khách với quyền customer |
| MH03 | Quản lý sản phẩm | Manager | Dung An | Thêm/sửa/ngừng bán sản phẩm, biến thể và tồn kho bằng hộp thoại |
| MH04 | Danh sách sản phẩm | Khách | Văn Đức | Xem, tìm kiếm và lọc theo danh mục |
| MH05 | Chi tiết sản phẩm | Khách | Văn Đức | Xem thông tin, chọn biến thể và số lượng |
| MH06 | Giỏ hàng | Khách | Văn Đức | Xem, sửa, xóa món và chuyển sang đặt hàng |
| MH07 | Đơn hàng của khách | Khách | Bảo | Xem đơn, chi tiết, hủy trước khi xác nhận và mở yêu cầu trả |
| MH08 | Danh sách đơn của manager | Manager | Bảo | Lọc trạng thái, xem đơn mới và cảnh báo giao thất bại |
| MH09 | Chi tiết đơn của manager | Manager | Bảo | Xác nhận/từ chối, phân công, giao lại, hoàn và nhận hàng trả |
| MH10 | Danh sách nhiệm vụ shipper | Shipper | Minh Đức | Xem các nhiệm vụ giao đi, lấy hàng trả và giao lại được phân công |
| MH11 | Chi tiết nhiệm vụ | Shipper | Minh Đức | Nhận/bàn giao hàng, cập nhật kết quả, thu COD và báo sự cố |
| MH12 | Đối soát COD | Shipper, Manager | Minh Đức | Shipper xem khoản của mình; manager xác nhận đã nhận đủ tiền |
| MH13 | Tạo yêu cầu trả | Khách | Sơn | Gửi yêu cầu trong hạn, chọn lý do và tải video bằng chứng |
| MH14 | Theo dõi yêu cầu trả của khách | Khách | Sơn | Xem tiến độ, bổ sung bằng chứng và xem kết quả hoàn tiền |
| MH15 | Quản lý yêu cầu trả | Manager | Sơn | Duyệt/từ chối, chỉ định lấy hàng, kiểm tra và ghi hoàn tiền |
| MH16 | Đặt hàng | Khách | Văn Đức | Nhập người nhận, chọn vị trí Hà Nội, tính phí 30.000 VND và đặt COD |
| MH17 | Thông báo | Khách, Manager, Shipper | Bảo | Xem thông báo theo người nhận, lọc chưa đọc và đánh dấu đã đọc |
| MH18 | Bản đồ điểm đến nhiệm vụ | Shipper | Minh Đức | Xem điểm đến đã lưu của nhiệm vụ được phân công; không bắt buộc pin cửa hàng |
| MH19 | Danh sách hội thoại | Khách, Manager | Dung An | Khách mở hội thoại; manager xem danh sách và tin chưa đọc |
| MH20 | Chi tiết hội thoại | Khách, Manager | Sơn | Đọc lịch sử, gửi/nhận tin văn bản và cập nhật đã đọc |

## Điều hướng chính

- Khách: MH01/MH02 → MH04 → MH05 → MH06 → MH16 → MH07.
- Khách trả hàng: MH07 → MH13 → MH14; hỗ trợ: MH19 → MH20.
- Manager: MH08 → MH09; truy cập MH03, MH12, MH15 và MH19 → MH20.
- Shipper: MH10 → MH11 → MH18; MH12 chỉ hiển thị COD của shipper đó.
- MH17 là màn dùng chung theo quyền. Khi mở liên kết từ thông báo, server phải
  kiểm tra lại quyền với đơn, nhiệm vụ, yêu cầu trả hoặc hội thoại.

## P00.1 — Điểm thao tác theo hợp đồng trạng thái

Tham chiếu [bảng chuyển trạng thái P00.1](business_states.md#p001--hợp-đồng-chuyển-trạng-thái-giao-nhận-23102026).
Các mã O/P/R và D bên dưới trỏ tới hàng chuyển trạng thái và quyết định còn mở
trong tài liệu đó. Đây là mapping đề xuất để review, chưa có xác nhận của
Bảo/Sơn/Văn Đức. Không thay đổi số lượng MH01–MH20 hoặc triển khai route.

| Màn / owner | Mốc và hành động | Ranh giới cần giữ |
| --- | --- | --- |
| MH09 / Bảo | O1/O2 phân công; O7 giao đi lần 2; O8 hoàn sớm; O11 nhận hàng thất bại rồi kiểm tra; O12 hủy hợp lệ | Phân công không phải thực nhận; manager nhận/kiểm tra khác shipper báo bàn giao. D1–D5. |
| MH10 / Minh Đức | Hiển thị ba kind và trạng thái task đúng enum; mở MH11 | Không gọi mọi trạng thái ngoài đang giao là hoàn tất. `manager_action_required` cần xử lý; `failed` có thể còn hàng cần hoàn. Không suy ra custody từ nhóm UI. |
| MH11 / Minh Đức | O3/O4 thực nhận tại cửa hàng rồi start; O5/O6/O9 kết quả; O10 báo bàn giao. P2 nhận tại khách, P3 vận chuyển về, P4 thất bại lấy, P5 báo bàn giao. R2/R3 nhận/start, R4/R5 kết quả, R6 báo bàn giao | Một màn theo kind; không có nút shipper xác nhận manager đã nhận/kiểm tra; pickup không kết thúc khi vừa lấy từ khách; redelivery không thu COD. D2/D3/D6/D8/D9. |
| MH15 / Sơn | P1 duyệt thu hồi/phân công, P6 thực nhận tại cửa hàng và mở kiểm tra; R1 quyết định giao lại, R6 nhận hàng giao lại thất bại và giải quyết tiếp | Duyệt lấy không phải duyệt hoàn tiền; thất bại giao lại không đóng request. Chốt mapping enum với Sơn D8/D9. |
| MH07 / Bảo, MH14 / Sơn | Đọc trạng thái order và return tương ứng | Order đã `delivered` không chuyển thành cancelled vì trả hàng; hiển thị chờ manager ở nhánh chưa có kết quả cuối. |
| MH12 / Minh Đức | Shipper xem COD đã thu; manager xác nhận thực nhận đủ từng đơn | Tách bàn giao tiền khỏi bàn giao hàng; trả/hoàn tiền không xóa hoặc bù trừ nghĩa vụ COD. |
| MH16 / Văn Đức | Snapshot đơn và hợp đồng giữ/xuất/nhận tồn hỗ trợ O3/O11/P6 | D4 là phụ thuộc transaction, không chuyển thao tác nhận/kiểm tra của manager sang checkout UI. |
| MH17 / Bảo | Nhận event giao thất bại, bàn giao và các mốc được chốt ở D7 | Recipient và deep link theo quyền hiện tại; nội dung không lộ dữ liệu riêng tư. |

Tại thời điểm P00.1, router chỉ có `/` trong `lib/app/router/app_router.dart`.
Các hàng gộp trong bảng trên chỉ là mô tả màn hình: tạo/phân công phải đọc
riêng O1a/O1b, P1a/P1b, R1a/R1b; MH09 nhận hàng theo O11a rồi kiểm tra
theo O11b; MH11 báo bàn giao theo R6a và MH15 nhận hàng theo R6b. Các mốc
này có actor, tiền điều kiện và tác dụng độc lập trong hợp đồng trạng thái.
Route đề xuất trong kế hoạch (`/shipper/tasks`, `/shipper/tasks/:taskId`,
`/shipper/tasks/:taskId/map`, `/cod`) chưa được đăng ký trong P00.1; mục P01.3
bên dưới ghi trạng thái mới sau tích hợp router.
P00.2 bên dưới xác định phạm vi MH18 theo yêu cầu hiện tại; provider bản đồ
vẫn chưa chọn và không được coi đã chốt qua bảng trạng thái P00.1.

## P00.2 — Route, quyền và hợp đồng tích hợp đề xuất

Tại P00.2, ngoại trừ `/`, các route dưới **chưa đăng ký**. Khi đó chờ Dung An tích hợp
router/go_router dùng chung; không tạo router, Supabase client hoặc theme riêng.
UUID lấy từ đối tượng thật, không dùng mã demo. `taskId`, `orderId`,
`returnRequestId` phải parse thành UUID trước truy vấn; sai định dạng hiển thị
lỗi đầu vào, không query; UUID hợp lệ vẫn phải qua kiểm tra quyền server.

| Màn / route đề xuất | Guard và nguồn dữ liệu / action |
| --- | --- |
| MH10 `/shipper/tasks` | Shipper từ profiles.role; list_my_delivery_tasks; lịch sử chỉ qua S4 nếu được duyệt |
| MH11 `/shipper/tasks/:taskId` | Shipper đang được phân công; get_my_delivery_task; allowed_actions theo kind/state, mọi write kiểm tra lại server |
| MH18 `/shipper/tasks/:taskId/map` | Cùng kiểm tra quyền live task MH11; destination_* đã lưu; history không cấp quyền map |
| MH12 `/cod` và query tùy chọn `orderId=UUID` | Shipper chỉ khoản của mình; manager được filter và confirm_cod_received; không customer; COD PK là order_id |
| MH09 `/manager/orders/:orderId` | Đề xuất phối hợp Bảo/Dung An; manager; create/assign/decide/receive_failed/inspect trong hợp đồng orders/task |
| MH15 `/manager/returns/:returnRequestId` | Đề xuất phối hợp Sơn/Dung An; manager; receipt/inspection/request và task cùng transaction server |
| MH17 `/notifications` | Authenticated theo quyền; link resolve bằng subject_type/id, chọn route theo role rồi đọc lại quyền đích |

Các tên API là đề xuất trong [api_contracts.md](api_contracts.md), không phải
endpoint đang có. Guard phải chờ session và role tải xong; lỗi/mất role không
render dữ liệu cũ. Logout/đổi user hủy subscription và invalidate cache scoped
theo user; đổi phân công reload quyền, xóa dữ liệu không còn được phép.
Back navigation hoặc notification cũ không khôi phục quyền task. Thiếu quyền
trả trạng thái lỗi/không truy cập, không chuyển sang demo success.

MH18 tập trung **điểm đến nhiệm vụ đã lưu**, không bắt buộc pin cửa hàng,
không chọn địa chỉ thay MH16, không GPS tracking. Không truyền contact/địa chỉ
qua route URL. Đọc task lại bằng UUID; thiếu tọa độ hoặc map/directions lỗi
thì giữ địa chỉ được phép đọc và báo lỗi/thử lại, không tạo tọa độ giả.
Provider, platform, license/key và interface maps với Văn Đức còn chờ chốt.
NT25 theo mô tả pin cửa hàng gốc cần điều chỉnh theo phạm vi yêu cầu này;
không khẳng định đã kiểm chứng toàn văn báo cáo gốc.

Theo đề xuất quyền P00.2, MH18 chỉ mở khi task đang được phân công hiện tại
và có status `assigned/accepted/in_transit`; task terminal chuyển sang history
tối thiểu và không mở bản đồ/contact. Task `failed/manager_action_required`
chỉ còn thao tác xử lý custody phù hợp, không giữ PII đích theo mặc định.
Đây là quyền đề xuất cần migration review; baseline chưa có bộ lọc status này.

Các screen-owned wrappers của Bảo/Sơn gọi nghiệp vụ task nội bộ trong một
transaction server, không gọi hai RPC client liên tiếp để giả transaction.
Auth/router, inventory, event recipients, returns/custody và schema S1–S4
còn chờ owner duyệt; xem bảng bàn giao P00.2 trong api_contracts.md.

## P01.1 — Nguồn đọc task đã triển khai trong migration

MH10/MH11 dùng projection `read_my_delivery_tasks(p_task_id uuid DEFAULT NULL)`;
item MH11 dùng `read_my_delivery_task_items(p_task_id uuid)`. Đây mới là lớp
SQL trong repository, chưa có UI/repository Flutter hoặc route nghiệp vụ.
Các list/get/pagination/version đầy đủ ở P00.2 chưa được triển khai.

MH18 chỉ nhận destination khi snapshot_scope=current (assigned/accepted/
in_transit đúng người). History/restricted có destination NULL nên không thể
dùng deep link để đọc vị trí. ID ngoài quyền trả 0 row, không dùng dữ liệu
route/cache cũ làm fallback. Đổi người/null trên cùng task thu hồi quyền ở
lần đọc tiếp theo; task cũ còn gán user chỉ mở projection lịch sử tối thiểu,
không mở item hoặc task mới cùng order/request. Plan item redelivery còn chờ
Sơn; source flag báo rõ chưa sẵn sàng, không giả hàng từ toàn bộ đơn.

Chi tiết quyền bảng gốc và giới hạn snapshot xem mục P01.1 trong
[api_contracts.md](api_contracts.md) và [database.md](database.md).

## P01.2 — Providers cho màn hình tương lai

Tại P01.2 đã có domain/DTO/read repository và Riverpod providers, chưa dựng
màn hình hoặc đăng ký route. MH10 dùng deliveryTasksProvider; MH11 dùng
deliveryTaskDetailsProvider(taskId); MH18 tương lai dùng destination của
snapshot current từ chính task đã đọc, không dựng store pin giả.
MH12 dùng codCollectionsProvider hoặc filteredCodCollectionsProvider với
filter shipperId/orderId; manager/shipper được kiểm tra qua profiles.role
trên server ở mỗi lượt đọc.

Consumers xử lý AsyncLoading, AsyncError(OperationalFailure), empty và data;
không hiện previous data khi provider đang tải lại hoặc session đổi. Các
provider này chỉ tải dữ liệu, không có nút/action accept/start/fail/complete/
confirm COD trong phase này. Chi tiết model/null/source và API thật xem
mục P01.2 trong [api_contracts.md](api_contracts.md).

## P01.3 — Route và khung điều hướng đã tích hợp

Đây là trạng thái hiện hành của router trong repository sau P01.3. Dùng duy
nhất appRouterProvider/GoRouter trong `lib/app/router/app_router.dart`, theme
hiện có và client/provider Supabase hiện có. Chưa có guard/shell auth của
Dung An trong repo trước phase này, nên guard chung nối trực tiếp lifecycle
P01.2 và profiles.role server; không dựng MH01/MH02 hay router auth thứ hai.

| Màn / route đã đăng ký | Quyền và recheck | Trạng thái giao diện |
| --- | --- | --- |
| MH10 `/shipper/tasks` | Chỉ shipper, role đọc từ profiles qua OperationalReadAccess | Outlet nền tảng, chưa triển khai danh sách/tìm/lọc nhiệm vụ |
| MH11 `/shipper/tasks/:taskId` | UUID hợp lệ, DeliveryRepository.getTask đọc đúng task qua P01.1/RLS; ID ngoài quyền hoặc task đổi người về `/` | Outlet chi tiết; history/restricted chỉ có quyền projection tối thiểu, không tự mở item/PII |
| MH18 `/shipper/tasks/:taskId/map` | UUID + cùng quyền task; chỉ snapshot_scope=current và destination có dữ liệu | Outlet bản đồ, chưa có provider map; điểm đến đã lưu, không bắt buộc pin cửa hàng |
| MH12 `/cod`, tùy chọn `?orderId=UUID` | Manager/shipper; nếu có orderId phải đọc được khoản COD đúng scope bằng CodRepository; rỗng/ngoài quyền về `/` | Outlet COD, chưa bảng tiền/đối soát hoặc thao tác xác nhận |
| MH17 `/notifications` | Authenticated với role customer/manager/shipper, recheck profile khi vào | Slot notificationRouteBuilderProvider để Bảo tích hợp; mặc định ghi rõ chưa tích hợp, không mô phỏng nội dung thông báo |

Một ShipperShell chung trong `lib/app/shells` có hai đích Nhiệm vụ/COD, dùng
theme hiện tại. Manager vào COD không có tab chỉ dành cho shipper. Nút
Thông báo giữ link `/notifications`; không tạo thêm mã màn hình. Child outlet
của feature không tự dựng Scaffold/theme/client hoặc tải dữ liệu nghiệp vụ.

Task UUID và query orderId được kiểm tra trước gọi backend; orderId lặp/không
hợp lệ hoặc encoding không hợp lệ hiện trạng thái lỗi đầu vào, không mở
outlet nghiệp vụ. Không truyền địa chỉ/contact/token qua URL. Không dùng
`from`, `redirect`, URL tuyệt đối hoặc dữ liệu query làm đích redirect.
Mất phiên/không đủ role/mất quyền task chỉ redirect về hằng local `/`.
Chưa redirect `/login` hoặc home role vì màn/route đó chưa có hợp đồng live.

Guard chạy lại theo navigation, refresh auth và sau imperative pop/back.
Backend timeout/lỗi/quyền chưa xác định đóng outlet và hiện lỗi/thử lại,
không chuyển sang fixture/demo. Khi user ID đổi (cả shipper A → shipper B),
protected navigator bị đưa về `/`; token refresh cùng user recheck URL hiện
tại. Boundary không render child nếu epoch không khớp. Providers P01.2 bỏ
cache user cũ; auth listener được giữ để theo dõi đăng nhập tiếp theo và
hủy khi router/container dispose. Chưa có Realtime subscription để giữ lại.

Auth UI của Dung An, nội dung MH17 của Bảo, business UI MH10/MH11/MH12,
map provider MH18 và backend live vẫn là dependency chưa nghiệm thu. Các
outlet nền tảng không được báo là bốn màn hoàn chỉnh. API ghi/RLS/migration
và dependency không đổi trong P01.3.
