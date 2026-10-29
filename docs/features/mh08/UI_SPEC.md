# MH08 — UI specification

Design plan MH08-01 và mapping triển khai đến MH08-04B2, ngày16/10/2026; UI chưa được duyệt.
Business/permissions nằm trong [BEHAVIOR_CONTRACT](BEHAVIOR_CONTRACT.md).

## Visual source và bằng chứng

- [HTML gốc](../../ui_mocks/MH08_Manager_Order_List.html), giữ nguyên source.
- [Ảnh 390×844](artifacts/html_390x844.png), [full page](artifacts/html_390_full.png).
- [Render manifest](artifacts/html_render_manifest.json): viewport/DPR/font/geometry/request failures.
- Renderer: `tool/ui_preview/render_mh08_reference.cjs`, dùng lại cách Playwright/Chromium của MH07.
- Render xác minh width 390, height 844, DPR 1, scrollWidth 390; font Inter/Barlow/Symbols loaded.
- Flutter mới: [so sánh04B2](artifacts/visual_04b2/comparison_390.png), widget render có fonts, không phải Android screenshot.

## Layout hierarchy đích

`ManagerOrdersPage` → manager access/theme → MH08 header → search/filter → KPI → horizontal chips → async feed/cards/footer.
Header giữ trên cùng; search/KPI/chips phải nhường diện tích list khi keyboard mở.
Tại text scale lớn, reflow nội dung thay vì khóa font hoặc ép chiều cao.

## Tokens

| Token | Giá trị / áp dụng |
| --- | --- |
| Surface / ink / cloud | `#ffffff` / `#111111` / `#f5f5f5` |
| Muted / stone / body variant | `#707072` / `#9e9ea0` / `#444748` |
| Sale / success / border | `#d30005` / `#007d48` / `#e5e5e5` |
| Body font | Inter; đã có asset project |
| Display font | Barlow Condensed 700; Flutter family `BarlowCondensed` đã có |
| Brand | Barlow Condensed 14/16 px, weight700, tracking .08em |
| Header surface | White alpha .8, shadow(0,1)/blur8/alpha .04; Flutter có thể dùng surface đặc nếu cần ổn định |
| Title header / KPI | 28/32 px, weight 700 |
| Order ID / total | Inter 20/26 px, weight 700 |
| Buyer / action label | Inter 14/18 px, weight 600 |
| Body / search | Inter 14/20 px, weight 400 |
| Chip | Inter 12/16 px, weight 600, tracking .02em |
| Caption | Inter 11/14 px |
| Page inset / card gap | 20 / 16 logical px |
| Card padding / inner gap | 16 / 8 logical px |
| Radius intent | Card/KPI/buyer 16; search/chips/actions pill |
| Card shadow intent | Offset (0,4), blur 16, ink alpha .06 |

Reuse shared theme tokens. Không chỉnh shared theme chỉ để ép MH08 giống một chi tiết HTML.
HTML dùng `rounded-DEFAULT` nhưng Chromium đo radius 0: class không sinh border radius.
Flutter dự kiến dùng radius 16 theo design intent/config, ghi rõ là deviation khi so ảnh.

## HTML → Flutter mapping và responsibility

Các file `widgets/mh08/*` được tích hợp ở03A, Preview nối ở03B, tinh chỉnh presentation ở04B2.
Base path: `lib/features/orders/presentation/`.

| Thành phần | HTML / geometry audit | Baseline → component đang được dùng |
| --- | --- | --- |
| Header | 64h, inset20, brand trái, title28/32, avatar32 | Shared `orderStoreAppBar` → `widgets/mh08/mh08_header.dart`, `Mh08Header` |
| Search/filter | Top y68, pill40h, gap8, filter40 | `_ManagerListHeader` → `widgets/mh08/mh08_search_section.dart`, `Mh08SearchSection` |
| KPI strip | y124, h81, gap8, 3 cột demo | `_CountPill` → `widgets/mh08/mh08_kpi_strip.dart`, `Mh08KpiStrip`; 2 authoritative panels |
| Status chips | Sau KPI16, horizontal gap4, pill | `_ManagerStatusChips` → `widgets/mh08/mh08_status_chips.dart`, `Mh08StatusChips` |
| Order card shell | x20, width350, y269 card1, p16, gap16 | `ManagerOrderCard` generic → `widgets/mh08/mh08_order_card.dart`, `Mh08OrderCard` |
| ID/time/status | Row; ID20/26, caption11/14, status pill | `mh08_card_header.dart`; UUID/status cùng row khi đủ rộng, stack khi hẹp/chữ lớn |
| Buyer panel | Cloud, avatar40, p8, name14/18, address | Generic text → `widgets/mh08/mh08_buyer_section.dart`, `Mh08BuyerSection` |
| Item preview | HTML card2 placeholder56, name/variant | Shared `_ItemsPreview` → `widgets/mh08/mh08_item_preview.dart`, `Mh08ItemPreview` |
| Amount/COD | Amount20/26, quantity14/20, COD11/14 pill | Shared `_Footer` → `widgets/mh08/mh08_payment_section.dart`, `Mh08PaymentSection` |
| Warnings | Icon14 + caption11/14, sale; shipper panel cloud | `_ManagerProjection` → `widgets/mh08/mh08_operational_notice.dart`, `Mh08OperationalNotice` |
| Actions | 2 columns, gap8, soft reject / ink confirm | Feed generic Wrap → `widgets/mh08/mh08_card_actions.dart`, `Mh08CardActions` |
| Dialogs | Không có visual dialog gốc trong HTML | Reuse `OrderActionDialog`, không chỉnh shared dialog trong component task |
| Feed states/paging | Không có API HTML | Reuse `OrderFeed` async/footer + `itemBuilder`, không duplicate state |

Mỗi widget ≤180 LOC; chỉ thêm subcomponent khi có responsibility riêng.
Không cần thêm dependency/font mới. Icon Material Flutter tương đương, không render chuỗi icon web.

## Responsive behavior dự kiến

- 320/360/390/412: content theo viewport, inset20 có thể giảm có chủ đích nếu cần giữ nội dung đọc được.
- Landscape: hạn chế header section chiếm hết height; list vẫn scroll được.
- Scale1.5/2: ID/status/buyer/amount/actions reflow bằng Wrap/Column; không truncate reason/warnings.
- UUID dài: ellipsis khi cần, semantic/tooltip có full UUID; callback/search giữ UUID đầy đủ.
- Controls có hit target tối thiểu48; visual pill có thể thấp hơn trong hit area.
- Chips scroll ngang, không Wrap gây chiếm hết list; không tạo flex overflow.
- SafeArea/bottom padding theo thiết bị; không thêm bottom navigation không có route.
- Keyboard: search/clear và list vẫn dùng được, inset chỉ xử lý một lần.

## Visual differences và intentional deviations

| Audit hiện tại | Hướng đích / sai khác được giữ có chủ đích |
| --- | --- |
| Tiêu đề body lớn + tổng đơn làm phần đầu cao | Bỏ heading trùng header; giữ total/accessibility theo data thật |
| KPI padding12, số headline lớn; thiếu subcaption | Compact KPI theo HTML; **2** panel, không hardcode 12/8/3 |
| UUID wrap nhiều dòng, card dài | Compact ID/time/status, vẫn full identity qua semantics/tooltip |
| Buyer chỉ là các dòng text | Buyer panel nền cloud với address snapshot |
| COD block full width, nhiều label | Compact amount/COD; thiếu summary vẫn ghi unavailable, không bỏ trạng thái thật |
| Generic outlined action Wrap | Pill actions; giữ capability/stale/session gate |
| HTML nested h1 tạo heading rỗng và title bị cắt | Header Flutter đúng hierarchy, không sao chép lỗi DOM |
| HTML 2 navigation cố định chồng nhau | Không copy navigation dashboard/search/account chưa được route hỗ trợ |
| HTML báo unassigned ở pending | Chỉ warning theo projection/server; không suy luận pending là lỗi |
| HTML DH-ID / call shipper / Returns chip | UUID thật / không call / không trộn return lifecycle với order status |
| HTML ảnh và copy demo | Placeholder vì thiếu historical image contract; không hardcode hàng/shipper/giờ |

Chưa có đo pixel-diff; không tuyên bố pixel-perfect. Xác nhận visual mới thuộc MH08-04.

## Quyết định component MH08-02

- Header là widget thường để tự tăng height/reflow ở text scale≥1.5; parent task03A sở hữu SafeArea/app-bar placement, không ép height64 khi chữ lớn.
- Search có controller chỉ cho editing/focus/selection; `value` do parent echo ngay, không timer/query state trong component.
- Card yêu cầu parent truyền `isFresh` và `showDecisionActions`; eligibility mặc định false, callback null là unavailable.
- Card không đọc lại role/capability từ summary. Parent task03A phải truyền quyết định hiện hành và recheck trước khi mở/submit dialog.
- UUID hiển thị một dòng ellipsis với tooltip/semantics đầy đủ; timestamp/status wrap độc lập vì UUID khác mã ngắn trong HTML.
- Payment nền trắng, pill COD cloud; thiếu COD projection vẫn hiện unknown, không biến thành uncollected.
- Warning chỉ hiện message của typed projection, không đưa raw code kỹ thuật lên UI hoặc tự tạo unassigned/failed warning.
- Screenshot đối chiếu hiện tại ở04B2 bên dưới; component tests không thay thế user visual approval.

## Composition03A đang dùng

- `Mh08PageLayout`: Scaffold/SafeArea; header+controls scroll tối đa55% chiều cao khả dụng để feed còn chỗ khi chữ lớn/keyboard.
- Header/controls nằm trong body thay cho fixed AppBar cũ; viewport nhỏ có thể scroll cùng nhau (intentional accessibility reflow).
- `Mh08ListControls`: search +2 KPI+total canonical+chips; keyboard mở ẩn KPI/total, giữ search/chips.
- `Mh08OrderCard` qua shared `OrderFeed.itemBuilder`; toàn bộ10 components có đường dùng thực tế.
- Bỏ `_ManagerListHeader/_CountPill/_ManagerStatusChips` khỏi page; không có UI trùng, không sửa10 components task02.
- 03A chỉ xác minh integration; bằng chứng visual mới04B2 bên dưới, visual approval vẫn thuộc người dùng.

## Refinement04B2 — presentation hiện tại

- Giữ inset20/card padding16/radius16; inner gaps8. `Mh08CardHeader` sở hữu UUID/status/time, full UUID tooltip/semantics.
- Header dùng Row có constraint cho status dài; width≤300 hoặc scale≥1.5 chuyển về UUID rồi Wrap timestamp/status.
- `Mh08BuyerSection`: avatar32, panel radius12, inline label/value khi đủ rộng; width nội dung≤240 hoặc chữ lớn thì stack.
- Account/recipient khác nhau, toàn bộ address/phone soft-wrap; không thu gọn dữ liệu vào navigation.
- `Mh08ItemPreview`: placeholder48, variant/quantity Wrap; card truyền `showQuantity:false`, standalone mặc định true.
- Render mọi snapshot được cung cấp (contract tối đa2); metadata dòng chưa có preview giữ nguyên, không fetch catalog.
- Tổng quantity duy nhất trong `Mh08PaymentSection`; amount20/26, integer VND/COD/unknown không đổi; gap stack4.
- `Mh08ListControls`: search vẫn48h; gap KPI8, số BarlowCondensed28/28; total canonical là leading text trong strip trạng thái.
- `Mh08StatusChips`: padding8/4, padded hit target≥48, đủ10 enum; All count vẫn search-wide, không thay bằng total đã lọc.
- K1 giữ nguyên bool trước Scaffold; keyboard ẩn cả KPI và leading total, không thêm resize/padding/state.
- 390×844/scale1 cùng fixtures: card580→476h, y318→277; buyer142→106h, items148→104h; actions y633/48h.
- HTML card234h khác dữ liệu/contracts; vẫn giữ2 KPI, UUID, COD, typed warning,48px actions và details; không claim pixel-perfect.
- Đo và ảnh: [measurements](artifacts/visual_04b2/density_measurements.json), [report](artifacts/visual_04b2/mh08_04b2_refined_report.json).
