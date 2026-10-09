# Báo cáo trạng thái Phase 2 — Presentation

Ngày 09/10/2026. Baseline Phase 1: commit `8e982ac`, 92 tests PASS trước khi bắt đầu Phase 2.

## Quyết định

**PHASE 2 INCOMPLETE.** Presentation foundation và phần lớn UI của MH07, MH08, MH09, MH17 đã được triển khai, nhưng chưa đạt quality gate cuối vì các kiểm thử Notifications còn lỗi trong lần chạy gần nhất. Các file Phase 2 hiện vẫn là untracked và chưa được commit.

## Đã triển khai

- MH07: trang đơn hàng khách hàng, tìm kiếm debounce, lọc 10 trạng thái, đếm từ snapshot server, cursor pagination, stale/error/loading/empty, detail bottom sheet, timeline, item/recipient/payment sections, dialog hủy và điểm vào trả hàng.
- MH08: trang danh sách quản lý, tìm kiếm/lọc, counters từ `statusCounts`, order cards, cảnh báo giao thất bại, dialog xác nhận/từ chối, validation lý do và callback an toàn tới MH09.
- MH09: thông tin người mua/người nhận, item snapshot, thanh toán/COD, timeline, delivery/COD/returns độc lập, action footer, dialogs và các action phụ thuộc Delivery/COD/Returns ở trạng thái unavailable.
- MH17: inbox tất cả/chưa đọc, unread badge theo count server, cursor pagination, stale/error/loading/empty, mark-read có canonical acknowledgement, typed target resolver, navigation độc lập với read acknowledgement, notification-only context và session isolation.
- Shared presentation: `FeatureAccessGate`, `ForegroundRefresh`, safe Vietnamese failure messages, action dialog có recheck capability và tự khóa khi snapshot bị invalidated.
- Tests: widget/state tests cho loading, empty, error, stale, session expiry, account switch, pagination, search/filter, action validation, typed navigation, notification read state và responsive text scaling.

## Foundation được reuse

Riverpod providers, `SessionScope`, `EpochCache`, `SnapshotReadViewModel`, repository interfaces, retry policy, `AsyncContent`, AppTheme và domain/DTO Phase 1. Không thêm Supabase adapter, RPC, migration, Auth, router hoặc dependency mới.

## Kiểm thử đã chạy

- `flutter analyze --no-pub`: PASS tại lần chạy gần nhất trước các thay đổi test cuối.
- Widget tests MH09 và action dialog: PASS, gồm 15 tests trong lần chạy focused gần nhất.
- Session-isolation tests MH17 bổ sung: PASS, 5 tests.
- `git diff --check`: PASS; 22 file Phase 2 mới không có whitespace errors.
- Full suite gần nhất: 132 PASS, 5 FAIL. Các lỗi thuộc Notifications page/VM tests; Phase 1 tests vẫn giữ PASS trong run đó.
- Focused Notifications run gần nhất: 21 PASS, 4 FAIL, liên quan pending timers trong fixture/error tests và một expectation unread badge `0` không phù hợp với badge semantics.

## Chưa đạt và blockers

- BLOCKER: phải sửa và chạy lại toàn bộ Notifications tests, sau đó chạy lại full suite.
- MAJOR: Phase 2 files chưa được add/commit vào Git.
- EXTERNAL DEPENDENCY: Auth/session provider thật, central routes, Supabase read/mutation adapters, Orders RPC/receipt storage, Notification producers và target routes của Delivery/COD/Returns/Chat chưa tồn tại.
- NOT VERIFIED: pixel comparison với mockup vì các ảnh MH07/MH08/MH09 không có trong repository; MH17 chỉ có proposed design.

## Không triển khai trong Phase 2

Backend/RPC/migrations, Auth, router ownership, production Supabase adapters, Delivery/COD/Returns/Chat workflows, push notifications và mutation success giả.

## Next actions

1. Hoàn tất 4 Notifications tests còn lỗi và thêm kiểm tra poll head-page/pagination nhiều trang.
2. Chạy `dart format`, `flutter analyze --no-pub`, `flutter test --no-pub`, `git diff --check` lại trên snapshot cuối.
3. Review `git status`, add các file Phase 2 vào version control và tạo commit riêng sau khi user yêu cầu lưu trạng thái.
4. Chỉ sau đó mới đánh giá lại `PHASE 2 COMPLETE`.
