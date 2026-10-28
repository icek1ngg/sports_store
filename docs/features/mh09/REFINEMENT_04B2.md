# MH09-04B2 — Contact grouping và product tiles

Ngày20/10/2026. **MH09-04B2 — CONTACT & PRODUCT TILES REFINED, READY FOR VISUAL REVIEW**.
Chỉ VA04/VA05; MH09 UI vẫn NOT YET APPROVED. Không bắt đầu VA06/VA07 hoặc Android acceptance.

## Quyết định trước production edits

Recipient180/180: tách contact controls/reasons thành `Mh09ContactActions` presentation-only, giữ nguyên section public API.
Items135/180: sửa private row cục bộ thành white tile; chưa cần ItemTile extraction hoặc state/controller mới.
Baseline [SHA/status](artifacts/visual_04b2/baseline.json) chụp working versions trước edit, không dùng HEAD.
Branch `feature/orders-notifications-phase2`;2910files;2235dirty entries(19trackedmodified,2216untracked).
Existing focused194PASS mới trước edits;original04A8/04B1 5/matrix15 đều PASS.

## VA04 — kết quả đo

390×844/DPR1/scale1,canonical order `30000000-0000-4000-8000-000000019999`,bundled Inter/Barlow.

| Vùng | Trước | Sau |
| --- | --- | --- |
|Call|x36,y430,w88.9748,h48|x36,y430,w155,h48|
|Chat|x132.9748,y430,w123.3059,h48|x199,y430,w155,h48|
|Group gap|8px|8px; dùng hết318px content width|
|Recipient card|x20,y232,w350,h310|x20,y232,w350,h302|
|Reason|body14/20,primary density|bodySmall12/16,muted token; nguyên nội dung/lý do|

Public constructor `Mh09RecipientSection({required Order order,Buyer? buyer,VoidCallback? onCall,VoidCallback? onChat,bool contactEnabled=true,Key? key})` giữ nguyên.
Giữ account holder khác recipient snapshot; giữ phone/address thật và fallback.
Thiếu phone chỉ khóa Call,không khóa Chat; callback null chỉ khóa action tương ứng; contactEnabled=false khóa cả hai.
Không dialer/chat navigation/repository/provider/auth logic mới. Parent vẫn giữ manager/session/current-detail authority.
Heading có `container:true,header:true` đúng một node; controls/reasons/child data không bị ẩn.

`Mh09ContactActions({bool callEnabled=false,bool chatEnabled=false,String? callReason,String? chatReason,VoidCallback? onCall,VoidCallback? onChat,Key? key})`.
Section tính availability như cũ; helper chỉ render explicit flags/reasons/callbacks.
Stack khi availableWidth <300×max(1,textScale); chỉ layout threshold,không clamp text scale.
390/412 scale1.5/2 stack;320scale2 stack;844landscape scale2 vẫn row rộng,đủ labels.
Giữ keys,semantic labels,disabled/no-tap semantics,48px targets,8px spacing và pill shape.

## VA05 — kết quả đo

| Vùng | Trước | Sau |
| --- | --- | --- |
|Item surface|row318×112,không inner tile|white tile318×128,radius16,padding8|
|Inner row|318×112|302×112; giữ64px placeholder|
|Inter-item separation|24px divider region|12px gap,không divider|
|Items section|350×354|350×374|
|Name / line total|theme weights|w600 / w700 cục bộ để làm rõ snapshot hierarchy|

Card cao hơn20px là khoảng thở bên trong tiles,không ép height theo HTML khác dữ liệu.
Giữ `Mh09ItemsSection({required List<OrderItem> items,Key? key})`,unmodifiable list,cùng OrderItem objects/attributes/UUID/order.
Giữ name,variant,quantity,stored unit price/line total và shared formatVnd;không recompute order totals/copy catalog.
Raw attributes vẫn nguyên map; fixture `source`/debug metadata không được biến thành thông tin sản phẩm hiển thị.
Variant snapshot tiếp tục hiển thị nguyên giá trị;không thêm arbitrary attributes formatter hoặc che field đang có.
Không remote images;placeholder trung thực;không nested scroll. Heading semantics giữ nguyên.

## Source và physical LOC

Production prefix:`lib/features/orders/presentation/widgets/mh09/`.

| File | Trước → sau / limit |
| --- | ---: |
|mh09_recipient_section.dart|180→131/180|
|mh09_items_section.dart|135→155/180|
|mh09_contact_actions.dart|new109/180|
|test/visual_refinement/mh09_04b2_contact_test.dart|new330/400|
|test/visual_refinement/mh09_04b2_items_test.dart|new226/400|
|test/visual_refinement/mh09_04b2_visual_test.dart|new192/400|
|test/visual_refinement/mh09_04b2_capture.dart|new57/150|

Utilities prepare/compare/verify≤150;all feature Markdown≤200,HANDOFF≤100.
Items đã trên80% cap;future additions cần xem xét meaningful tile extraction,nếu thực sự cần,không inflate hoặc dùng part files.

## Tests và source safety

[Baseline194](artifacts/visual_04b2/baseline_tests.log),[focused221](artifacts/visual_04b2/focused_final.log).
[New04B227PASS](artifacts/visual_04b2/new_tests_final.log):contact8/items17/actualPreview2.
[Full final461PASS](artifacts/visual_04b2/full_suite_final.log);không fail/skip/weaken old assertions.
Original04A8/8PASS,04B1 5/5PASS,matrix15/15PASS,VA01/02/03 không regress.
Full gồm MH07/MH08,Preview navigation/scenarios,header/frameworkBack,K1,session/privacy/dialog/owner regressions.
Reachability bổ sung sau focused:long reason+Chat320scale2,item40line total và timeline bottom nằm trong viewport,không bị footer che.
[Reachability2PASS](artifacts/visual_04b2/reachability_final.log),sau đó chạy lại new27 vàfull461 trên final source.
[Analyze](artifacts/visual_04b2/analyze_verified.log),[format](artifacts/visual_04b2/format_final.log),diff/LOC/links/manifest PASS.
Review độc lập không còn finding;wide-landscape stacking được sửa theo combined width/font threshold.

Hai test mới ban đầu sai oracle (Ahem metrics và callback non-null nhưng đòi unavailable);sửa fixture/font loading,không sửa test cũ.
Unused import trong capture helper mới được loại bỏ;analyze chạy lại không còn issue. Giữ logs lần đầu để trace.
Missing phone là defensive legacy presentation test double;không tuyên bố đó là valid production aggregate.

Original04A/04B1 tests có fixed output paths,nên chạy isolated exact-source copy để bảo toàn lịch sử.
[Environment](artifacts/visual_04b2/validation_environment.json);lib/test/tool/assets phải khớpSHA working tree.
Before captures dùng source hai widget khớp fresh baseline SHA:[proof](artifacts/visual_04b2/baseline_capture_sources.json).
[Verification](artifacts/visual_04b2/verification.json),[results](artifacts/visual_04b2/results.json) ghi protected count/source equality/LOC/matrix.
FinalSHA:2905protected files nguyên trạng;322lib/test/tool/assets files trong validation copy khớpworking source.
Không unexpected newfiles;9widget captures và derived comparison đúnghash/dimensions/provenance;all feature links/LOC PASS.
Protected gồm MH07/MH08,footer/header/payment/page/coordinator/Preview/shared/models/providers/oldtests/oldartifacts.
Không commit/push/reset/clean/checkout/switch/stash/merge/delete;existing dirty/untracked giữ nguyên.

## Ảnh và comparison

[HTML / BEFORE / AFTER](artifacts/visual_04b2/comparison_contact_items.png),[comparison provenance](artifacts/visual_04b2/comparison_manifest.json).
[Contact390](artifacts/visual_04b2/final/contact_390.png),[Items390](artifacts/visual_04b2/final/items_390.png).
[Long recipient320scale2](artifacts/visual_04b2/final/contact_320_scale2.png),[controls/reason](artifacts/visual_04b2/final/contact_320_controls.png).
[Long items320scale2](artifacts/visual_04b2/final/items_320_scale2.png),[item40](artifacts/visual_04b2/final/items_40_last.png),[later sections](artifacts/visual_04b2/final/items_40_later_sections.png).
[Capture manifest](artifacts/visual_04b2/capture_manifest.json):before/after source,font/imageSHA,scenario,UUID,size,DPR,textScale,method.
Actual stable Preview MH08→integratedMH09,fonts loaded,real scrolling,không simplified page hoặc synthetic full-page stitching.
9widget rasters gồm2baseline+7final;1derived native-pixel comparison. HTML reference có membership/photos/mockdata,không copy vào Flutter.
Card height khác HTML do account≠recipient và đủ snapshot fields;không dùng pixel fidelity score giữa datasets khác nhau.

## Còn lại và review tiếp theo

VA06/VA07 optional vẫn chưa triển khai. MH09 UI chưa approved.
Không build/install/launch Android mới;ảnh chỉ widget rasters,KHÔNG Android runtime.
FULL TALKBACK FOCUS/AUDIO,actual docked Android IME,gesture Back/device acceptance NOT VERIFIED trong04B2.
Không backend/Auth/router/RLS/concurrency/external mutation integration mới;submissions vẫn unavailable đúng contract.
Đề xuất user review comparison +screenshots trước;Android/manual acceptance chỉ trong task riêng được giao.
Sau visual review mới kiểm tra docked IME/TalkBack/gesture/session/navigation trên thiết bị;không tự bắt đầu.
