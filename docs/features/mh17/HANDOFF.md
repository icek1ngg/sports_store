# MH17 — Final UI & Android acceptance

**READY FOR USER UI ACCEPTANCE** trong phạm vi UI/client đã kiểm tra. MH17 UI vẫn NOT USER APPROVED.
User đã bỏ toàn bộ LOC gates/ngoại lệ cũ; [ENGINEERING_RULES](ENGINEERING_RULES.md) là chính sách hiện hành.
[Acceptance](FINAL_UI_ANDROID_ACCEPTANCE.md), [verification mới](artifacts/final_acceptance/verification.json) dùng working-source baseline.

## Cấu trúc và trách nhiệm

- Screen canonical: lib/features/notifications/presentation/screens/notifications_screen.dart (NotificationsScreen).
- Widgets: notifications_header.dart trả AppBar thật; notifications_content.dart giữ layout/filter/access-error presentation.
- Reuse Filters/Feed/NotificationTile/UnreadBadge, shared AsyncContent loading/empty/error và ContextModal/Handle; không redesign.
- Providers canonical: lib/features/notifications/presentation/providers/ gồm foundation, InteractionVM, invalidation và các coordinator/Actions hiện có.
- pages/notifications_page.dart giữ typedef NotificationsPage; view_models/ chỉ re-export canonical implementation cho router/Preview/tests cũ.
- Legacy/canonical imports có cùng provider/class identity, không tạo duplicate state/cache. Preview/router wiring không cần thay đổi.
- Foundation giữ canonical pages/count/cache; InteractionVM giữ canonical ack và typed target validation.
- ReadCoordinator/FeedCoordinator giữ một accepted-feed/filter/cursor/refresh/retry authority; SessionBridge giữ lease/subscriptions.
- Coordinator/Actions theo lifetime Screen, không thêm provider wrapper chỉ để đạt hình thức thư mục.
- Screen chỉ watch/wire UI, giữ live ref/context, lifecycle guards, polling eligibility, modal push và callbacks.

## Actions và ThemeData

Actions đã tích hợp; orchestration read/open cũ đã được thay thế. Không optimistic readAt/count, vẫn giữ read/open độc lập và F05 behavior.
Port context đổi nhỏ sang (namespace, NotificationItem) đồng bộ; Screen recheck exact accepted-row identity, recipient/type và live provenance trước handle.
Test-support chỉ adapt callback shape, không thay original assertions. Adapter không giữ raw item trong asynchronous continuations.
N07 modal vẫn độc lập sau Screen disposal; handoff, denial/two-fresh recovery, F02 và late-response protections giữ nguyên.
AppTheme.notifications/notificationsScope reuse style hiện hành tại lib/app/theme/storefront_theme.dart.
AppTheme.light global không đổi; OrderNotificationTheme giữ compatibility API và delegate cùng shared ThemeData/font licenses.
Không nested MaterialApp, không dark-theme mới, dependency/backend/Auth/router/Preview/business contract không đổi.

## Verification —26/10/2026

Refactor trước task này:426focused/89Page/268Orders/7selected PASS; evidence cũ giữ nguyên, không coi268Orders là rerun mới.
Fresh cuối acceptance:441MH17focusedPASS (426baseline+15new); Page/session89+selected7=96PASS; analyzer PASS.
Format/diff/links/SHA PASS; baseline3214files,3212protected giữ nguyên; chỉ tile semantics và HANDOFF là existing files được sửa.
Đã sửa duplicate title/type trong native accessibility label bằng ExcludeSemantics; body/time/read control và gesture giữ nguyên.
Có failing reproduction trước sửa và tree Android sau sửa; không thay original test assertions, không đổi F05 policy.
Pixel_5/API35 build/install/launch PASS; APK cuối khớp installedSHA, launcher debug mới reuse Preview fixtures có nhãn DEMO.
Native All/Unread, badge/read, tail, empty/error/stale/expired, context Close/Back và scrolling320/font2 đã thao tác.
Flutter12width/text combinations long text/scroll PASS; Android12matrix screenshots; widget48dp/labels/Tab→Space PASS.
TalkBack15 bật/bind service; Tab input focus đã quan sát, chưa xác minh TalkBack accessibility focus/traversal/audio.
Đã khôi phục TalkBack tắt và display/font gốc; touchExplorationEnabled=false trong service dump.
[Ảnh Android cuối](artifacts/final_acceptance/android/mh17_final.png), [modal](artifacts/final_acceptance/android/final_context.png).
[Before/after](artifacts/structure_refactor/visual_comparison.json):7cặpPNG byte-identical, gồm MH17 390/320/text2 và Preview MH07/MH08/MH09/MH17.
Comparison load Inter/Barlow; ảnh review riêng load thêm MaterialIcons. Đã xem MH17 390/text1 và320/text2 với icon font thật.
[Ảnh MH17](artifacts/structure_refactor/review/mh17_390_text1.0.png), [text2](artifacts/structure_refactor/review/mh17_320_text2.0.png).
New tests ở test/features/notifications/presentation/screens/: canonical/legacy identity, Actions exact-row transfer/rejection, header/content và responsive/Preview.
Independent Sol medium read-only review: các finding identity/AppBar/theme entrypoint đã xử lý; không còn blocker. Main triển khai vì Luna không có trong tool catalog.
Các attempt logs, before/after/review captures và evidence cũ được giữ nguyên. Không commit/push/reset/clean/checkout/switch/stash/merge.

## Còn lại để nghiệm thu

- User review UI; TalkBack audio/phát âm/full traversal chưa xác minh. Native matrix không phải full interaction matrix.
- Session loss trong modal/A→B/late/cache/first-frame PASS bằng regressions; chưa tái tạo tất cả race bằng native manual.
- Backend/API/Auth/router/resolver production và server authorization chưa được xác minh bằng task này.
- F03 typed role matrix, F05 route/navigation policy review, F07 legacy fixture canonicality vẫn pending; không tự nhận hoàn thành.
- Không chạy full repository suite có legacy fixed-output captures; đã chạy focused/Orders/selected và ảnh task-specific an toàn.
Đọc tiếp: AGENTS → ENGINEERING_RULES → Screen → providers/Actions → test screens → verification. Không có LOC gate hay audit mới.
