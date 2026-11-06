# MH17 — Notifications

Ngày21/10/2026. Owner Bảo. **MH17-03A2 — ISOLATED FEED COORDINATOR IMPLEMENTED, READY FOR REVIEW**.
MH17-01/02/03A1 đã được user duyệt; MH17 UI/production integration chưa được duyệt. STOP trước page integration.

## Phạm vi và trạng thái

MH17 là hộp thông báo trong ứng dụng dùng chung Customer/Manager/Shipper, mỗi người chỉ đọc inbox của mình.
Client đã có domain/DTO/contracts, Riverpod reads/interactions, page, tile, badge và focused tests.
Chưa có repository adapter production, resolver production, Auth wiring hoặc business route trong central router.
Event producers và target modules vẫn là dependency; không có evidence backend end-to-end hoặc Android MH17 mới.
OP-N01–03 production repository và own Orders producers thuộc Bảo, còn thiếu integration/runtime evidence.
Auth, central router và destination modules là external/shared dependencies, không chuyển trách nhiệm owned adapter ra ngoài.
Task01 chỉ thêm tài liệu/evidence/utilities trong thư mục này và closeout hai tài liệu MH09.
Task02 thêm ba isolated Stateless widgets và39 tests; chưa import/integrate vào NotificationsPage.
[COMPONENT_APIS](COMPONENT_APIS.md) ghi exact constructors, state boundaries và verification02.
Task03A1 chỉ tách page tests, thêm14 characterization và method→owner map; production vẫn nguyên bytes.
[REFACTOR_03A1](REFACTOR_03A1.md) ghi từng original test/assertion, split, findings và proposed bounded03A2.
[COORDINATOR_03A2](COORDINATOR_03A2.md): isolated accumulator152LOC,26new unit tests; fresh focused146 +selected7 PASS.
Page/providers/interaction/models/02widgets/Preview và existing tests không đổi; page922LOC vẫn là debt.

MH09: user xác nhận **"MH09 UI/Preview accepted at the current implemented scope."**
Backend mutations chưa tích hợp; full TalkBack audio/focus và một số native manual checks còn chưa xác minh.
Các giới hạn backend/Auth/router MH09 giữ external ownership như user đã chốt.
MH07/MH08/MH09 UI source được bảo vệ bằng working-file SHA-256.

## Đọc theo thứ tự

1. [HANDOFF](HANDOFF.md): trạng thái, evidence và điểm tiếp tục cho session mới.
2. [SOURCE_AUDIT](SOURCE_AUDIT.md): actual paths, API, LOC, coverage, findings.
3. [BEHAVIOR_CONTRACT](BEHAVIOR_CONTRACT.md): actual/target/external authority.
4. [UI_SPEC](UI_SPEC.md) và [MANUAL_REVIEW](MANUAL_REVIEW.md): HTML, giới hạn visual và checklist.
5. [ARCHITECTURE_PLAN](ARCHITECTURE_PLAN.md): component boundaries và các task có STOP gate.
6. [ENGINEERING_RULES](ENGINEERING_RULES.md) và [TEST_PLAN](TEST_PLAN.md): ràng buộc và kiểm chứng.

## Source map tối thiểu

| Vùng | Actual path, tương đối project root | Vai trò |
| --- | --- | --- |
| View | `lib/features/notifications/presentation/pages/notifications_page.dart` | Feed, pagination, session guards, callback, modal |
| Widgets | `lib/features/notifications/presentation/widgets/` | `NotificationTile`, `UnreadBadge` |
| Isolated02 | `lib/features/notifications/presentation/widgets/mh17/` | Filters60/Feed121/ContextSheet51 LOC, chưa page integration |
| State | `lib/features/notifications/presentation/view_models/` | Foundation reads, interaction VM, ack invalidation |
| Domain | `lib/features/notifications/domain/` | Item/page/query/typed target, repository và resolver contracts |
| Data | `lib/features/notifications/data/models/notification_dto.dart` | Nine-field mapper và read signal; adapters chưa có |
| Tests | `test/features/notifications/` |16 test files:120 PASS; original19 page cases bảo toàn qua3files|
| Preview reference | `tool/ui_preview/preview_app.dart` | Fake inbox, không có resolver/onNavigate |
| Entry đang dùng | `tool/ui_preview/main.dart` | Chạy `Mh08PreviewApp`, không phải entry MH17 |

Không có `NotificationCenter`, `NotificationsViewModel` hay pagination controller riêng trong source hiện tại.
Không tạo lại các tên/path proposed trong rev1.2 chỉ vì specification cũ ghi “Missing”.

## Nguồn nghiệp vụ và dependencies

- [Đặc tả rev1.2 §9, §12.2–12.5, §17](../../technical_specification_mh07_mh08_mh09_mh17.md).
- [Data/API §2.5, OP-N01–05, §11](../../technical_specification_mh07_mh08_mh09_mh17_data_api.md).
- [Cross-module CIN-01/03/05/06/09](../../Cross_Module_Integration_Contracts.md).
- [Acceptance oracle T17](../../technical_specification_mh07_mh08_mh09_mh17_tests.md).
- Shared session/cache/read lifecycle, shared theme/formatters/async/access/foreground widgets phải reuse.
- Auth owner cung cấp trusted scope; destination owners cung cấp authorized reads; router owner chọn route thực.
- Push delivery infrastructure ngoài phạm vi; không biến event production thành trách nhiệm UI.

Spec rev1.2 có các mô tả historical “chưa có model/UI/tests”; audit này cập nhật tình trạng client bằng source hiện tại.
Không sửa shared specification/contracts trong task01, không suy rằng các external contracts đã được ký/tích hợp.

## Verification và evidence

- [Working baseline](artifacts/audit_01/workspace_baseline.json): 3.176 existing files, không dùng HEAD.
- [Inventory đầy đủ](artifacts/audit_01/source_inventory.json): imports, public types, physical LOC, SHA-256.
- [Focused tests](artifacts/audit_01/focused_verified.log): 67 PASS; [analyzer](artifacts/audit_01/analyze.log): no issues.
- [HTML primary](artifacts/html_reference/primary_390x844.png), [full page](artifacts/html_reference/full_page_390.png).
- [Render manifest](artifacts/html_reference/render_manifest.json), [verification](artifacts/audit_01/verification.json).
- Full suite, SQL/backend integration, Android/TalkBack MH17: **NOT RUN** trong MH17-01.
- Task02 [baseline67](artifacts/components_02/baseline_tests.log), [final106](artifacts/components_02/focused_final.log),
  [selected regressions7](artifacts/components_02/protected_regressions.log), [analyze](artifacts/components_02/analyze_verified.log).
- [Verification02](artifacts/components_02/verification.json): format/LOC/links/diff/working SHA; no protected code changes.
- Task02 full suite/Android/production modal session/backend **NOT RUN**; standalone semantics không phải TalkBack audio PASS.
- Task03A1: fresh [baseline106](artifacts/refactor_03a1/baseline_tests.log), [focused120](artifacts/refactor_03a1/focused_verified.log),
  [individual files](artifacts/refactor_03a1/individual_results_final.json), [selected7](artifacts/refactor_03a1/regressions_verified.log).
- [Analyze](artifacts/refactor_03a1/analyze_verified.log), [preservation](artifacts/refactor_03a1/test_preservation_report.json),
  [verification03A1](artifacts/refactor_03a1/verification.json). Không full suite/Android/backend/capture rerun trong03A1.

## Roadmap

MH17-02 components được duyệt;03A1 test extraction/characterization hoàn tất, chưa integrate page.
Đề nghị03A2 isolated pure feed coordinator + tests, page vẫn read-only; composition task sau phải chứng minh page≤300.
03B fixture/navigation/session Preview theo architecture đang có.
04A visual/responsive evidence; 04B chỉ sửa defect đã chứng minh và nghiệm thu Android.
Chi tiết files/budget/dependencies/verification/STOP trong [ARCHITECTURE_PLAN](ARCHITECTURE_PLAN.md).
