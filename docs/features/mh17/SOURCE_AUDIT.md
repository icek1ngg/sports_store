# MH17 — Source audit

Snapshot MH17-01 ngày21/10/2026; baseline working files, không HEAD. Historical audit01 không thay source/tests/Preview.
Branch `feature/orders-notifications-phase2`; status có dirty/untracked trước task, lưu nguyên trong baseline.
[Inventory JSON](artifacts/audit_01/source_inventory.json) chứa 47 entries gồm placeholders, dependencies và references.
Feature có **13 Dart files + 7 `.gitkeep`**, sáu focused test files; không có production repository adapter.
Đếm physical lines gồm blank/comment, tính dòng cuối thiếu newline; không dùng `Measure-Object -Line` bỏ blank.

## Actual feature files

Paths bên dưới nối với `lib/features/notifications/`. T=coverage map ở bảng kế tiếp; risk là rủi ro khi refactor.

| Path | LOC | Responsibility / public API | Dependencies / coverage / risk |
| --- | ---: | --- | --- |
| `domain/models/notification_item.dart` |137| `NotificationItem`, `NotificationSubjectType`; nine fields, `isRead`, `toMap`, parse unknown | wire parsing/errors; T1/T3/T4; cao vì identity/privacy |
| `domain/models/notification_page.dart` |51| `NotificationPage`, immutable items, nullable cursor/count/asOf, `copyWith` | item/errors; T1/T2/T4; vừa, cursor gap F02 |
| `domain/models/notification_query.dart` |62| `NotificationFilter`, `NotificationQuery`, equality, `toQueryParameters` | errors; T1/T2/T4; vừa, cursor namespace |
| `domain/models/notification_target.dart` |99| mode/screen enums, target/decision, `targetFromNotification` | item/wire UUID/errors; T3; cao vì permission mapping |
| `domain/repositories/notification_repository.dart` |30| `getPage`, `getUnreadCount`, `markRead`; resolver `resolve(id)`; aliases | domain models; T2–T5 fakes; cao, giữ signatures |
| `domain/repositories/notification_repository_contract.dart` |1| compatibility export duy nhất | repository; gián tiếp T1–T5; thấp, giữ import surface |
| `data/models/notification_dto.dart` |65| `NotificationDto.fromJson`, `domain`, `toJson`, alias, `notificationReadSignal` | item/wire/errors; T1; cao, không fabricate timestamp |
| `presentation/view_models/notification_providers.dart` |98| repository provider; page family/count providers; 2 foundation VMs | SnapshotReadViewModel/session/cache/repository; T4/T2/T5; cao |
| `presentation/view_models/notification_read_invalidation.dart` |33| provider + `NotificationReadInvalidation.acknowledge` | cache/scope/item; T3/T4; cao, canonical ack boundary |
| `presentation/view_models/notification_interaction_view_model.dart` |455| resolver provider; state; VM `markRead`/`openNotification`; interaction provider | repository/resolver/scope/cache/ack; T3/T2/T5; cao |
| `presentation/widgets/notification_tile.dart` |185| data/callback-only `NotificationTile`; private icon/label mapping | item/Hanoi formatter/theme; T6/T2; vừa, preserve text/action/semantics |
| `presentation/widgets/unread_badge.dart` |42| `UnreadBadge(count:int?)`; hide unknown/zero, 99+ visual | Theme/Semantics; T6/T2/T5; thấp, preserve exact spoken count |
| `presentation/pages/notifications_page.dart` |922| `NotificationsPage(onNavigate,enablePolling)`; local merged cursor feed, guards, refresh, context modal | page/count/interaction providers, access/async/poll/theme, models; T2/T5; cao |

Seven `.gitkeep` chỉ giữ directory, không phải feature implementation; `data/repositories/` chỉ có placeholder.
Domain không import Flutter/Supabase SDK. Không có mark-all-read, mark-unread, realtime subscription hoặc push adapter.

## Test map và fresh baseline

Paths nối với `test/features/notifications/`. Tất cả sáu files được chạy mới cùng command; tổng **67 PASS**.

| ID / path | LOC / limit | Coverage thực tế đọc trong test |
| --- | --- | --- |
| T1 `data/notification_dto_test.dart` |62/400| nine keys, unknown kind, required nullable read_at, immutable page/query |
| T2 `presentation/pages/notifications_page_test.dart` |721/400| filters, count unknown/exact, cursor append/retry/loop, head poll, late filter response, stale, ack, navigation |
| T3 `presentation/view_models/notification_interaction_view_model_test.dart` |562/400| canonical ID/owner/read ack, dedup, retry/timeout, disposal/scope, resolver denial/invalid decision |
| T4 `presentation/view_models/notification_foundation_test.dart` |418/400| bad recipient/filter, empty/error, missing adapter, count epoch/negative, session/retry/late reads |
| T5 `presentation/pages/notifications_session_test.dart` |314/400| expiry/modal, first-frame account switch row/badge, denied reads, unresolved/logout, empty recovery |
| T6 `presentation/widgets/notification_widgets_test.dart` |95/400| unread action/read row, badge124→99+ exact semantics, 320dp/text2 layout |

Read tests không chứng minh RLS/trigger/server mutation hoạt động. Xem [TEST_PLAN](TEST_PLAN.md) cho gaps.
[Fresh log](artifacts/audit_01/focused_verified.log); [analyze no issues](artifacts/audit_01/analyze.log).

## Shared dependencies và Preview

| Actual path | LOC / limit | Responsibility / consumption / risk |
| --- | --- | --- |
| `lib/core/state/foundation_providers.dart` |16/150| unresolved session input + scoped cache provider; mọi MH17 provider; cao |
| `lib/core/state/session_scope.dart` |37/150| user/role/generation equality + readable roles; page/VM; cao |
| `lib/core/state/epoch_cache.dart` |120/250| epochs/query/request tokens, block/dispose; reads/ack; cao |
| `lib/core/state/snapshot_read_view_model.dart` |183/250| serialized read/refresh/retry/late response; foundations; cao |
| `lib/core/state/read_snapshot.dart` |19/150| data/loading/failure/stale envelope; page; cao |
| `lib/core/state/read_retry_policy.dart` |19/150| read backoffs provider; shared VM; vừa |
| `lib/core/errors/app_failure.dart` |196/150| typed failures; all layers; cao, protected dependency |
| `lib/core/errors/wire_parsing.dart` |367/150| strict wire primitives; domain/DTO; cao |
| `lib/core/errors/unsupported_data_exception.dart` |55/150| unsupported/invalid domain errors; models; vừa |
| `lib/core/errors/presentation_failure_message.dart` |21/150| failure messages; page; thấp |
| `lib/core/utils/display_formatters.dart` |221/150| Hanoi timestamp formatter; tile; vừa |
| `lib/features/orders/presentation/widgets/order_notification_theme.dart` |254/180| shared visual tokens/font scope; page; cao, approved screens |
| `lib/shared/widgets/async_content.dart` |402/180| loading/empty/error/stale states; page; cao |
| `lib/shared/widgets/feature_access_gate.dart` |63/180| role/session gate; page/modal; cao |
| `lib/shared/widgets/foreground_refresh.dart` |87/180| foreground/route refresh timer; page; cao |
| `lib/app/router/app_router.dart` |26/300| current root-only coordinator; notification route chưa có; external |
| `tool/ui_preview/preview_app.dart` |308/250| `UiPreviewApp`, private `_PreviewInbox` fake; no resolver/onNavigate; shared protected Preview |
| `tool/ui_preview/main.dart` |17/250| debug entry chạy Mh08PreviewApp; không mở MH17 trực tiếp |
| `test/fixtures/order_notification_fixtures.dart` |182/400| shared UUID/nine-field fixtures; focused tests/Preview |
| `test/visual_refinement/preview_app_test.dart` |123/400| legacy UiPreviewApp switching, expiry/badge; NOT RUN task01 |
| `test/visual_refinement/visual_layout_test.dart` |654/400| legacy screenshot/responsive harness, bốn màn; NOT RUN để giữ evidence |

Inventory JSON ghi exact imports/public types/SHA cho từng dependency; static import closure không phải full repository audit.
Shared infrastructure có tests riêng ngoài focused run; không coi test coverage gián tiếp là full verification.

## LOC violations và extraction proposals

- MH17 production: page **922>300**, interaction VM **455>250**, tile **185>180**.
- MH17 tests: page **721>400**, foundation **418>400**, interaction **562>400**.
- Shared: failures196, parsing367, formatters221 >150; theme254 và AsyncContent402 >180.
- Reference: Preview308>250; legacy visual test654>400. Không sửa shared/approved files để đạt MH17 gate.
- Page: extract existing filters/feed/load-more/context UI; sau đó characterize và tách local feed/lifecycle coordination.
- Tile: chỉ tách icon/type presentation nếu cần; không thay toàn component vì mock khác structure.
- VM: tách typed decision policy/read orchestration theo responsibility sau characterization, giữ providers/contracts.
- Tests: chia theo cursor/read/navigation/session responsibility, không bỏ assertions; chi tiết [roadmap](ARCHITECTURE_PLAN.md).

## Findings có nguồn

| ID | Evidence | Kết luận / đề xuất |
| --- | --- | --- |
| F01 | providers:13, interaction VM:20, foundation_providers:6, router:5 | production DI/Auth/router chưa tích hợp; client tested ≠ feature end-to-end |
| F02 | page model:5/28; page:484/510; query:44 | nextCursor rỗng/quá2048 chưa bị chặn khi nhận; có thể normalize sai hoặc throw lúc build; thêm reproducer ở task sau |
| F03 | interaction VM:356–449; T3 positive cases | typed mapping đã có nhưng positive/negative role matrix còn thiếu; không nhận mọi route PASS |
| F04 | tile:43/68, page context:756; spec §9.2/CIN09 | plain text hiển thị nguyên văn; safe payload phụ thuộc producer, UI không lọc PII |
| F05 | page `_open`, VM `openNotification`; `_readRequests` chỉ markRead | read dedup đã có; rapid repeated navigation chưa có dedicated guard/test; cần characterization, chưa khẳng định defect runtime |
| F06 | rev1.2 §10–12, data/API OP-N01–04 | “Missing models/UI” historical đã lỗi thời; feature docs này phân biệt current client và missing adapter |
| F07 | `preview_app.dart:239–251`, shared fixture:169–181 | ba fake rows reuse eventId/recipient, notification_only giữ order subjectId≠eventId; chưa canonical producer fixtures; sửa riêng03B khi được giao |

F02 là static defect candidate được reviewer độc lập đối chiếu; không chạy reproducer mới vì task01 không thêm tests/source.
SQL access baseline xem migration `20261006034259_sports_store_access.sql`: own-recipient policies + read_at column grant/first-time trigger.
Không chạy SQL/connection; không xác nhận deployed schema. Không sửa migration hoặc shared contracts.

## Giữ nguyên working code

Giữ models/DTO/contracts; exact count provider; canonical acknowledgement; read/navigation độc lập;
first-frame session clearing; epoch rejection; cache identity checks; head refresh thay append khi polling;
cursor duplicate protection; per-ID pending read; unknown/notification_only handling; tile/badge/accessibility đã có.
Đặc biệt giữ callback API `Future<bool> Function(NotificationTargetDecision)`; không tạo raw route từ title/body.

## MH17-03A1 current delta — tests only

Production16Dart files (gồm3components02) giữ nguyên working hashes; no UI/provider/model/cache/Preview changes.
Original page test721→222(root)/221(pagination)/124(read-navigation), giữ18declarations/19cases/94expect expressions103expanded.
New14 characterization cases trong4files74/146/116/130LOC; helpers137/52/43≤150, không private production-method access.
[REFACTOR_03A1](REFACTOR_03A1.md) ghi exact test map, method→owner và proposed03A2; [proof](artifacts/refactor_03a1/test_preservation_report.json).
Current focused120 PASS; no skips; existing components02/interaction/foundation/session tests giữ nguyên.
Debt còn: page922,VM455,tile185,interaction test562,foundation418; không claim whole-feature LOC compliance.
F05 characterized: pending read hit +2body taps→3authorized nav callbacks/1read request; không chứng minh3production routes hoặc forbidden navigation.
F02/F03/F07 giữ nguyên; current source/old artifacts SHA xem [verification](artifacts/refactor_03a1/verification.json).
