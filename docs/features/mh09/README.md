# MH09 — Manager Order Details

**MH09-01/02A/02B/03A1/03A2 — USER APPROVED**.
**MH09-03B — PREVIEW INTEGRATED, READY FOR VISUAL AUDIT**. **MH09 UI — NOT YET APPROVED**.
Current Preview/scenarios/evidence: [PREVIEW_03B](PREVIEW_03B.md); bàn giao [HANDOFF](HANDOFF.md).

## Phạm vi và ownership

Owner Orders: Bảo. Flutter/Dart + Riverpod, feature-first MVVM theo AGENTS.
MH07 và MH08 đã được người dùng duyệt; bảo vệ đúng working files, kể cả dirty/untracked.
03A2 wire7 components và MH09-local active/ticket owner; không mutations/backend/shared changes.
Approved production/02A/02B/shared/providers/models/DTO/contracts/router/Auth/SQL giữ nguyên hash;03B chỉ mở rộng debug Preview.
Không coi UI MH09 hoặc workflow backend hoàn tất từ kết quả audit.

## Baseline audit01 — lịch sử, không phải rerun02A

- Production widget: `lib/features/orders/presentation/pages/manager_order_details_page.dart`, 578 LOC.
- Provider: `orderDetailsFoundationProvider(orderId)` → `OrderDetailsFoundationViewModel` → `OrderRepository.getOrderDetails`.
- Provider repository mặc định null; session mặc định unresolved. Router production mới có `/`.
- Route `/manager/orders/:orderId` là contract target, chưa có trong router production.
- Preview đang dùng `tool/ui_preview/main.dart` → `Mh08PreviewApp` → stable ProviderScope → Navigator.
- MH08 mở MH09 bằng exact UUID; pop giữ query và refresh canonical list/count.
- 39 focused tests hiện có PASS; không rerun full suite/analyze hoặc Android trong task này.
- HTML Chromium thật 390×844/DPR1, fonts/ảnh đầy đủ, scrollHeight1475, không đổi HTML nguồn.
- Snapshot trước task: branch `feature/orders-notifications-phase2`, 1556 dirty entries với untracked-files=all.
- SHA-256 baseline2237 files, gồm scratch đã có; kết quả cuối ở [verification](artifacts/source_verification.json).

## Bản đồ tài liệu

| Tài liệu | Dùng khi |
| --- | --- |
| [SOURCE_AUDIT](SOURCE_AUDIT.md) | File/API/LOC/dependency/risk thực tế |
| [UI_SPEC](UI_SPEC.md) | Geometry, tokens và khác biệt HTML/Flutter |
| [BEHAVIOR_CONTRACT](BEHAVIOR_CONTRACT.md) | Canonical read, 4 lifecycle, actions/privacy |
| [ARCHITECTURE_PLAN](ARCHITECTURE_PLAN.md) | Component APIs, ownership, estimated LOC, task acceptance |
| [ENGINEERING_RULES](ENGINEERING_RULES.md) | Scope, LOC, state/lifecycle, Git/DoD |
| [TEST_PLAN](TEST_PLAN.md) | Coverage hiện có và test cần bổ sung |
| [MANUAL_REVIEW](MANUAL_REVIEW.md) | Ảnh thật/lịch sử, Android checklist, approval |
| [HANDOFF](HANDOFF.md) | Checkpoint ngắn cho phiên mới |
| [REFACTOR_03A1](REFACTOR_03A1.md) | Baseline, extraction, bảo toàn test và dialog disposal reproducer |
| [INTEGRATION_03A2](INTEGRATION_03A2.md) | Wiring/lifecycle, red→green và blocker2 protected Preview test finders |

## Roadmap — mỗi task đều dừng để review

| Task | Deliverable / allowed changes | Gate |
| --- | --- | --- |
| MH09-01 approved | Docs, source/LOC audit, HTML screenshots, plan, handoff | Audit được người dùng duyệt |
| MH09-02A approved | Header/Identity/Recipient/Items + tests cô lập; chưa wire page | User approved; giữ readonly |
| MH09-02B approved | Payment/Footer/OperationalActions + tests cô lập |107 focused PASS lịch sử; giữ readonly |
| MH09-03A1 hoàn tất | Tách layout/footer/contact;9 test gốc giữ nguyên +6 regression mới | Page209, test entry62;122 focused/368 full PASS; STOP |
| MH09-03A2 BLOCKED |7 components integrated +active owner;138 focused PASS|full391 PASS/2 FAIL do protected Preview finders cũ; cần scope follow-up |
| MH09-03B | Extend stable Preview, fixture/scenario MH09 khi cần | Exact UUID, repeated pop, session/dialog safety; STOP |
| MH09-04A | Fresh Flutter render, compare same viewport, responsive matrix | 320/360/390/412/landscape ×1/1.5/2; STOP |
| MH09-04B | Chỉ sửa defect đã chứng minh, Android/full regression | Evidence + user approval; STOP |

03A2 dừng ở gateE; không tự sửa2 protected Preview tests hoặc bắt đầu03B.
Không triển khai mutation/backend trong roadmap visual này; đó là dependency riêng cần task được giao.
Không chuyển MH17 trước khi MH09 được người dùng duyệt.

## Minimal context cho phiên mới

1. Root AGENTS → HANDOFF → ENGINEERING_RULES → README.
2. Task02: UI_SPEC + ARCHITECTURE_PLAN + BEHAVIOR_CONTRACT, source model/API đúng component.
3. Tiếp03A2: INTEGRATION_03A2 blocker +page43/content275/body82/layout45; không cần load3 unused legacy files.
4. Task03B: stable Preview surface121/app44 + navigation tests; không dùng harness legacy làm entrypoint mới.
5. Chỉ đọc spec §8/§12.2–12.5, Data/API OP-O03/O04/O05/O07 và CIN cần dùng.
6. Preferred20–50k context, aim<60k; gần70k thì checkpoint/HANDOFF và dừng.

## Nguồn authoritative

- [Technical Specification revision1.2](../../technical_specification_mh07_mh08_mh09_mh17.md): §8, §12, §17.
- [Data/API revision1.2](../../technical_specification_mh07_mh08_mh09_mh17_data_api.md): §3–4, OP-O03–O08.
- [Cross-module contracts](../../Cross_Module_Integration_Contracts.md): CIN01/03/04/05/06/08/09-CHAT chưa accepted/implemented.
- [Technical test catalog](../../technical_specification_mh07_mh08_mh09_mh17_tests.md): §4 T09, §6 TX; test IDs là kế hoạch, không tự thành PASS.
- [HTML nguyên bản](../../ui_mocks/MH09_Manager_Order_Details.html): visual source, không phải authority cho policy/mutation.
- [MH08 HANDOFF](../mh08/HANDOFF.md), [ANDROID_ACCEPTANCE](../mh08/ANDROID_ACCEPTANCE.md): process/evidence lịch sử, không sửa/copy wholesale.

## Lệnh audit có thể chạy lại

Chạy từ project root; Node/Chrome/Playwright phải có sẵn. Không cài package hoặc đổi lockfile.
`PLAYWRIGHT_MODULE` trỏ package Playwright có sẵn; `CHROME_PATH` tùy chọn executable Chromium.
`node tool/ui_preview/render_mh09_reference.cjs` tạo lại artifacts HTML, cần network cho CDN/fonts/ảnh.
`node --check tool/ui_preview/render_mh09_reference.cjs` và `node --check tool/ui_preview/audit_mh09.cjs`.
`node tool/ui_preview/audit_mh09.cjs` kiểm tra source baseline/links/LOC/Git và screenshot hashes.
Chỉ dùng baseline01 để xác minh task01; task triển khai sau phải capture baseline mới trước khi sửa.

## Checkpoint02A — lịch sử đã duyệt

Baseline mới: [02a/baseline.json](artifacts/02a/baseline.json),2257 working files,1576 dirty entries;
hai thư mục component/test MH09 trước task chưa tồn tại. Không áp baseline01 cho files được phép tạo ở02A.
CheckpointA:21 existing page/widgets/dialog tests PASS; CheckpointB:20 Header/Identity tests PASS.
CheckpointC:22 Recipient/Items tests PASS; CheckpointD:63 tests PASS =42 mới +21 regression hiện có.
Flutter analyze --no-pub PASS; format9files/0changed, diff/LOC/hash/links PASS; full suite/Android NOT RUN.
Production LOC: Header80, Identity65, Recipient177, Items131 (tất cả≤180); không integrate page/Preview.
Public APIs/integration requirements ở ARCHITECTURE_PLAN + HANDOFF; no providers/navigation inside components.
Evidence task02A riêng [02a/verification.json](artifacts/02a/verification.json).
`node docs/features/mh09/artifacts/02a/verify.cjs` kiểm tra baseline02A,allowed docs/LOC/links/dependencies/Git.
Utility và artifacts01 nằm trong `tool/ui_preview/` giữ nguyên; không chạy renderer01 để ghi đè evidence cũ.
02A user approved; không thay component/tests/evidence02A trong task02B.

## Checkpoint02B — lịch sử đã duyệt

Baseline mới [02b/baseline.json](artifacts/02b/baseline.json):2270 existing files/1589 dirty entries, gồm toàn bộ02A.
A63 existing PASS; Payment B12 PASS; Footer C17 PASS; Operational D15 PASS.
Final **107 PASS =44 new02B +42 approved02A +21 existing page/widgets/dialog**; full suite/Android NOT RUN.
New components LOC Payment133/Footer179/Operational100≤180;4 new test/support files≤400/helper≤150.
Financial rows đọc nguyên fields +shared formatter; null COD unknown. Footer cần per-operation capability AND fresh/scope/not-busy/callback.
Ops false capability hidden; true capability vẫn unavailable, không mutation callback. Full lifecycle COD giữ shared widget riêng.
APIs/verification/integration requirements ở [HANDOFF](HANDOFF.md), [ARCHITECTURE_PLAN](ARCHITECTURE_PLAN.md), [TEST_PLAN](TEST_PLAN.md).
`node docs/features/mh09/artifacts/02b/verify.cjs` kiểm tra hash/LOC/links/test evidence/analyze/format/diff theo baseline02B.
Checkpoint02B kết thúc trước03A1; không dùng baseline02B để cấm các thay đổi page/test được giao ở03A1.

## Checkpoint03A1 — lịch sử đã duyệt

Baseline mới2281 files/1600 dirty entries; branch giữ nguyên `feature/orders-notifications-phase2`.
Page578→209; entry test440→62; body129/contact81/footer176, không thay layout/labels hoặc provider identity.
Test gốc9/49 assertions bảo toàn tokens sau đổi tên helper; thêm6 cases/32 assertions. API6 parameters giữ nguyên.
Dialog root còn sau source unmount đã tái hiện ref crash; guard page `context.mounted` chặn read sau unmount.
15 page tests +86 component tests +12 shared widget/dialog +9 Preview =122 focused PASS; full suite368 PASS.
Analyzer/format/diff/LOC/links PASS;2273 protected working files nguyên SHA-256, gồm MH07/MH08/02A/02B.
Evidence [verification03A1](artifacts/03a1/verification.json), [test integrity](artifacts/03a1/test_preservation.json).
Independent review không P1/P2; inactive/deactivation cùng frame vẫn cần03A2 xem xét, không claim guard giải quyết hết.
Chưa render fresh full MH09/Android, chưa wire7 visual widgets, chưa integration/backend. **STOP sau03A1**.

## Checkpoint03A2 — lịch sử trước finder fix03A2F

Baseline2300 files/1620 dirty entries, branch giữ nguyên. Page209→43; content275/body82/layout45, legacy3files untouched/inactive.
Same-frame inactive red được sửa active/generation trước ref; submittedScope/sourceCache identity/current freshness/capability giữ authority.
4 external IDs đọc current aggregate và fail closed sau scope/owner/null-callback invalidation; refresh không duplicate in-flight read.
15 existing cases/81 assertions tương đương sau finder migrations;25 new runtime cases,138 focused PASS.
Full mới **391 PASS/2 FAIL**:2 protected Preview tests phụ thuộc nhãn legacy và tester.pageBack(), chưa all-green.
New navigation contract qua existing Preview PASS với header thật; exactUUID/query/search/status/container/head refresh giữ đúng.
Analyzer/format/LOC/diff/links PASS;2287 protected files nguyên SHA-256, gồm MH07/MH08/7components/shared/tool/evidence cũ.
Đề xuất3 finder edits trong2 test files tại INTEGRATION_03A2; chưa áp dụng vì scope protected. STOP, chưa03B.
Android/same-viewport MH09/backend chưa kiểm chứng; chưa đủ gate để báo READY FOR PREVIEW INTEGRATION.

## Checkpoint03B — hiện tại

03A2F đã sửa đúng3 finders và full393 PASS trước03B; các Preview tests đó không sửa trong03B.
Giữ main→Mh08PreviewApp→stable ProviderScope→Surface→Navigator, MH07 default; thêm selector DEMO trên routeMH09.
19 scenario values: canonical/normal/large, null projections riêng, async/session và per-operation capabilities.
Selected summary/detail cùng fixture world; Order/UUID/money giữ nguyên;40items phân bổ đúng subtotal;Back reset canonical.
Không tự restore manager sau session revoke; explicit DEMO recovery tạo generation mới. Không mutation/backend success.
28 test cases mới; focused181 PASS; full421 PASS; analyze/format/diff/LOC/links PASS;2311 protected working files nguyên hash.
Android API35 build/install/launch PASS; Header/framework/ADB route và modal Back đã kiểm tra riêng.
Ảnh runtime/provenance/giới hạn IME/gesture ở [PREVIEW_03B](PREVIEW_03B.md); chưa same-viewport visual acceptance.
STOP03B. Chỉ đề xuất04A so HTML390×844 và responsive matrix; không tự bắt đầu hoặc đánh dấu MH09 approved.
