# MH16 — nhập địa chỉ trước khi chỉnh bản đồ

## Luồng dành cho khách

1. Nhập tên đường, phường hoặc tòa nhà tại Hà Nội và bấm **Tìm địa chỉ**.
2. Chọn gợi ý thật từ dịch vụ tra cứu, nhập số nhà/ngõ/tầng/phòng.
3. Bấm **Xác nhận địa chỉ** để dùng cho đơn. Nếu cần chỉnh điểm, bấm
   **Chỉnh vị trí**, kéo bản đồ lớn dưới ghim cố định rồi **Xác nhận vị trí**;
   kiểm tra và xác nhận lại địa chỉ trên form.

Form chính đã bỏ bản đồ nhỏ và ô tọa độ. Hộp bản đồ toàn màn hình vẫn thuộc
MH16 trong Navigator khách được bảo vệ, không tạo màn nghiệp vụ thứ 21.
Nếu tìm chưa ra hoặc dịch vụ lỗi, nhập địa chỉ đầy đủ và chọn điểm thủ công
trong hộp bản đồ; không tự suy đoán tọa độ từ văn bản hay dùng tâm Hà Nội
làm điểm nhận hàng. Máy chủ tiếp tục quyết định vùng phục vụ Hà Nội.

## Hợp đồng dữ liệu và trạng thái

- `AddressSearchRepository.search(query)` trả `AddressSuggestion` gồm
  `id`, `label`, `latitude`, `longitude`. Repository Photon nằm trong data;
  `AddressSearchViewModel` qua Riverpod quản lý loading/error/empty/results.
  View không gọi HTTP hoặc Supabase trực tiếp.
- Chỉ gửi chuỗi ở ô tìm đường/khu vực khi khách chủ động tìm. Số điện thoại,
  tên người nhận và phần số nhà/tầng/phòng không được ghép vào request tra cứu.
- Photon trả GeoJSON `[longitude, latitude]`; chỉ nhận point hữu hạn, tên
  có thật, countrycode VN và bbox bao quanh boundary Hà Nội hiện có.
  Bbox chỉ giới hạn tìm kiếm, không thay kiểm tra polygon phía máy chủ.
- Dùng endpoint mặc định `https://photon.komoot.io/api/`, có thể đổi qua
  `PHOTON_API_URL` khi build. Không đặt `lang=vi` vì public server hiện không
  hỗ trợ; bỏ lang để giữ tên địa phương. Giới hạn 5 kết quả, request tối thiểu
  cách nhau 1 giây, có singleflight và timeout 15 giây. Không tìm mỗi phím gõ.
- Địa chỉ đặt hàng là chi tiết + nhãn gợi ý khách đã chọn, tối đa 500 ký tự;
  đường chọn thủ công dùng nguyên địa chỉ khách nhập. Chỉ draft đã xác nhận
  mới đi vào `place_order`, cùng tọa độ đã chọn. Không đổi schema/RPC/snapshot.
- Sửa query xóa nhãn/điểm cũ; sửa chi tiết yêu cầu xác nhận lại. Khi nhập thủ
  công toàn bộ địa chỉ, sửa văn bản cũng xóa điểm cũ để tránh đổi đường nhưng
  giữ ghim của đường trước.
- `CheckoutAddressEditorDraft` giữ query/chi tiết/nhãn/điểm/trạng thái xác
  nhận trong bộ nhớ của CheckoutPage qua loading khi recheck session. Đổi
  tài khoản/đăng xuất xóa route và editor cũ. Không lưu query xuống thiết bị.
- Yêu cầu đặt hàng đang chờ mới ưu tiên nguyên snapshot đã gửi và khóa chỉnh sửa;
  retry/recovery không geocode lại hoặc thay request ID/nội dung đơn.
- Bản đồ cố định đầu ghim tại camera center. Chỉ xác nhận sau gesture kết
  thúc và tile dưới ghim hiện tại đã decode; edge tile hoặc callback từ
  source/generation cũ không được mở khóa xác nhận. Lỗi có nút thử lại.

## Kiểm chứng và giới hạn

Repository/ViewModel: 20 bài đạt. Bản đồ/adapter: 24 bài đạt. Router/session:
8 bài đạt, gồm giữ draft chưa xác nhận, giữ cấu trúc địa chỉ đã xác nhận,
pending snapshot, đổi tài khoản và modal được bảo vệ.

Public probe Photon dùng địa danh công cộng Tràng Tiền/Hoàn Kiếm trả HTTP200
và tọa độ thực. Probe không tạo tài khoản hoặc đơn. Native Android flow đạt:
tìm địa chỉ thật → chọn gợi ý → xác nhận → kéo ghim → xác nhận điểm mới;
sửa query sau đó xóa tọa độ cũ. Log `build/address_first_android_flow.log`.

186 kiểm thử checkout/maps/router đạt, 1 visual opt-in được bỏ qua trong bộ
hồi quy; capture visual chạy riêng đạt tại 390×1900, 390×844 và 320×800
(form và biên nhận). Đã xem ảnh form ở 390×1900 và 320×800, không tràn bố
cục. Đây là fixture render, không phải ảnh chụp đơn thật. `flutter analyze`
không lỗi; APK debug build đạt. Log: `build/address_first_regression_verified.log`,
`build/address_first_visual.log`, `build/address_first_analyze_verified.log`,
`build/address_first_app_run.log`.

Dữ liệu công cộng có thể thiếu ngõ/số nhà; khách kiểm tra chi tiết và chỉnh
ghim khi cần. Photon demo áp dụng fair use và không đảm bảo sẵn có; đường
chọn bản đồ thủ công vẫn dùng được khi tìm địa chỉ lỗi. Khi triển khai rộng,
cấu hình dịch vụ geocoding có năng lực phù hợp, giữ nguyên repository contract.

Nguồn chính thức: [Photon API](https://github.com/komoot/photon/blob/master/docs/api-v1.md),
[public demo và điều kiện sử dụng](https://github.com/komoot/photon#demo-server),
[dữ liệu OpenStreetMap](https://www.openstreetmap.org/copyright).
