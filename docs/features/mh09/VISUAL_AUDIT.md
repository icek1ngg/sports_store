# MH09-04A — Visual, responsive và accessibility audit

**MH09-04A — VISUAL AUDIT COMPLETE, READY FOR TARGETED REFINEMENT**.
Ngày20/10/2026 Asia/Saigon. MH09 UI NOT YET APPROVED. Audit không sửa production hoặc bắt đầu04B.

## Phương pháp và provenance

Fresh baseline2637working files/1962dirty entries,branch feature/orders-notifications-phase2; SHA-256 working versions, không HEAD.
[Baseline](artifacts/visual_04a/baseline.json), [verification](artifacts/visual_04a/verification.json), [capture manifest](artifacts/visual_04a/capture_manifest.json).
2634protected baseline files nguyên hash: toàn lib/,existing Preview/fixtures/tests,HTML và old artifacts.
Actual `Mh08PreviewApp(showControls:false)`→same stable ProviderScope→MH08 card push→integrated ManagerOrderDetailsPage.
Audit wrapper chỉ RepaintBoundary/MediaQuery; không page giả, provider mới, fixture/model mới hoặc sections bị loại bỏ.
Navigation mở ở390/scale1 rồi áp target size/scale trên cùng tree/container, tránh đánh giá approved MH08 dưới stress của MH09.
FontLoader thực tải Inter variable,BarlowCondensed Bold và MaterialIcons; asset hashes trong manifest, không Ahem.
Primary390×844,DPR1,scale1,insets0; same viewport với reference HTML. Test captures là widget raster, KHÔNG Android runtime.
Các ảnh top/middle/bottom chụp sau gesture trên scroll owner thật; sticky footer hiện đúng từng viewport, không ghép full-page giả.
82direct widget captures và2derived comparison figures có hash; mỗi capture ghi UUID/scene/viewport/DPR/scale/fonts/insets/method.
HTML/source/2PNG khớp original hashes; [reference validation](artifacts/visual_04a/reference_validation.json) PASS.
Reuse validated Chromium390×844/DPR1,Inter/Barlow/Symbols loaded,2images decoded,scrollHeight1475; không render HTML mới.
HTML full screenshot fixed-footer tại initial y772 là capture behavior, không target footer giữa Flutter content.

## Screenshot index

| Evidence | Link |
| --- | --- |
| HTML vs actual Flutter |[paired390](artifacts/visual_04a/comparison_390.png), [paired footer](artifacts/visual_04a/comparison_footer.png)|
| Primary top/identity/footer |[top](artifacts/visual_04a/primary_390_top.png)|
| Buyer/recipient/contact |[recipient](artifacts/visual_04a/primary_390_recipient_focus.png)|
| Product snapshots |[items](artifacts/visual_04a/primary_390_items_focus.png)|
| Exact financial overview |[payment](artifacts/visual_04a/primary_390_payment_focus.png)|
| Independent Delivery/COD |[delivery](artifacts/visual_04a/primary_390_delivery_focus.png), [COD](artifacts/visual_04a/primary_390_cod_focus.png)|
| Returns/timeline/end |[returns](artifacts/visual_04a/primary_390_returns_focus.png), [timeline](artifacts/visual_04a/primary_390_timeline_focus.png), [bottom](artifacts/visual_04a/primary_390_bottom.png)|
| External unavailable |[operations](artifacts/visual_04a/primary_390_operations.png)|
| Large/long stress |[40items end](artifacts/visual_04a/mh09_04a_390_large_bottom.png), [320 scale2 long](artifacts/visual_04a/mh09_04a_320_s2_long.png)|
| Synthetic keyboard / expiry |[keyboard](artifacts/visual_04a/mh09_04a_320_s2_dialog_keyboard.png), [expired](artifacts/visual_04a/mh09_04a_320_s2_dialog_expired.png)|

All82 captures/scenario labels và source hashes có trong manifest; hình failure/menu cũ của task khác không dùng làm evidence04A.
[Geometry JSON](artifacts/visual_04a/comparison_geometry.json), [primary measurements/styles](artifacts/visual_04a/primary_390.report.json).

## Region comparison — logical px tại primary390

Rect Flutter đo trước scroll; y của các card sau chịu offset tích luỹ, không phải defect riêng theo từng delta.

| Vùng | HTML expected | Flutter actual | Đánh giá / root cause / target |
| --- | --- | --- | --- |
| Header |h64,title28/32,back44|h64,title28/32,back/refresh48;title box x68,w254 vsx56,w282|cân giữa;48target/refresh intentional; flat surface VA06; mh09_header.dart|
| Identity |short DH+badge/meta96|full UUID+badge+time132,y84|canonical identity làm tăng36px; intentional, không cắt UUID; mh09_order_identity.dart giữ contract|
| Buyer/recipient |x20,y160,w350,h186.5|x20,y232,w350,h310|+123.5h:2identities/4rows/48controls/reasons; không bỏ data;contact refinement VA04|
| Contact |2×155×38,surface white|88.97×48 và123.31×48,intrinsic widths,disabled gray|48/disabled intentional;balance/reason density VA04; mh09_recipient_section.dart|
| Products |x20,y362.5,w350,h249,white inner tiles|x20,y558,w350,h354,placeholder/divider|+105h do full variant/quantity/unit/line price;tile hierarchy VA05; mh09_items_section.dart|
| Payment |y627.5,h289,includes fake discount|y928,h271,total32/36 Bold700|no discount/real30kfee intentional;total dominant;minor label weight VA07; mh09_payment_section.dart|
| Delivery |mock shipper strip|separate249px card|contract-required independent state/null truth, không fake assignment|
| COD |single payment badge|separate281px reconciliation card|expected/collected/received riêng;null không zero; không gộp OrderStatus|
| Returns |absent|separate93px empty summary;active Return in normal delivered scene|contract-required,read-only;empty/source-unavailable model limitation giữ như trước|
| Timeline |6planned stages,h414|actual events,h185,y1878|khác dataset/events,không copy6stages;shared OrderTimeline unchanged|
| Operations |mock external behavior|capability true vẫn disabled+reason|intentional owner boundary, không fake success; mh09_operational_actions.dart|
| Footer |bar y772,h72;Reject126.53×48,Confirm215.47×48|bar y772,h72;equal171w,Reject48/Confirm56,top lệch4|reserve/insets đúng;label wrap/unequal geometry VA03; mh09_action_footer.dart|
| Typography |Inter20/26,body14;totalBarlow800|same primary sizes;bundled700 total;case/icons differ|700 intentional font asset;headings semantics VA02;polish VA07|
| Density |document scrollHeight1475|main scroll content2059|khác metrics/data;3independent panels riêng623px giải thích phần lớn tăng, không quality percentage|

Main gutter20,section gap16,card padding16/radius32 khớp. Footer không che last content; không ép mọi card theo mock height.
Không dùng pixel similarity percentage hoặc tổng scroll length để kết luận quality khi business datasets khác nhau.

## Responsive matrix — 15 actual layout combinations

| Logical viewport |scale1|scale1.5|scale2|
| --- | --- | --- | --- |
|320×844|PASS|PASS|PASS|
|360×844|PASS|PASS|PASS|
|390×844|PASS|PASS|PASS|
|412×844|PASS|PASS|PASS|
|844×390|PASS|PASS|PASS|

[Matrix test log trong final audit](artifacts/visual_04a/audit_tests_verified.log);15per-case JSON/PNG top/bottom trong manifest.
Không RenderFlex overflow/uncaught exception;full UUID/status/amount semantics,sections/bounds/order/non-overlap PASS.
Back/refresh/contact/actions≥48;body scroll/payment/timeline reachable bằng gestures;footer reserve và disabled gates PASS.
Tất cả portrait dùng synthetic top24/bottom34;landscape left24/right24/bottom24,không clamp text scale.
Primary comparison riêng insets0 để ngang reference browser. SafeArea/insets ở đây là widget simulation, không device measurements.
High-risk thêm320scale2 long names/address/products,390scale1 40items→last row→timeline,landscape1.5/2footer PASS.
Functional matrix PASS không xoá contrast/heading FAIL hoặc visual wrap finding VA03.

## Scenario coverage — 19/19 values, targeted sampling

| Scene values thực thi | Fixture / assertions |
| --- | --- |
|canonical|pending record1,fullUUID,buyer≠recipient,multiple items,payment,normal footer|
|normal|delivered record5,Delivery delivered/COD collected/Return pending_review và actual timeline riêng|
|large|record9,40snapshots,valid integer amount relationships,last item và last section reachable|
|missingDelivery,missingCod|null riêng;unknown truthful,không suy unassigned/uncollected|
|missingBuyer,emptyReturns|projection null/empty riêng,không crash/fixture fallback|
|confirmOnly,rejectOnly,commandsDenied|per-operation independently enabled/disabled,không infer từ pending status|
|exceptionalCancel|preparing record3,manager cancel distinct,48target|
|operations|preparing và failed-delivery fixtures,external capability true vẫn unavailable|
|loading,error,stale|held refresh/release,explicit network error/retry,stale snapshot read-only|
|expired,unauthorized,unresolved|UUID/buyer/items không còn trên screen,explicit denied/loading state|
|accountSwitch|new manager owner/cache,old40world biến mất;authorized B được xem cùng store-wide canonical buyer|

Cả19 values đã có capture+checks;không phải19×15 exhaustive cross-product hoặc backend verification.
[Scenario report](artifacts/visual_04a/mh09_04a_scenarios.report.json), [privacy/capabilities](artifacts/visual_04a/mh09_04a_privacy.report.json).
Transport selector là refresh trên accepted detail;existing page tests kiểm tra thêm cold loading/error và owner/late states.

## Accessibility, footer và keyboard

Full canonical UUID/header/back/refresh/status/money semantics và visual section order PASS;status không chỉ dùng màu.
Major headings chưa có heading flag:VA02;không gọi visual order checks là full TalkBack traversal/audio test.
Active Reject contrast4.3085:1 FAIL threshold4.5 cho14px;Confirm white/ink18.8831:1 PASS.
Disabled gray contact exempt active-text contrast nhưng vẫn có disabled semantics/reasons,callback không dispatch.
Footer Reject trước Confirm;48/56px targets đều reachable,không overlap;unequal height/wrapped Confirm giữ VA03 mở.
Reject320scale2 với viewInsets.bottom300:reason/submit/close≥48,reachable,controls trên y544 PASS.
Blank và>1000rune reason validation PASS;valid reason→unavailable,expiry xoá reason/private fields và Close hoạt động PASS.
[Dialog report](artifacts/visual_04a/mh09_04a_dialog.report.json);không double bottom inset/overflow trong simulated test.
FULL TALKBACK FOCUS/AUDIO — NOT VERIFIED. Actual docked Android IME/gesture Back — NOT VERIFIED trong04A.
Không launch/build Android mới;19Android03B images và API35 smoke là lịch sử, không relabel widget captures.

## Defect register / severity

P0=0,P1=0;P2=5 (2automated accessibility failures +3visual findings);P3=2cosmetic observations.

| ID |Severity/evidence|Root cause và bounded04B target|
| --- | --- | --- |
|VA01|P2:Reject4.3085<4.5;test FAIL|sale foreground trên pale red; local foreground change trong mh09_action_footer.dart,không theme global|
|VA02|P2:3major headings header flag=false;test FAIL|Text chỉ style,không semantic header;MH09 heading composition trong recipient/items/payment|
|VA03|P2:Confirm wrap2lines/h56 vsReject48/top4px|equal171w+icon/padding/letter spacing;adapt normal footer widths/label layout,giữ full label/callback/gates|
|VA04|P2:contact intrinsic89/123w,explanation dài|layout chưa cân/hierarchy thấp;MH09 recipient grid/reason compaction,giữ disabled truth/2identities|
|VA05|P2:product rows cloud+Divider thiếu white tiles|visual hierarchy khác HTML;MH09 items inner surface/radius16,giữ snapshot/quantities/prices/readability|
|VA06|P3:flat header/footer thiếu subtle separation|MH09 header/layout surface/divider/elevation optional,không global theme|
|VA07|P3:case/icons/non-total semibold khác reference|optional MH09-only heading/financial-label polish;giữ total dominant/bundled fonts|

Không nâng VA01–03 thànhP1 vì vẫn đọc/dispatch/reach được,không clipping/overlap/mất nội dung/sai tiền;FAIL vẫn giữ nguyên.
Intentional deviations KHÔNG tính là defects:fullUUID,real amounts,account≠recipient,placeholder,no vouchers,4lifecycles,actual events,unknown projections,unavailable actions,48targets,adaptive height.

## Verification và handoff

Existing focused181PASS mới:page/integration/owner/session/components/Preview navigation/header+frameworkBack/MH08/K1.
New audit run8widget tests:6PASS/2FAIL;one matrix test thực thi đủ15combinations. FAIL chỉ VA01/VA02,không skip/weaken.
PowerShell: `$tests = @(Get-ChildItem test/visual_refinement/mh09_04a*_test.dart | ForEach-Object FullName)` rồi `flutter test --no-pub @tests`.
[Existing log](artifacts/visual_04a/baseline_tests.log), [final audit](artifacts/visual_04a/audit_tests_verified.log), [analyze](artifacts/visual_04a/analyze_final.log).
Full suite NOT RUN04A;421fullPASS là historical03B,không cộng counts hoặc claim freshfullgreen.
Analyze/format/diff/LOC/links/screenshot hashes/protected source PASS;[verification](artifacts/visual_04a/verification.json) tách integrityPass khỏi auditFailures.
Intermediate import/finder/scroll-owner/oracle issues là test harness corrections;logs giữ lại,không sửa protected source để làm xanh.
Helpers≤150,tests≤400,Markdown≤200,HANDOFF≤100;legacy protected LOC violations không tự refactor.

## Đề xuất MH09-04B bounded, chưa thực hiện

04B1:chỉ VA01/VA02/VA03;local contrast/semantic heading/normal footer geometry,rerun failing tests+15matrix+regressions.
Recipient177/180 vàFooter179/180 gần cap;chỉ meaningful MH09 heading/style extraction nếu cần,giữ public APIs và capability/session gates.
04B2 nếu được duyệt:VA04/VA05;contact grouping/product tiles,không bỏ identity/snapshot/prices để ép giống mock.
VA06/VA07 optional,không gộp thành broad redesign. Sau targeted fixes mới Android dockedIME/TalkBack/gesture/full regression acceptance.
Shared dialog/lifecycle/providers/models/backend/router giữ scope riêng;không cần shared fix từ evidence04A hiện tại.
STOP04A. Người dùng review defect register trước04B;MH09 UI vẫn NOT YET APPROVED.

## MH09-04B1 — refinement được giao sau audit

VA01/VA02/VA03 được sửa cục bộ; kết quả04A phía trên là lịch sử trước refinement.
Reject7.2390:1 (trước4.3085),Confirm18.8831:1 giữ nguyên;3heading có node riêng.
390/DPR1/scale1:Reject146.571×48,Confirm195.429×48,cùng top;footer reserve động64px,không sửa layout/SafeArea.
Xem [REFINEMENT_04B1](REFINEMENT_04B1.md) và [HANDOFF](HANDOFF.md) cho fresh results,ảnh,hash và LOC.
VA04/VA05 chưa sửa;VA06/VA07 optional chưa làm. MH09 UI vẫn NOT YET APPROVED.
Ảnh04B1 là widget rasters;TalkBack audio/focus,dockedAndroidIME,gesture/device acceptance vẫn NOT VERIFIED.
Không tự bắt đầu04B2.
Fresh04B1:original8auditPASS,new5PASS,matrix15/15PASS,focused194PASS,full434PASS;2836protected SHA unchanged.

## MH09-04B2 — contact và product tiles

VA04/VA05 được refine sau04B1;findings/evidence phía trên là lịch sử trước refinement.
390/DPR1/scale1:contact155×48 mỗi nút,gap8;recipient310→302;white item tiles318×128,radius16,padding8,gap12.
Items section354→374 để giữ đủsnapshot fields;footer/header/payment vàVA01–03 không đổi.
Fresh:new27PASS,focused221PASS,full461PASS,original04A8/04B1 5/matrix15 đềuPASS.
[REFINEMENT_04B2](REFINEMENT_04B2.md),[comparison](artifacts/visual_04b2/comparison_contact_items.png),[HANDOFF](HANDOFF.md).
VA06/VA07 optional chưa làm;MH09 UI NOT YET APPROVED. Widget rasters không phải Android runtime.
TalkBack/dockedIME/gesture/device acceptance vẫnNOT VERIFIED trong04B2;review/manual stage riêng khi được giao.
