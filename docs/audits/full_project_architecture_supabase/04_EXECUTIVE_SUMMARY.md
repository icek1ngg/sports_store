# Tóm tắt audit kiến trúc và Supabase

Ngày: 26/10/2026, Asia/Saigon. **Audit hoàn tất, kế hoạch chờ review. Không refactor hoặc tích hợp Supabase trong lượt này.**

## A. Architecture overview

Current working source có nền Flutter + Riverpod + go_router + Supabase, feature-first MVVM phù hợp. Không có business API call trực tiếp trong Screen build; không phát hiện provider/cache authority trùng do compatibility exports. MH17 Screen/Widgets/Providers, NotificationPageActions và session/privacy/lifecycle protections được giữ.

Không có lý do viết lại dự án. Cơ hội refactor chính là đưa feed/query acceptance thuần của MH07 ra coordinator để dễ test và tránh lệch MH08; đây là cải thiện tùy chọn, không phải lỗi UI đã xác nhận.

## B. Screen compliance matrix

Phát hiện **4 màn nghiệp vụ**: MH07/MH08/MH09/MH17. Thêm **2 bề mặt kỹ thuật** là root placeholder và startup failure; không gán mã MH mới cho chúng. Modal chi tiết khách và Preview wrappers không tăng screen count.

| Màn | Cấu trúc | Khuyến nghị | Production routing/data |
|---|---|---|---|
| MH07 My Orders | Phù hợp nền tảng; query/feed state còn inline | SMALL REFACTOR tùy chọn | Chưa registered; Preview fixture |
| MH08 Manager Orders | Tách widgets/query/feed owners rõ | KEEP | Chưa registered; Preview fixture |
| MH09 Manager Details | Tách sections; route/dialog guards rõ | KEEP | Chưa registered; Preview fixture |
| MH17 Notifications | Screen/Widgets/Providers/Actions đã có | KEEP cấu trúc; F03/F05/F07 pending | Chưa registered; Preview fixture |

Theo phân loại khuyến nghị: **3 KEEP, 1 SMALL REFACTOR tùy chọn, 0 STRUCTURAL/MAJOR rewrite**. UI của cả bốn màn đã được user duyệt; không redesign. **16 màn còn lại chỉ có trong specification**, chưa có Flutter Screen/Page implementation.

ThemeData đã có shared StorefrontTheme cho bốn màn; AppTheme/OrderNotificationTheme là facade/compatibility. Một số constants/styles của Orders còn local, global app shell vẫn dùng defaults. Có thể gom alias tương đương sau này, không cần theme system thứ hai.

## C. Supabase connection status

**VERIFIED CONNECTED chỉ cho endpoint probe:** Auth settings HTTP 200 và PostgREST probe limit=0 HTTP 404/PGRST205 đúng kỳ vọng. Có cấu hình/client dùng chung, đã đối chiếu installed supabase_flutter 2.18.0.

**Business integration chưa nối:** featureSessionScopeProvider unresolved; OrderRepository/NotificationRepository/NotificationTargetResolver production bindings vẫn null. Không feature Auth sign-in/profile bridge, business CRUD/RPC adapter, Storage client hoặc Realtime subscription.

- **0/4 màn nghiệp vụ** có production data path hoàn chỉnh; **4/4 có fixture path trong ít nhất một Preview**.
- Không có bằng chứng Spring Boot/backend REST business source trong workspace. Current infrastructure hướng Flutter → Supabase trực tiếp; Preview hướng Flutter → Mock Repository.
- Có ba migrations, final schema 18 tables, RLS/grants/private Storage policies trong source. **Deployment/RLS effectiveness/business rows hiện tại NOT VERIFIED.**
- Lịch sử tài liệu 06/10/2026 không thay live metadata/tests mới. Probe không chứng minh login, SELECT orders, Storage, RPC hoặc end-to-end.

## D. Critical findings

| ID | Severity | Tác động |
|---|---|---|
| ARC-01 | Blocker | Router chính chỉ có “/” placeholder; bốn màn chưa truy cập từ production main |
| INT-01/02 | Blocker | Thiếu Auth/session bridge, production repositories và target resolver |
| INT-03 | Blocker | Orders DTO aggregate/proposed RPC chưa có SQL/runtime producer đáp ứng shape/quyền |
| INT-04 | Blocker | Dialog chỉ validate/unavailable; chưa command persistence/transport, transactional stock/money/state, auto-confirm job |
| INT-05 | Major | Delivery/COD/Returns/Chat và notification producer contracts/implementations còn thiếu |
| SEC-01 | Major, NEEDS DECISION | RLS shipper dựa assignee, chưa thể hiện rõ thu hồi thông tin task lịch sử/terminal; cần chốt lifecycle và kiểm allowed/denied |
| MH17-F03/F05 | Major, pending | Bằng chứng kiểm thử/nghiệm thu role × target matrix chưa đầy đủ; rapid taps đã có characterization nhiều resolver/navigation callbacks, chưa chứng minh production route stack |
| MH17-F07 | Minor, pending | Preview inbox còn fixture event/recipient/subject chưa canonical; không làm mất UI acceptance |
| ARC-02/THM-01/SEC-02 | Minor | Cơ hội gom MH07 feed/theme aliases; customer variant SELECT gồm stock internals, cần chốt fields tối thiểu |

Không tuyên SEC-01/02 là live data breach: predicate/grants có source evidence, cloud deployment và necessity/history policy chưa được kiểm chứng. Không coi thiếu 16 màn là lỗi kiến trúc của bốn màn đã có.

## E. Refactor roadmap

1. Test-only role/target matrix và bảo vệ baseline.
2. Canonical Preview fixtures cho F07 khi owner chốt semantics.
3. MH07 pure query/feed coordinator và theme aliases nếu user chọn ưu tiên; giữ giao diện/imports/constructors.
4. F05 chỉ sửa sau khi duyệt single-flight/route-lifetime/pending-read interaction policy; giữ read/open độc lập và privacy guards.

MH08/MH09/MH17 không cần refactor lại chỉ để đổi folder/name. Không thêm provider theo hình thức.

## F. Integration roadmap

1. Xác nhận environment, deployed schema và accepted contracts; xử lý SEC-01/02 theo owner.
2. Auth/profile/server-role → SessionScope generation.
3. Notifications raw page/count/read adapter và Orders authorized aggregate adapter; strict errors/DTOs.
4. Central protected routes + business ID callbacks; giữ target chưa implement ở trạng thái unavailable.
5. Command persistence/idempotency + ordering/reservation server transaction → delivery → COD.
6. Cancellation/failure/inspection/returns/refund + notification producers; Storage/Chat/Realtime theo feature readiness.
7. Staging allowed/denied, concurrency/replay, runtime reads/writes và production release evidence trước nghiệm thu end-to-end.

Backend writes/migrations/SQL fixtures hoặc production-impact tests không được thực hiện từ kế hoạch audit này.

## G. Quyết định cần user/team xác nhận

- Ưu tiên integration trước hay làm MH07/theme cleanup tùy chọn.
- Policy F05 và matrix F03; canonical producer fixtures F07.
- Auth/router/protected pending storage contract; environment/backend ngoài workspace nếu có.
- Current/historical shipper access và customer stock fields.
- External CIN-02–09, Hà Nội/store coordinates, custody/COD/returns cutoff/producer contract còn thiếu; full business report/NT01–NT30 để trace acceptance.

## Verification và bảo toàn workspace

- **VERIFIED:** analyzer PASS, exit 0; **763 safe existing tests PASS**, exit 0. Không phải toàn suite hoặc rerun nguyên checkpoint MH17 441.
- **VERIFIED:** safe GET endpoint probe PASS; không đọc business rows, không tạo tài khoản/session.
- **VERIFIED:** 480 protected files được băm trước/sau, **0 modified / 0 missing / 0 added** trong source/test/tool/config/Supabase/platform/assets/dependency/instructions scope.
- Không sửa production source/config/test; chỉ tạo tài liệu/logs trong thư mục audit. Không commit/push/reset/clean/checkout/stash/merge; không database mutation/migration.
- Không chạy visual evidence writers, không ghi đè ảnh cũ, không build/install Android hoặc kiểm tra TalkBack mới.
- Model reviewer thực dùng: GPT-5.6 Sol/Medium. Worker GPT-5.6 Luna/Max không khả dụng; coordinator khảo sát trực tiếp.

Evidence: [analyzer](verification/flutter_analyze_verified.log), [763 tests](verification/focused_tests_verified.log), [GET probe](verification/supabase_readonly_probe_verified.log), [source guard](verification/source_guard.json), [baseline SHA256](verification/protected_baseline_sha256.json).

Chi tiết: [screen audit](01_SCREEN_ARCHITECTURE_AUDIT.md), [Supabase audit](02_SUPABASE_INTEGRATION_AUDIT.md), [task-by-task plan](03_REFACTOR_PLAN.md).

**PRM393 — FULL ARCHITECTURE & SUPABASE AUDIT COMPLETE — PLAN READY FOR REVIEW**
