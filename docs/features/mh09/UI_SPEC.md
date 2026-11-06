# MH09 — UI specification và visual audit

Visual authority: [HTML nguyên bản](../../ui_mocks/MH09_Manager_Order_Details.html).
Business authority ở BEHAVIOR_CONTRACT; không tái tạo policy sai trong mock.
**MH09 — NOT YET APPROVED**. Chưa có fresh Flutter screenshot task01.

## Ảnh Chromium thật và phương pháp

- [390×844 viewport](artifacts/html_390x844.png), [390×1475 full page](artifacts/html_390_full.png).
- [Manifest](artifacts/html_render_manifest.json): Chromium155.0.8059.84, viewport390×844, DPR1, scrollWidth390.
- `document.fonts.ready` + explicit9 font loads Inter400–700/Barlow600–800/italic700/Symbols400;
  mỗi load có faces>0/status loaded; cả2 ảnh product decode/naturalWidth>0; failedRequests0.
- Source hash before=after. Source HTML không sửa; manifest có renderer/screenshot hashes.
- Lượt sandbox bị DNS fail CDN/fonts/ảnh; [attempt log](artifacts/html_render_attempt1.log).
  Render ngoài sandbox thành công. Không dùng capture thiếu CSS/font làm reference.
- Full-page API giữ fixed footer tại y772 của viewport gốc; nó cắt ngang payment trong ảnh dài.
  Đây là hành vi capture Chromium, không phải footer ở giữa scroll content hoặc layout target Flutter.
- Safe-area desktop env=0; Android system bars/insets chưa được đo tại task01.

## Geometry đo tại 390, scale1 (logical px)

| Vùng | x/y | width×height | Ghi chú |
| --- | --- | --- | --- |
| Header fixed |0/0|390×64|white80%, backdrop blur, shadow nhẹ; px20|
| Title |56/16|282×32|center, BarlowCondensed28/32 w700, uppercase|
| Back hitbox |12/10|44×44|icon24; avatar x338,size32, chỉ trang trí mock|
| Identity/status/overflow |0/64|390×60|padding16 20 8; badge pill; overflow36×36|
| Placed-at row |0/124|390×36|bottom16, body14/20|
| Buyer/recipient card |20/160|350×186.5|padding16, radius32|
| Contact buttons |36/292.5;199/292.5|155×38 mỗi nút|gap8, pill; future hitbox≥48|
| Items card |20/362.5|350×249|gap từ card trước16|
| Payment card |20/627.5|350×289|subtotal, fee, mock discount, total, COD|
| Timeline card |20/932.5|350×414|shipper strip + six mocked stages|
| Sticky footer |0/772|390×72|padding8 20; inner h56; white95%|
| Reject |20/784|126.53×48|errorContainer, sale text, pill|
| Confirm |154.53/784|215.47×48|ink/white, pill; gap8|

Main top64; content bottom padding128; section margin20/gap16/padding16; image64×64, radius16.
HTML product names truncate; Flutter phải cho đọc đầy đủ snapshot khi tên dài.
Mock header truncates title; giữ semantics toàn title và fallback wrap khi text scale cao.

## Typography, tokens và mapping

| Token | HTML | Flutter kế hoạch |
| --- | --- | --- |
| Header/order ID |Barlow Condensed28/32,700|reuse bundled `BarlowCondensed`, local TextStyle|
| Section title |Inter20/26,600 uppercase|MH09-specific style từ shared theme, không đổi theme global|
| Body |Inter14/20,400|body text, readable wrap|
| Product title |Inter14/18,600|snapshot name; không infer catalog|
| Label/caption |Inter12/16,600;11/14,400|metadata, không dùng cho critical amount quá nhỏ|
| Total |Barlow32/36,800|integer formatVnd, amount prominent|
| Footer label |Barlow14/16,700, uppercase,letterSpacing .08em|min hitbox48, wrap/flexible|
| Ink/cloud/muted |#111111/#f5f5f5/#707072|OrderNotificationTheme tokens reuse|
| Charcoal/stone/hairline |#39393b/#9e9ea0/#e5e5e5|decorative/secondary only; contrast kiểm tra sau|
| Sale/reject bg |#d30005/#ffdad6|reject action, errorContainer local visual|
| Surface/radii |#fff;16/32/9999|item/card/pill|

Không thêm fonts/packages hoặc theme song song. Shared theme hiện section24 Barlow, title16 Inter;
đó là gap thật cần style riêng trong MH09 components, không sửa MH07/MH08/MH17.
Icons dùng Material Flutter hiện có; không import remote Symbols font vào app.

## HTML → Flutter mapping dự kiến

Header → Mh09Header; meta → Mh09OrderIdentity; customer/contact → Mh09RecipientSection.
Items → Mh09ItemsSection (private item row cùng file nếu đủ LOC); payment → Mh09PaymentSection.
Delivery/COD/Returns giữ public shared sections qua Mh09LifecycleSections composition ban đầu.
Timeline giữ `OrderTimeline` normalization hiện hữu, local composition/style hạn chế theo ARCHITECTURE_PLAN.
Warnings phải từ field authorized hiện có; footer → Mh09ActionFooter, eligibility ở owner page.
API/LOC/tests/risk từng component: [ARCHITECTURE_PLAN](ARCHITECTURE_PLAN.md).

## Visual difference matrix

So sánh source hiện tại + [historical Flutter top](../../visual_refinement_artifacts/mh09_390_s1_0_top.png)
và [bottom](../../visual_refinement_artifacts/mh09_390_s1_0_bottom.png), đã xem trực tiếp trong audit.
Ảnh lịch sử390×800, fixture1 item, không back vì standalone; không coi là fresh/equal-viewport diff.

| Vùng | Current Flutter / HTML | Hướng kế hoạch |
| --- | --- | --- |
| Header |left title24 Barlow + refresh / centered28 uppercase + back/avatar|center header/back, giữ refresh; không tạo account/profile route|
| Identity |card UUID wrap + status/time / short DH code ngoài card|giữ full canonical UUID; visual meta có thể cao hơn|
| Buyer |buyer và recipient tách, contact ở cuối / merged customer, member badge|giữ hai khái niệm, đưa callback contact gần recipient; bỏ member badge|
| Items |1 placeholder, verbose multiline /2 photos và compact rows|giữ placeholder vì model không URL; compact có wrap, không giấu giá/variant|
| Payment |real subtotal+fee=COD / mock shipping discount|giữ phí30k; bỏ discount, total tăng đúng dữ liệu|
| Delivery |card riêng/nullable / strip trong timeline|giữ lifecycle riêng, không fake unassigned từ null|
| COD |payment state + reconciliation card / badge Chưa thu|giữ expected/collected/received/times riêng, null rõ|
| Returns |summary riêng / không có section|giữ read-only section khi data có, unavailable khi thiếu|
| Timeline |actual chronological events /6 planned stages|giữ actual events + incomplete/fallback notice|
| Operations |disabled services và contact ở cuối /không có warning riêng|giữ unavailable và warnings authorized, không thêm action|
| Footer |Confirm→Reject Wrap /Reject→Confirm 48px, width split|target thứ tự HTML, adaptive Wrap, full safe-area|
| Spacing |20 outer,12 section gap,32 radius /20,16,32|MH09-only gap16; không đổi shared defaults|

## Responsive và intentional deviations

- Matrix future: widths320/360/390/412 + landscape (844×390) ×textScale1/1.5/2.
- Không fixed card height; UUID/name/address/amount wrap; amount-label stack khi thiếu width.
- Sticky footer trong Scaffold + SafeArea, scroll khi landscape/large text, không che final row.
- Không hardcode bottom128 như HTML nếu Scaffold đã reserve footer; dùng actual inset/layout.
- Dialog scrollable, IME inset, close/submit≥48, state reason chỉ owner dialog giữ và dispose.
- Không copied demo membership, SMS, voucher, OTP, 3PL auto-assignment, ETA hoặc manager wallet.
- Mock confirm700ms success/reject browser confirm không phải behavior Flutter.
- Timestamps server → formatHanoiDateTime; không copy weekday/date minh họa từ HTML.
- Reachability/readability/authorization ưu tiên hơn ép pixel/height bằng mock dataset khác.

## Quyết định implementation02A — isolated, chưa screen acceptance

- Header là content-sized StatelessWidget: min64, title wrap đầy đủ,48px slots đối xứng; không fixed PreferredSize.
  Parent sở hữu SafeArea và future Scaffold integration; component tự có gutter20, test host không bọc thêm gutter.
- Identity giữ full UUID visible/semantics/tooltip; badge xếp dưới UUID để tránh ép mã thật vào row ngắn của HTML.
- Recipient/Items card padding16/radius32, parent future main scroll sở hữu gutter20/gap16; contact≥48, reflow bằng Wrap.
- Chat callback độc lập phone/Buyer projection; parent bind customerId, call bind recipientPhone. Không tự dial/chat.
- Items count là số dòng (`items.length`), không suy tổng số lượng;64px placeholder, không fetch ảnh lịch sử chưa có.
- Các quyết định này chưa chứng minh fidelity toàn màn hình; fresh screenshot comparison/Android vẫn dành04A/04B.

## Quyết định implementation02B — isolated

- Payment card16padding/32radius; total Barlow32/36 weight700 dùng font Bold bundled, không thêm/synthesize asset800 từ mock.
- Financial rows wrap/stack theo width và text scale; full amount semantics, method COD theo business scope, no discount row.
- Footer Reject trước Confirm; cân hai actions ở390, stack khi hẹp/scale cao/landscape. Exceptional cancel là block cảnh báo riêng.
- Native disabled colors/semantics và48px targets; footer không tự SafeArea/Scaffold/dialog/nav, parent reserve real height sau này.
- Operational capability false ẩn control, all-false không tạo card; true vẫn disabled với reason ngắn, không có owner callback/API giả.
- Chưa render fresh full-screen Flutter/Android trong02B; không suy pixel fidelity hoặc screen approval từ widget tests.
