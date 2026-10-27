# MH17 — Test plan và baseline

## Implementation checkpoint01

[Scope/API/oracles](IMPLEMENTATION_CHECKPOINT_01.md):26 new pure snapshot predicate cases; existing tests/assertions protected.
Scope/generation/cache replacement/block/dispose, stale head/tail, active/access latch, exact server count và identity keys.
Evidence/counts thực thi ở [verification](artifacts/implementation_checkpoint_01/verification.json); failed fixture-compile attempt giữ riêng.
Không coi pure predicate tests là Page first-frame/modal runtime proof; N01/N04/N05/N07 cần future integration tests.
R architecture accepted với sole ReadCoordinator≤280 exception; F02 response validation tests thuộc separate authorized fix.

Ngày 21/10/2026. [Original T17 oracles](../../technical_specification_mh07_mh08_mh09_mh17_tests.md).
Status “covered” chỉ nói client assertions đã đọc/chạy; không chuyển backend oracle thành PASS bằng fake repository.

## MH17-03A2 — isolated accepted-feed coordinator

- Fresh working-source baseline120 PASS +relevant pagination/feed8 PASS trước implementation; final focused146 PASS.
- New26unit cases: stable head/tail ID projection/order, immutable snapshots, independent count/no optimistic readAt,
  filter/owner reset, same-owner refresh/late ticket rejection, retry cursor/request ordering, self/history loops/null exhaustion,
  synchronous replay, stale authority boundary, consecutive refresh và raw empty/oversized F02 cursors.
- Source152/250LOC, test379/400; old Dart/03A1 assertions untouched. Existing page/pagination/characterization files run individually.
- New coordinator individual26; old individual counts9/6/2/3/4/5/4; selected protected regressions7 PASS; analyzer/format PASS.
- [Transition design/results](COORDINATOR_03A2.md), [focused146](artifacts/coordinator_03a2/focused_final.log),
  [individuals](artifacts/coordinator_03a2/individual_results.json), [verification](artifacts/coordinator_03a2/verification.json).
- No full suite/fixed-output capture, Android/backend/RLS/TalkBack or production modal/navigation acceptance inferred.

## MH17-03A1 — test extraction và characterization

- Fresh baseline106 PASS trước edits; final focused120 PASS =106preserved +14new, không cộng historical461.
- Original page18declarations/19cases/94assertions103expanded qua3files222/221/124LOC; support137/52.
- Full body/assertion/literal/loop/setup/fake preservation +5negative mutation controls: [report](artifacts/refactor_03a1/test_preservation_report.json).
- New2feed cases: duplicate projection/count independence và explicit refresh rejecting old in-flight tail.
- New3gesture cases: available/pending/rapid taps, stale disabled body, captured callbacks after disposal.
- New4privacy cases: own inbox3roles/foreign row rejection; late A count99 cannot replace B count3.
- New5navigation cases: unknown/null resolver/unavailable target; pending resolver after disposal or generation change while mounted.
- Reuse protected7session cases for logout/unresolved/expiry/late list/modal privacy; full F03 role destination matrix remains separate.
- [Focused120](artifacts/refactor_03a1/focused_verified.log), [individual7files](artifacts/refactor_03a1/individual_results_final.json),
  [selected regressions7](artifacts/refactor_03a1/regressions_verified.log), [analyze](artifacts/refactor_03a1/analyze_verified.log),
  [format](artifacts/refactor_03a1/format_verified_final.log), [verification](artifacts/refactor_03a1/verification.json).
- Tests ran on working source. Full suite NOT RUN: legacy fixed-output capture paths protected; no validated mirror prepared.
- No actual forbidden navigation reproduced, no failing production oracle hidden; F05 callback multiplicity is observed current behavior.
- Two review issues fixed in new test tooling/oracle, not production: literal/cardinality preservation; mounted-generation isolation.
- Initial analyzer export ambiguity +2brace infos fixed without ignores/assertion removal; [notes](artifacts/refactor_03a1/attempts.txt).
- Android/production routes/backend/RLS/NFR/TalkBack NOT RUN. [Detailed inventory/plan](REFACTOR_03A1.md).

## Thực thi MH17-02 — isolated components

- Fresh original baseline67 PASS: [log](artifacts/components_02/baseline_tests.log).
- Final `flutter test --no-pub test/features/notifications --reporter expanded`: **106 PASS** = original67 +new39,
  không skip/weaken assertions; [log](artifacts/components_02/focused_final.log).
- New directory `test/features/notifications/presentation/widgets/mh17/`: filters9, context10, feed15, feed_interaction5.
- Filters: controlled default/selected/null/busy/one callback, selected/disabled semantics,320/390×text1.5/2, targets≥48.
- Context: plain authorized strings/explanation, null/delegated close, exact heading/live-region semantics, safe area,
  long scroll/Close matrix, parent removal/remount; không modal session authorization claim.
- Feed: tile reuse/identity/text/Hanoi time, mixed rows giữ thứ tự và không local filtering, independent callbacks,
  pending/null callbacks, unknown kind, empty all/unread, loading/error/retry/stale/refresh, pagination error/pending/exhaustion,
 45rows/last footer reachable, immutable inputs/removal, long Vietnamese matrix và semantics.
- New support fixture có unique event/recipient và notification_only.subjectId=eventId; không sửa Preview/F07 fixtures cũ.
- Selected read-only regression: `feature_access_gate_test`, `foreground_refresh_test`, `preview_app_test` **7 PASS**,
  [log](artifacts/components_02/protected_regressions.log); đây không phải Android hoặc full protected suite.
- `dart format --output=none --set-exit-if-changed` trên8new Dart files **0 changed/exit0**:
  [format](artifacts/components_02/format_verified.log); analyzer **No issues found/exit0**: [log](artifacts/components_02/analyze_verified.log).
- Initial new-test attempts có lỗi expectation/semantics handle/refresh animation timing; sửa test harness, không sửa protected source.
- Initial analyze có7 deprecated hasFlag info; thay bằng flagsCollection/Tristate, giữ assertions, không ignore diagnostics.
- [Attempt notes](artifacts/components_02/attempts.txt), [working-file verification](artifacts/components_02/verification.json).
- Full suite, Preview launch, Android/TalkBack, backend/RLS, production modal invalidation **NOT RUN** trong02.

## Thực thi trong MH17-01

| Check | Result / evidence |
| --- | --- |
| `flutter test --no-pub test/features/notifications --reporter expanded` | **67 PASS**, exit0; [log](artifacts/audit_01/focused_verified.log) |
| `flutter analyze --no-pub` | **No issues found**, exit0; [log](artifacts/audit_01/analyze.log) |
| Full `flutter test` | **NOT RUN**, không sử dụng MH09 historical461 để thay thế |
| Android build/install/runtime/TalkBack MH17 | **NOT RUN** |
| SQL/RLS/concurrency/backend | **NOT RUN**, không có deployed backend evidence |
| `dart format` changed Dart | N/A: không sửa Dart |
| HTML/links/physical LOC/diff/hashes | [verification](artifacts/audit_01/verification.json), chỉ task-owned gates |

Lần Flutter sandbox đầu không tạo output, stopped; log0byte không phải PASS.
Verified retry dùng installed SDK ngoài workspace qua tool escalation. Không đổi SDK/deps/lockfile/source.
Không chạy legacy visual captures vì fixed output có thể ghi đè evidence cũ.

## Focused coverage map

| Requirement / oracle | Existing coverage | Missing / future verification |
| --- | --- | --- |
| Nine-field identity, unknown/invalid data T17-13 | DTO tests nullable key/unknown; foundation rejects foreign row | adapter row envelope/zero-row PATCH runtime |
| Owner/session T17-01/02 | foundation + interaction owner guards; page session/modal expiry | RLS allowed/denied every role, foreign PATCH unchanged, real account switch |
| All/Unread T17-03 | page filter/reset/empty/read removal after reload | live filter sorted paging, unread-empty vs all-empty screenshots |
| Server unread count T17-04/10 | unknown badge absent; count independent visible rows, negative reject | exact whole inbox count during concurrent insert/read on backend |
| First stamp/monotonic T17-05/06/07 | canonical row required, repeated local read avoids mutation | two sessions same timestamp, protected columns denied, cannot unread via direct request |
| Pagination/cursors | page append/retry/same-cursor/expired cursor, head refresh | empty/oversized nextCursor F02 reproducer, opaque user/filter binding, same-time tie sorting |
| Dedup/late responses T17-26 | per-ID read future; epochs/count invalidation/filter switch/disposal tests | backend source-event dedup and frozen fanout T17-08/09/28–31 |
| Ack/timeout T17-17/24 | canonical owner/ID/read, no optimistic count, retry/outcome_unknown, navigation independent | lost PATCH response with real server commit; authoritative refetch recovery |
| Typed order navigation T17-11 | customer authorized callback, denied/missing/invalid decision, foreign owner guard | Manager order positive/negative matrix, real destination re-fetch authorization |
| Tasks/COD/Returns/Chat T17-12/15/27 | static role/type/entity allowlist in VM | all positive/negative mode/role/screen/entity tuples, manager task→order mapping, reassigned task denial |
| Unknown/missing target T17-13/14/23 | unknown/notification_only bypass resolver, missing callback unavailable; context sheet | deleted target/revoked assignment real owner adapters, event ID relation |
| Notification vs chat read T17-16 | no chat write in notification client | actual Chat read state unchanged when notification read |
| Error/retry/stale T17-20 | page/foundation error retry, stale rows/disabled action, next-page error preserves data | screenshots + network recovery + native lifecycle |
| Privacy/access T17-01/15/22 | first-frame A→B row/badge clear, expiry/modal, invalid callback rejection | producer payload PII restrictions, all roles backend auth, old-network delayed responses |
| Rapid navigation | pending resolver discarded on session/disposal | rapid double-tap/route-return/current-permission-revoke dedicated characterization F05 |
| Foreground T17-18/19 | head polling/page disposal client tests | real notification inserted by other session≤5s, background/resume/reconnect measurement |
| No optional features T17-21 | source inspection no mark-all/unread/push | UI acceptance confirm no accidental mock metrics/category/bulk features |
| Text scale/semantics | tile320dp/text2, exact124 badge semantics, long page text | full320/360/390/412×1/1.5/2, contrast,48dp targets, actual TalkBack |

Coverage files và LOC chi tiết trong [SOURCE_AUDIT](SOURCE_AUDIT.md); không sửa assertions trong task01.
NT01–NT30 report definitions chưa có trong minimal supplied context; không tự gán oracle chi tiết cho NT ID.

## Priority cho follow-up

1. P0 privacy: current-owner only first frame, badge/context clearing, delayed old account reads/count/ack/resolve,
   role loss/unresolved/logout/expiry, blocked cache recovery, foreign recipient rejected trước callback.
2. P0 navigation: full typed matrix, mismatched UUID/mode/screen fail closed; Manager task→authorized order exception;
   Shipper không chat/Returns sensitive view; destination fetch rechecks current permission.
3. P1 data robustness: canonical cursor empty/oversized/mismatched/loop/expired; duplicates across pages, filter during request,
   poll from tail refresh head once, concurrent refresh invalidates prior page/count, no unread resurrection.
4. P1 ack: same-ID dedup vs other-ID independence, canonical read ID/owner/UTC, zero-row/timeout/outcome unknown,
   lost-response refetch, no optimistic subtraction, navigate allowed independent of read failure.
5. P1 UI: all/empty-unread/loading/error/stale/loadmore/disabled/context, long text/accessibility/Back/dispose.

Không thêm tests trong task01. Future tests phải có behavioral oracle, không mirror private implementation chỉ để tăng count.

## Protected regression protocol

- Fresh SHA-256 từ working files trước task và kiểm sau task; MH07/MH08/MH09 source/tests/Preview/evidence được bảo vệ.
- Task01 xác nhận bytes không đổi, không tuyên bố rerun toàn bộ protected regression suite.
- Future integration cần chọn existing read-only tests orders/MH08/MH09/Preview/session; không chạy capture tests ghi fixed path.
- Nếu cần full suite có captures, chạy exact-source isolated output/mirror do task riêng chuẩn bị; preserve provenance.
- Không modify approved UI để thỏa MH17 style hoặc LOC gates.

## Android acceptance tương lai

Build từ exact approved working hashes; ghi APK SHA/device/API/DPR/font/orientation và logs.
Thực thi scrolling cuối feed/loadmore/context, refresh/retry, repeat navigation, account swap trong pending read/resolver.
Portrait/landscape/text1/1.5/2; Back route/modal; native48dp tap targets.
TalkBack thực: nghe title/body/read state/exact count/time/filter selected/pending/error, focus order, duplicate labels, Close/Back.
Không suy audio PASS từ Semantics tester, Android PASS từ HTML/widget test, backend PASS từ Preview fake.
