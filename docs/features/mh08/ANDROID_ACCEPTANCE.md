# MH08-04B3 — Android acceptance evidence

Runtime verification ngày16/10/2026. **MH08-04B3 hoàn tất; người dùng chốt MH08 ngày19/10/2026**.
**MH08 — USER APPROVED** theo xác nhận trực tiếp; commit/push được yêu cầu19/10, chưa chuyển MH09/MH17/Phase3.

## Environment / launch

- Pixel_5, emulator-5554, Android15/API35/x86_64; physical1080×2340, density440 (DPR2.75).
- Toàn màn hình logical khoảng392.73×850.91 gồm system bars; DEMO toolbar48 logical px chiếm thêm vùng nội dung.
- APK mới build96.0s/install10.2s, launch thực và chuyển màn bằng touch; không chỉ build APK.
- Entrypoint giữ nguyên main.dart → Mh08PreviewApp; default MH07, manager fixtures riêng10 đơn/page3.
- Một ProviderScope trên MaterialApp/Navigator; repository/session demo overrides, không Supabase initialization/login/mutation.

```powershell
flutter devices
$env:GRADLE_OPTS='-Dorg.gradle.project.kotlin.incremental=false -Dorg.gradle.project.kotlin.compiler.execution.strategy=in-process'
flutter run --no-pub -d emulator-5554 -t tool/ui_preview/main.dart
```

Chọn **Chọn màn hình → MH08** trên toolbar DEMO. GRADLE_OPTS chỉ process-local; không sửa Gradle config.

## Executed runtime cases

| Case | Kết quả quan sát / evidence | Status |
| --- | --- | --- |
| APK/install/launch | Preview mới chạy PID28965, default MH07 | PASS |
| MH07↔MH08 | MH07 total16, MH08 total10; quay lại cả hai màn | PASS |
| Full UUID | …019999 trả1 đơn; …019998 trả pending không capability, field được quan sát đủ36 ký tự | PASS |
| Account search | Minh Anh → Nguyễn Minh Anh, total1, KPI1/0 | PASS |
| Clear/re-enter/nonexistent | NoSuchCustomer không match; clear khôi phục2/2/10 | PASS |
| Product-name search | AirFlex không match account/full UUID | PASS |
| Status/search | Pending→delivering→All giữ Minh Anh, delivering0 results nhưng KPI search-wide1/0 | PASS |
| Horizontal strip | Scroll tới lifecycle cuối Không giao được — đã nhận hàng về; không thêm Returns | PASS |
| Paging | Quan sát10 UUID unique qua4 pages;3 cursor requests unique, canonical KPI vẫn2/2/10 | PASS |
| Cards | Multi-item, remaining-line metadata, long buyer/address/product, COD null/amount và typed failed warning đọc được qua scroll | PASS |
| Confirm | Mở/đóng lặp; Tiếp tục trả unavailable, không status success | PASS |
| Reject blank | Hiện Vui lòng nhập lý do trước khi gửi | PASS |
| Reject reason | Khach yeu cau tu choi được nhập thật; submit unavailable | PASS |
| Disabled actions | …019998 Confirm/Reject enabled=false; tap Confirm không mở modal | PASS |
| Navigation | MH09 nhận đúng …019998; Back giữ UUID search/pending filter; lặp navigation | PASS |
| Canonical pop refresh | VM raw object inspection: head54→55 khi detail accepted,55→56 khi pop; cursor3→3 | PASS |
| data/loading | Spinner và unknown counts được chụp trước800ms; sau đó data | PASS |
| empty | Chưa có đơn hàng cần xử lý | PASS |
| error/retry | Retry có touch response; error fixture tiếp tục error, KPI unknown không=0 | PASS |
| stale | Stale notice, conflicting controls khóa theo freshness | PASS |
| expired |0 private order/buyer nodes, expired-session UI | PASS |
| unauthorized |0 private nodes, denied UI | PASS |
| session unavailable |0 private nodes, session-resolution UI | PASS |
| K1 IME open/close/reopen | Floating/handwriting IME mở ẩn KPI/total; Search/Enter đóng phục hồi đúng query/counts | PASS limited |
| Docked Android IME | Show on-screen keyboard/menu/drag vẫn floating; WindowManager frame66physicalpx, không đủ bằng chứng docked | NOT VERIFIED |
| Portrait/landscape/font1.5 | Reflow/scroll được; primary actions đọc được, không uncaught/overflow | PASS smoke |
| Native touch targets | Confirm/Reject/details132physical=48logical, details đầy đủ sau scroll | PASS |
| TalkBack sample | Service bound, thử Tab/swipe; keyboard focus Chọn màn hình được ghi nhận | PARTIAL |
| Full TalkBack focus/audio | Chưa kiểm chứng toàn bộ swipe order/announcements | NOT VERIFIED |
| Runtime errors | Flutter console + app-PID logcat:0 uncaught/RenderFlex/ProviderScope/lifecycle/font-asset error matches | PASS |

## Evidence map

Base: artifacts/visual_04b3/. PNG là **Android runtime screenshot**, XML là native hierarchy cùng bước, trừ transient loading/native TalkBack chỉ PNG.

- [HTML / widget04B2 / Android](artifacts/visual_04b3/comparison_html_widget_android.png); Android chỉ scale để đặt cạnh, không coi cùng viewport.
- [Initial](artifacts/visual_04b3/android_mh08_initial.png), [pending bottom](artifacts/visual_04b3/android_pending_card_bottom.png), [review start](artifacts/visual_04b3/android_user_review_start.png).
- [Warning](artifacts/visual_04b3/android_paging_05.png), [multi-item](artifacts/visual_04b3/android_paging_06.png), [long buyer](artifacts/visual_04b3/android_paging_08.png), [10 UUIDs](artifacts/visual_04b3/paging_all_ten.json).
- [Confirm](artifacts/visual_04b3/android_confirm_dialog.png), [reject blank](artifacts/visual_04b3/android_reject_blank_validation.png), [valid reason unavailable](artifacts/visual_04b3/android_reject_valid_unavailable.png).
- [K1 reopen](artifacts/visual_04b3/android_k1_reopened.png), [restore](artifacts/visual_04b3/android_k1_restored.png), [floating attempt](artifacts/visual_04b3/android_docked_keyboard_attempt.png).
- [Loading](artifacts/visual_04b3/android_loading_350ms.png), [empty](artifacts/visual_04b3/android_scenario_empty.png), [error](artifacts/visual_04b3/android_scenario_error.png), [stale](artifacts/visual_04b3/android_scenario_stale.png).
- [Privacy](artifacts/visual_04b3/scenario_privacy_results.json), [navigation counters](artifacts/visual_04b3/navigation_read_results.json), [targets](artifacts/visual_04b3/runtime_visual_metrics.json).
- [Landscape](artifacts/visual_04b3/android_landscape.png), [font1.5](artifacts/visual_04b3/android_font_scale_1_5_card_scroll.png), [TalkBack native](artifacts/visual_04b3/android_talkback_native_sample.png).
- [Error check](artifacts/visual_04b3/runtime_error_check.json), [restored settings](artifacts/visual_04b3/android_restored_settings.json), [source protection](artifacts/visual_04b3/source_verification.json).

## Verification / boundaries

- Fresh **100 affected tests PASS**, **276 full-suite tests PASS**, gồm MH07 và original2 K1 audit tests/15case matrix +2 lifecycle tests.
- Analyze No issues found, git diff --check PASS; không Dart source nào sửa nên Dart format không có changed files.
- 328/328 protected baseline files giữ SHA-256: production/MH07/fixtures/shared/page/coordinator/HTML/04A/04B2 evidence nguyên trạng.
- Helpers mới: mh08_04b3_android.ps1 141/150; compare.py123/150; vm.py150/150. Docs và LOC report trong HANDOFF.
- VM dùng getObject read-only; HTTP transport/compile-evaluate probes thất bại không phải app error, raw-fields probe sau đó đo được counters thật.
- Harness sửa guard path/Test-Path, đợi input đủ trước submit, chụp loading sau animation; không sửa production để làm tests PASS.
- Font1.0/rotation0/auto-rotate1/accessibility0/services=null/Gboard và show_ime_with_hard_keyboard1 đã khôi phục như baseline.
- Không sửa backend/API/auth/router, không fake transaction success, không commit/push/reset/clean/checkout/merge.

## Limitations / excluded attempts

- Card476h khác HTML234h do account/recipient/snapshots/COD/details/48px targets;2 KPI/UUID/placeholders/no unsupported navigation là intentional.
- Android toolbar/system bars giảm vùng feed: initial details cần scroll thêm, không phải card bị mất nội dung.
- Docked IME/full TalkBack/audio còn cần thiết bị/kiểm tra của người dùng;15/15 widget matrix không thay bằng chứng runtime.
- ADB nhập UUID36 một lần từng dừng ở30 ký tự; đã xác nhận field và nhập suffix còn thiếu để test full UUID. Chưa xác định gốc IME/automation; người dùng cần thử typing/paste thật.
- Không tính lượt input thiếu ký tự hoặc harness Back thoát Activity là PASS. android_keyboard_closed_uuid.png là launcher; android_search_account_restored.png chưa nhập query.
- android_pending_without_capability.png là lượt input thiếu; dùng android_disabled_order_full_uuid.png cho kết luận disabled.
- android_loading_transient.png còn menu animation; chỉ android_loading_350ms.png là loading evidence. Các attempts giữ riêng, không ghi đè ảnh cũ.
- TalkBack/audio và performance release không được suy ra từ emulator debug/ảnh tĩnh hoặc UI approval của người dùng19/10.

## User manual acceptance

- [ ] Mở Preview, chọn MH08; so hierarchy/card density với HTML và ảnh04B2/04B3.
- [ ] Tự gõ/paste full UUID, account name, clear; thử pending/delivering/All, paging và long-text/warning cards.
- [ ] Mở/đóng dialogs, reject blank/valid, unavailable và disabled controls; không có success giả.
- [ ] MH08→MH09→Back giữ query/filter; keyboard docked mở/đóng/reopen, counts/list còn đúng.
- [ ] Kiểm tra font lớn, landscape, SafeArea, TalkBack đọc đầy đủ UUID/status/actions và thứ tự focus.
- [x] Người dùng xác nhận chốt MH08 ngày19/10/2026 và yêu cầu lưu Git. Chờ task mới trước khi triển khai MH09.
