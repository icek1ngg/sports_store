# Kế hoạch triển khai MH10 MH11 MH12 MH18 của Minh Đức

Kế hoạch bao quát giao diện, ViewModel, repository, xử lý server, phân quyền, kiểm thử và bàn giao bốn màn của Minh Đức. Thứ tự ưu tiên là tích hợp được luồng nhận hàng → giao thành công → thu COD → manager đối soát, sau đó hoàn thiện giao thất bại, thu hồi và giao lại. Đây là kế hoạch triển khai; các hạng mục dưới đây chưa được đánh dấu là đã hoàn thành.

## Căn cứ và hiện trạng

- Nguồn nghiệp vụ: Báo cáo nghiệp vụ cửa hàng thể thao phiên bản 3.0 ngày 29/09/2026, đặc biệt mục 4, 5, 6, 7, 8, 9, 10 và 11.
- Kiến trúc dùng chung: Flutter, Riverpod, go_router, Supabase; tổ chức feature-first MVVM theo `AGENTS.md`.
- Dự án đã có khởi tạo ứng dụng, theme, cấu hình Supabase và provider client dùng chung. Router mới có route `/`; chưa có bốn màn, ViewModel hoặc repository giao nhận/COD/bản đồ.
- Đã có ba migration nền và tài liệu schema/RLS. Có bảng nhiệm vụ, lần giao, COD, hàng trả, sự kiện và thông báo; chưa có RPC hoàn thành các nghiệp vụ giao nhận/COD. Không coi constraint là quy trình đã triển khai.
- Lần lập kế hoạch này đối chiếu mã nguồn và tài liệu trong repository, chưa xác minh trạng thái database cloud hoặc chạy ứng dụng.
- MH18 theo yêu cầu trước của bạn sẽ tập trung vào **địa điểm giao/nhận của nhiệm vụ**. Báo cáo gốc còn mô tả pin cửa hàng; ghi nhận khác biệt này trong đặc tả và điều chỉnh tiêu chí NT25 tương ứng. Cấu hình cửa hàng dùng chung vẫn có thể được bàn giao nếu luồng khác cần, không bắt buộc thêm pin cửa hàng vào UI của bạn.

## Phạm vi chịu trách nhiệm

| Màn hoặc phần dùng chung | Kết quả cần bàn giao |
| --- | --- |
| MH10 Danh sách nhiệm vụ | Danh sách được phân công, tìm kiếm, lọc trạng thái/loại nhiệm vụ, làm mới và mở đúng chi tiết |
| MH11 Chi tiết nhiệm vụ | Ba loại nhiệm vụ dùng chung một màn; nhận/xuất/bàn giao hàng, bắt đầu giao, thành công/thất bại, thu COD và báo sự cố theo quyền |
| MH12 Đối soát COD | Shipper xem tiền của mình; manager xem theo đơn/shipper và xác nhận đã nhận đủ từng khoản |
| MH18 Bản đồ giao nhận | Đọc điểm đến đã lưu, hiển thị bản đồ, gọi người nhận, mở chỉ đường và xử lý lỗi |
| Backend giao nhận | API tạo/phân công nhiệm vụ để MH09 và MH15 gọi; kiểm tra trạng thái, số lần giao và phân công hiện tại |
| Backend COD | Giao thành công và thu đủ tiền trong một transaction; chỉ manager xác nhận nhận đủ; chống ghi lặp |
| Tích hợp bản đồ | Abstraction trong `core/maps` để Văn Đức dùng cho MH16; bộ chọn vị trí MH16 vẫn thuộc Văn Đức |

Dialog xác nhận, báo thất bại và báo sự cố nằm trong MH11; hai giao diện theo role của MH12 vẫn là một màn. Không thêm màn quản lý shipper hoặc thay đổi tổng MH01–MH20.

## Phase 0 Chốt hợp đồng và dữ liệu tích hợp

**Mục tiêu:** nhóm dùng cùng định nghĩa trước khi xây backend và UI.

- [ ] Đối chiếu các bảng `delivery_tasks`, `delivery_attempts`, `cod_collections`, `orders`, `order_items`, `return_items`, `business_events`, `notifications` và `store_settings` sau cả ba migration.
- [ ] Chốt bảng chuyển trạng thái theo từng `kind`: `outbound`, `return_pickup`, `redelivery`. Phân biệt nhận nhiệm vụ, nhận hàng, bắt đầu vận chuyển, báo bàn giao và manager xác nhận đã nhận hàng.
- [ ] Chốt lúc tăng bộ đếm giao đi, lúc tạo `delivery_attempts` và xử lý retry. Không đếm thêm khi chỉ mở màn hoặc bấm lại; đổi shipper không reset số lần.
- [ ] Đề xuất mapping giao đi để chốt với nhóm: `accept_delivery_task` ghi **thực nhận hàng** (`accepted`, `accepted_at`) và xuất tồn một lần cho đơn trong cùng transaction; từ mốc này manager không còn được hủy ngoại lệ. `start_delivery_task` yêu cầu đã nhận hàng, đổi task sang `in_transit`, order sang `delivering`, ghi mốc bắt đầu và tăng bộ đếm đúng một lần. Bản ghi kết quả `delivery_attempts` được tạo khi kết thúc lần giao. Lần giao hai không xuất cùng hàng khỏi tồn lần nữa. Nếu cần hành động nhận nhiệm vụ trước thực nhận hàng thì phải có mốc riêng, không dùng `accepted_at` cho hai nghĩa.
- [ ] Chốt cách lưu thông báo shipper đã bàn giao hàng về cửa hàng mà chưa có manager xác nhận; không dùng một trạng thái để ngầm coi manager đã kiểm tra hoặc nhập lại tồn.
- [ ] Chốt route, tham số UUID, dữ liệu hiển thị, nhãn trạng thái, hành động hợp lệ, mã lỗi và request ID. Không hardcode mã NV001/DH001 từ mockup vào API.
- [ ] Chốt dữ liệu đọc tối thiểu cho shipper: snapshot nhiệm vụ, dòng hàng, tổng COD và ghi chú giao nhận. `delivery_tasks` đã có `destination_*` và `amount_to_collect_vnd`; ưu tiên dữ liệu này. Shipper không được đọc nguyên `orders`/`return_requests` hoặc thông tin ngân hàng/hoàn tiền.
- [ ] Chốt với Bảo API phân công/đổi shipper/giao lần hai/hoàn sớm và sự kiện thông báo; với Sơn API thu hồi/giao lại và hàng thực tế cần lấy; với Văn Đức thao tác xuất/nhận tồn trong transaction.
- [ ] Chốt với Dung An session, role guard và dữ liệu tài khoản demo. Chọn nhà cung cấp bản đồ, nền tảng demo và cách mở chỉ đường; kiểm tra tài liệu, chi phí/hạn mức, license và giới hạn key tại thời điểm triển khai.

**Tài liệu cập nhật:** `docs/screen_mapping.md`, `docs/business_states.md`, `docs/api_contracts.md`, `docs/database.md`. Ghi rõ thay đổi phạm vi MH18 so với đoạn bản đồ trong báo cáo.

**Điều kiện hoàn tất:** các API có input/output, role, tiền điều kiện, thay đổi dữ liệu, mã lỗi và quy tắc retry; các trạng thái không còn cách hiểu khác nhau giữa đơn, nhiệm vụ, COD và trả hàng.

## Phase 1 Xây model repository điều hướng và API đọc

**Mục tiêu:** bốn màn có nền tảng chung và đọc dữ liệu thật đúng quyền.

- [ ] Tạo domain model và repository contract trong `features/deliveries` và `features/cod`; giữ enum và đơn vị tiền/thời gian khớp database. Dùng model do feature sở hữu cung cấp, không tạo một bản Order khác cho shipper.
- [ ] Tạo projection dành cho danh sách/chi tiết nhiệm vụ từ snapshot `delivery_tasks` và dòng hàng được phép đọc. Dùng `amount_to_collect_vnd` đã được server tạo đúng từ đơn; chỉ thêm API đọc hạn chế khi thiếu dữ liệu thực sự, không join nguyên bảng đơn rồi nới RLS cho shipper.
- [ ] Tạo Supabase repository, mapper và Riverpod providers; chuẩn hóa lỗi hết phiên, không có quyền, nhiệm vụ đã đổi người, trạng thái đã thay đổi, dữ liệu không hợp lệ và lỗi mạng.
- [ ] Đề xuất route: `/shipper/tasks` (MH10), `/shipper/tasks/:taskId` (MH11), `/shipper/tasks/:taskId/map` (MH18), `/cod` (MH12 cho shipper/manager). Tích hợp tuần tự vào router chung với Dung An; không tạo router riêng.
- [ ] Tạo navigation shell cho shipper với Nhiệm vụ và Đối soát COD, dùng theme/widget chung. Điểm mở MH17 chỉ tích hợp, không triển khai lại màn của Bảo.
- [ ] Cài cơ chế xóa cache/subscription khi đăng xuất hoặc đổi tài khoản. Deep link luôn kiểm tra lại quyền ở backend.
- [ ] Rà soát và sửa policy/API đọc dòng hàng: policy nền đang kiểm tra tồn tại task từng được gán, có thể cho task lịch sử mở rộng quyền tới order/request đang giao cho người khác. Ràng buộc quyền chi tiết vào task/phân công hiện hành và trạng thái được phép. Chốt riêng quyền xem snapshot nhiệm vụ đã hoàn tất để MH10 vẫn có lịch sử hợp lệ; không dùng lịch sử đó để cấp quyền đọc dữ liệu của task mới. Kiểm thử đổi shipper, task hủy/kết thúc và deep link sau mất quyền.
- [ ] Chuẩn bị fixture phát triển đúng contract và tách rõ chế độ demo với dữ liệu thật; lỗi API không được tự chuyển thành thành công giả.

**Điều kiện hoàn tất:** hai shipper đăng nhập lần lượt chỉ đọc được phần của mình; dùng task ID không thuộc quyền bị từ chối; repository và ViewModel xử lý được loading/error/empty/data; có kiểm thử mapper, quyền và điều hướng liên quan.

## Phase 2 Hoàn thành MH10 và MH11 cho giao đi thành công

**Mục tiêu:** chạy được luồng giao hàng thật đầu tiên từ đơn do manager chuẩn bị/phân công.

- [ ] Backend tạo/phân công nhiệm vụ giao đi từ MH09, kiểm tra manager, đơn đã chuẩn bị, shipper hợp lệ và không có nhiệm vụ giao đi đang hoạt động khác. Đổi người chỉ khi còn được phép; tránh hai manager phân công đồng thời.
- [ ] Server giữ `delivery_tasks.amount_to_collect_vnd`, `cod_collections.expected_amount_vnd` và `orders.total_cod_vnd` bằng nhau cho giao đi. Đây là tính nhất quán liên bảng cần triển khai, schema nền chưa tự bảo đảm.
- [ ] MH10 hiển thị nhiệm vụ của shipper hiện tại; tìm mã đơn/tên người nhận; lọc loại nhiệm vụ và nhóm trạng thái. Chốt nhóm Chờ giao/Đang đi/Hoàn tất từ enum, không gộp mọi trạng thái còn lại thành Hoàn tất.
- [ ] Đếm số nhiệm vụ theo tập dữ liệu truy vấn có quyền; tìm kiếm/lọc/phân trang không chỉ áp dụng cho trang đầu. Làm mới sau thao tác và khi quay lại từ MH11.
- [ ] MH11 hiển thị snapshot người nhận, điện thoại, địa chỉ, ghi chú, hàng/biến thể/số lượng, lần giao và toàn bộ COD gồm phí 30.000 VND. Ảnh sản phẩm chỉ tải khi Storage policy cho phép; nếu chưa có quyền/ảnh thì dùng placeholder rõ ràng.
- [ ] Nhận hàng tại cửa hàng và xuất giao đúng một lần, tích hợp thao tác tồn của Văn Đức trong transaction server. Không tự nhận hàng chỉ vì mở chi tiết.
- [ ] RPC thực nhận hàng khóa order/task và cạnh tranh với RPC hủy của Bảo bằng cùng quy ước khóa/precondition: nếu hủy thắng thì nhận hàng bị từ chối; nếu nhận hàng thắng thì hủy bị từ chối. Xuất tồn và ghi custody không được tách thành hai request client.
- [ ] Chỉ cho bắt đầu vận chuyển sau khi đã nhận hàng. Nút hành động dựa trên `kind` và trạng thái, backend kiểm tra lại mọi điều kiện.
- [ ] Xác nhận giao thành công chỉ khi khách nhận toàn bộ hàng và shipper đã thu đủ. Server lấy số tiền chuẩn từ đơn; không tin số tiền hoặc shipper ID do client tự khai.
- [ ] Trong cùng transaction: khóa dữ liệu cần thiết, kiểm tra phân công/trạng thái, cập nhật task/order, ghi lần giao thành công và COD, ghi event/notification liên quan. Thất bại giữa chừng phải rollback.
- [ ] Gọi điện mở ứng dụng gọi, không tự thực hiện cuộc gọi. Bấm lặp hoặc timeout được retry bằng cùng request ID; backend trả lại kết quả cũ khi payload trùng.

**Điều kiện hoàn tất:** demo từ MH09 → MH10 → MH11 → giao thành công tạo đúng một lần giao, một khoản COD và một tập sự kiện; thu thiếu, thao tác sai thứ tự hoặc shipper khác đều bị từ chối.

## Phase 3 Hoàn thành MH12 cho cả shipper và manager

**Mục tiêu:** kết thúc luồng tích hợp đặt → giao → đối soát trước khi mở rộng các nhánh lỗi.

- [ ] Shipper xem khoản mình đã thu, tổng COD còn giữ và hai nhóm Chưa đối soát/Đã đối soát. Tổng còn giữ chỉ cộng khoản `collected` chưa `received`; không cộng khoản chưa thu.
- [ ] Hiển thị đúng mã đơn, số tiền, thời điểm thu, người thu và kết quả bàn giao. Sau khi đơn phát sinh trả hàng, khoản COD vẫn còn nguyên cho đến khi manager xác nhận nhận đủ.
- [ ] Manager dùng cùng MH12 để lọc theo shipper/đơn và xem chi tiết khoản thu; có thao tác xác nhận thực nhận đủ theo từng đơn.
- [ ] Backend xác nhận COD chỉ cho manager; khóa khoản thu, kiểm tra trạng thái và đủ toàn bộ tiền, ghi `received_by`/thời gian server/event/thông báo. Retry không ghi tiền hoặc thông báo hai lần.
- [ ] Shipper không có nút tự đối soát hoàn tất; dù gọi API trực tiếp cũng bị chặn. Không làm đối soát một phần, phiếu gộp hoặc tự bù trừ khoản hoàn tiền.
- [ ] Sau xác nhận, đồng bộ cả danh sách shipper và manager bằng invalidation/làm mới; nếu dùng Realtime phải kiểm tra policy và cleanup subscription.

**Điều kiện hoàn tất:** ví dụ 520.000 VND tiền hàng + 30.000 VND phí giao hiển thị 550.000 VND; chỉ manager chuyển khoản từ `collected` sang `received`; NT02, NT11, NT17 và NT18 liên quan COD đạt.

## Phase 4 Giao thất bại hoàn hàng và sự cố trên MH11

**Mục tiêu:** hoàn thiện ngoại lệ giao đi mà không sai số lần, tồn hoặc tiền.

- [ ] Dialog thất bại có lý do: không liên hệ được, khách hẹn lại, sai địa chỉ, từ chối nhận hoặc khác kèm mô tả; chỉ ghi khi đang giao.
- [ ] Lần đầu thất bại: ghi đúng một attempt, lý do/thời gian/shipper, đưa đơn về chờ quyết định manager và gửi cảnh báo tương ứng.
- [ ] API cho MH09 chọn lần hai hoặc hoàn sớm; shipper không tự mở lần giao tiếp theo. Đổi người vẫn giữ lịch sử và giới hạn theo đơn.
- [ ] Chốt bàn giao custody khi đổi shipper cho lần hai: ai đang giữ hàng, người mới đã thực nhận chưa và có cần bàn giao qua cửa hàng không. Ghi lịch sử/điều kiện phía server; không tự xuất tồn lại hoặc suy ra đã nhận hàng chỉ từ việc phân công người mới.
- [ ] Lần thứ hai thất bại: chuyển chờ hoàn về cửa hàng, từ chối lần thứ ba kể cả khi đổi task/shipper hoặc gọi API trực tiếp.
- [ ] Shipper báo bàn giao hàng về; manager nhận và kiểm tra qua luồng của Bảo. Chỉ hàng được xác nhận đạt chất lượng mới có thể nhập lại tồn, không restock ngay lúc giao thất bại hoặc báo đã về.
- [ ] Báo sự cố hỏng/mất/khác vào `business_events`, có actor/task/request ID/lý do; gửi manager. Không ghi sự cố hỏng/mất thành khách từ chối và không tự ghi bồi thường.
- [ ] Kiểm tra retry và các race: đổi phân công cùng lúc nhận hàng, bấm thất bại hai lần, hai yêu cầu kết thúc task đồng thời, manager nhận hàng hoàn hai lần.

**Điều kiện hoàn tất:** NT08, NT09, NT10, NT18 và NT24 đạt; không có COD thu thành công khi giao thất bại, không phát sinh lần ba hoặc tồn bán được khi hàng chưa được nhận/kiểm tra.

## Phase 5 Hoàn thiện thu hồi và giao lại trên MH10 MH11

**Mục tiêu:** dùng lại hai màn cho phần giao nhận trong quy trình trả hàng của Sơn.

- [ ] Cung cấp API tạo/phân công `return_pickup` và `redelivery` để MH15 gọi, kiểm tra manager và trạng thái yêu cầu trả. Liên kết request/task/order phải cùng một đơn.
- [ ] Hai loại task này giữ `amount_to_collect_vnd = 0` và `attempt_number = 1` theo schema hiện có; số 1 tại đây không biểu thị trần số lần thu hồi. Không ghi hai loại này vào `delivery_attempts`, bảng đó chỉ lưu kết quả giao đi.
- [ ] `return_pickup`: hiển thị danh sách và số lượng hàng thực tế cần thu; cho nhận hàng từ khách và báo bàn giao về cửa hàng. Không yêu cầu trả món chưa giao và không tự coi duyệt lấy hàng là duyệt hoàn tiền.
- [ ] Tách hai mốc thu hồi: `collect_return_items` ghi hàng thực nhận tại khách, giữ task đang vận chuyển và đổi return sang `returning_to_store`; `report_store_handover` chỉ báo bàn giao. Sau đó API nhận hàng của Sơn do manager gọi mới đổi task sang `returned_to_store` và return sang `under_inspection` trong cùng transaction. Nhập tồn/kết luận chất lượng là thao tác kiểm tra riêng của Sơn phối hợp inventory, không xảy ra tự động khi shipper lấy hàng.
- [ ] Ghi nhận lấy hàng thất bại và báo manager hẹn lại; không tự áp dụng giới hạn hai lần của giao đi cho nhiệm vụ này.
- [ ] Tách việc shipper ghi số lượng thực nhận với kết luận chất lượng/nhập lại tồn của manager; tránh hoàn tất task khi dữ liệu bàn giao chưa hợp lệ.
- [ ] `redelivery`: chỉ tạo từ nhánh bị từ chối sau kiểm tra; giao lại miễn phí, không thu COD lần hai. Thành công mới đóng yêu cầu theo kết quả từ chối sau kiểm tra.
- [ ] Giao lại thất bại giữ yêu cầu chờ manager giải quyết; thống nhất mapping enum `redelivery_failed`/`manager_action_required` với Sơn, không tự đóng yêu cầu.
- [ ] MH10 phân biệt ba loại nhiệm vụ; MH11 tự đổi nội dung/nút theo loại, không tạo thêm màn chi tiết. Shipper không thấy video/bank details/bằng chứng hoàn tiền nằm trên `return_requests`.

**Điều kiện hoàn tất:** NT12, NT15, NT16 và NT17 liên quan đạt; kiểm tra riêng trường hợp COD chưa nộp nhưng khách đã trả/được hoàn tiền: nghĩa vụ nộp COD vẫn đủ số ban đầu.

## Phase 6 Hoàn thiện MH18 và bàn giao tích hợp bản đồ

**Mục tiêu:** dẫn đúng tới điểm giao/nhận đã lưu mà vẫn dùng được khi dịch vụ bản đồ gặp lỗi.

- [ ] Tạo abstraction địa điểm, hiển thị bản đồ và mở chỉ đường trong `core/maps`; adapter theo provider đã chốt ở Phase 0. Thêm dependency/config đúng nền tảng và kiểm tra tài liệu API hiện hành khi triển khai.
- [ ] MH11 mở MH18 bằng `taskId`; MH18 đọc lại nhiệm vụ đúng quyền, lấy `destination_*` đã lưu. Không truyền nguyên dữ liệu cá nhân qua URL hoặc cho người dùng sửa địa chỉ nhiệm vụ.
- [ ] Hiển thị pin điểm đến, tên/số điện thoại người nhận, địa chỉ chi tiết, ghi chú, loại nhiệm vụ; có thao tác gọi, đưa bản đồ về điểm đến và mở chỉ đường bằng tọa độ.
- [ ] Chỉ đường mở ứng dụng/dịch vụ điều hướng ở điểm đã chọn; không cần xây route engine, tính khoảng cách/phí hoặc theo dõi vị trí shipper trong app.
- [ ] Nếu thiếu dữ liệu vị trí, tile/API lỗi hoặc không mở được ứng dụng chỉ đường: giữ địa chỉ hiển thị, báo lỗi phù hợp và cho thử lại/sao chép địa chỉ; không bịa tọa độ hoặc báo mở thành công giả.
- [ ] Khi nhiệm vụ đổi người hoặc session đổi, dừng cung cấp dữ liệu nhiệm vụ và chặn thao tác tiếp theo; không thêm lưu vị trí nền hay lịch sử hành trình.
- [ ] Bàn giao cho Văn Đức component/interface chọn điểm ở MH16 và tài liệu config. MH16 vẫn chịu trách nhiệm form đặt hàng; server vẫn kiểm tra tọa độ/địa chỉ thuộc Hà Nội, không dùng MH18 để thay validation đặt đơn.
- [ ] Kiểm thử trên nền tảng demo thật và luồng fallback khi không có app bản đồ phù hợp. UI dùng theme hiện tại, không thiết lập bảng màu riêng.

**Điều kiện hoàn tất:** NT25 theo phạm vi điểm nhiệm vụ đã điều chỉnh và NT26 liên quan shipper đạt; ba loại nhiệm vụ mở đúng điểm, không đọc nhiệm vụ ngoài quyền và không yêu cầu GPS nền.

## Phase 7 Kiểm thử tích hợp và bàn giao

**Mục tiêu:** chứng minh đủ UI, backend, quyền và dữ liệu cho bốn màn.

- [ ] Bổ sung SQL tests bên cạnh `supabase/tests/database_security.sql`: truy cập được/bị chặn theo role, phân công hiện tại, số lần giao, số tiền đầy đủ, transaction rollback và idempotency.
- [ ] Repository/ViewModel tests kiểm tra lỗi API, retry cùng request ID, cập nhật cache và đổi tài khoản. Widget tests tập trung hành động hợp lệ theo loại/trạng thái và MH12 theo role.
- [ ] Integration tests cho giao thành công → đối soát; thất bại lần một → đổi shipper → thất bại lần hai → nhận hoàn; thu hồi; giao lại miễn phí thành công/thất bại; mở task từ thông báo sau khi mất quyền; bản đồ lỗi.
- [ ] Đặc biệt kiểm tra thu COD và ghi giao thành công là nguyên tử; đối soát đồng thời chỉ ghi một lần; trả/hoàn tiền không xóa hoặc bù trừ COD.
- [ ] Kiểm tra race manager hủy ↔ shipper thực nhận hàng/bắt đầu giao; order/task/tồn phải có một kết quả nhất quán. Kiểm tra policy/API đọc sau đổi người, hủy hoặc kết thúc task, gồm lịch sử MH10 được phép xem và dữ liệu task mới phải bị chặn.
- [ ] Chuẩn bị dữ liệu demo có manager, hai shipper, khách, ba loại nhiệm vụ, COD chưa/đã đối soát và các nhánh lỗi. Không reset database dùng chung; dữ liệu kiểm thử có phạm vi riêng và cách dọn rõ ràng.
- [ ] Format Dart đã thay đổi, chạy `flutter analyze`, test liên quan và build nền tảng demo; `flutter pub get` khi đổi dependency. Ghi rõ check thực chạy và check chưa chạy.
- [ ] Cập nhật bốn tài liệu hợp đồng dùng chung, hướng dẫn cấu hình map, migration/RPC, tài khoản test và kịch bản demo; không ghi mật khẩu/secret vào repository.

**Điều kiện hoàn tất:** bốn màn chạy với backend thật; kịch bản trong phạm vi đạt; không còn placeholder nghiệp vụ hoặc thành công giả; lỗi/quyền được kiểm tra cả client và server; có hướng dẫn để thành viên khác chạy lại.

## Hợp đồng API cần đặc tả ở Phase 0

Tên dưới đây là **đề xuất**, chưa phải RPC đang có. Có thể gộp/tách sau khi chốt transaction và quyền; không triển khai chỉ dựa trên tên.

| Hợp đồng đề xuất | Caller và điều kiện chính | Kết quả và phạm vi |
| --- | --- | --- |
| `list_my_delivery_tasks`, `get_my_delivery_task` | Shipper; phân công hiện tại hoặc snapshot lịch sử được phép theo hợp đồng Phase 0 | Projection cần thiết, bộ lọc/phân trang/counts; lịch sử không mở rộng quyền tới task mới; không lộ dữ liệu tài chính riêng tư của yêu cầu trả |
| `assign_delivery_task` | Manager qua MH09/MH15; đơn/request đủ điều kiện | Tạo/phân công/đổi người hợp lệ; kiểm soát task đang hoạt động và số lần giao đi |
| `accept_delivery_task`, `start_delivery_task` | Shipper đang được phân công; đúng kind/trạng thái | Với outbound: accept ghi thực nhận + dispatch một lần và chặn hủy; start chuyển task/order sang đang giao và đếm lần giao một lần; mỗi action là transaction. Kind khác không gọi dispatch tồn của đơn |
| `complete_outbound_delivery` | Shipper; đang giao, nhận đủ hàng và đủ COD | Task/order/attempt/COD/event/notification cập nhật trong một transaction |
| `fail_delivery_task` | Shipper; task được phép báo thất bại, lý do hợp lệ | Xử lý riêng theo kind; chỉ outbound ghi lần giao đi và áp dụng trần hai lần |
| `report_delivery_incident`, `report_store_handover` | Shipper; task đang thuộc quyền, đúng giai đoạn | Ghi sự cố hoặc thông báo bàn giao; không tự xác nhận đã kiểm tra/nhập lại tồn |
| `collect_return_items`, `complete_redelivery` | Shipper; task/request hợp lệ | Lấy hàng tại khách chỉ ghi hàng thực nhận/đang hoàn về, không hoàn tất bàn giao tại cửa hàng; redelivery thành công phối hợp đóng yêu cầu, không COD mới |
| `receive_failed_delivery_return`, `receive_customer_return` | Manager; có hàng bàn giao và đúng luồng | API thứ nhất thuộc Bảo/orders; thứ hai thuộc Sơn/returns. Cùng gọi hợp đồng nhiệm vụ của Minh Đức trong transaction server; không tự ghi nhập tồn/quality hai lần |
| `list_cod_collections` | Shipper xem của mình; manager xem theo bộ lọc | Khoản thu và tổng chưa nộp đúng quyền; không mất nghĩa vụ khi đơn được trả |
| `confirm_cod_received` | Chỉ manager; đã thu và thực nhận đủ | Một lần xác nhận theo đơn, full amount, thời gian server, event và thông báo |

Mọi action ghi phải có business ID và request ID; identity/role lấy từ server. Hợp đồng phải định nghĩa retry cùng payload trả cùng kết quả, dùng lại ID với payload khác bị từ chối, và hai action trái nhau được tuần tự hóa bằng khóa/precondition. Rà soát cơ chế lưu idempotency hiện có rồi bổ sung constraint/ghi nhận cần thiết qua migration; không mặc định schema nền đã đủ cho mọi action.

## Phối hợp và quyền sửa file

| Thành viên | Minh Đức cung cấp | Cần nhận hoặc tích hợp |
| --- | --- | --- |
| Dung An | Route/role yêu cầu cho bốn màn | Session, role provider, guard và router dùng chung |
| Bảo | API nhiệm vụ, kết quả giao và COD | MH09 gọi phân công/giao lần hai/hoàn sớm; nhận hàng hoàn do giao đi thất bại thuộc orders; event/notification đúng người |
| Văn Đức | Abstraction map và cấu trúc địa điểm | Snapshot đặt hàng, thao tác xuất/nhập tồn có transaction và idempotency |
| Sơn | API thu hồi/giao lại và kết quả vận chuyển | Nhận hàng khách trả tại cửa hàng, trạng thái trả, danh sách thực tế cần thu, kiểm tra/nhập tồn và quyết định giao lại |

Minh Đức sở hữu `lib/features/deliveries/**`, `lib/features/cod/**`, phần map thống nhất trong `lib/core/maps/**`, tests tương ứng và migration giao nhận/COD mới. Models/repositories của orders, inventory và returns dùng hợp đồng chung; không sao chép sang feature của mình. Sửa `pubspec.yaml`, lockfile, router, shell, tài liệu hợp đồng và migration dùng chung phải tích hợp tuần tự để tránh ghi đè. Dùng Supabase client hiện có; không thêm client/theme riêng.

## Thứ tự thực hiện

**Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6 → Phase 7.** Contract bản đồ và component dùng chung cần chốt từ Phase 0; phần MH18 có thể làm song song sau Phase 1 nếu có người hỗ trợ, không làm chậm luồng giao → đối soát đầu tiên. Kiểm thử và tích hợp thực hiện ngay trong mỗi phase; Phase 7 là nghiệm thu tổng, không phải lúc mới bắt đầu test.

Mỗi phase chỉ chuyển sang hoàn tất khi có kết quả chạy/kiểm thử đúng phạm vi. Nếu dependency từ thành viên khác chưa có, có thể tiếp tục bằng fixture đánh dấu rõ để phát triển UI, nhưng ghi phần tích hợp là chưa hoàn thành.
