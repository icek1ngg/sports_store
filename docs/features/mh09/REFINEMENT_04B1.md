# MH09-04B1 — Accessibility và footer

Ngày20/10/2026. Chỉ VA01/VA02/VA03; MH09 UI vẫn NOT YET APPROVED.
Không đổi business state, session/capability checks, callback IDs, dialog, Preview hay shared theme.

## Thay đổi và số đo

| Finding | Baseline04B1 | Sau sửa |
| --- | --- | --- |
|VA01 Reject active|foreground `#D30005`, background `#FFDAD6`,4.3085117:1|local `colorScheme.onErrorContainer` resolve `#93000A`, cùng background,7.2390331:1|
|Confirm|white/`#111111`,18.883061:1|giữ nguyên|
|VA02 headings|3title thiếu heading flag|3node `Semantics(container:true,header:true)`,label đúng riêng tiêu đề|
|VA03 Reject390|x20,y784,w171,h48|x20,y788,w146.5714,h48|
|VA03 Confirm390|x199,y780,w171,h56|x174.5714,y788,w195.4286,h48|
|Footer child|h56|h48; hai nút cùng top/bottom|
|Scaffold footer reserve|y772,h72|y780,h64; padding8 mỗi phía vẫn giữ nguyên|
|Body viewport|y64,h708|y64,h716; footer reserve vẫn do layout thực tính|

Đo390×844/DPR1/scale1/insets0 trên actual integrated page, bundled fonts, canonical fixture đầu tiên.
Tỷ lệ3:5 được thử nhưng Reject wrap thành56px; chọn3:4 sau đo, không cắt text hoặc giảm font.
Không ép height48: branch stack ở width≤320,scale>1.25 hoặc chiều cao<500 giữ nguyên.
Không sửa Mh09PageLayout; SafeArea và footer scrolling/reserve tiếp tục thích ứng theo nội dung thực.
Reject vẫn destructive secondary với nền hồng/border đỏ; disabled colors và callback gates không đổi.
Contrast chỉ chứng minh hai action label trong state đã đo, không phải WCAG toàn màn hình.

Ba title: `Người mua và người nhận`, `Sản phẩm trong đơn`, `THANH TOÁN`.
`container:true` tránh kéo toàn bộ card vào một heading; không exclude/flatten child content.
Giữ typography, tên buyer/recipient, item snapshots và amount semantics.

## File và physical LOC

| File | Trước | Sau / limit |
| --- | ---: | ---: |
|widgets/mh09/mh09_action_footer.dart|179|180/180|
|widgets/mh09/mh09_recipient_section.dart|177|180/180|
|widgets/mh09/mh09_items_section.dart|131|135/180|
|widgets/mh09/mh09_payment_section.dart|133|137/180|
|test/visual_refinement/mh09_04b1_regression_test.dart|new|333/400|
|artifacts/visual_04b1/verify.cjs|new|75/150|

Đường dẫn production có prefix `lib/features/orders/presentation/`.
Public constructors nguyên trạng; không helper/model/provider/state authority mới.
Gates Confirm/Reject/Exceptional Cancel độc lập, fail closed; owner page vẫn recheck khi mở/submit dialog.

## Verification và bảo toàn evidence

Baseline [SHA/status](artifacts/visual_04b1/baseline.json) lấy working versions, không dùng HEAD làm oracle.
Original04A tests/helpers giữ nguyên, nhưng chúng ghi đường dẫn04A cố định.
Vì vậy validation chạy trên bản sao source cách ly ở writable visualization directory; package config chỉ đổi đường dẫn.
`lib/test/tool/assets` phải khớp SHA với workspace; [environment](artifacts/visual_04b1/validation_environment.json).
Mọi output của bản sao được chuyển vào namespace04B1; original workspace04A artifacts không bị ghi đè.
[Baseline log](artifacts/visual_04b1/baseline_tests.log): contrast FAIL,headings FAIL; matrix test PASS đủ15combinations.
Baseline folder chứa reports tham khảo được copy từ mirror; chỉ2a11y+15matrix là baseline rerun mới.
[Original audits](artifacts/visual_04b1/original_audits_green.log), [new tests](artifacts/visual_04b1/new_tests_final.log).
Kết quả cuối và counts: xem HANDOFF và [verification](artifacts/visual_04b1/verification.json).
Fresh:original04A8/8PASS,new04B1 5/5PASS,matrix15/15PASS;focused194PASS vàfullsuite434PASS.
[Focused log](artifacts/visual_04b1/focused_final.log),[fullsuite](artifacts/visual_04b1/full_suite.log),[results](artifacts/visual_04b1/results.json).
Analyze final/format/diff/LOC/links/5capture manifests PASS;2836protected SHA unchanged từ2843baselinefiles.
317sourcefiles lib/test/tool/assets trong validation copy khớpworkspaceSHA;không unexpected newfiles hoặc protected changes.
New test kiểm tra đúng geometry48,full label,contrast,heading duy nhất/child semantics,callback gates và stress layout.
Một finder mới ban đầu tìm semantics của recipient sau khi đã scroll đến payment nên FAIL; sửa bằng scroll đến content trước khi kiểm tra.
Không sửa/skip/weaken assertion audit04A hoặc test cũ; giữ log lần chạy đầu để truy vết.

## Ảnh và provenance

[Footer390](artifacts/visual_04b1/footer390.png), [Recipient](artifacts/visual_04b1/recipientheading.png),
[Items](artifacts/visual_04b1/itemsheading.png), [Payment](artifacts/visual_04b1/paymentheading.png),
[320/scale2](artifacts/visual_04b1/footer320scale2.png).
[Manifest](artifacts/visual_04b1/capture_manifest.json): source/font/image SHA,fixtureUUID,viewport,DPR,scale,capture method.
Actual `Mh08PreviewApp(showControls:false)`→MH08→MH09; cùng valid aggregate, không fake simplified page.
Ảnh là Flutter widget raster, KHÔNG Android runtime; ảnh04A/03B giữ nguyên.

## Còn lại

VA04 contact grouping và VA05 product tiles chưa sửa; VA06/VA07 optional chưa triển khai.
Full TalkBack focus/audio,actual docked Android IME,gesture Back và Android final acceptance NOT VERIFIED trong04B1.
Synthetic keyboard/dialog regression không thay thế docked IME. Không backend/Auth/router/mutation integration mới.
Đề xuất04B2 bounded: chỉ VA04/VA05 nếu user duyệt, giữ snapshot/contact callbacks và business contract; review trước optional polish.
Không tự bắt đầu04B2 và không đánh dấu MH09 UI approved.
