# MH17 — Architecture và bounded follow-up tasks

Current decision22/10/2026: [R baseline](REVISED_ARCHITECTURE_03A3R.md) accepted subject to runtime/tests; R2 canceled.
Sole LOC exception ReadCoordinator≤280; Page≤300, all other gates unchanged. [Checkpoint01](IMPLEMENTATION_CHECKPOINT_01.md)
chỉ thêm pure snapshot predicates và tests, không integrate page/coordinator/widgets hoặc F02. Historical plans dưới đây giữ làm context.

MH17-01/02/03A1/03A2 đã được user duyệt;03A3-P design review kết luận NOT YET FEASIBLE. Page integration/03B/03C/04 chưa thực hiện.
[PAGE_COMPOSITION_PLAN_03A3P](PAGE_COMPOSITION_PLAN_03A3P.md): inventory922/79regions; estimated page679/owner237, alternative512/448.
Giữ486measured original lines tại page đã vượt300; cần revised owner/budget và head/modal binding review, không source implementation.
Mục tiêu nhỏ nhất: giữ client contracts/state authority đang hoạt động; tách responsibilities đang dồn trong page922 LOC.
Không tạo lại NotificationTile/UnreadBadge, không dựng framework/router/cache/repository thứ hai.

## Boundaries hiện có và proposed

| Responsibility | Hiện tại | Đề xuất nhỏ nhất / điều kiện |
| --- | --- | --- |
| Canonical page/count | foundation providers + SnapshotReadViewModel/EpochCache | giữ nguyên authority và signatures |
| Read ack/target checks | interaction VM + ack hook | giữ behavior; độc lập review LOC/validation ở03C |
| Tile + badge | existing public components | reuse; tile185 LOC chỉ tách icon/type nếu giúp responsibility |
| Filter controls | page private `_FilterBar` | extract callback-only, giữ all/unread/refresh |
| Feed rendering | page AsyncContent/ListView | extract data/callback-only body; không read repository trong widget |
| Load-more | page private `_LoadMoreButton` | compose trong feed; chỉ tách riêng nếu feed budget cần |
| Notification context | page `_showNotificationContext` | presentation sheet, scope/access predicate vẫn do owner cung cấp |
| Local paging accumulation | page fields/merge/reset | page-specific feed coordinator, không canonical cache mới |
| Snapshot provenance/actions | page scope/cache checks/listeners | page-specific ViewModel chỉ compose existing authority, không đổi provider behavior |
| Header | AppBar + badge | giữ inline nếu đủ đơn giản; không bắt buộc header file |

Data flow giữ: View → page-specific coordination → existing foundation/interaction providers → repository contract.
OP-N01–03 adapter/own Orders producers do Bảo sở hữu; Auth/router/destination owners là external/shared dependencies.
Các integration tasks tách khỏi visual work, không được giả lập thành công production.
State feed chỉ giữ presentation accumulation của snapshots đã được current scope/cache chấp nhận.
Không move guards vào tile; callback phải recheck mounted/current scope/current cache/freshness tại thời điểm gọi.

## MH17-02 — isolated presentation IMPLEMENTED, READY FOR REVIEW

Actual classes: `Mh17NotificationFilters`60LOC, `Mh17NotificationFeed`121, `Mh17NotificationContextSheet`51.
Exact constructors/ownership: [COMPONENT_APIS](COMPONENT_APIS.md); page/provider/tile/badge/Preview không đổi.
New tests: filters9, feed15, feed interaction5, context10; original67 +new39 =106 PASS; selected regressions7 PASS.
Feed tests tách render/pagination với callback/pending/refresh/removal để mỗi file≤400; fixtures/host helper54LOC.
Task02 STOP trước page integration; phần files/budgets dưới đây giữ contract của task đã thực hiện.

- Files mới dự kiến dưới `lib/features/notifications/presentation/widgets/mh17/`:
  `notification_filters.dart`≤100, `notification_feed.dart`≤180, `notification_context_sheet.dart`≤150 physical LOC.
- Không bắt buộc tạo header/load-more file riêng; compose load-more trong feed nếu≤180.
- Tests mới dưới `test/features/notifications/presentation/widgets/mh17/`:
  `notification_filters_test.dart`, `notification_feed_test.dart`, `notification_context_sheet_test.dart`, mỗi file≤400.
- Dependencies đã dùng: user giao02, contracts/UI_SPEC, shared theme/AsyncContent/current models.
- API: data + callbacks + explicit pending/disabled/current-access inputs; không Riverpod repository access từ widgets.
- Verify: format new Dart, analyze, isolated widget callbacks/empty/error/loading/pagination/320dp-text2/semantics +67 existing tests.
- STOP: components độc lập reviewable, không page integration, không Preview changes, không behavior/provider/model/router edits.
- Preserve existing tile/badge; không sửa tile chỉ để bắt chước HTML radius hoặc đổi server text.

## MH17-03A — phased extraction, chưa production integration

03A1 completed: original page tests721→222/221/124;18declarations/19cases/94assertions preserved,14new characterization.
[REFACTOR_03A1](REFACTOR_03A1.md) là inventory method→owner A–O, actual gesture/privacy findings và bounded03A2 scope.
03A2 có isolated synchronous stateful feed coordinator152LOC +unit test379LOC/26cases; production page vẫn read-only.
[COORDINATOR_03A2](COORDINATOR_03A2.md) ghi exact API/T01–14, raw F02 boundary và future composition review gate.
Fresh focused146 +selected7 PASS; không có authority/provider/page behavior changes hoặc automatic integration.
Page hiện coupling provenance/session/refresh/modal rất chặt; không coi hai VM proposed dưới đây đã chứng minh đủ budget.
Later composition cần review file-budget bảo đảm page≤300 ở endpoint, không partial rewrite còn700LOC rồi claim LOC PASS.

- Files chính: existing `notifications_page.dart` target≤300; các widgets02; new
  `presentation/view_models/mh17/notification_feed_coordinator.dart`≤250 và
  `presentation/view_models/mh17/notification_page_view_model.dart`≤250 nếu characterization chứng minh cần.
- Feed coordinator sở hữu cursor/history/dedup/merge/reset, không sở hữu server count hoặc read receipts.
- Page VM compose snapshot provenance/access/action orchestration; chỉ dùng existing providers/epochs; không authority mới.
- Test split03A1 actual: root `notifications_page_test.dart`, `pages/mh17/mh17_pagination_test.dart`,
  `pages/mh17/mh17_read_navigation_test.dart`; helpers≤150, original body/assertion/fake/timing giữ nguyên.
- Dependency:02 accepted, original working baseline mới, characterization map method→owner trước move logic.
- Verify: tests scope-switch first frame, head polling once, invalid/loop cursor, late filter/count/read, stale actions,
  permission denial/recovery, context modal/session/disposal, callback after deactivation; analyze + relevant protected regressions.
- STOP: page≤300, UI≤180, new VM≤250; không đổi contracts, foundation behavior, router/Auth/backend hoặc protected order UI.
- Nếu hai coordinator proposed không chứa logic đúng responsibility trong budgets, STOP plan review; không thêm layers chỉ để chia LOC.
- Existing interaction VM455/foundation test418 thuộc03C, không tuyên bố whole-feature LOC PASS sau03A.

## MH17-03B — canonical Preview scenarios và navigation/session fixtures

- Files candidate mới: `tool/ui_preview/mh17_preview_fixtures.dart`, `mh17_preview_environment.dart`,
  `mh17_preview_surface.dart`, `mh17_preview_navigation.dart`, mỗi file≤250.
- Reuse existing Preview shell/scope lifecycle; fixture inbox phải qua NotificationRepository/domain/DTO contracts.
- F07: fake rows hiện reuse cùng event/recipient và notification_only subject sai nguồn; future fixtures dùng unique event IDs,
  notification_only.subjectId=eventId, đúng producer constraints; không đổi shared fixture hoặc Preview trong01/02.
- `tool/ui_preview/preview_app.dart`308 LOC là protected shared architecture: read-only mặc định.
  Nếu cần adapter hook vào shared file/main, STOP xin scope cụ thể trước; không sửa tự động hay tạo parallel app shell.
- Tests mới `test/ui_preview/mh17_preview_{fixtures,navigation,session}_test.dart`, mỗi file≤400.
- Dependencies:03A accepted; reviewed host extension point; target mode/screen mappings với synthetic canonical UUIDs.
- Cases: all/unread/count>page size, empty/loading/error/stale/loadmore, valid/denied/missing targets, notification_only,
  generation/account switch, expiry/disposal, delayed read/count/resolve, rapid repeated navigation; no fake production success.
- Verify: Preview tests +67 original focused tests + protected MH07/MH08/MH09 read-only regressions; format/analyze.
- STOP: demo được gắn nhãn, current-owner privacy cases PASS, không gọi backend hoặc tuyên bố destination production integrated.
- Current `main.dart` chạy Mh08PreviewApp; không đưa launch command giả cho MH17 trước khi host hook được giao.

## MH17-03C — robustness/LOC follow-up, review riêng

Đây là task bổ sung từ findings F02/F03/F05, không tự gộp vào isolated UI02.
F02 validation/reproducer cần xử lý trước production integration. F03 role matrix và F05 rapid navigation cần characterization;
chỉ thêm navigation guard khi evidence chứng minh cần. LOC extraction chỉ triển khai khi task được duyệt.

- Files candidate: `domain/models/notification_page.dart`≤150, `notification_query.dart`≤150;
  existing interaction VM target≤250; proposed `view_models/notification_target_policy.dart`≤150,
  `view_models/notification_read_coordinator.dart`≤250 chỉ khi có responsibility độc lập rõ ràng.
- Tests: split foundation418/interaction562 vào `{foundation,read_acknowledgement,target_policy,interaction_lifecycle}_test.dart`,
  mỗi file≤400 trong `test/features/notifications/presentation/view_models/`; thêm malformed cursor tests trong pages/domain tests.
- Dependencies: own contract owner review, characterization trước sửa; không đổi public repository signatures hoặc read semantics.
- Verify: empty/oversized/mismatched cursor, all typed role/mode/entity allow/deny pairs, duplicate route taps,
  canonical ack/dedup/timeout/refetch recovery/session disposal, original assertions; format/analyze/focused tests.
- STOP: smallest validated extraction, no shared business contract/backend change; timeout10/15s cần quyết định rõ trước đổi.
- Không coi mọi item là defect đã reproduced; rapid navigation là investigation, cursor là static issue chưa có reproducer mới.

## MH17-04A — visual fidelity và responsive audit

- Files mới: `test/visual_refinement/mh17_04a_{primary,matrix,states,accessibility}_test.dart`≤400/file;
  capture/compare utility dưới `docs/features/mh17/artifacts/visual_04a/`≤150/file.
- Evidence mới cùng folder; docs `VISUAL_AUDIT.md`≤200, HANDOFF≤100; không overwrite reference/old evidence.
- Dependencies:03A/03B accepted,03C blockers triaged; canonical fixture/host available; HTML policy exclusions giữ nguyên.
- Verify: matched390×844 DPR1 pairs, font/geometry/source manifests, width320/360/390/412×text1/1.5/2,
  async/loadmore/empty/session matrix, semantics and contrast/targets measurements.
- STOP: report demonstrated defects + measurements, không sửa UI trong audit04A, không pixel parity hoặc Android PASS giả.

## MH17-04B — targeted refinement và Android acceptance

- Files: chỉ approved defect paths từ04A trong MH17 presentation/tests; page≤300/widget≤180/VM≤250/test≤400.
  Không sửa MH07/MH08/MH09/shared theme/Preview architecture nếu chưa được giao riêng.
- Docs `REFINEMENT.md`, `ANDROID_ACCEPTANCE.md`≤200; HANDOFF≤100; utilities≤150 trong new artifacts directory.
- Dependencies: defect shortlist approved, stable Android runtime, truthful Preview, known external gates documented.
- Verify: format/analyze/focused+protected regressions; full suite chỉ nếu chạy an toàn không overwrite historical output;
  new APK provenance/build/install/launch, native back/rotation/textscale, tap targets, real TalkBack audio/focus, session privacy.
- STOP: báo rõ PASS/FAIL/NOT VERIFIED từng mục; user quyết định acceptance riêng, không tự đánh dấu MH17 USER APPROVED.
- Backend adapter/Auth/router/RLS/producers vẫn separate owner gate; Android Preview không thay backend end-to-end acceptance.

## Bất biến qua mọi task

Approved source theo working-file baseline, không lấy từ HEAD; fresh hashes trước task; no commit/push/reset/clean/stash/checkout/merge.
Giữ canonical count, no optimistic ack, typed permission recheck, independent notification/chat/business states.
Không dashboard metrics/category filters/mark-all/push theo HTML; không thêm màn chính ngoài MH01–MH20.
