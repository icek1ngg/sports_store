# MH17 — Engineering rules

## Quyết định hiện hành của user —26/10/2026

BỎ toàn bộ LOC gates và các ngoại lệ LOC trước đây cho công việc MH17.
Không đặt giới hạn dòng cho Screen/coordinator/widget/test/helper/docs; không xin thêm ngoại lệ và không tạo audit/budget để giảm dòng.
Các con số/gates trong evidence/checkpoint lịch sử chỉ mô tả chính sách tại thời điểm đó, không phải điều kiện nghiệm thu hiện hành.
Ưu tiên trách nhiệm rõ ràng, code dễ đọc, correctness, privacy và kiểm thử; không nén code hoặc chia file vô nghĩa.
Refactor hiện hành được phép tổ chức presentation thành screens/widgets/providers, tích hợp Actions và đưa style hiện tại vào AppTheme dùng chung.
Không đồng nghĩa MH17 UI USER APPROVED; MH07/MH08/MH09 current UI/Preview accepted, external limitations giữ nguyên.

## Cấu trúc và authority

- Canonical Screen: presentation/screens/notifications_screen.dart; đường pages cũ chỉ tương thích import/API.
- Canonical Riverpod providers/ViewModels/local coordinators: presentation/providers/; view_models cũ chỉ re-export cùng implementation.
- Foundation giữ canonical list/count/cache/epochs; InteractionVM giữ ack và typed target validation.
- ReadCoordinator giữ rounds/receipts/denial/recovery; FeedCoordinator giữ một accepted presentation list/cursor/retry.
- SessionBridge giữ lease/subscriptions; Screen giữ live WidgetRef/BuildContext, mounted lifecycle, modal push và wiring.
- Actions chỉ điều phối qua các authority hiện có; không repository/cache/count/permission authority thứ hai.
- Widgets nhận data/callback; dùng ColorScheme/TextTheme, reuse shared states; không tự gọi repository hoặc tính canonical count.
- ThemeData/storefront styles thuộc lib/app/theme; AppTheme.light global không đổi ngoài scope được giao.
- Không redesign UI; bảo vệ font/layout/styles đã duyệt của Orders bằng regressions và ảnh task-specific trước/sau.
- Không thêm nested MaterialApp, router/client/auth/SQL/backend riêng hoặc dependency upgrade không cần thiết.

## Security và correctness

- Account/logout/expiry/role/generation/cache block phải fail closed trước private render; lease/revision/requestId không phải authorization.
- Same-owner readable cache handoff chỉ giữ stale display; clear receipts/cursors/intents và chờ head/count mới trước actions.
- Canonical mark-read phải xác minh ID/recipient/readAt/session/cache; không optimistic readAt hoặc unread count decrement.
- All/Unread là server-side query; exact unread count từ foundation count, độc lập paginated rows.
- Typed navigation vẫn qua VM/resolver và permission hiện hành; không parse title/body thành route hoặc PII fallback.
- Actions context phải chuyển canonical row đồng bộ; Screen recheck object identity, recipient, namespace/query/cache provenance trước tạo handle.
- Route builder chỉ capture revocable handle; modal tự giữ subscriptions khi Screen đã dispose; revoke không đồng nghĩa pop.
- N01 arm-before-I/O; N04 cached head adoption; N05 ack invalidation coalescing; deferred invalid_cursor request recovery giữ nguyên.
- F02 malformed response cursor guard vẫn ở foundation; không normalize/decode cursor. F03/F05/F07 vẫn pending.

## Verification và Git safety

- Baseline là current working files: branch/status và SHA trước sửa; không dùng HEAD thay approved working source.
- Preserve approved dirty/untracked work và historical evidence. Không reset/clean/checkout/switch/stash/merge/commit/push.
- Không xóa/ghi đè evidence cũ; screenshot mới vào namespace riêng và từ chối ghi đè file tồn tại.
- Giữ original assertions; chỉ điều chỉnh test-support API khi tương thích bắt buộc, thêm behavior regressions cho thay đổi.
- Chạy dart format, flutter analyze --no-pub, MH17 focused/Page/session và safe selected/order regressions.
- Không chạy legacy fixed-output capture tests trên historical paths. Không pub get nếu dependencies không thay đổi.
- Phân biệt Flutter code verified, UI visually reviewed và backend/production integration verified; chỉ claim theo evidence thực thi.
- HANDOFF ngắn gọn: cấu trúc/authority, tests, visual/backend limitations và việc còn lại; không tạo thêm architecture/LOC reports.
- Review độc lập tập trung security/correctness, không kiểm số dòng. Không recursive delegation.
