# Checklist triển khai Phase 2

Baseline revision 1.2, Phase 1 commit `8e982ac`; đầu lượt working tree sạch. Chỉ presentation, không migrations/RPC/adapters/Auth/router của nhóm.

## Đối chiếu và dependencies

- Reuse domain/DTO/repository contracts, SessionScope, EpochCache, SnapshotReadViewModel, query-family providers, retry, AsyncContent và các order/notification widgets.
- Central router hiện chỉ `/`, session mặc định unresolved, repositories chưa có production adapter. Pages được bàn giao dưới dạng widgets và callbacks/typed navigation; không tự tạo phiên để demo.
- UI07/UI08/UI09 source images không có trong repository; dùng hierarchy Main §6–8, theme hiện tại. Pixel comparison chưa kiểm chứng. MH17 giữ Proposed Design §9.1.
- Orders mutations thiếu protected command storage và backend: chỉ dialog/validation/current-capability recheck; luôn thông báo unavailable khi submit hợp lệ. Không tạo request key/receipt/success giả.
- CIN-03/04/05/06/08/09 chưa accepted/runtime implemented: external action disabled; navigation chỉ qua callback/typed resolver đã recheck current permissions.

## Phân công file

| Nhóm | File dự kiến | Đối chiếu |
|---|---|---|
| Chung, coordinator | `lib/shared/widgets/feature_access_gate.dart`, `lib/core/errors/presentation_failure_message.dart`, `lib/features/orders/presentation/widgets/order_action_dialog.dart` + tests | Main §5.3/12.2/12.4; Data/API §5.3 |
| MH07/MH08, worker lists | `orders/presentation/pages/customer_orders_page.dart`, `manager_orders_page.dart`, `widgets/order_feed.dart` + page tests | Main §6/7; Data/API §4.1/6.1 |
| MH09, worker detail | `orders/presentation/pages/manager_order_details_page.dart`, `widgets/order_lifecycle_sections.dart` + page tests | Main §8; Data/API §3/4.2 |
| MH17, worker notifications | `notifications/presentation/pages/notifications_page.dart`, `view_models/notification_interaction_view_model.dart` + tests | Main §9; Data/API §11/12 |
| Review/verification/report | `docs/phase_2_completion_report.md` | User Phase 2 quality gates |

## Checklist theo màn

- MH07: customer gate, debounce350 search/server query, all10 status filters, exact total, cursor paging; read-only stale; detail/tracking modal own fetched UUID; recipient/items/payment/history; cancel dialog; return entry/callback unavailable; search/scroll preserved on back.
- MH08: manager gate, buyer search query, statusCounts from whole query not page length, summary/warnings, confirm/reject reason dialog, current capability recheck, MH09 callback unavailable safely.
- MH09: manager gate, buyer/recipient/items/totals/timeline; delivery/COD/return separate lifecycle and null unavailable; confirm/reject/exceptional cancel dialogs; assignment/retry/receipt/inspection disabled; optional COD/return/chat intents.
- MH17: all/unread paging, server unread count/null unknown badge, explicit mark-read canonical acknowledgement, no optimistic count decrement, typed resolver/current authorization, read/nav independent, notification-only/unknown safe handling, pending read IDs/session isolation.
- Các màn: loading/empty/error/refresh/stale/session states, 320px/text scale/long text, no cross-user UI/callback.

## Verification

Tests dùng injected test-only repositories; không backend acceptance. Run format các file thay đổi, `flutter analyze --no-pub`, `flutter test --no-pub` (92 baseline tests phải giữ PASS), `git diff --check`. Review độc lập sau khi workers ổn định. Chỉ đánh dấu hoàn thành sau toàn bộ presentation scope và tests đạt; nếu còn thiếu ghi next-action checklist.
