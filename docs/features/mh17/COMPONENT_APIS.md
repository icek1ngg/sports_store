# MH17-02 — Controlled presentation APIs

Checkpoint A ngày21/10/2026, ghi trước khi tạo Dart. User đã duyệt01 và chỉ giao isolated components02.
Fresh baseline:3.194 working files, branch `feature/orders-notifications-phase2`; hai new code/test directories chưa tồn tại.
Existing MH17 tests chạy lại:67 PASS; [baseline log](artifacts/components_02/baseline_tests.log).
[Working SHA baseline](artifacts/components_02/workspace_baseline.json), không dùng HEAD.

## Constructor contracts

```dart
const Mh17NotificationFilters({
  NotificationFilter selectedFilter = NotificationFilter.all,
  ValueChanged<NotificationFilter>? onFilterChanged,
  VoidCallback? onRefresh,
  bool isRefreshing = false,
  Key? key,
});

Mh17NotificationFeed({
  required List<NotificationItem> items,
  required bool hasData,
  NotificationFilter filter = NotificationFilter.all,
  bool isInitialLoading = false,
  bool isRefreshing = false,
  bool isStale = false,
  String? errorMessage,
  VoidCallback? onRetry,
  Future<void> Function()? onRefresh,
  bool hasMore = false,
  bool isLoadingMore = false,
  String? loadMoreErrorMessage,
  VoidCallback? onLoadMore,
  ValueChanged<NotificationItem>? onOpen,
  ValueChanged<NotificationItem>? onMarkRead,
  Set<String> pendingReadIds = const <String>{},
  Key? key,
});

const Mh17NotificationContextSheet({
  required String title,
  required String body,
  String? availabilityMessage,
  VoidCallback? onClose,
  Key? key,
});
```

## Decisions và parent ownership

- Cả ba StatelessWidget, không Riverpod/VM/repository/router/session reads; không side effects từ build.
- Filters controlled selection, nullable callbacks disable; refresh disabled khi busy; Wrap và hit targets≥48dp.
- Feed defensive immutable items/pending-set snapshot cho render; không cache, mutate, filter, sort, merge hoặc dedup.
- `hasData` là accepted-snapshot input, không infer từ list length; empty presentation chỉ dùng items.isEmpty.
- Shared AsyncContent owns loading/error/empty/stale/refresh UI; không tạo state class mới.
- Feed dùng một bounded ListView; consumer phải đặt trong bounded height (Scaffold body/Expanded).
- `hasMore` do parent/cursor quyết định; false không footer. Load-more pending/error chỉ đổi footer, giữ rows.
- `onLoadMore` được parent bind next-page hoặc retry đúng cursor; null là unavailable, không tự retry.
- Optional pull refresh dùng parent Future; no callback thì không RefreshIndicator. Retry error dùng callback riêng.
- Callback item là NotificationItem instance do parent cung cấp; tile key giữ canonical item.id.
- `pendingReadIds` chỉ display pending state cho tile; mark-read/open độc lập; read row không explicit read action.
- Parent phải cung cấp null item callbacks khi stale/unauthorized; Feed không tự cấp quyền theo flag/role.
- Parent cung cấp rows đã authorize, safe error strings; access gate/session-clear vẫn bắt buộc ở integration03A.
- Không có unread count input/badge trong Feed; server exact count vẫn là foundation/shell authority.
- Reuse NotificationTile nguyên trạng: title/body/time/type/unread semantics không copy hoặc truncate.
- ContextSheet nhận strings đã được parent cho phép hiển thị, không nhận raw IDs/targets hoặc tự sanitize PII.
- Heading Semantics chỉ wrap Text, không duplicate label; Close≥48dp; SafeArea/scroll, parent owns modal route.
- On scope loss parent phải remove/close sheet; standalone tests chỉ chứng minh component không retain state sau removal.
- Nullable close callback disable button; không tự Navigator.pop hoặc tự chạy mark-read/navigation.

## Files, budgets và verification

Production additions dưới `lib/features/notifications/presentation/widgets/mh17/`:
`notification_filters.dart`≤100, `notification_feed.dart`≤180, `notification_context_sheet.dart`≤150.
Tests mới cùng file names với suffix `_test.dart` dưới `test/features/notifications/presentation/widgets/mh17/`,≤400/file.
Optional `notification_test_support.dart` chỉ nếu shared fixture/host responsibility cần,≤400.
Tests dùng valid UUIDs/UTC/nonblank title/body; unique event/recipient pair, notification_only.subjectId=eventId.
Format/analyze/new isolated tests + original67 tests; physical LOC/docs links/diff/protected SHA.
No production page/provider/model/tile/badge/Preview/shared/MH07–09/backend edits; no new dependencies.
STOP02 trước integration03A/03B/03C. [Architecture](ARCHITECTURE_PLAN.md) giữ các phase sau là proposals.

## Implementation02 verified

Ba constructors trên được implement nguyên API; production LOC60/121/51; không helper production mới.
Feed tests được chia render/pagination297LOC và interactions139LOC theo responsibility, không bỏ test để đạt gate.
Filters test196LOC, context233LOC; shared test fixture/host54LOC;39new +67original =106 PASS.
Tile pending disabled read hit có thể đi tới outer open; giữ behavior protected tile, parent callback guard vẫn cần.
Empty-state pull refresh không thay outer AsyncContent: owner có thể dùng explicit Filters refresh, như existing page.
Tests không có ProviderScope/repository/router giả để nhận authorization success; chỉ assertion presentation/callback.
Final [test log](artifacts/components_02/focused_final.log), [verification](artifacts/components_02/verification.json).
