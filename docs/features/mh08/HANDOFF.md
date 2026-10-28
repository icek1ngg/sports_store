# MH08 Handoff

## Current Status
Task: **MH08-GIT**, ngày19/10/2026 (Asia/Saigon); runtime04B3 hoàn tất16/10.
Status: **MH08 — USER APPROVED**, người dùng xác nhận chốt và yêu cầu commit/push19/10.
Chỉ xuất bản milestone MH08 trên feature/orders-notifications-phase2; chưa bắt đầu MH09/MH17/Phase3.
Goal: xuất bản milestone MH08 đã duyệt; production UI/business logic giữ nguyên.

## Completed / Evidence
- Pixel_5/emulator-5554, Android15/API35/x86_64,1080×2340,density440/DPR2.75.
- APK build96s/install10.2s/launch thật; main.dart hiện tại default MH07, switchMH08 bằng control DEMO.
- Search full UUID/account/clear/nonexistent/product-negative, pending/delivering/All và chip cuối đã kiểm tra bằng touch.
- Cuộn đủ10 UUID unique,4pages/page3; VM ghi3 cursor reads unique, KPI2/2/total10 độc lập loaded rows.
- Buyer/account/recipient/address/phone/items/COD/null/warning/long names đọc được qua scroll.
- Confirm/reject mở/đóng lặp, blank reason bị chặn, valid reason và confirm trả unavailable; không fake success.
- Pending …019998 không capability: enabled=false, tap Confirm không mở dialog.
- MH08→MH09 exact UUID …019998→Back giữ search/pending; đã lặp navigation.
- VM raw getObject: head54→55 khi detail accepted,55→56 khi pop; pop+1 canonical read, cursor3 giữ nguyên.
- data/loading spinner/empty/error+retry/stale/expired/unauthorized/session unavailable đã chạy.
- 3 privacy scenarios có0 private order/buyer nodes; old async/session regressions cũng PASS trong full suite.
- Android portrait/landscape/font1.5 smoke; targets132physical=48logical, details fully reachable sau scroll.
- K1 floating/handwriting open-close-reopen PASS qua Search/Enter; **DOCKED ANDROID IME — NOT VERIFIED**.
- Show on-screen keyboard/menu/drag vẫn floating; WindowManager IME frame66physicalpx, không suy ra docked PASS.
- TalkBack service bound/Tab/swipe sample attempted; full focus order/audio **NOT VERIFIED**.
- Font1.0/rotation0/auto-rotate1/accessibility0/services=null/defaultGboard/show-IME-hardware1 đã restore baseline.
- Flutter console/app-PID logcat0 uncaught/overflow/ProviderScope/lifecycle/font-asset error matches.
- MH07 quay lại total16 và MH08 total10; app để ở MH08 data/top cho user review.

## Files / LOC
| File | LOC | Limit |
| --- | ---: | ---: |
| test/visual_refinement/mh08_04b3_android.ps1 (new) |141|150|
| test/visual_refinement/mh08_04b3_compare.py (new) |123|150|
| test/visual_refinement/mh08_04b3_vm.py (new) |150|150|
| docs/features/mh08/ANDROID_ACCEPTANCE.md (new) |100|200|
| docs/features/mh08/README.md |142|200|
| docs/features/mh08/MANUAL_REVIEW.md |189|200|
| docs/features/mh08/TEST_PLAN.md |199|200|
| docs/features/mh08/HANDOFF.md |≤100|100|

Only3 runtime utilities +5 feature docs changed; production0 changes, no new Dart code/tests.
PS helper owns native UI/XML/PNG; compare owns offline visual/target metrics; VM helper owns read-only raw counter inspection.
LOC gate PASS, không exception; không thêm logic vào page288/controller238/visual-test399/TestPlan199.
Artifacts mới: artifacts/visual_04b3/; không ghi đè HTML/04A/04B2 screenshots/evidence.

## Verification — lịch sử04B3,16/10/2026
- Fresh **100 affected tests PASS**: components/page/coordinators/Preview/original audits/keyboard lifecycle/new04B2 renderer.
- Fresh **276 full-suite tests PASS**, gồm MH07 và business/session/capability regressions; không weaken/skip assertions.
- **Original2 K1 audit tests PASS**,15/15 viewport/scale cases;2 keyboard lifecycle tests PASS.
- flutter analyze --no-pub: No issues found; git diff --check/physical LOC/source hashes PASS.
- Dart format: không có changed Dart files; Python AST/PowerShell syntax đã kiểm tra, SDK/temp paths auto-resolve theo user.
- Baseline328 source/reference/artifact files và164 dirty Git entries; **328/328 giữ SHA-256**.
- Production/MH07/fixtures/shared/providers/page/coordinators/router/HTML/04A/04B2 nguyên trạng; independent review không P1/P2.
- [Source verification](artifacts/visual_04b3/source_verification.json), [runtime errors](artifacts/visual_04b3/runtime_error_check.json).
- [Navigation reads](artifacts/visual_04b3/navigation_read_results.json), [native targets](artifacts/visual_04b3/runtime_visual_metrics.json).
- Đối chiếu [HTML/widget/Android](artifacts/visual_04b3/comparison_html_widget_android.png): fonts/hierarchy giữ đúng, system bars/DEMO giảm feed.
- Widget04B2 card476h/y277 giữ nguyên source; Android có viewport khác, không claim pixel-perfect.

## Remaining / Known Limitations
- Publish verification19/10:100 MH08 PASS, analyzer PASS; full snapshot232 PASS/1 MH17 timer FAIL, xem [GIT_RELEASE](GIT_RELEASE.md).
- UI đã được người dùng approve19/10; docked IME/full TalkBack/audio vẫn chưa được xác minh, không suy ra PASS từ approval.
- ADB nhập UUID36 có lượt dừng30 ký tự; retry suffix đủ36 rồi verify. Chưa xác định gốc IME/automation; user cần typing/paste thật.
- Không tính incomplete-input/harness Back thoát Activity/menu-transition captures là PASS; excluded attempts được mô tả trong acceptance.
- VM HTTP/evaluate probes cũ unavailable vì transport/compilation service; raw getObject sau đó đo được, không fake counters.
- Card khác HTML do2 KPI/UUID/account+recipient/snapshots/COD/details/48px targets; không bỏ dữ liệu để ép chiều cao.
- Backend chưa tích hợp; mọi mutation phải unavailable, không optimistic/fake success.
- Không có production defect P0/P1 đã xác nhận trong kiểm tra này; không biến giới hạn emulator thành runtime PASS.
- Next action: lưu/push milestone MH08 theo yêu cầu; chỉ làm MH09 khi có task tiếp theo của người dùng.

## Run / Minimal Context
Chạy flutter devices, sau đó flutter run --no-pub -d emulator-5554 -t tool/ui_preview/main.dart; chọn Chọn màn hình→MH08.
Nếu cần, process-local GRADLE_OPTS theo [ANDROID_ACCEPTANCE](ANDROID_ACCEPTANCE.md); không sửa Gradle config.
Root AGENTS, [README](README.md), HANDOFF, [ENGINEERING_RULES](ENGINEERING_RULES.md), ANDROID_ACCEPTANCE.
[MANUAL_REVIEW](MANUAL_REVIEW.md), [TEST_PLAN](TEST_PLAN.md), artifacts04B3 cho evidence/checklist.
Chỉ đọc production code khi có failure cụ thể; toàn bộ protected source readonly trong task này.
Working tree vốn dirty/untracked; commit/push MH08 được user cho phép19/10; giữ nguyên phần chưa thuộc milestone.
