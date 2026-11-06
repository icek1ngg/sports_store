# Phase 2 — Visual Refinement

Ngày 10/10/2026. Trạng thái: **IMPLEMENTED AND TESTED — READY WITH CONDITIONS**. Không thay đổi business/API revision 1.2. Acceptance trực quan cuối còn cần đối chiếu HTML render và thao tác Android Emulator.

## Nguồn và mapping

Năm HTML ban đầu chưa có trong repository. Đã copy nguyên byte từ các attachment do người dùng cung cấp vào `docs/ui_mocks/`, đối chiếu SHA-256 đều khớp:

| Flutter | HTML |
|---|---|
| MH07 | `ui_mocks/MH07_My_Orders.html` |
| MH08 | `ui_mocks/MH08_Manager_Order_List.html` |
| MH09 | `ui_mocks/MH09_Manager_Order_Details.html` |
| MH17 | `ui_mocks/MH17_Notifications.html` |
| Chỉ tham khảo style | `ui_mocks/REFERENCE_Return_Request_Details_OUT_OF_SCOPE.html` |

HTML/CSS/Tailwind/JavaScript đã được khảo sát. Browser tích hợp từ chối `file://` theo URL policy; **chưa render/chụp HTML**. Không có pixel-diff hoặc tỷ lệ tương đồng. PNG Flutter trước thay đổi ở `ui_review_artifacts/`; các ảnh `mock1.jpg`–`mock3.jpg` đã được mở xem nhưng không thay thế screenshot HTML mới.

## Visual Difference Matrix trước sửa

| Thành phần | HTML | Flutter trước sửa | Kế hoạch |
|---|---|---|---|
| Theme/font | Trắng/đen, Inter + Barlow Condensed | Material 3 xanh, Roboto | Theme cục bộ cho 4 trang, font OFL bundled; giữ AppTheme toàn nhóm |
| Header | Brand nhỏ, title thể thao, hairline | AppBar mặc định | Header và title hierarchy native; routes ngoài module vẫn unavailable |
| MH07 | Search pill, chips đen, card 32px, preview 72px, COD nổi bật, action trong card | Search viền, card viền, preview text, action ngoài card | Rounded surfaces, placeholder ảnh, payment block và action grouping |
| MH08 | Search, KPI nhỏ đen/xám, card buyer, action confirm/reject | Count pills, cards text | KPI từ server counts; không có KPI Returns giả |
| MH09 | Section xám 32px, payment, timeline dọc, footer sticky | Sections/card viền, action cuối scroll | Đổi layout/presentation, giữ 4 lifecycle, đưa order actions ra sticky footer |
| MH17 | Tile bo góc, icon đen, unread dot, timestamp, badge đen | Tile xanh, icon xanh, badge đỏ | Minimal cards; giữ All/Unread, server count và explicit mark-read |
| Responsive | Có truncation/fixed footer trong HTML | Modal MH07 header bị ép khi chữ 2x; session gate thiếu Material fallback | Stack header, SafeArea, footer có giới hạn chiều cao/scroll, material page boundary |

## Intentional deviations bắt buộc

Không copy discount/free shipping, Mua lại, mark-all-read, category filters chưa có contract, KPI hardcode, GHN/SPX, OTP, loyalty, ví/đổi size, planned timeline/ETA, JavaScript fake success. Giữ UUID đầy đủ, snapshot text, placeholder ảnh; tổng tiền gồm phí 30.000 VND. Bottom navigation không tạo dashboard/profile/routes ngoài contract. Backend unavailable không báo success.

## Implementation checklist

- [x] Scoped tokens/theme/font assets và source/license.
- [x] MH07 layout, modal và tests/render.
- [x] MH08 layout, KPI/actions và tests/render.
- [x] MH09 sections/sticky footer và tests/render.
- [x] MH17 tiles/actions/count và tests/render.
- [x] Debug preview qua DI, không production Auth/Supabase.
- [x] Widget matrix: 320/360/390/412, landscape, scale 1/1.5/2, keyboard/SafeArea.
- [x] Format/analyze/full tests/diff check; không thay baseline expectations để che lỗi.

Git đầu lượt: nhánh `feature/orders-notifications-phase2`, HEAD `4d22a8d`; 5 tracked modified và 11 source/test untracked từ Phase 2, thêm mockups/harness/artifacts review có sẵn. Giữ nguyên các file này; không reset/clean/chuyển nhánh/stage/commit/push/merge.

## Kết quả từng màn

**MH07 — IMPLEMENTED AND TESTED:** Header thể thao, search pill, filter chips ngang, selected text trắng; card radius 32 có product block, placeholder ảnh, gray COD summary và actions trong card. Modal xếp riêng title/UUID/badge. Giữ ownership, search/filter/pagination, details/timeline, cancel/return eligibility, capability recheck và session isolation. Header compact khi bàn phím mở để search không bị clip.

**MH08 — IMPLEMENTED AND TESTED:** Search pill, hai KPI đen/xám lấy từ authoritative server counts, order/buyer/address cards, warnings, confirm đen/reject đỏ, callback tới MH09. Giữ reason validation và freshness checks; không có KPI Returns hoặc tổng số tự suy từ current page. Header/KPI thu gọn khi keyboard mở.

**MH09 — IMPLEMENTED AND TESTED:** Sections xám bo góc, title hierarchy thống nhất, buyer/recipient snapshots, product items, payment breakdown, timeline và bốn lifecycle độc lập. Orders actions nằm ở sticky footer có divider, giới hạn chiều cao và scroll; không tạo footer rỗng khi không có capability. External actions giữ disabled/unavailable và wording nói rõ dịch vụ chưa tích hợp. Phí 30.000 VND được cộng đúng vào tổng COD, không copy shipping discount.

**MH17 — IMPLEMENTED AND TESTED:** Tiles radius 16, icon đen/xám, unread dot/bold, timestamp, gutter 20, badge đen compact. Giữ All/Unread, server count, canonical acknowledgement, typed target resolution, authorization, cursor pagination và foreground polling. Count 0/unknown không tạo badge giả; >99 hiện 99+ với semantics số đầy đủ. Tile stale được disable; captured callbacks còn recheck session/cache/head-page freshness ngay trước thao tác, kể cả trước rebuild.

**Reuse:** Models/DTO, repository contracts, Riverpod DI/ViewModels, SessionScope, EpochCache, SnapshotReadViewModel, retry policy, FeatureAccessGate, ForegroundRefresh, AsyncContent và AppTheme. Không sửa migrations, backend, production adapters, Auth hoặc central router.

## Tokens, fonts và scope

Theme mới `OrderNotificationTheme` chỉ scope trong bốn page, kế thừa AppTheme. Ink `#111111`, cloud `#F5F5F5`, muted `#707072`, success `#007D48`, red `#D30005`; outer gutter 20, cards 32, notification tiles 16, pill buttons và tap targets tối thiểu 48. Barlow Condensed cho heading, Inter cho body; Inter fallback khắc phục glyph `₫` thiếu trong heading font.

Font nguyên bản từ Google Fonts, SIL OFL 1.1, có copyright/license được giữ và đóng gói trong assets; đăng ký LicenseRegistry. Xem [provenance](../assets/fonts/README.md), [Inter OFL](https://github.com/google/fonts/blob/main/ofl/inter/OFL.txt), [Barlow Condensed OFL](https://github.com/google/fonts/blob/main/ofl/barlowcondensed/OFL.txt). `pubspec.yaml` chỉ thêm fonts/license assets; không thêm package, không thay lockfile.

## Screenshot evidence thực tế

**197 PNG Flutter đã render** với bundled fonts và fixture-only DI. [Manifest](visual_refinement_artifacts/render_manifest.json) ghi 197 captures, tất cả `exception: null`; stale notification tap ghi `mark_read_calls: 0`. Không có screenshot HTML hoặc phép đo phần trăm/pixel similarity. Đánh giá fidelity dựa trên HTML source và ảnh Flutter thực sự xem được.

| Màn | 390px, scale 1 | 320px, scale 2 |
|---|---|---|
| MH07 | [Top](visual_refinement_artifacts/mh07_390_s1_0_top.png) | [Top](visual_refinement_artifacts/mh07_320_s2_0_top.png), [Detail](visual_refinement_artifacts/mh07_detail_320_s2_0_top.png) |
| MH08 | [Top](visual_refinement_artifacts/mh08_390_s1_0_top.png) | [Top](visual_refinement_artifacts/mh08_320_s2_0_top.png) |
| MH09 | [Top](visual_refinement_artifacts/mh09_390_s1_0_top.png) | [Footer](visual_refinement_artifacts/mh09_320_s2_0_bottom.png), [Returns projection](visual_refinement_artifacts/mh09_320_s2_0_lifecycle_returns.png) |
| MH17 | [Top](visual_refinement_artifacts/mh17_390_s1_0_top.png) | [Bottom](visual_refinement_artifacts/mh17_320_s2_0_bottom.png) |

Matrix: portrait 320/360/390/412 × scale 1/1.5/2, top/bottom; landscape 800×390 × ba scales; long Vietnamese content; loading/empty/error/stale/session loading/expired; MH07 modal; validation/unavailable dialogs; MH09 Delivery/COD/Returns projections và disabled assignment. SafeArea top/bottom 24 được mô phỏng. Keyboard open/close ở 320px, scale 2, inset 300: assert cả bounds trên keyboard lẫn hit-test của search. Ảnh không vẽ bàn phím Android thật. Xem [MH07 keyboard](visual_refinement_artifacts/mh07_keyboard_open.png), [MH08 keyboard](visual_refinement_artifacts/mh08_keyboard_open.png), [expired](visual_refinement_artifacts/mh07_320_expired.png).

Đã mở xem ảnh từng màn và các edge cases, sửa glyph tiền thiếu, badge kéo cao theo AppBar, chip contrast, modal header, footer/gutter và search bị clip. Review source độc lập bằng GPT-5.6 Sol Medium đã kiểm tra exclusions, scope và preview isolation. Các findings còn đúng đã sửa; finding body MH09 dựa trên line cũ được đối chiếu lại, source thực tế đã có gutter 20.

## Files tạo/chỉnh sửa trong lượt refinement

Production presentation:

- `lib/features/orders/presentation/pages/customer_orders_page.dart`
- `lib/features/orders/presentation/pages/manager_orders_page.dart`
- `lib/features/orders/presentation/pages/manager_order_details_page.dart`
- `lib/features/orders/presentation/widgets/order_notification_theme.dart` (mới)
- `lib/features/orders/presentation/widgets/order_card.dart`
- `lib/features/orders/presentation/widgets/order_feed.dart`
- `lib/features/orders/presentation/widgets/order_items_section.dart`
- `lib/features/orders/presentation/widgets/order_payment_section.dart`
- `lib/features/orders/presentation/widgets/order_recipient_section.dart`
- `lib/features/orders/presentation/widgets/order_lifecycle_sections.dart`
- `lib/features/orders/presentation/widgets/order_timeline.dart`
- `lib/features/notifications/presentation/pages/notifications_page.dart`
- `lib/features/notifications/presentation/widgets/notification_tile.dart`
- `lib/features/notifications/presentation/widgets/unread_badge.dart`
- `pubspec.yaml`

Tests/preview:

- `test/features/orders/presentation/pages/customer_orders_page_test.dart`
- `test/features/orders/presentation/pages/manager_orders_page_test.dart` (đã untracked trước lượt này)
- `test/features/notifications/presentation/pages/notifications_page_test.dart`
- `test/visual_refinement/visual_layout_test.dart`, `preview_app_test.dart` (mới)
- `tool/ui_preview/main.dart`, `preview_app.dart` (mới)

Assets/docs/evidence:

- `assets/fonts/Inter-Variable.ttf`, `BarlowCondensed-Bold.ttf`, hai `*-OFL.txt`, `README.md`.
- Năm HTML `docs/ui_mocks/` đã mapping ở trên.
- `docs/visual_refinement_artifacts/`: PNG, manifest, verification logs.
- Báo cáo này; scratch harness/logs trong `.ui_review_tmp/` được giữ lại, không import production.

Các sửa có trước trong `docs/phase_2_completion_report.md`, notification session tests và các untracked Phase 2 foundation/tests khác được giữ nguyên; không gán chúng cho lượt refinement.

## Tests và quality gates

Thêm **4 tests**: layout/render matrix; preview DI chuyển bốn màn và expiry; unread badge compact/semantics; captured notification callbacks bị invalidation trước rebuild. Existing tests chỉ đổi locator/scroll và KPI descendant finder theo layout mới; vẫn assert đúng server counts, cursor, return ID, capability và không dispatch mutation. Không giảm/xóa business assertions.

| Lệnh/kiểm tra | Kết quả thực tế |
|---|---|
| `flutter pub get` | PASS; packages giữ nguyên |
| `dart format` và readonly `--set-exit-if-changed` scoped files | PASS |
| `flutter analyze --no-pub` | PASS — No issues found |
| `flutter test --no-pub` | PASS — **182 passed, 0 failed**, gồm đủ 178 baseline |
| Opt-in render `UI_VISUAL_OUTPUT=1` | PASS — 197 captures, 0 layout exceptions |
| `git diff --check` | PASS; cảnh báo LF→CRLF theo Git config không phải whitespace error |
| Android debug APK preview | PASS với process option phía dưới; build thường trước đó FAIL Kotlin incremental C/D roots |
| Manual Android Emulator interaction | NOT RUN — chưa launch/install/chạy trên emulator |
| Real backend integration / HTML pixel comparison | NOT RUN |

Sau layout ban đầu có 5 failures do locator/offscreen, sau section wrap thêm fixed-distance modal scroll. Đã dùng scroll tới widget + pump/FilterChip finder, giữ nguyên expected business values.

Logs cuối: [pub get](visual_refinement_artifacts/verification_pub_get.log), [analyze](visual_refinement_artifacts/verification_analyze.log), [182 tests](visual_refinement_artifacts/verification_tests.log), [APK build từ source cuối](visual_refinement_artifacts/verification_android_final.log), [diff check](visual_refinement_artifacts/verification_diff_check.log). Lần build source cuối PASS trong 10,6 giây, sau retry ban đầu PASS trong 35,5 giây.

## Manual preview trên Android

Entrypoint `tool/ui_preview/main.dart` nằm ngoài `lib/` để tái sử dụng test fixtures qua file imports mà không kéo fixture vào package production. Có `kDebugMode` guard; normal `lib/main.dart` không import preview. Không cần SUPABASE env/login. Orders mutation vẫn unavailable; notification read acknowledgement là fake riêng của preview, có nhãn DEMO UI.

Máy này có AVD `Pixel_5`; chưa có Android device chạy khi kiểm tra. Từ project root, PowerShell:

```powershell
flutter emulators --launch Pixel_5
flutter devices
flutter run --debug --no-pub -t tool/ui_preview/main.dart -d <android-device-id>
```

Thay placeholder bằng ID thật từ `flutter devices`. Menu “Chọn màn hình”: MH07/08/09/17; “Chọn trạng thái”: data/loading/empty/error/stale/expired. Loading kéo dài 4 giây; MH09 empty là resource unavailable. Với stale, chọn scenario rồi refresh. MH08 mở MH09 qua Navigator riêng của harness; external routes unavailable. Search/filter và Notifications pagination/read ack có thể thao tác. Fixture Orders hiện có một đơn pending, không mô phỏng toàn bộ vận hành. Production polling giữ nguyên; preview tắt polling để tiện thao tác.

Nếu gặp Kotlin `different roots` do Pub Cache ở C và project ở D, tùy chọn tạm dưới đã build APK thành công, không sửa `android/gradle.properties`:

```powershell
$previewGradleOptions = $env:GRADLE_OPTS
try {
  $env:GRADLE_OPTS = "$previewGradleOptions -Dorg.gradle.project.kotlin.incremental=false"
  flutter run --debug --no-pub -t tool/ui_preview/main.dart -d <android-device-id>
} finally {
  $env:GRADLE_OPTS = $previewGradleOptions
}
```

Build đã chạy thực tế với cùng process option: `flutter build apk --debug --no-pub -t tool/ui_preview/main.dart`; APK: `build/app/outputs/flutter-apk/app-debug.apk`. Tham chiếu [Kotlin incremental compilation](https://kotlinlang.org/docs/gradle-compilation-and-caches.html), [Gradle project properties](https://docs.gradle.org/current/userguide/build_environment.html). Native-access JVM warning còn hiện nhưng retry build PASS.

Tái tạo PNG (không cần SDK font path):

```powershell
$env:UI_VISUAL_OUTPUT = '1'
flutter test --no-pub test/visual_refinement/visual_layout_test.dart
Remove-Item Env:UI_VISUAL_OUTPUT
```

Tests mặc định không ghi PNG. Fonts được load từ asset bundle thật. Evidence/geometry tests chưa phải golden pixel baseline.

## Remaining visual issues và dependencies

| Phân loại | Trạng thái |
|---|---|
| MUST FIX / BLOCKER trong phần UI kiểm thử | Không còn defect đã xác nhận; không đồng nghĩa chứng minh không có mọi lỗi |
| SHOULD FIX / visual acceptance | Cần đối chiếu HTML render trực tiếp trong môi trường cho phép; chưa có image-to-image comparison |
| ACCEPTABLE | Native glyph/shadow/wrap có thể khác browser; chữ 2x cần cuộn; header ellipsis để không overflow |
| INTENTIONAL DEVIATION | Unsupported HTML elements và shared bottom navigation/routes ngoài module như đã nêu |
| EXTERNAL DEPENDENCY | Production Auth/session/router shell; Orders RPC/receipt transport; CIN Delivery/Inventory/COD/Returns và external target route owners |
| ENVIRONMENT | Build Android trên máy C/D cần process option; manual keyboard/tap/SafeArea thực tế chưa kiểm chứng trên emulator |

Presentation refinement **IMPLEMENTED AND TESTED**. Visual/browser/Android manual acceptance **PARTIALLY VERIFIED**. Backend/other modules **NOT IMPLEMENTED / BLOCKED BY EXTERNAL DEPENDENCY**, theo scope. Không tuyên bố pixel-perfect, backend COMPLETE hoặc triển khai Phase 3.

## Git cuối lượt

Giữ nhánh `feature/orders-notifications-phase2`, HEAD `4d22a8d`. Không stage/commit/push/merge/chuyển nhánh/reset/clean. Working tree còn modified/untracked. Pages MH07/08/09, shared access/refresh và nhiều Phase 2 tests đã untracked từ trước; font/theme/preview/tests/HTML/evidence mới cũng chưa được version control.

Không xóa untracked hoặc rollback thay đổi người khác. Khi dùng SmartGit, chọn đúng source/assets/docs/tests cần lưu; scratch logs và evidence là lựa chọn riêng. Git diff không chứa nội dung untracked; các Dart files đó đã được đọc/review và đưa vào format/analyze/test tương ứng.
