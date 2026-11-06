# Kế hoạch triển khai phần Văn Đức

> Cập nhật 27/10/2026: MH16 và backend đặt hàng đã được hoàn thiện theo
> [bàn giao hiện hành](van_duc_completion.md). Các bảng “hiện trạng” dưới đây
> giữ lịch sử lập kế hoạch ngày 24/10, không phải danh sách thiếu việc mới nhất.

Ngày lập: 24/10/2026. Phạm vi: MH04, MH05, MH06 và MH16.

Cập nhật sau triển khai MH06 ngày 24/10/2026: cart đã có domain/data/ViewModel,
UI, route và điểm nối MH05; xem kết quả kiểm tra hiện hành trong
[hướng dẫn chạy](supabase_catalog_guide.md). Bảng hiện trạng và checklist mốc
bên dưới ghi baseline lúc lập kế hoạch, không thay thế trạng thái cập nhật này.
Tại mốc 24/10, MH16 và RPC đặt đơn chưa triển khai; kết quả hoàn thiện ngày
27/10 được cập nhật trong tài liệu bàn giao ở đầu trang.

Mục tiêu là hoàn thiện luồng khách xem sản phẩm → chọn biến thể → giỏ hàng →
đặt COD → xem đơn ở MH07, rồi bàn giao đơn/tồn đúng hợp đồng để nhóm nối giao
hàng và đối soát. Kế hoạch này chưa phải xác nhận API đã triển khai hoặc các
chủ sở hữu khác đã chấp nhận hợp đồng.

## 1. Hiện trạng được kiểm tra trong repository

| Phần | Hiện trạng | Việc tiếp theo |
| --- | --- | --- |
| Nền ứng dụng | Đã có Flutter, Riverpod, go_router, theme và Supabase client dùng chung | Kế thừa nền hiện tại |
| MH04 | Đã có model, repository Supabase, ViewModel, danh sách, tìm kiếm, lọc danh mục và phân trang | Kiểm tra lại code, test và demo thực tế |
| MH05 | Đã có chi tiết, chọn biến thể/số lượng; nút thêm giỏ đang bị vô hiệu hóa | Nối CartRepository và trạng thái ghi khi MH06 sẵn sàng |
| MH06 | `features/cart` mới có khung thư mục | Triển khai domain, data, ViewModel, UI và route |
| MH16 | `features/checkout` mới có khung thư mục | Triển khai backend đặt đơn trước khi nối hành động đặt hàng thật |
| Database | Migration có `cart_items`, tồn trên `product_variants`, bảng đơn/snapshot và ledger | Chưa có write RPC đặt đơn/giữ tồn trong các migration hiện tại |
| Orders | Checkout hiện tại chưa có model/repository orders; remote ref của Bảo có các contract/model | Review và tích hợp hợp đồng chung, không tạo một Order riêng cho checkout |
| Auth/maps | Có adapter quyền tạm từ nền delivery; `core/maps` mới có khung | Dùng điểm tích hợp chung với An/Minh Đức |

Hiện có test catalog và điều hướng trong repo; lượt lập kế hoạch này chưa chạy
lại test, build, đăng nhập hay kiểm tra cloud. Working tree đang có thay đổi
catalog và tài liệu chưa commit; giữ nguyên các thay đổi đó.

Cơ sở: [AGENTS.md](../AGENTS.md), [hợp đồng Văn Đức](van_duc_catalog_checkout_contract.md),
[API](api_contracts.md), [database](database.md), [trạng thái](business_states.md)
và [mapping màn hình](screen_mapping.md). Hợp đồng phía Bảo được đối chiếu từ
remote ref cục bộ `origin/feature/orders-notifications-phase2`; chưa fetch xác
nhận phiên bản mới nhất trong lượt này. Chưa tìm thấy bản báo cáo v3.0 đầy đủ
trong checkout; cần đối chiếu NT01–NT30 trước nghiệm thu, không tự gán số NT.

## 2. Phạm vi và luồng màn hình

| Màn | Nội dung phải hoàn thiện | Route |
| --- | --- | --- |
| MH04 | Danh sách, tìm tên, lọc danh mục, phân trang, mở chi tiết và giỏ | `/customer/products` đã có |
| MH05 | Thông tin/ảnh, giá và tồn theo biến thể, chọn số lượng, thêm giỏ thật | `/customer/products/:productId` đã có |
| MH06 | Danh sách hàng trong giỏ, sửa số lượng, xóa dòng, tạm tính, chuyển đặt hàng | `/customer/cart` đề xuất, chưa đăng ký |
| MH16 | Người nhận, điện thoại, địa chỉ, chọn tọa độ, tiền hàng, phí 30.000 VND, COD | `/customer/checkout` đề xuất, chưa đăng ký |

MH16 có bộ chọn vị trí trong màn hình; MH18 tiếp tục thuộc shipper. Sau đặt
thành công, chuyển đến MH07 theo route do Bảo và router owner thống nhất, mang
`order.id`. Không thêm màn xác nhận thành công độc lập vào MH01–MH20.

Giữ feature-first MVVM và dependency injection Riverpod. Domain chứa model và
repository contract; data chứa mapping/Supabase; ViewModel quản lý thao tác và
trạng thái; widget gọi ViewModel. Dùng theme, client và router hiện có.

## 3. Các mốc triển khai

### Mốc 0 — Kiểm tra nền và chốt điểm tích hợp

- [ ] Chạy catalog tests/analyze làm baseline; demo MH04/MH05 bằng tài khoản
  customer và dữ liệu thật có quyền. Ghi rõ kiểm tra local và cloud riêng.
- [ ] Review thay đổi catalog hiện có, chỉ sửa lỗi ảnh hưởng luồng mua hàng.
- [ ] Chốt giỏ: thao tác thêm trùng biến thể, số lượng mục tiêu khi retry,
  phạm vi hàng chuyển checkout và dọn giỏ sau khi xác nhận đặt thành công.
  Đề xuất mặc định đặt toàn bộ giỏ; không thêm chức năng chọn từng dòng khi
  chưa có yêu cầu trong báo cáo.
- [ ] Chốt với Bảo `place_order`, receipt/lỗi/replay, model Order/OrderItem,
  route MH07 và helper event/notification theo CIN-02/04/07/09.
- [ ] Chốt với Minh Đức quy tắc dispatch một lần khi bàn giao vật lý và map
  interface; với An chốt session/role guard và model catalog dùng chung MH03.
- [ ] Xác định nguồn, phiên bản và phạm vi vùng Hà Nội được nhóm chấp nhận;
  chọn dịch vụ bản đồ, key/license và nền tảng demo trước khi thêm package.
- [ ] Chốt UX khi giá/tồn đổi, cách lưu request đang chờ và recovery sau khi
  đóng/mở ứng dụng. Đây là quyết định cần hoàn tất trước khi nối submit thật.

Đầu ra: checklist baseline, hợp đồng có kiểu dữ liệu/lỗi/quyền/transaction rõ
ràng, danh sách dependency còn thiếu và người phụ trách. Đề xuất trong tài
liệu không được đánh dấu đã được chủ sở hữu khác chấp nhận.

### Mốc 1 — Hoàn thiện và ổn định MH04/MH05

- [ ] Kiểm tra tìm kiếm/lọc/phân trang, sản phẩm không tồn tại/ngừng bán,
  biến thể hết hàng, ảnh lỗi và bốn trạng thái loading/error/empty/data.
- [ ] Giữ giá `int` VND theo biến thể; số lượng không vượt dữ liệu tồn đang
  hiển thị. Đây là hỗ trợ UI, backend vẫn kiểm tra tồn khi đặt đơn.
- [ ] Kiểm tra UI điện thoại, back navigation và đổi/hết phiên khi request
  đang chạy; dùng chung Product/ProductVariant với MH03.
- [ ] Chuẩn bị điểm gọi CartViewModel cho thêm giỏ; chỉ bật khi mốc 2 nối thật.

Điều kiện hoàn tất: catalog hoạt động đúng với backend và test phù hợp; chưa
coi việc xem/chọn hàng là đã thêm giỏ hoặc giữ tồn.

### Mốc 2 — Triển khai MH06 và nối thêm giỏ từ MH05

- [ ] Tạo CartItem/CartRepository trong `features/cart`, adapter Supabase,
  CartViewModel và UI. Đọc đúng schema cuối: khóa `(customer_id, variant_id)`
  trên `cart_items`, không tạo lại bảng `carts`.
- [ ] Hỗ trợ đọc giỏ, thêm biến thể, sửa số lượng và xóa dòng theo hợp đồng
  mốc 0. Retry không được tự cộng thêm lần nữa; không gửi nhiều thao tác xung
  đột cùng dòng khi thao tác trước chưa xác định kết quả.
- [ ] Kết hợp dữ liệu giỏ với catalog hiện tại để hiển thị tên/biến thể/giá/
  tồn. Giữ thông báo cho dòng ngừng bán hoặc không còn truy cập được, cho
  khách xóa; không âm thầm coi dữ liệu thiếu là hàng hợp lệ.
- [ ] Hiển thị tạm tính từ dữ liệu đọc hiện tại; không ghi giá client thành
  giá đơn. Thêm/sửa giỏ không cập nhật `reserved` hay `on_hand`.
- [ ] MH05 báo thành công sau kết quả ghi xác nhận; có trạng thái đang ghi,
  lỗi và retry. MH06 có giỏ rỗng, lỗi, refresh và nút sang checkout hợp lệ.
- [ ] Đăng ký route MH06, guard customer; xóa state riêng theo tài khoản khi
  đổi/thoát phiên và bỏ response cũ.
- [ ] Test repository/ViewModel/UI; SQL kiểm tra khách A không đọc/sửa giỏ B,
  manager/shipper/anon bị chặn, số lượng không hợp lệ bị từ chối.

Điều kiện hoàn tất: thêm ở MH05 → thấy đúng ở MH06 → sửa/xóa → tải lại vẫn
đúng; không giữ tồn, không ghi thành công giả và không lộ giỏ tài khoản trước.

### Mốc 3 — Backend đặt đơn và tồn kho trong cùng transaction

- [ ] Dựa trên contract đã chốt, triển khai `place_order` và tra kết quả theo
  request ID. Tạo migration qua CLI thật, sau khi kiểm tra version/help/docs.
- [ ] Server lấy identity/role đáng tin cậy; kiểm tra người nhận/điện thoại,
  hàng hợp lệ, địa chỉ và tọa độ trong vùng phục vụ Hà Nội. Khi chưa có dữ
  liệu xác thực vùng, từ chối đặt thật; không dựa riêng vào chữ “Hà Nội”.
- [ ] Claim idempotency, khóa biến thể theo thứ tự thống nhất, kiểm tra đủ
  mọi món rồi tạo order/items snapshot, giữ tồn, ledger, event và thông báo
  trong một transaction. Bất kỳ bước nào lỗi đều rollback toàn bộ.
- [ ] Server quyết định giá/phí 30.000 VND/tổng tiền/thời gian; trạng thái đầu
  `pending_confirmation`. Không nhận giá, tổng tiền hoặc customer ID làm
  nguồn tin từ Flutter.
- [ ] Retry cùng request/payload trả cùng đơn; cùng request khác payload bị
  từ chối. Kiểm tra lại quyền cả khi replay/lookup; timeout là chưa biết kết
  quả, không tự tạo request mới. Thực thi quy tắc giá đổi đã chốt ở mốc 0.
- [ ] Cung cấp primitive tồn nội bộ cho release/dispatch và inspection theo
  hợp đồng chung. Chặn tác động lặp kể cả khi caller đổi request ID; dispatch
  lần hai không xuất tồn lại, hàng giao thất bại chỉ nhập sau manager kiểm tra.
- [ ] Tích hợp wrapper của Bảo/Minh Đức tuần tự, cùng thứ tự khóa; không để
  Flutter tự ghép nhiều request thành một transaction. Không làm thêm UI
  quản lý tồn ngoài phạm vi bốn màn.
- [ ] Test đồng thời món cuối, giỏ nhiều món thiếu một món, retry/payload
  conflict, rollback khi ghi event/thông báo lỗi và mọi trường hợp sai quyền.

Điều kiện hoàn tất: SQL/RPC chứng minh không oversell, không tạo đơn một phần,
không nhân đôi đơn/ledger/thông báo; model kết quả được orders đọc đúng. Phân
biệt migration đã tạo, đã chạy local và đã áp dụng cloud bằng bằng chứng riêng.

### Mốc 4 — Triển khai MH16 với backend đã kiểm chứng

- [ ] Tạo checkout input/receipt adapter, CheckoutRepository và
  CheckoutViewModel; tái sử dụng model orders khi tích hợp. Không dùng
  ViewModel của orders/catalog làm repository.
- [ ] Hiển thị giỏ được kiểm tra lại, form người nhận/điện thoại/địa chỉ,
  tọa độ đã chọn, tiền hàng + 30.000 VND và phương thức COD.
- [ ] Tích hợp picker theo interface map đã chốt cùng Minh Đức; chọn vị trí
  là một phần MH16. Khi dịch vụ lỗi, báo lỗi/thử lại, không tự bịa tọa độ.
- [ ] Thực hiện UX giá/tồn thay đổi đã chốt; khách có thể sửa giỏ rồi xác
  nhận lại. Không tự tạo đơn với dữ liệu form lỗi hoặc vùng chưa xác thực.
- [ ] Trước submit lưu request ID và payload ổn định theo hợp đồng recovery;
  scope theo tài khoản, bảo vệ dữ liệu người nhận, không log payload nhạy cảm.
  Lưu không được thì báo lỗi, không âm thầm bỏ cơ chế chống đặt trùng.
- [ ] Khóa nút khi đang gửi; timeout chuyển sang chờ xác minh và dùng lại
  request ID để lookup/retry. `not_found` không tự chứng minh lần trước thất bại.
- [ ] Chỉ sau kết quả committed mới báo thành công, dọn đúng phần giỏ đã
  đặt theo contract (không xóa nhầm thay đổi mới), invalidate dữ liệu và mở
  MH07 bằng order ID. Bảo đảm khôi phục sau lỗi không đặt lại đơn.
- [ ] Tích hợp route/guard MH16 trong router chung; test account switch giữa
  submit và response, hết phiên, back/reopen và app restart với request chờ.

Điều kiện hoàn tất: MH04 → MH05 → MH06 → MH16 → MH07 chạy bằng backend thật,
đơn có snapshot đúng, giữ tồn đúng và retry không tạo thêm đơn.

### Mốc 5 — Nghiệm thu tích hợp và bàn giao

- [ ] Cùng nhóm chạy đặt → manager xử lý → shipper giao thành công → nhận đủ
  COD → manager đối soát. Checkout bàn giao đúng total và snapshot cho các bước.
- [ ] Tiếp tục kiểm tra hủy/giải phóng tồn, giao lại không xuất tồn hai lần,
  hàng thất bại không tự restock; nhánh trả hàng không xóa nghĩa vụ COD.
  Bảo/Minh Đức/Sơn sở hữu màn và hành động tương ứng.
- [ ] Đối chiếu NT01–NT30 từ báo cáo đầy đủ; đánh dấu phạm vi Văn Đức và phụ
  thuộc liên thành viên, ghi kết quả thực chạy và phần chưa chạy.
- [ ] Chạy `dart format` cho Dart thay đổi, `flutter analyze`, test liên quan,
  build nền tảng demo và smoke test thật. Chạy `flutter pub get` khi đổi
  dependency, giữ lockfile; không nâng dependency toàn dự án trong cùng việc.
- [ ] Cập nhật hợp đồng API/database/trạng thái/mapping khi implementation
  thiết lập hoặc thay đổi contract; bàn giao cách chạy, dữ liệu cần có,
  migration và demo. Fixture/demo phải có nhãn, không thay fake khi API lỗi.

Điều kiện hoàn tất: bốn màn đủ chức năng trong phạm vi, có bằng chứng frontend
và backend, quyền cho phép/từ chối đều được thử, dependency chưa có được ghi
rõ. Không đánh dấu toàn luồng hoàn tất nếu MH07/backend liên quan chưa tích hợp.

## 4. Phụ thuộc và quyền sở hữu

| Phối hợp | Văn Đức chịu trách nhiệm | Cần thống nhất/tích hợp |
| --- | --- | --- |
| Dung An | Customer catalog/cart/checkout qua client chung | Auth/session/role guard, catalog model MH03, invalidation khi đổi dữ liệu |
| Bảo | Input/receipt đặt đơn, snapshot và reserve/release | Order/OrderItem, MH07 route, cancellation lock, event/notification atomic |
| Minh Đức | Tồn và địa chỉ/tọa độ snapshot của đơn | Dispatch tại bàn giao lần đầu, custody lần hai, component/interface map |
| Sơn | Primitive tồn và snapshot chung khi luồng trả cần dùng | Quantity thực nhận/kiểm tra thuộc returns; không copy logic trả vào checkout |

Văn Đức sở hữu thay đổi catalog dành cho khách, cart, checkout, phần inventory
đã được phân công qua hợp đồng, test tương ứng và migration mới đúng phạm vi.
`core/maps`, auth/orders models, router/theme, dependency/lockfile, tài liệu
chung và schema dùng chung được tích hợp tuần tự với chủ sở hữu. Không tự sửa
nhánh thành viên khác. Mỗi mốc nên là một thay đổi có thể review độc lập.

## 5. Cách triển khai ngay và xử lý phụ thuộc

Thứ tự: **Mốc 0 → Mốc 1 → Mốc 2 → Mốc 3 → Mốc 4 → Mốc 5**. Kiểm thử đi cùng
từng mốc. Khởi động thảo luận contract backend/map từ mốc 0, không chờ làm xong
giỏ mới phát hiện thiếu API. Trong khi chờ điểm tích hợp, vẫn có thể hoàn thiện
giỏ và test UI bằng fixture ghi rõ; đặt đơn thật chỉ bật khi backend đủ điều kiện.

Bước coding đầu tiên là lấy baseline catalog, rồi triển khai MH06 và nối nút
thêm giỏ. Chưa cần dựng lại Flutter, thiết kế lại toàn bộ UI hoặc thay kiến trúc.
Không ấn định ngày hoàn thành trước khi baseline, hợp đồng orders và dữ liệu
vùng giao được kiểm chứng. Ưu tiên demo giỏ thật trước, rồi demo đặt một đơn
nguyên tử, sau đó mở rộng các ca lỗi và nối luồng giao/đối soát của nhóm.

Tài liệu Supabase tham chiếu cho giai đoạn triển khai:
[RLS](https://supabase.com/docs/guides/database/postgres/row-level-security),
[quyền database functions](https://supabase.com/docs/guides/database/functions)
và [kiểm thử local](https://supabase.com/docs/guides/local-development/testing/overview).
Kiểm tra lại API theo dependency/CLI thực tế khi viết code; tài liệu này không
thay thế việc kiểm tra phiên bản hoặc xác minh quyền trên backend.
