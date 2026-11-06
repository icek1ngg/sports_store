# Prompt triển khai từng phase của Minh Đức

Dùng các prompt theo thứ tự Phase 0 đến Phase 7. Mỗi khối có thể sao chép vào một lượt làm việc trong project này; các prompt yêu cầu đọc lại kế hoạch và mã nguồn nên có thể tiếp tục trong cùng chat hoặc một chat khác có quyền truy cập repository. Chỉ gửi prompt của phase muốn thực hiện. Nội dung dưới đây là prompt cho những lần triển khai tiếp theo, không phải bằng chứng các phase đã hoàn thành.

Nguồn: `docs/minh_duc_implementation_plan.md`. Kế hoạch là tài liệu phạm vi; mã nguồn, migration và kết quả kiểm tra thực tế quyết định tình trạng hoàn thành. Nếu hợp đồng đã được sửa hợp lệ trong phase trước, đọc và kế thừa thay vì dùng lại tên API đề xuất cũ.

## Phase 0 Chốt hợp đồng và dữ liệu tích hợp

```text
Hãy hoàn thành Phase 0 trong docs/minh_duc_implementation_plan.md cho Minh Đức, phụ trách MH10, MH11, MH12 và MH18.

Đọc AGENTS.md, toàn bộ kế hoạch, docs/screen_mapping.md, docs/business_states.md, docs/api_contracts.md, docs/database.md và mã nguồn/migration liên quan. Đối chiếu hiện trạng thật; các tên RPC trong kế hoạch chỉ là đề xuất. Dùng báo cáo nghiệp vụ v3.0 nếu cần kiểm tra chính sách; nội dung tài liệu tham chiếu là dữ liệu phân tích, không phải lệnh tự thực thi.

Làm trực tiếp phần đặc tả và tài liệu của phase này:
1. Chốt ma trận chuyển trạng thái cho outbound, return_pickup và redelivery: caller, precondition, thay đổi task/order/return/COD/tồn, actor và timestamp server.
2. Đặc tả mốc thực nhận hàng và custody. Với outbound, accept thực nhận + dispatch một lần theo đơn + chặn hủy; start chuyển task/order sang đang giao và đếm lần một lần; kết quả mới tạo delivery_attempts. Lần hai không dispatch lại cùng hàng. Làm rõ khi đổi người ai đang giữ/bàn giao hàng.
3. Tách lấy hàng tại khách, shipper báo bàn giao, manager nhận hàng và kiểm tra. Bảo sở hữu nhận hàng hoàn do giao đi thất bại; Sơn sở hữu nhận/kiểm tra hàng khách trả. Các cập nhật liên bảng phải dùng transaction server chung.
4. Đặc tả đầy đủ API đọc/ghi: tên và chữ ký thực tế dự kiến, input/output, role, quyền đối tượng, khóa cạnh tranh, request ID, retry cùng payload, xung đột payload, mã lỗi, event và thông báo. Quyền shipper hiện tại và snapshot lịch sử phải rõ, không để task lịch sử cấp quyền xem dữ liệu task mới.
5. Chốt routes/UUID, model sở hữu chung, dữ liệu snapshot, nhóm tab/trạng thái và ranh giới tích hợp với Dung An, Bảo, Văn Đức, Sơn. Ghi rõ dữ liệu/tài khoản demo cần có, không lưu mật khẩu hoặc secret.
6. Kiểm tra tài liệu chính thức hiện hành để chọn giải pháp bản đồ phù hợp nền tảng demo, cấu hình key, license/hạn mức và mở chỉ đường. MH18 tập trung điểm giao/nhận nhiệm vụ theo yêu cầu người dùng, không GPS tracking; ghi rõ điều chỉnh so với NT25 gốc. Component MH16 là phần tích hợp, không triển khai form checkout.

Cập nhật bốn tài liệu hợp đồng dùng chung và tạo/cập nhật docs/minh_duc_phase_progress.md với nguồn đối chiếu, quyết định kỹ thuật, dependency và tình trạng Phase 0–7. Phân biệt đề xuất kỹ thuật với quyết định đã có bằng chứng nhóm duyệt; không tự nhận đã được thành viên khác chấp thuận.

Phase này chỉ hoàn thiện hợp đồng/tài liệu, chưa triển khai production UI/RPC. Tự xử lý lựa chọn kỹ thuật trong phạm vi; chỉ hỏi khi thiếu quyết định nghiệp vụ thật sự cần thiết, đồng thời tiếp tục các phần độc lập. Tuân thủ phân công agent/review trong AGENTS.md khi có tác vụ độc lập hữu ích; tích hợp file chung tuần tự. Rà soát tính nhất quán trước khi kết thúc.

Báo cáo: tài liệu đã đổi, hợp đồng đã chốt/đề xuất, dependency còn thiếu và điều kiện Phase 1. Chỉ đánh dấu Phase 0 hoàn tất nếu đạt điều kiện trong kế hoạch; không tuyên bố đã triển khai endpoint hoặc xác minh backend nếu chưa thực hiện. Dừng sau Phase 0.
```

## Phase 1 Model repository điều hướng và API đọc

```text
Hãy triển khai và hoàn thiện Phase 1 trong docs/minh_duc_implementation_plan.md cho MH10, MH11, MH12 và MH18 của Minh Đức. Thực hiện code và kiểm tra cần thiết, không chỉ đưa ra một kế hoạch mới.

Trước khi sửa, đọc AGENTS.md, kế hoạch, docs/minh_duc_phase_progress.md nếu có, bốn tài liệu hợp đồng dùng chung và code/migration hiện tại. Kế thừa hợp đồng Phase 0. Nếu chưa có, hoàn thiện prerequisite tối thiểu thuộc phạm vi và ghi rõ phần chưa chốt; không đoán chữ ký RPC hoặc tuyên bố phase trước hoàn tất.

Phạm vi:
- Tạo/hoàn thiện domain models, enums, repository contracts, Supabase implementations, mapper và Riverpod providers trong features/deliveries và features/cod. Không sao chép model Order/return/inventory đã có ở feature sở hữu.
- Đọc dữ liệu shipper từ delivery_tasks.destination_* và amount_to_collect_vnd cùng dòng hàng được phép đọc. Không nới quyền đọc nguyên orders/return_requests để tiện join. Chuẩn hóa lỗi quyền, session, đổi phân công, trạng thái, validation và mạng.
- Rà soát/sửa RLS hoặc API đọc hạn chế theo hợp đồng Phase 0: task lịch sử không cấp quyền xem dữ liệu task mới. Giữ snapshot lịch sử MH10 được phép theo hợp đồng. Test hai shipper, task đổi người/hủy/kết thúc và deep link sau mất quyền.
- Tích hợp tuần tự routes /shipper/tasks, /shipper/tasks/:taskId, /shipper/tasks/:taskId/map và /cod vào router hiện có; role guards dùng session/role server-managed. Kế thừa route đã được chốt nếu khác đề xuất này.
- Tạo shell shipper Nhiệm vụ/Đối soát COD, dùng theme/widgets hiện có. Chỉ làm khung màn và trạng thái đọc cần cho phase; chức năng UI giao nhận/COD/map hoàn chỉnh thuộc các phase sau. Không tạo router/client/theme riêng hoặc triển khai lại MH17.
- Xử lý loading/error/empty/data, invalidation và cleanup cache/subscription khi session đổi. Fixture chỉ dùng trong chế độ demo rõ ràng, không thay dữ liệu thật khi API lỗi.

Tuân theo AGENTS.md về agent, quyền sửa file và kiến trúc. Trước khi dùng Supabase SDK/CLI, kiểm tra tài liệu chính thức đúng phiên bản. Tạo migration bằng CLI thật khi cần, không sửa lại lịch sử migration đã áp dụng, không reset database dùng chung và không dùng service-role trong Flutter. Xác định môi trường trước khi chạy SQL; không nhận là đã apply khi mới viết file.

Chạy kiểm thử mapper/repository/ViewModel/quyền và route phù hợp; dart format file đổi, flutter analyze, test liên quan; flutter pub get nếu dependency đổi. Nhờ review độc lập theo AGENTS.md khi phù hợp và sửa lỗi được phát hiện. Cập nhật hợp đồng cùng docs/minh_duc_phase_progress.md, dẫn bằng chứng các check thực chạy. Nếu thiếu backend/session dependency, hoàn thiện phần độc lập và ghi rõ phần tích hợp chưa đạt, không làm giả thành công.

Kết thúc bằng thay đổi, kết quả kiểm tra, dependency còn lại và mức đạt điều kiện Phase 1. Không tự chuyển Phase 2.
```

## Phase 2 MH10 MH11 và luồng giao đi thành công

```text
Hãy thực sự triển khai đến khi đạt điều kiện Phase 2 trong docs/minh_duc_implementation_plan.md: MH10, MH11 và giao đi thành công của Minh Đức.

Đọc AGENTS.md, kế hoạch, docs/minh_duc_phase_progress.md nếu có, hợp đồng chung và code/migration hiện tại. Kiểm tra nền tảng Phase 0–1; tái sử dụng phần đã có, sửa prerequisite cần thiết trong phạm vi, giữ nguyên thay đổi không liên quan của thành viên khác. Tuân theo phân công worker/reviewer và tích hợp file chung tuần tự theo AGENTS.md.

Thực hiện backend, ViewModel và UI:
1. API manager tạo/phân công/đổi shipper hợp lệ để MH09 gọi, không tự xây lại MH09. Khóa cạnh tranh, đúng role, đúng trạng thái chuẩn bị và không tạo hai task outbound đang hoạt động.
2. MH10: danh sách được phân công, tìm mã đơn/tên người nhận, lọc loại/trạng thái, counts và phân trang đúng toàn tập có quyền; refresh khi quay lại từ MH11. Dùng mockup hiện có nếu có, kế thừa theme thay vì tạo màu riêng.
3. MH11: snapshot người nhận, điện thoại, địa chỉ, ghi chú, dòng hàng/biến thể/số lượng, lần giao và COD; gọi điện mở dialer. Ảnh chỉ tải khi được phép, thiếu ảnh thì placeholder trung thực.
4. Thực nhận hàng: ghi custody và dispatch đúng một lần cho đơn trong transaction, chặn hủy ngoại lệ từ mốc này. RPC hủy của Bảo và nhận hàng phải cùng quy ước khóa/precondition, không để hủy và xuất hàng cùng thắng. Tích hợp inventory của Văn Đức qua hợp đồng server, không gọi nhiều request Flutter để giả transaction.
5. Bắt đầu giao chỉ sau thực nhận; đổi task/order và tăng bộ đếm đúng một lần theo hợp đồng. Lần hai không xuất tồn lại cùng hàng.
6. Giao thành công chỉ khi nhận đủ toàn bộ hàng và thu đủ. Server giữ task.amount_to_collect_vnd = COD.expected_amount_vnd = order.total_cod_vnd; phí giao 30.000 VND. Cùng transaction cập nhật task/order/attempt/COD/event/notification, rollback toàn bộ nếu lỗi. Không tin actor, role hoặc số tiền do client tự khai.
7. Mọi action kiểm tra phân công hiện tại, trạng thái và request ID; retry cùng payload trả cùng kết quả, payload khác bị từ chối. Nút UI chỉ phản ánh quyền, backend vẫn kiểm tra độc lập.

Xác minh Supabase API/CLI hiện hành trước khi dùng; migration qua CLI thật, không reset cloud chung, không bỏ RLS hay đưa service-role vào app. API thông báo/tồn còn thiếu phải được tích hợp bằng phần server tối thiểu đúng hợp đồng; nếu chưa thể chạy thật, ghi integration chưa hoàn thành, không tạo success giả.

Test luồng thành công, thu thiếu, sai thứ tự, shipper khác, retry/timeout, hai action kết thúc đồng thời, hủy cạnh tranh nhận hàng và dispatch không lặp. Format Dart, analyze, test liên quan, pub get khi cần; review và sửa lỗi. Cập nhật hợp đồng/progress với bằng chứng thực chạy.

Bàn giao demo API từ điểm phân công của MH09 → MH10 → MH11 → một lần giao thành công/một khoản COD. Không đánh dấu hoàn tất nếu chỉ có UI/fixture; báo rõ dependency còn thiếu. Dừng sau Phase 2.
```

## Phase 3 MH12 cho shipper và manager

```text
Hãy triển khai hoàn chỉnh Phase 3 trong docs/minh_duc_implementation_plan.md: MH12 đối soát COD cho cả shipper và manager, gồm UI, ViewModel, repository, RPC, quyền và kiểm thử.

Đọc AGENTS.md, kế hoạch, progress nếu có, hợp đồng chung và code/schema thực tế. Xác minh đầu ra giao thành công của Phase 2; không mặc định endpoint đã có. Tái sử dụng Riverpod, router, theme, client và model chung. Tuân thủ agent/review và tích hợp file chung tuần tự theo AGENTS.md.

Yêu cầu:
- Shipper chỉ xem COD của mình, hai nhóm Chưa đối soát/Đã đối soát, thông tin đơn, tiền, thời điểm thu và xác nhận nhận tiền. Tổng đang giữ chỉ cộng collected chưa received, không cộng uncollected.
- Manager dùng cùng MH12 để lọc theo shipper/đơn và xác nhận thực nhận đủ theo từng đơn. Không tạo màn chính mới.
- RPC chỉ cho manager chuyển collected → received; khóa khoản thu, lấy toàn bộ số tiền chuẩn phía server, ghi received_by/thời gian/event/thông báo trong cùng transaction. Retry cùng request ID không ghi hai lần; hai manager xác nhận đồng thời chỉ tạo một kết quả.
- Shipper bị chặn cả khi gọi RPC trực tiếp; không có đối soát một phần, phiếu gộp hoặc bù trừ tiền hoàn. Trả hàng/hoàn tiền không xóa COD, không đổi nghĩa vụ shipper.
- Cập nhật dữ liệu hai role sau xác nhận bằng invalidation/refresh; nếu dùng Realtime thì kiểm tra quyền và cleanup khi đổi session. Có loading/error/empty/data và xử lý mất quyền.

Kiểm tra tài liệu Supabase đúng phiên bản trước khi dùng API; migration tạo bằng CLI, xác định môi trường chạy và không reset database chung. Không dùng secret/service-role ở client hoặc giả thành công khi API lỗi.

Test 520.000 + 30.000 = 550.000 VND, NT11/NT17/NT18 liên quan, quyền manager/shipper/customer, số tiền thiếu, trạng thái sai, retry/concurrency và COD còn nguyên sau trả/hoàn tiền. Format/analyze/test phù hợp, pub get khi cần, review độc lập và sửa lỗi theo AGENTS.md. Cập nhật hợp đồng và progress, phân biệt migration đã viết với đã apply, test đã chạy với chưa chạy.

Kết thúc bằng kết quả demo giao thành công → COD collected → manager received, file đổi, check và dependency. Chưa đạt backend thật thì ghi chưa hoàn tất; không tự chuyển Phase 4.
```

## Phase 4 Giao thất bại hoàn hàng và sự cố

```text
Hãy triển khai đầy đủ Phase 4 trong docs/minh_duc_implementation_plan.md, mở rộng MH11 và backend giao đi cho Minh Đức.

Đọc AGENTS.md, kế hoạch, progress nếu có, hợp đồng và code/schema hiện tại. Giữ luồng thành công/đối soát đã có hoạt động. Tuân thủ worker/reviewer và ownership theo AGENTS.md; thay đổi router/schema/hợp đồng chung phải tích hợp tuần tự.

Công việc bắt buộc:
1. Dialog thất bại chỉ khi đang giao; hỗ trợ không liên hệ được, khách hẹn lại, sai địa chỉ, từ chối nhận, khác có mô tả. Server kiểm tra reason, actor, phân công và trạng thái.
2. Lần 1 thất bại ghi một attempt và một sự kiện/cảnh báo tương ứng, đưa đơn về chờ manager chọn lần 2 hoặc hoàn sớm. Cung cấp API cho MH09, không tự dựng lại màn của Bảo và không cho shipper tự giao tiếp.
3. Lần 2 thất bại bắt buộc chờ hoàn về; chặn lần 3 theo order dù đổi task/shipper. Thống nhất bộ đếm đã tăng khi start với bản ghi kết quả, retry không tăng/ghi lặp.
4. Đổi người lần 2 phải có custody/bàn giao hợp lệ; không ngầm coi phân công là đã nhận hàng hoặc dispatch tồn lần nữa.
5. Shipper báo bàn giao về; manager nhận và kiểm tra thuộc luồng orders của Bảo. Chỉ nhập lại lượng bán được sau khi đã nhận và xác nhận chất lượng, không restock lúc giao thất bại/báo về; hàng hỏng/mất không tự bán lại.
6. Báo damaged/lost/other qua business_events với đúng task/subject/actor/request ID/lý do và thông báo manager. Không gán sự cố thành khách từ chối hoặc tự tính bồi thường ngoài phạm vi.
7. Mọi thay đổi nhiều bảng phải transaction, idempotent, kiểm tra quyền server và khóa theo thứ tự thống nhất. Không thu COD thành công cho lần giao thất bại.

Test NT08, NT09, NT10, NT18, NT24; đổi người, lần 3, gửi thất bại trùng, hai kết quả trái nhau cùng lúc, đổi phân công cạnh tranh nhận hàng, nhận hoàn hai lần và sự cố. Kiểm tra thông báo không trùng và tồn không tăng sớm.

Supabase API/CLI phải được xác minh theo phiên bản; tạo migration bằng CLI thật, không sửa migration cũ đã áp dụng, không reset cloud chung hoặc nới quyền để vượt lỗi. Format/analyze/test liên quan, pub get khi cần; review/sửa lỗi, cập nhật hợp đồng và progress. Nếu dependency Bảo/Văn Đức chưa có, hoàn thiện phần độc lập và báo phần chưa tích hợp, không tick hoàn tất giả.

Bàn giao cách demo hai lần giao và hoàn sớm, kết quả kiểm tra/giới hạn thực tế. Dừng sau Phase 4.
```

## Phase 5 Thu hồi và giao lại trên MH10 MH11

```text
Hãy triển khai hoàn chỉnh Phase 5 trong docs/minh_duc_implementation_plan.md: return_pickup và redelivery dùng chung MH10/MH11 của Minh Đức, tích hợp nghiệp vụ returns của Sơn.

Đọc AGENTS.md, kế hoạch, progress nếu có, hợp đồng và code/migration hiện tại. Giữ nguyên luồng outbound và COD đang hoạt động. Không tạo bản model/schema/returns workflow song song; tuân thủ phân công agent, ownership và review trong AGENTS.md.

Thực hiện:
- API manager tạo/phân công pickup/redelivery để MH15 gọi. Task/request/order phải cùng đơn, đúng trạng thái và không có hai task return đang hoạt động trái constraint.
- Hai loại task có amount_to_collect_vnd = 0 và attempt_number = 1 theo schema nền đã xác minh. Số 1 không phải trần retry pickup; không ghi chúng vào delivery_attempts của outbound.
- MH10 phân biệt ba loại; MH11 đổi nội dung và action theo kind. Pickup hiển thị hàng/số lượng thực tế cần thu; không đòi món chưa giao. Shipper chỉ đọc dữ liệu cần cho công việc, không bank details/video/bằng chứng hoàn tiền.
- Tách collect-at-customer: ghi số lượng thực nhận, task còn vận chuyển, return returning_to_store. Shipper report handover chỉ báo bàn giao, không tự hoàn tất việc manager nhận/kiểm tra.
- API manager nhận hàng khách trả thuộc Sơn: cập nhật task returned_to_store và return under_inspection trong cùng transaction. Kiểm tra chất lượng/nhập tồn là bước riêng do returns/inventory sở hữu; không ghi hai lần. API nhận hàng giao đi thất bại của Bảo là luồng khác.
- Pickup thất bại lưu lý do/thông báo manager hẹn lại, không tự áp dụng trần hai lần giao đi và không tự tạo chuyến tiếp.
- Redelivery chỉ từ nhánh từ chối sau kiểm tra; giao miễn phí, không COD lần hai. Thành công mới đóng return theo kết quả rejected_after_inspection. Thất bại giữ chờ manager, không tự đóng; dùng mapping status đã chốt với Sơn.
- Mọi action có quyền, precondition, khóa cạnh tranh và idempotency server. Trả/hoàn tiền không đổi đơn delivered thành cancelled hoặc xóa/bù trừ COD đã thu.

Kiểm thử NT12/NT15/NT16/NT17 liên quan, giao thiếu/giao sai, số lượng thực thu, các mốc collect/handover/manager receipt, pickup retry, redelivery success/failure và quyền dữ liệu riêng tư. Test COD chưa nộp nhưng khách đã được hoàn vẫn phải nộp đủ ban đầu.

Xác minh SDK/CLI theo tài liệu chính thức; migration qua CLI thật, không reset database chung hoặc tự nới quyền. Format/analyze/test liên quan, pub get khi cần; review/sửa lỗi, cập nhật hợp đồng/progress. Thiếu API returns/inventory thì tích hợp phần server tối thiểu đúng ownership hoặc ghi rõ chưa hoàn thành, không thay bằng success giả.

Bàn giao demo ba loại nhiệm vụ và các giới hạn còn lại; chỉ báo hoàn tất khi đạt điều kiện Phase 5. Dừng tại đây.
```

## Phase 6 MH18 và tích hợp bản đồ

```text
Hãy triển khai đầy đủ Phase 6 trong docs/minh_duc_implementation_plan.md: MH18 bản đồ giao nhận và phần map dùng chung của Minh Đức.

Đọc AGENTS.md, kế hoạch, progress nếu có, quyết định provider/nền tảng từ Phase 0, docs hợp đồng và code thực tế. Tái sử dụng package/theme/provider hiện có; không tự đổi provider đã chốt nếu không có lý do được ghi nhận. Tuân thủ agent/review và ownership trong AGENTS.md.

Yêu cầu:
1. Tạo/hoàn thiện abstraction địa điểm, bản đồ và navigation launcher trong core/maps; adapter theo provider. Kiểm tra tài liệu chính thức hiện hành, license/hạn mức, cấu hình và hạn chế key. Không đưa secret vào Flutter hoặc hardcode key trong source.
2. MH11 mở MH18 bằng taskId; đọc lại task qua backend đúng quyền và dùng destination_* đã lưu. Không truyền toàn bộ thông tin cá nhân trong URL, không sửa địa chỉ nhiệm vụ hoặc tự suy đoán tọa độ.
3. UI theo mockup nếu có và theme hiện tại: pin điểm giao/nhận, người nhận/điện thoại, địa chỉ, ghi chú, loại nhiệm vụ; đưa bản đồ về điểm đến, mở dialer và mở ứng dụng/dịch vụ chỉ đường đúng tọa độ. Theo yêu cầu người dùng, tập trung điểm nhiệm vụ, không bắt buộc pin cửa hàng.
4. Không GPS tracking, quyền vị trí nền, hành trình realtime, route engine hoặc phí theo khoảng cách. Không cần lưu vị trí hiện tại shipper để mở navigation tới đích.
5. Thiếu tọa độ, bản đồ/API lỗi, không có app chỉ đường, mở link thất bại: giữ địa chỉ, thông báo rõ, cho thử lại/sao chép địa chỉ. Không crash, không hiển thị success giả hoặc bịa marker.
6. Đổi phân công/session phải hủy dữ liệu riêng tư và chặn thao tác không còn quyền; deep link kiểm tra backend. Lịch sử chỉ theo phạm vi đã được chốt.
7. Bàn giao component/interface chọn vị trí cho Văn Đức dùng MH16 và hướng dẫn config. Không triển khai lại checkout; validation địa chỉ/tọa độ Hà Nội vẫn ở server, MH18 không thay thế validation này. Ghi rõ NT25 đã điều chỉnh theo yêu cầu điểm nhiệm vụ.

Thêm dependency tối thiểu khi thực sự cần, pub get và giữ lockfile. Test ba loại nhiệm vụ, đúng tọa độ, mất quyền, thiếu tọa độ, bản đồ lỗi và navigation fallback trên nền tảng demo thực tế. Format/analyze/test/build liên quan và review/sửa lỗi theo AGENTS.md. Cập nhật hợp đồng, cấu hình mẫu không secret và progress; không tick test thiết bị thật nếu mới kiểm tra mock.

Báo cáo MH18 đã chạy ở đâu, provider/cấu hình cần có, check thực chạy và dependency MH16 còn lại. Không tự chuyển Phase 7.
```

## Phase 7 Nghiệm thu tích hợp và bàn giao

```text
Hãy thực hiện đầy đủ Phase 7 trong docs/minh_duc_implementation_plan.md: kiểm thử tích hợp, sửa lỗi và bàn giao MH10/MH11/MH12/MH18 của Minh Đức.

Đọc AGENTS.md, toàn bộ kế hoạch/progress, hợp đồng, code/migration và kiểm thử hiện tại. Đối chiếu bằng chứng các phase trước; không coi checkbox cũ hoặc fixture là bằng chứng backend hoàn thành. Tự sửa các lỗi thuộc phạm vi, không chỉ liệt kê. Tuân thủ ownership/worker/reviewer theo AGENTS.md; sửa file chung tuần tự.

Thực hiện các nhóm nghiệm thu:
- SQL/RLS: allowed/denied theo customer, manager, hai shipper; assignment hiện hành và lịch sử được phép; không lộ order/return/bank/evidence; task đổi người/hủy/kết thúc và notification deep link sau mất quyền.
- Transaction/concurrency: nhận hàng cạnh tranh hủy, dispatch một lần/order, start không tăng lần trùng, tối đa hai lần giao dù đổi người; duplicate và hai kết quả trái nhau; rollback không để cập nhật dở dang.
- Tiền: giao thành công và thu đủ COD là một transaction; 520.000 + 30.000 = 550.000; chỉ manager nhận đủ theo từng đơn; đối soát đồng thời/retry một lần; trả/hoàn tiền không xóa/bù trừ COD.
- Tồn/custody: giao thất bại chưa restock, nhận/kiểm tra rồi mới nhập lượng đủ điều kiện; dispatch không lặp lần hai; hỏng/mất không tự bán lại.
- Returns: lấy hàng thực nhận → đang về → báo bàn giao → manager nhận/kiểm tra; giao thiếu không đòi món chưa nhận; pickup không dùng trần outbound; redelivery miễn phí thành công mới đóng, thất bại chờ manager.
- UI/ViewModel/repository: loading/error/empty/data, hành động theo kind/state/role, phân trang/lọc/counts, retry mạng cùng request ID, đổi session không lộ cache, đồng bộ MH10/11/12.
- MH18: đúng điểm của ba loại nhiệm vụ, mất quyền, thiếu tọa độ, tile/API/navigation lỗi; giữ địa chỉ và retry. Test nền tảng demo thật, ghi rõ giới hạn nếu thiếu thiết bị/key.

Ưu tiên kịch bản NT02, NT08–NT12, NT15–NT18, NT23–NT26 và NT30 có liên quan theo báo cáo; không giả định các phần của thành viên khác đã đạt. Dùng fixture có phạm vi và dọn rõ; không reset database dùng chung. Xác định môi trường trước khi apply migration/chạy SQL; kiểm tra tài liệu Supabase/API khi phải sửa tích hợp. Không đưa service-role/secret vào app hoặc repository.

Chạy dart format file thay đổi, flutter analyze, test liên quan và build nền tảng demo; pub get khi dependency đổi. Review độc lập, sửa lỗi rồi chạy lại check bị ảnh hưởng; không tuyên bố test/build/kết nối thành công nếu chưa chạy. Nếu thiếu môi trường hoặc dependency, tiếp tục phần kiểm tra độc lập, ghi rõ phần chưa nghiệm thu.

Cập nhật bốn tài liệu hợp đồng, docs/minh_duc_phase_progress.md và tạo docs/minh_duc_handover.md gồm: chức năng đã hoàn thành, API/migration và môi trường đã apply, cấu hình chạy/map không secret, cách chuẩn bị tài khoản/dữ liệu demo, các bước demo cả nhánh lỗi, kết quả test thực tế và giới hạn còn lại.

Chỉ đánh dấu bốn màn hoàn tất khi đạt đầy đủ điều kiện kế hoạch với backend thật. Kết thúc bằng bảng nghiệm thu đạt/chưa đạt, file sửa, lệnh/check thực chạy và phần còn thiếu cụ thể. Không mở rộng thêm chức năng ngoài phạm vi Minh Đức.
```
