# MH08-04A — Visual audit

Trạng thái: **VISUAL AUDIT COMPLETE, READY FOR TARGETED REFINEMENT**. Ngày16/10/2026.
**MH08 UI NOT YET APPROVED**. Các bảng04A là lịch sử; kết quả refinement04B2 ở cuối tài liệu.

## Evidence và phương pháp

Base: `docs/features/mh08/artifacts/visual_04a/`.

- [So sánh390](artifacts/visual_04a/comparison_390.png), [overlay50%](artifacts/visual_04a/overlay_390.png), [geometry](artifacts/visual_04a/comparison_metrics.json).
- [HTML390×844 mới](artifacts/visual_04a/html_390x844.png), [full page](artifacts/visual_04a/html_390_full.png), [HTML manifest](artifacts/visual_04a/html_render_manifest.json).
- [Flutter top](artifacts/visual_04a/mh08_04a_390_top.png), [first card](artifacts/visual_04a/mh08_04a_390_firstcard.png), [middle](artifacts/visual_04a/mh08_04a_390_middle.png), [bottom](artifacts/visual_04a/mh08_04a_390_bottom.png).
- [Pending actions](artifacts/visual_04a/mh08_04a_390x844_s1_0_pending_actions.png), [warning](artifacts/visual_04a/mh08_04a_390x844_s1_0_warning.png), [long text](artifacts/visual_04a/mh08_04a_390_longtext.png).
- [Confirm](artifacts/visual_04a/mh08_04a_390_confirm.png), [reject](artifacts/visual_04a/mh08_04a_390_reject.png), [keyboard inset](artifacts/visual_04a/mh08_04a_390_keyboard.png).
- [Loading](artifacts/visual_04a/mh08_04a_390_loading.png), [empty](artifacts/visual_04a/mh08_04a_390_empty.png), [error](artifacts/visual_04a/mh08_04a_390_error.png), [stale](artifacts/visual_04a/mh08_04a_390_stale.png).

HTML render Chromium mới giữ nguyên source; DPR1,390×844, font Inter/Barlow/Symbols loaded,0 failed requests.
Flutter là **widget render**, DPR1,390×844/scale1, load Inter/Barlow/MaterialIcons qua FontLoader.
Dùng `Mh08PreviewApp(showControls:false)` thật + manager fixtures03B, không mock card/page khác.
Ẩn toolbar DEMO để so viewport tương đương; không giả system bars. Android evidence có toolbar/system bars, ghi riêng.
Overlay chỉ giúp thấy offset; khác data, font rasterization và contract nên không dùng làm điểm pixel-perfect.
Các ảnh keyboard widget chỉ giả bottom inset300, không vẽ bàn phím OS; vùng trắng phía dưới là vùng IME dành chỗ.

## Region comparison

Các target dưới thuộc `lib/features/orders/presentation/widgets/mh08/`; giữ shared theme/dialog/provider nguyên trạng.

| Vùng | HTML expected | Flutter actual / difference | Severity / cause | Suggested04B / target |
| --- | --- | --- | --- | --- |
| Header | h64, Barlow28, brand14 | h64; đúng font/weight700; refresh thay cart/profile | P3 intentional; không copy title bị cắt | Giữ `mh08_header.dart` |
| Search/filter | y68, visual40h | y68, field/filter48h; search w294 | P2 nhỏ; min48 hit target làm tăng8px | Nếu cần, tách visual40 khỏi hit48; `mh08_search_section.dart` |
| KPI | y124/h81,3 demo panels | y132/h82,2 authoritative panels | P3 intentional2 KPI; y+8 theo search | Giữ counts/asOf; keyboard sửaK1 ở layout/controls |
| Status chips | y223, compact pill | region y250/h52; total canonical thêm một dòng | P2 density; hit area + total + spacing | Tune gaps/count placement, giữ đủ10 status/hit targets; `mh08_list_controls.dart`, `mh08_status_chips.dart` |
| Card shell | x20/y269/w350/h234 card1 | x20/y318/w350/h580; radius16 | P2 density, P3 radius intent; data khác nhiều | Tune spacing, không ép234 bằng cách bỏ data; `mh08_order_card.dart` |
| ID/time/status | short DH code + time cùng row | UUID20/26 ellipsis + tooltip/semantics; time/status row riêng | P3 contract; đúng font20/700 | Giữ UUID thật/callback; không fake short code |
| Buyer panel | cloud, avatar40, tên/address ngắn | cloud/40px; h142 do account+recipient/address/phone | P2 presentation có thể gọn; phần lớn do data contract | Inline label/gap có kiểm chứng, giữ distinction/readability; `mh08_buyer_section.dart` |
| Item preview | card1 rút gọn; card2 một item56px |2 snapshot rows/placeholder; h148, quantity lặp ở payment | P2 duplicate quantity/density; placeholder P3 intentional | Gộp quantity hợp lý, giữ snapshot names; `mh08_item_preview.dart`, `mh08_payment_section.dart` |
| Payment/COD | amount20/26 + COD pill | h48, amount20/26, COD status truthful/unknown | P3 contract projection; không hardcode HTML amount | Giữ integer VND/COD states; không rút bỏ unknown |
| Operational notice | demo unassigned/shipper | chỉ typed failed warning, full wrap | P3 intentional/no unsupported action | Giữ full warning; `mh08_operational_notice.dart` |
| Action buttons | reject cloud/red + confirm black, pill38h |155×48 mỗi nút; details318×48, enabled đúng capability | P3 min48 + navigation; colors/hierarchy hợp intent | Không giảm hit target; `mh08_card_actions.dart` |
| Scroll density | khoảng2 cards + phần card3/top | first card580h, feed bắt đầu muộn49px; details xuống dưới fold | P2, data+controls+duplicate quantity; không phải raw pixel error | Compact sections tuần tự, giữ readable scales và authority |

Chiều cao card chênh346px không phải lỗi346px độc lập: buyer142 + item148 + full UUID/COD/details khác reference.
Tổng quantity đang xuất hiện ở cả item preview và payment là phần dư có thể xử lý trước.
Màu, typography chính, x20/w350, pill actions đã gần visual intent; không phát hiện missing business section.

## Defect priorities — lịch sử04A; K1 đã đóng ở04B1 bên dưới

- **K1 / P1**: KPI/total không ẩn khi keyboard inset>0, trái UI_SPEC; cả15 cases tái hiện.
- Cause: `mh08_page_layout.dart:19` tạo Scaffold resize mặc định, consume viewInsets trước body.
- `mh08_list_controls.dart:42` đọc viewInsets trong body nên luôn thấy0. Feed vẫn tránh inset; không có overflow.
- Target04B: truyền keyboard visibility từ context trước Scaffold hoặc giữ đúng MediaQuery; consume inset đúng1 lần.
- **D1 / P2**: density/duplicate quantity, target card/buyer/item/payment/list controls như bảng; tránh mất data.
- **D2 / P2**: search/chip visual size/gaps và discoverability khi controls phải cuộn ở scale lớn/landscape.
- **P0**: không phát hiện runtime crash/private leak/broken action trong phạm vi đã chạy.

## Responsive matrix — historical04A execution (giữ evidence nguyên trạng)

[Matrix JSON](artifacts/visual_04a/mh08_04a_matrix_report.json), [reference JSON](artifacts/visual_04a/mh08_04a_reference_report.json).
Tên ảnh matrix: `mh08_04a_<width>x<height>_s<scale>_{top,pending_actions,bottom,keyboard,failure}.png`.
390 có thêm warning/longtext/SafeArea. Mỗi case dùng font thật và pagination đủ10 rows.

| Viewport | Scale1.0 | Scale1.5 | Scale2.0 |
| --- | --- | --- | --- |
|320×844|FAIL K1|FAIL K1|FAIL K1|
|360×844|FAIL K1|FAIL K1|FAIL K1|
|390×844|FAIL K1|FAIL K1|FAIL K1|
|412×844|FAIL K1|FAIL K1|FAIL K1|
|844×390|FAIL K1|FAIL K1|FAIL K1|

15/15 PASS cho không RenderFlex/Flutter exception, scroll/pagination, chip gesture, KPI reflow, long buyer/address,
confirm/reject/details hit targets≥48, SafeArea bottom, list/footer tránh keyboard300.
15/15 FAIL riêng KPI/total hiding; không gọi toàn bộ responsive PASS. Controls cuộn riêng theo cap55% là documented reflow.
Ở scale lớn/landscape phải cuộn header để tới chips; harness đưa chips vào visible bounds trước khi thử gesture.

## Android và accessibility

- Pixel5/API35, build/install/launch `tool/ui_preview/main.dart` thực; default MH07 và chuyển MH08/back MH07 hoạt động.
- Full UUID→1 order/counts đúng; clear/search, chip scrolling, scrolling page2+, KPI, dialogs/blank reason/unavailable: PASS.
- MH08→MH09→Back exact UUID, scenario empty/error/stale/expired/unauthorized/session unavailable: PASS.
- Expired/unauthorized/session unavailable:0 private UUID/buyer nodes trong UI hierarchy; không fake fallback.
- Logcat không ghi nhận uncaught Flutter/AndroidRuntime errors trong smoke; không có mutation success.
- [Android data](artifacts/visual_04a/android_runtime_data.png), [paging](artifacts/visual_04a/android_runtime_paging.png), [search/IME](artifacts/visual_04a/android_runtime_search.png).
- IME báo shown=true nhưng Gboard dùng toolbar nổi, không có docked inset300; không dùng runtime này để bác bỏ K1.
- TalkBack installed/bound tạm; labels đọc được trong hierarchy. Sample Tab focus thấy screen selector/refresh.
- Full TalkBack swipe focus order và audio announcements **NOT VERIFIED**; không tự đánh dấu accessibility PASS.
- Đã khôi phục accessibility_enabled=0/enabled_accessibility_services=null như trước audit; không đổi project config.

## Quality / tooling boundaries

- 2 audit tests chạy và **FAIL** vì K1; không sửa assertions để xanh, không sửa production để vượt scope.
- 89 existing affected tests PASS gồm19 Preview +70 MH08; Analyze sạch, format/diff/LOC PASS.
- 265 full-suite PASS là lịch sử03B, không rerun full trong04A vì production không đổi; hiện audit tests còn đỏK1.
- Harness corrections: import scenario, real I/O trong runAsync, settle query, scroll chips vào visible bounds.
- 6 infrastructure files mới: capture helper146, matrix395, evidence343, HTML renderer98, Android helper31, compare script46 LOC.
- Protected source/reference hashes và manifest04A ghi ở [verification](artifacts/visual_04a/audit_verification.json).

## Bounded MH08-04B proposal — chờ người dùng duyệt

1. Chỉ sửa keyboard visibility tại MH08 layout/controls; giữ page288/controller238/shared/MH07, rerun15 cases +19 Preview +70 MH08.
2. Sau đó tune P2 density từng section: duplicate quantity, gaps/count placement; không bỏ account/recipient/warnings/COD/snapshots.
3. Render lại cùng390×844 và giữ scalable48px hit targets; full responsive/Android recheck và full suite ở checkpoint04B.
4. Không sửa shared dialogs/theme, MH09/MH17/backend hoặc tự đánh dấu UI APPROVED.


## MH08-04B1 — K1 resolved,16/10/2026
Capture bool keyboardVisible từ MediaQuery trước Scaffold; Mh08KeyboardVisibility thông báo controls khi bool đổi.
Controls đọc signal thay consumed viewInsets; không timer/state mới, không thêm inset/padding, không disable resize.
Chỉ sửa `mh08_page_layout.dart` (74LOC), `mh08_list_controls.dart` (65LOC); page/shared/coordinators/cards không đổi.
Red baseline: original2audit tests FAIL K1. Sau fix:2PASS, toàn15matrix cases PASS, không thay assertions/audit sources.
Test mới `test/ui_preview/mh08_keyboard_lifecycle_test.dart`274LOC:15 open-close-reopen + paginated feed,2PASS.
KPI/total trở lại đúng counts, search/status/paging/read count giữ nguyên; không exception/overflow/double resize.
89 affected tests PASS; full suite269 PASS, Analyze/format/diff/LOC PASS.290 protected baseline hashes giữ nguyên.
Ảnh/report/overlay/failure04A phía trên không bị ghi đè; bảng FAIL04A là lịch sử red baseline, current K1 đã PASS.
Android K1 APK chạy trên Pixel5/API35; Gboard còn floating/toolbar, docked keyboard runtime **NOT VERIFIED**.
K1 đóng. P2 density/search/chip geometry không sửa trong04B1; chờ duyệt04B2. UI NOT YET APPROVED.

## MH08-04B2 — D1/D2 refined,16/10/2026

[HTML / baseline / refined](artifacts/visual_04b2/comparison_390.png), [overlay](artifacts/visual_04b2/overlay_before_after.png).
Widget render mới, fonts thật, Preview composition/fixtures03B; không phải Android runtime hoặc user approval.

| Vùng | Baseline04B2 | Sau04B2 | Kết luận |
| --- | --- | --- | --- |
| First card | y318/h580 | y277/h476 | Giảm104px/17.93%, cùng dữ liệu; không bỏ thông tin |
| Buyer | h142 | h106 | Inline label/value, avatar32; hẹp/chữ lớn stack |
| Item preview | h148 | h104 | Placeholder48, variant/qty Wrap; aggregate chỉ ở payment |
| KPI | y132/h82 | y124/h81 | Barlow28,2 canonical counts giữ nguyên |
| Chips | y250/h52 | y213/h48 | Total canonical cùng strip, đủ enum; hit target≥48 |
| Actions/details | y778/y834 | y633/y689 | Mỗi control48h, hiện đủ trong viewport đầu390×844 |

UUID tooltip/semantics đầy đủ; account/recipient/address/phone/snapshots/COD/typed warning giữ nguyên.
Warning vẫn hiển thị nguyên message; không tạo action, mutation hoặc hidden expansion mới.
Original2 audit tests PASS, **15/15 responsive cases PASS**, keyboard lifecycle2 PASS; affected100 PASS, full276 PASS.
Không P0/P1 mới trong phạm vi đã chạy; P2 density giảm rõ nhưng card vẫn lớn hơn HTML vì dữ liệu/contracts thật.
Search48 thay HTML40,2 KPI, UUID, placeholders, details48, radius intent16 và không bottom navigation vẫn intentional.
[Refined report](artifacts/visual_04b2/mh08_04b2_refined_report.json) xác minh logical390×844/scale1,320×844/scale2 và844×390.
Baseline390 hợp lệ; hai ảnh baseline tên320 bị cấu hình DPR nhầm thành160×422/scale1, report đánh dấu excluded; không dùng kết luận responsive.
Nguồn04A/HTML/MH07/shared/page/controller/fixtures được giữ hash; [source check](artifacts/visual_04b2/source_verification.json).
Android/docked IME/TalkBack lượt này **NOT RUN**; dành04B3. Không tuyên bố pixel-perfect hoặc APPROVED.
