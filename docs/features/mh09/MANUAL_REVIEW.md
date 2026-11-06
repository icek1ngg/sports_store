# MH09 — Manual review

**MH09 — NOT YET APPROVED**.
04A audit hoàn tất;15layout cases PASS,2accessibility assertions FAIL;[VISUAL_AUDIT](VISUAL_AUDIT.md) ghi finding hiện tại.
03B full421PASS/Android smoke là lịch sử. Chưa targeted refinement04B hoặc Android acceptance mới.

## Reference HTML — fresh Chromium render

390×844 logical, DPR1, fonts gốc fully loaded, images2/2; source không sửa.
[Manifest và measured geometry](artifacts/html_render_manifest.json), [UI_SPEC](UI_SPEC.md).

![MH09 HTML viewport390×844](artifacts/html_390x844.png)

![MH09 HTML full390×1475](artifacts/html_390_full.png)

Full capture giữ fixed footer ở y772 viewport ban đầu; overlay trên payment trong ảnh dài là capture behavior.
Không dùng vị trí footer trong ảnh full làm target giữa scroll content.

## Flutter references — HISTORICAL, không phải fresh render

Đã xem ảnh [390 top](../../visual_refinement_artifacts/mh09_390_s1_0_top.png)
và [390 bottom](../../visual_refinement_artifacts/mh09_390_s1_0_bottom.png) trong audit.
Kích thước390×800,1 item fixture, standalone không back; [historical manifest](../../visual_refinement_artifacts/render_manifest.json).
Không có source hash tại thời điểm chụp để chứng minh ảnh phản ánh chính xác workspace hiện tại;
source inspection task01 xác nhận cấu trúc tương tự, không claim pixel comparison same-viewport.
[MH08 Android→MH09 exact UUID](../mh08/artifacts/visual_04b3/android_mh09_exact_uuid.png) cũng chỉ lịch sử.
Task01 không launch Android hoặc render Flutter mới.

## Visual difference matrix — lịch sử task01 trước component integration

| Vùng | Observed current / reference | Planned / intentional |
| --- | --- | --- |
| Header |left mixed-case title/refresh vs center uppercase/back/avatar|center/back/refresh; không profile route mới|
| Identity |fullUUID card vs DH code/badge ngoài card|giữ canonical UUID, responsive wrap|
| Buyer/contact |buyer và recipient tách/contact cuối vs customer card/contact cùng vùng|giữ hai identities; nhóm contact gần snapshot|
| Products |placeholder và verbose lines vs remote photos/compact2items|placeholder vì model thiếu image; all snapshot readable|
| Payment |real fee/total vs mock shipping promotion|bỏ promotion; full total đúng nghiệp vụ|
| Delivery/COD/Return |independent cards vs timeline strip/COD badge/no returns|giữ independent sections/null unavailable|
| Timeline |actual events vs6 stages hardcoded|không copy auto-assignment/OTP/ETA/wallet|
| Operations |external disabled + explanation vs mock success|giữ unavailable, không fake mutations|
| Footer |Confirm→Reject Wrap vs Reject→Confirm split|HTML order/pill48, adaptive height/SafeArea|
| Typography/spacing |shared24Barlow/gap12 vs20Inter/gap16|local MH09 styles; no approved screen edits|

Không có numeric Flutter delta mới; HTML measured geometry ở UI_SPEC là evidence fresh duy nhất.
Các khác biệt business không được sửa bằng bớt data/cộng voucher/chế event để ép ảnh giống mock.

## Android checklist — toàn bộ NOT RUN trong task01

- [ ] Launch current debug Preview trên Android; ghi device/API/viewport/DPR/insets/font scale và APK provenance.
- [ ] MH08 select real fixture UUID→MH09/back lặp nhiều lần; query/status/count/paging giữ đúng contract.
- [ ] Header/back hardware/system gesture/refresh có phản hồi và focus labels rõ.
- [ ] Scroll đọc hết UUID/buyer/recipient/phone/address/40items/amount/timeline/return summary.
- [ ] Delivery/COD/return absent có unavailable chính xác; no fake unassigned/uncollected/zero.
- [ ] Pending không capability không mở dialog; stale/loading/error disable mutations.
- [ ] Confirm/reject repeated open/close; empty reason blocked; valid reason trả unavailable, không success.
- [ ] Session expiry/account switch khi loading/dialog/refresh/pop: private data/reason cleared; no late flash.
- [ ] Dialog + docked Android IME mở/đóng/reopen; reason/submit/close reachable, no covered last row.
- [ ] Portrait/landscape/font1/1.5/2; small height footer scroll và SafeArea đúng system bars.
- [ ] TalkBack actual focus order/announcement/audio, disabled reasons và48dp touch targets.
- [ ] Callback COD/return/chat/call unavailable safe; active destinations chỉ khi owner routes đã tích hợp.
- [ ] App logs không overflow/uncaught/deactivated WidgetRef/disposed container; restore device settings sau test.
- [ ] MH07/MH08 approved screens giữ hash và behavior; MH09 fresh screenshot pairs same viewport.

## Known limitations / dependencies

- Production router/Auth/session/OrderRepository adapter chưa wire; Preview có DI fixture riêng, không production connectivity.
- Delivery/Inventory/COD/Returns/Chat external operations/routes chưa accepted/implemented; không được bật giả.
- ReturnSummary không có refund amount/evidence; giữ read-only summary, không mở private financial data mới.
- Shared timeline/lifecycle/dialog/theme có legacy LOC violations; không refactor ở audit hoặc sửa approved screens.
- Scoped owner03A2 inactive/reparent/unmount/late/session probes PASS; shared receipt callback risk vẫn dependency.
- Chromium external assets cần network; default sandbox DNS failed, render được phép ngoài sandbox đã PASS.
- Task01/03A2 counts là lịch sử;03A2F393full PASS.03B mới181focused/421full PASS,Android smoke đã chạy.
- MH08 historical dockedIME/TalkBack còn limitation riêng; approval MH08 không chứng minh MH09 acceptance.

## Review gate

Người dùng review Preview evidence tại [PREVIEW_03B](PREVIEW_03B.md); tiếp theo04A chỉ khi được giao.
MH09 vẫn NOT YET APPROVED; không tự04A/04B hoặc MH17.

## Checkpoint03A2 — giới hạn bằng chứng

7 components active không duplicate legacy; same aggregate/40items/amounts/null lifecycle/actual timeline được widget tests kiểm tra.
Contract test qua existing Preview tap real header back PASS, giữ exactUUID/query/search/status/container/canonical refresh.
2 existing Preview tests FAIL vì text prefix/BackButton cũ; giữ nguyên approved source/tests/fixtures, không làm UI giả để vượt test.
Không fresh same-viewport MH09 screenshot comparison; ảnh HTML/lịch sử phía trên không phải render sau03A2.
Full suite chạy fixture visual tests nhưng không thay thế04A fidelity/Android/IME/TalkBack acceptance.
MH07/MH08/7components/shared/Preview/evidence cũ nguyên SHA-256; xem [verification03A2](artifacts/03a2/verification.json).

## 03B — Android runtime smoke mới, không phải same-viewport comparison

Pixel_5 AVD/emulator-5554/API35,1080×2340, density440 (DPR2.75); app fixture-only, MH07 default.
[Manifest](artifacts/03b/runtime_manifest.json) ghi từng ảnh/provenance và các capture attempt không dùng làm evidence.
[MH09 normal](artifacts/03b/android_final_normal.png), [long recipient](artifacts/03b/android_long_recipient.png),
[40item cuối + payment](artifacts/03b/android_large_last_items.png), [timeline cuối](artifacts/03b/android_long_large_scrolled.png).
[Confirm](artifacts/03b/android_verified_confirm.png), [Reject](artifacts/03b/android_verified_reject.png),
[Header Back](artifacts/03b/android_verified_header_back.png), [System Back](artifacts/03b/android_verified_system_back.png).
Null Delivery/COD và stale có ảnh runtime riêng; tests kiểm tra semantics vì section có thể nằm dưới fold.
ADB Back đóng modal, rồi page vềMH08; Header Back riêng PASS; framework Back/query 3cycles mỗi loại PASS.
Emulator dùng floating IME: KEYCODE_BACK bỏ IME đồng thời đóng Reject, MH09 còn mở; không chứng minh keyboard-only Back.
Không sửa system settings; docked IME/gesture/TalkBack/physical device/responsive visual acceptance vẫn NOT VERIFIED.
Không có uncaught Flutter/AndroidRuntime error trong log đã lọc của app; render fidelity chưa được đánh giá.
04A: fresh Flutter390×844/DPR1 so HTML;320/360/390/412/landscape ×scale1/1.5/2, kiểm tra footer/long text/nulls.

## 04A — fresh widget capture và review gate

[Visual audit](VISUAL_AUDIT.md), [capture manifest](artifacts/visual_04a/capture_manifest.json), [comparison390](artifacts/visual_04a/comparison_390.png).
Actual Preview/MH09,Inter/Barlow loaded,DPR1,390×844/scale1,insets0;không debug selector hoặc synthetic full-page stitching.
15matrix cases với nonzero synthetic SafeArea PASS;19scene values targeted PASS;không claim19×15 full cross-product.
P0/P1 không phát hiện;P2 gồm contrastReject,heading semantics,footer wrap/geometry,contact grouping,product tile hierarchy.
Newaudit6PASS/2FAIL được giữ nguyên;không approval từ functional matrix;[FAIL evidence](artifacts/visual_04a/accessibility_contrast.report.json).
Rejectdialog320scale2+inset300:reason/submit/Close reachable,validation/unavailable/expiry clearing PASS;synthetic không phải actual keyboard.
Full TalkBack focus/audio,docked Android IME,gesture Back và device acceptance vẫn NOT VERIFIED trong04A.
Ảnh Android phía trên vẫn historical03B;ảnh04A là widget raster,không đổi tên thành Android evidence.
User reviewVA01–VA07 trước04B;không bắt đầu04B hoặc đánh dấu MH09 UI approved trong task này.

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

## MH09-04B3 — Android mới, có manual checks pending

[ANDROID_ACCEPTANCE](ANDROID_ACCEPTANCE.md),[current APK provenance](artifacts/visual_04b3/build_provenance.json),[Android manifest](artifacts/visual_04b3/runtime_manifest.json).
Build/install/launch mới04B2 PASS;Pixel_5/API35/emulator-5554,1080×2340,DPR2.75;installedAPK SHA khớp.
VA01–05 hiện trênAndroid mới;normal contact/footer aligned,white tiles,item40 vàlatersections cuộn tới được.
19scene values sampled;Confirm/Reject/Cancel unavailable,khôngsuccessfake;expired/unauthorized/unresolved chặn dữ liệu.
HeaderBack,KEYCODEroute/modal/IMEBack PASS riêng;ADB-injectededgegesturePASS,physicalfinger NOT VERIFIED.
**Docked Gboard portrait/font1 PASS**:reason/submit/Close reachable,Backchỉẩnkeyboard;ảnh mới dướiđây.
Portraitfont1/1.5/2 vàlandscape1/1.5/2 chạy;landscape+IME bịWindowsqemuAPPCRASH,khôngkếtluậnappcrash.
TalkBack service bật/tắt bằngSettings,greenfocus một phần;FULLTALKBACKFOCUS/AUDIO vẫn NOT VERIFIED.
Settingsfont/orientation/accessibility đãrestore;landscape+IME/last-rowlandscape2manual,physicalgesture,TalkBackđủaudio cònmanual.
Fresh focused221/full461/original04A8/04B1 5/04B2 27/matrix15 đềuPASS;analyze/diff/LOC/links/hashPASS.
2990protectedworkingfiles unchanged;khôngproduction/test/Preview edits;oldartifactsgiữnguyên bằngisolatedvalidation.
[Contact/footer](artifacts/visual_04b3/android_normal_top_verified.png),[producttiles](artifacts/visual_04b3/android_product_tiles.png),[item40](artifacts/visual_04b3/android_item40_complete.png).
[DockedIME](artifacts/visual_04b3/android_reject_valid_docked.png),[independentlifecycles](artifacts/visual_04b3/android_delivered_lifecycles.png),[privacy](artifacts/visual_04b3/android_expired.png).
Rawtransition/splash/focusattempts bịloạikhỏiclaim;producttilesactualscene missingDelivery đượcghiđúngmanifest.
**MH09-04B3 — RUNTIME VERIFIED WITH MANUAL CHECKS PENDING**. MH09 UI NOT YET USER APPROVED.
User làmmanualchecklist trongacceptance rồireviewvisual;khôngtựVA06/VA07/backend/MH17 hoặcmarkapproved.
