# Báo cáo hoàn tất Phase 1 — Flutter Foundation

Ngày 09/10/2026. Baseline: Technical Specification revision 1.2. Đây là continuation từ code có sẵn, không khởi tạo lại dự án.

## A. Quyết định hoàn thành

**PHASE 1 COMPLETE WITH EXTERNAL LIMITATIONS.** Models/DTO, repository contracts, utilities, shared widgets và nền state/cache đã được kiểm thử local. Bốn màn hình và các workflow production chưa được triển khai trong Phase 1.

## B. Implemented and tested

| Nhóm | Kết quả | Đặc tả đáp ứng trong phạm vi foundation |
|---|---|---|
| Domain/DTO | Order, items, summary/details/page, capabilities, lifecycle enums, timeline, warnings, receipt, operation result, notification/read state/query/page/typed target | Main §10; Data/API §2–4, §4.6, §4.8 |
| Parsing/validation | Snake_case, required nullable keys, UUID không giới hạn v1–v5, integer VND, UTC offset, invalid calendar rejection, unknown enum fail closed, unknown warning generic | Data/API §1, §4.6 |
| Graph | Items/buyer/attempt/COD/returns cùng order; full item subtotal; COD obligation bằng total_cod_vnd; unique IDs/counts; timeline state/entity/source/event và conflicting duplicate validation | Data/API §3, §4.1–4.4 |
| Errors | AppErrorDto allowlist, safe current_order chỉ cho state/precondition failures, unknown outcome, discriminated RPC envelope; ok=false không gọi success mapper | Data/API §5.2–5.3 |
| Utilities/UI | VND integer, Hanoi UTC+7, bốn lifecycle labels, order card/items/recipient/payment/timeline/status badge, notification tile/unread badge | Main §6.1/6.3, §8.1/8.2, §9.1/9.3, §12.3 |
| Async UI | Initial loading/error, accepted empty/data, refreshing/stale/error, session expired/unavailable; giữ dữ liệu stale để đọc và ẩn private data khi quyền/phiên không còn | Main §12.2–12.3 |
| State/cache | DI Riverpod, session/resource/query/request generations, serialized refresh, late response rejection, account isolation, expiry clearing; historical receipt không ghi vào canonical cache | Main §12.5; Data/API §4.8, §12; CIN-01 consumer boundary |
| Retry/invalidation | Read timeout 10s; network retry tối đa hai lần 0.5/1.5s; không tự retry application/validation/authorization/dependency errors; detail/read acknowledgement invalidate và refetch | Main §12.3/12.5; Data/API §11–12 |
| Repository boundary | Orders, Notifications, target resolver và protected pending-command store interfaces; thiếu adapter trả explicit external dependency | Data/API §12; DR-01/04 |

Các phần trên là consumer foundations, không phải acceptance cho backend/RLS/transactions hay full-page UX. SessionScope nhận đầu vào từ Auth owner, không tự xác thực hoặc tạo session service.

## C. Files changed trong lượt continuation

Chỉ báo cáo tệp foundation sửa nội dung hoặc format. Phần lớn đã tồn tại nhưng còn untracked từ lượt trước; không được coi là vừa tạo mới trong lượt này.

Core:

- `lib/core/errors/app_failure.dart`
- `lib/core/errors/unsupported_data_exception.dart`
- `lib/core/errors/wire_parsing.dart`
- `lib/core/state/snapshot_read_view_model.dart`
- `lib/core/utils/display_formatters.dart`
- `lib/shared/widgets/async_content.dart`

Orders:

- `lib/features/orders/data/models/order_dto.dart`
- `lib/features/orders/domain/models/buyer.dart`
- `lib/features/orders/domain/models/cod_summary.dart`
- `lib/features/orders/domain/models/delivery_summary.dart`
- `lib/features/orders/domain/models/model_validators.dart`
- `lib/features/orders/domain/models/operation_result.dart`
- `lib/features/orders/domain/models/order.dart`
- `lib/features/orders/domain/models/order_capabilities.dart`
- `lib/features/orders/domain/models/order_command.dart`
- `lib/features/orders/domain/models/order_details.dart`
- `lib/features/orders/domain/models/order_item.dart`
- `lib/features/orders/domain/models/order_mutation_receipt.dart`
- `lib/features/orders/domain/models/order_page.dart`
- `lib/features/orders/domain/models/order_query.dart`
- `lib/features/orders/domain/models/order_status.dart`
- `lib/features/orders/domain/models/order_summary.dart`
- `lib/features/orders/domain/models/order_timeline_entry.dart`
- `lib/features/orders/domain/models/order_warning.dart`
- `lib/features/orders/domain/models/return_summary.dart`
- `lib/features/orders/domain/repositories/order_repository.dart`
- `lib/features/orders/presentation/view_models/order_providers.dart`
- `lib/features/orders/presentation/widgets/order_card.dart`
- `lib/features/orders/presentation/widgets/order_items_section.dart`
- `lib/features/orders/presentation/widgets/order_payment_section.dart`
- `lib/features/orders/presentation/widgets/order_status_badge.dart`
- `lib/features/orders/presentation/widgets/order_timeline.dart`

Notifications:

- `lib/features/notifications/data/models/notification_dto.dart`
- `lib/features/notifications/domain/models/notification_item.dart`
- `lib/features/notifications/domain/models/notification_page.dart`
- `lib/features/notifications/domain/models/notification_query.dart`
- `lib/features/notifications/domain/models/notification_target.dart`
- `lib/features/notifications/presentation/view_models/notification_providers.dart`
- `lib/features/notifications/presentation/widgets/notification_tile.dart`
- `lib/features/notifications/presentation/widgets/unread_badge.dart`

Tests và fixtures:

- `test/core/utils/display_formatters_test.dart`
- `test/features/orders/data/order_dto_test.dart`
- `test/features/orders/presentation/view_models/order_foundation_test.dart`
- `test/features/orders/presentation/widgets/order_widgets_test.dart`
- `test/features/notifications/data/notification_dto_test.dart`
- `test/features/notifications/presentation/view_models/notification_foundation_test.dart`
- `test/features/notifications/presentation/widgets/notification_widgets_test.dart`
- `test/fixtures/order_notification_fixtures.dart`
- `test/shared/widgets/async_content_test.dart`

Tạo mới: `docs/phase_1_completion_report.md`.

Các nền có sẵn được tái sử dụng: SessionScope, EpochCache, ReadSnapshot, retry/DI providers, notification read invalidation, repository/export shims, shared AppTheme/Supabase provider. Không sửa pubspec/lockfile, router, theme, shared Supabase client hoặc migrations. Bốn shared documentation diffs đã có trước continuation được giữ nguyên.

## D. Problems fixed

- Baseline thực tế: không còn compile errors, nhưng analyzer có 36 issues và suite có 50 pass/4 fail. Không mặc định trạng thái lỗi từ lượt trước vẫn giữ nguyên.
- Sửa initializing/super parameters, braces và unused imports; không suppress analyzer.
- Sửa duplicate semantics của badges, notification overflow khi 320px/text scale 2 và các payment/item layouts.
- Sửa test retry khởi tạo policy sau initial read gây request thừa; giữ oracle hai retry, không tăng expected để che race.
- Phân biệt unresolved role loading với logged-out/expired session. Expiry ở một resource xóa data/outcome riêng tư ở các resource liên quan ngay khi Auth chưa cập nhật scope.
- Chặn receipt muộn sau expiry; giữ historical action outcome tách canonical order và clear khi hết quyền.
- Kiểm tra response identity/recipient/filter; dữ liệu tài khoản khác không được accept vào UI/cache.
- Chuẩn hóa DTO semantic violations thành unsupported_data; không tự lấp missing/null/unknown business fields.
- Chặn auto_confirm trong client command, giữ enum cho server receipt. Envelope business failure không trở thành HTTP-success business success.
- Timeline sort/dedup, actual milestone ưu tiên fallback; actor null/rỗng không bị suy thành system.
- VND formatter xử lý cả giới hạn integer âm mà không dùng abs gây overflow.

## E. Test coverage và verification thực tế

92 tests PASS: 85 tests Phase 1 và 7 tests cấu hình Supabase có sẵn. Fixture/fake tests không gọi Supabase và không chứng minh integration backend.

Coverage: valid/invalid DTOs, round-trip snake_case, missing nullable/unknown fields, UUID mới, integer amounts, timestamps/invalid dates, graph IDs/subtotal/COD/count, error reference scope/envelope, timeline actor/source/entity/duplicates, Unicode query normalization, epoch/query/request ordering, stale state, historical receipts, account switching, expiry, retry backoffs/limit/non-retry errors, notification acknowledgement/count, list/detail invalidation, role boundary và widget async/semantics/long text/320px text scale 2.

| Lệnh đã chạy | Kết quả |
|---|---|
| `flutter pub get` | PASS, exit 0, Got dependencies; không upgrade packages |
| `dart format` trên các path Phase 1 | PASS, exit 0; lượt tích hợp format 71 files, sau sửa graph cuối format 3 files |
| `flutter analyze --no-pub` | PASS, exit 0, No issues found, toàn dự án |
| `flutter test --no-pub` | PASS, exit 0, 92 tests, All tests passed, toàn suite |
| `git diff --check` | PASS trên tracked diffs; code untracked được đọc/review và analyzer/test kiểm tra |

Môi trường Windows PowerShell, Flutter SDK hiện có của nhóm. Các lệnh Flutter/Dart chạy với quyền ghi SDK cache được cấp; không cài SDK/dependencies mới. Review độc lập không còn finding P0/P1 mở trong scope; runtime verification do coordinator chạy.

## F. Remaining issues và boundaries

| Phân loại | Trạng thái |
|---|---|
| BLOCKER trong Phase 1 | Không còn phát hiện qua review/analyzer/tests |
| MAJOR trong Phase 1 | Không còn phát hiện |
| MINOR / chưa verified | Chưa QA thiết bị thật, benchmark, full responsive/device matrix; chỉ widget harness hiện có |
| EXTERNAL DEPENDENCY | Auth trusted role/session generation/protected pending store CIN-01; backend safe read RPC/receipt/lookup/job/producers; projection/operational contracts CIN-02–09 chưa đủ runtime evidence |
| NOT IMPLEMENTED | Full MH07/MH08/MH09/MH17 pages, router/guards, production adapters, mutations/recovery orchestration, polling lifecycle, SQL migrations/RPC/job/notification producers, Auth/Delivery/COD/Returns/Chat |
| IMPLEMENTED BUT NOT VERIFIED | Các interfaces/typed target/pending-store consumer shape chưa có real adapter hoặc integration environment để kiểm chứng production |

Repository mặc định không trả fake success. Khi chưa inject adapter thì foundation báo external_dependency_unavailable; default session chưa resolved không đọc private data. Pure interfaces không được báo như backend feature hoàn thành.

## G. Next phase readiness

Có thể bắt đầu Phase 2 ở phần presentation integration của bốn màn theo revision 1.2, dùng models/widgets/DI/cache hiện tại và test overrides. Trước khi bật live data/actions cần Auth/session bridge, safe backend operations/projections và acceptance của external owners. Adapter phải kiểm tra method với command.operation, dùng một Supabase client chung, parse envelope trước business data và recheck quyền cho target. Router owner xử lý guards/UUID route canonicalization. Pending command persistence, recovery, polling và backend acceptance tests thuộc phase tiếp theo được giao riêng.

Không triển khai Phase 2 trong lượt này.
