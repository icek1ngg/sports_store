# MH09 HANDOFF — MH09-04B3

Ngày20/10/2026. **MH09-04B3 — RUNTIME VERIFIED WITH MANUAL CHECKS PENDING**.
Ngày 21/10/2026, user xác nhận: **"MH09 UI/Preview accepted at the current implemented scope."**
MH07/MH08/MH09 UI source được bảo vệ; acceptance này không phải backend end-to-end hoặc mutation success.

## Đã thực hiện

Production/Preview/tests read-only. Chỉ thêm acceptance utilities/evidence/docs, cập nhật HANDOFF/MANUAL_REVIEW.
Build/install/launch APK MỚI từ working source04B2 PASS: Pixel_5 emulator-5554, API35,1080×2340,density440/DPR2.75.
Version0.1.0/code1,package com.example.sports_store; installed base.apk khớp APK mới, kể cả sau emulator recovery.
APK SHA256 `cb0fa351b4b0d754b7e9f92cef189094d51e28df5130304cd18a2e1e382894f5`.
246 input hashes nằm trong source_snapshot.json; baseline là working files, không dùng HEAD.
[Acceptance](ANDROID_ACCEPTANCE.md),[75 Android captures](artifacts/visual_04b3/runtime_manifest.json).
[Build/provenance](artifacts/visual_04b3/build_provenance.json),[source hashes](artifacts/visual_04b3/source_snapshot.json).

## Runtime đã quan sát

MH07 default→MH08→MH09 full UUID;19 scene values sampled, không exhaustive19×fonts/races.
Normal: buyer≠recipient, contact cân bằng, white product tiles, tổng1.960.000₫;VA01–05 hiện trên APK mới.
Contact156.36×48dp mỗi nút,gap8;Reject147.64×48/Confirm197.09×48 cùng top tại native393dp width.
Item40/name/variant/qty/amount đọc được; cuộn tiếp tới COD/Returns/Timeline, footer không che hàng cuối.
Delivered record5: delivery success, COD shipper375.000/store0, Return Chờ duyệt độc lập.
Missing Delivery/COD/Buyer và returns rỗng hiển thị trung thực; không catalog/fake ETA/discount/mutation.
Confirm/Reject/Cancel đúng capability; blank reason blocked, valid reason→unavailable, không đổi status/fake success.
Error→retry recovery; loading/stale khóa actions; expired/customer/unresolved settled screens không còn private content.
Account switch: manager khác được authorized đọc lại. Late-response/modal/same-frame races có automated tests riêng.
Call/Chat/COD/Return owner navigation chưa integrated; không destination success trong runtime Preview.

## Back / IME / accessibility

Header Back và KEYCODE_BACK route/modal PASS riêng; hai header cycles giữ UUID query/filter trong cùng session.
Gboard docked thật portrait/font1 PASS: field/submit/Close reachable; Back chỉ ẩn IME, giữ dialog/reason.
Edge gesture qua ADB native input swipe PASS với navigation_mode2; physical finger **NOT VERIFIED**.
Portrait font1/1.5/2, long address và landscape1/1.5/2 đã chạy; footer reflow, dialog landscape cuộn tới reason.
Landscape+IME dừng do Windows qemu APPCRASH0xc0000005 lúc22:11:03; không có Dart stack để quy cho app.
[Host events](artifacts/visual_04b3/emulator_host_events.json); cold AVD recovery PASS, APK không đổi.
Landscape+IME hoàn chỉnh/last-row landscape2 manual **NOT VERIFIED**; widget matrix15/15 PASS là evidence riêng.
TalkBack bật/tắt qua Settings UI; service bound/green focus một phần; **FULL TALKBACK FOCUS/AUDIO NOT VERIFIED**.
Đã restore font1.0/autoRotation1/userRotation0/accessibility0/Gboard/navigation; services null→empty đều disabled.
[Settings after](artifacts/visual_04b3/device_after.json). Không inject secure accessibility service setting.

## Fresh verification

Baseline181 focused PASS; final221 focused PASS; full `flutter test --no-pub` **461 PASS**, không skip/weaken assertions.
Original04A8/8,04B1 5/5,04B2 27/27; responsive15/15 PASS (widget, không phải native matrix15case).
[Focused](artifacts/visual_04b3/focused_verified.log),[full](artifacts/visual_04b3/full_verified.log),[results](artifacts/visual_04b3/regression_results.json).
Exact-source isolated mirror324 source files, tránh fixed audit outputs overwrite old artifacts; package root verified.
Analyze sạch; diff/LOC/links/utility syntax/imageSHA/inputSHA/protectedSHA PASS. Không có Dart edits: format N/A.
2992 baseline files,2990 protected unchanged; chỉ2existing MH09docs đổi, production/tests/Preview/old images nguyên vẹn.
[Verification](artifacts/visual_04b3/verification.json). Branch feature/orders-notifications-phase2;2317 pre-existing dirty entries.
PID4881 và recoveryPID3117 logs không app fatal/overflow/ref/container errors trong phần đã thu; không phủ mọi phút/race.
Không Git mutation/delete/commit/push. Worker SDK attempt logs0byte không phải passing results.

## LOC và ảnh review

Production unchanged: page43/content275/body82/layout45; recipient131/items155/contact109/payment137/footer180.
UI≤180/page≤300 giữ nguyên; new utilities≤150, Markdown≤200,HANDOFF≤100; exact LOC trong verification.
[Contact/footer](artifacts/visual_04b3/android_normal_top_verified.png),[products](artifacts/visual_04b3/android_product_tiles.png).
[Item40](artifacts/visual_04b3/android_item40_complete.png),[lifecycles](artifacts/visual_04b3/android_delivered_lifecycles.png).
[Docked IME](artifacts/visual_04b3/android_reject_valid_docked.png),[expired](artifacts/visual_04b3/android_expired.png).
Ảnh Android runtime;11 raw/focus/splash/over-scroll attempts bị loại khỏi claim; manifest ghi rõ actual XML banner.
Product/payment/timeline đầu actual scene missingDelivery, không gọi canonical; không overwrite ảnh cũ.

## Closeout — UI/Preview accepted, giới hạn bên ngoài còn mở

Device ổn định: landscape+large font+docked IME/last-row; TalkBack nghe UUID/status/3heading/VND/reasons/focus order.
Physical finger Back: keyboard→modal→route, kiểm query/filter. Các manual checks này vẫn chưa xác minh đầy đủ.
Full TalkBack audio/focus chưa PASS; backend/Auth/router do owner bên ngoài, mutations/RLS/concurrency chưa acceptance.
Không tự fix VA06/VA07/backend; MH17-01 chỉ audit/docs theo task mới, không triển khai MH17-02.
Minimal context: AGENTS→HANDOFF→ANDROID_ACCEPTANCE→MANUAL_REVIEW; REFINEMENT_04B2 khi cần source visual provenance.
