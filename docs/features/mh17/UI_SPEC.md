# MH17 — UI specification từ reference thật

[HTML nguyên bản](../../ui_mocks/MH17_Notifications.html) chỉ điều khiển visual intent.
[Behavior contract](BEHAVIOR_CONTRACT.md) và rev1.2 điều khiển nghiệp vụ, permission và navigation.
Không sửa HTML, không copy local JS read/filter logic vào Flutter.

## Rendering evidence

Chromium155.0.8059.85, viewport390×844 logical pixels, DPR1; full page390×1243.
7 font load specifications PASS: Inter400/500/600/700, Barlow Condensed600/700, Material Symbols400.
Request failures0; `document.fonts.status=loaded`; images0, không có bitmap image để decode/so sánh.
[Manifest](artifacts/html_reference/render_manifest.json) ghi source/renderer/image SHA, fonts, computed dimensions/colors.
[Primary](artifacts/html_reference/primary_390x844.png), [full page](artifacts/html_reference/full_page_390.png).
Ảnh primary/full được render mới; không phải ảnh Flutter/Android và không chứng minh visual parity.

## HTML → Flutter mapping

| Region | HTML thật | Current Flutter / hướng giữ an toàn |
| --- | --- | --- |
| Header shell | fixed64px, brand VN ATHLETICS, “Don Hang”, cart/avatar | AppBar “Thông báo”; không thêm cart/avatar/shell route chưa thuộc scope |
| Page heading | Barlow Condensed28/32, uppercase; badge “3 MỚI” | shared theme title + existing exact UnreadBadge; header component chỉ khi cần |
| Operational strip | Cần duyệt04/Đang giao12/COD₫6.3M | không có MH17 contract, loại khỏi production proposal |
| Bulk action | “Đọc tất cả” + JS local DOM mutation | không implement; canonical single-row ack hiện có phải giữ |
| Filter row | horizontal categories all/orders/shipping/returns/system | chỉ Tất cả/Chưa đọc theo query model, không mở thêm category API |
| Feed | six articles, margins20px, gap8px | existing ListView padding20 và card gap8; preserve virtualization |
| Unread card | cloud#f5f5f5, title700, dot, icon44px | existing NotificationTile tương ứng; body server text, action explicit read |
| Read card | white, quieter title/body/icon, không dot | existing tile không read action; không chỉ dùng màu phân biệt |
| Timestamp | relative fixture text + category | shared `formatHanoiDateTime(createdAt)` absolute Hanoi + type label; không giả relative time |
| End indicator | hardcoded “Đã hiển thị hết”, “Vừa xong” | cursor/null từ server mới quyết định hết; không fake last updated |
| Bottom nav | fixed64px, Đơn hàng selected | shell owner; không thêm navigation architecture trong MH17 |

## Geometry và typography quan sát được

- First card: x20/y243/width350/height118.5 tại390; padding16, horizontal icon/text gap16.
- CSS computed `border-radius:0px` dù class có `rounded-DEFAULT`; reference thực có góc vuông.
- Flutter tile hiện radius16 và icon-text gap12; ghi discrepancy, không sửa chỉ vì class name gợi rounded.
- Icon reference44×44, circle; current CircleAvatar radius22 tương ứng. Unread dot reference10px/current8px.
- Title reference Inter14/18 weight700; current titleSmall14, unread700/read500 theo shared theme.
- Body reference Inter14/20, line-clamp2; current body14/1.45 wrap đầy đủ để đọc long content.
- Timestamp reference Inter11/14; current bodySmall12/1.35; giữ formatter/model thay cho fixture relative labels.
- Theme chung đã có ink#111111/cloud#f5f5f5, Inter và BarlowCondensed local fonts; không thêm font/dependency.
- Badge Flutter99+ giữ exact count trong semantics; không hiển thị “3 MỚI” hardcoded hoặc count từ page length.

Những khác biệt trên là audit observations/plan inputs, chưa có user quyết định cần pixel-identical region nào.
Ưu tiên readable hierarchy và behavior contract; không truncate title/body làm mất nội dung mà không có accessible full view.

## Components và async states

Header title/badge, All/Unread filters, tile, feed và pagination states là responsibilities; xem [architecture](ARCHITECTURE_PLAN.md).
Giữ tile/badge hiện có; chỉ extract phần đang embedded trong page khi giúp page rõ responsibility.

| State | Current implementation | Yêu cầu visual/behavior kế tiếp |
| --- | --- | --- |
| Initial loading | shared AsyncContent | rõ loading, không flash row/badge account trước |
| Refreshing | AsyncContent + RefreshIndicator | giữ own confirmed rows, feedback refresh, khóa stale actions |
| Error/retry | shared failure message + retry | không fake count0/empty, không báo mark-read thành công |
| Empty all | “Chưa có thông báo” | khác unread-empty; cần capture riêng |
| Empty unread | “Không có thông báo chưa đọc” | filter vẫn hiện; không coi all inbox empty |
| Pagination | load-more spinner/button/retry | giữ rows khi lỗi, reachable khi text scale lớn |
| Stale | shared stale banner | không route/read từ obsolete snapshot |
| Missing resolver/target | unavailable message | ở MH17, không raw ID/PII fallback |
| Session denied/expired | FeatureAccessGate / access failure handling | bỏ private rows/count/context trong frame đổi scope |

HTML không cung cấp empty/loading/error/load-more/stale/session examples. Các state này lấy từ contract, cần Flutter evidence riêng.

## Responsive và accessibility requirements

- Future matrix widths320/360/390/412, text scale1/1.5/2, portrait/landscape, long title/body và timestamp wrap.
- Header/badge không chồng title; filters Wrap thay forced single row; không horizontal overflow ngoài category mock.
- Preserve safe areas, scroll đến tile cuối/load-more/context Close; không fixed-height text/card.
- Touch controls ≥48dp theo target Android; đo hit area thật, không suy từ glyph size hoặc mock44px.
- Heading semantics, selected filter, unread/read label, exact count và pending/disabled reason phải nghe được.
- Không chỉ dùng dot/color; unread weight + semantic label; đảm bảo contrast bằng measured colors trên target thật.
- Tile semantics hiện có parent label + child text: cần nghe TalkBack kiểm duplicate announcement và focus order.
- Read button độc lập tap tile: tránh double announcement/action; spinner không tạo trạng thái success giả.
- Empty/error/status updates cần accessible announcement phù hợp; không coi widget semantics test là audio PASS.
- `notification_only` sheet: focus/Close/Back/session-clear cần runtime review, không tạo thêm màn chính.

Không có fresh Android/Flutter screenshot comparison trong task01; [manual review](MANUAL_REVIEW.md) ghi rõ evidence lịch sử.

## Isolated implementation02

Filters dùng Wrap cho cả2chips/refresh để320dp/text2 không ép hàng; parent controlled selection, busy chỉ khóa refresh.
Context dùng heading Semantics không explicit duplicate label, SafeArea/scroll, Close min48dp và nullable callback.
Feed reuse tile nguyên trạng, margin20/gap8, shared AsyncContent; pagination button min48dp, không fake end/update label.
Tile pending read button disabled có thể chuyển tap tới outer tile open;02 giữ behavior này và có characterization test.
Parent phải recheck quyền khi mọi open callback chạy; standalone test không chứng minh navigation/read success hoặc modal auth.
Matrix320/390×text1.5/2 và targets/semantics được widget tests kiểm; không fresh pixel parity/Android/TalkBack claim.
