# MH17 checkpoint04C1 — Production modal integration

**MH17 CHECKPOINT04C1 — MODAL INTEGRATED, READY FOR REVIEW**
MH17 UI NOT USER APPROVED. Scope: Page modal opening +necessary revoke/cleanup/imports; no other owner integration.
[Verification](artifacts/implementation_checkpoint_04c1/verification.json), [scope proof](artifacts/implementation_checkpoint_04c1/page_scope.json).

## Working-source baseline và exact changes

Baseline22/10/2026: branch feature/orders-notifications-phase2,174status entries,3486working files; no HEAD approval assumption.
Original Page working SHA/snapshot captured before edits tại artifacts/implementation_checkpoint_04c1/notifications_page.before.txt.
Only existing production file changed: lib/features/notifications/presentation/pages/notifications_page.dart.
Original922→final952 physical LOC, net+30; interim Page>300 explicitly allowed, không claim whole-feature LOC compliance.
Modal region59→78LOC (includes new helper methods), net+19; imports/handle set/revoke/cleanup glue net+11.
Working diff85added/55removed; [patch](artifacts/implementation_checkpoint_04c1/page_working_diff.patch) compared to working copy, không HEAD.
Scope checker reconstructs all authorized outside edits exactly; all other Page text remains identical.
Public constructor/read/navigation/count/filter/pagination/provenance helper methods unchanged; only informational branch removes await route.
Existing isolated Modal/Handle/ContextSheet and all other Dart/test inputs read-only.

## Opening, authorization và retention

_showNotificationContext is synchronous: mounted/fresh current Page receipt, submitted scope and recipient checked first.
Read current cache/query/snapshot, verify snapshot↔cache identity +accepted visible row identity, reject current count denial.
Old same-ID projection callbacks cannot create handle after accepted projection replacement; foreign recipient fails closed.
Require Page and Navigator inherit same ProviderContainer; scoped DI confined below Navigator fails closed before handle creation.
Actual app/Preview/test topology places provider scope above Navigator; runtime check prevents route reading wrong DI after Page disposal.
Namespace uses current scope/cache and lease:null because Page has no integrated SessionBridge; live checks authorize, no fabricated lease.
Construct handle only from authorized server text; Page pushes showModalBottomSheet with approved Modal/ContextSheet presentation.
Static _contextBuilder(handle) captures only revocable handle; no raw item/Page State/title/body in route builder.
Static _pushContext owns completion cleanup: captures handle+detachable Set only; removes link and releases after completion.
Synchronous push failure removes link/releases/rethrows; guarded in source, injected Navigator push failure not runtime tested.
_open informational path no longer awaits route in item-holding Page frame; canonical VM/open/read behavior unchanged.

## N07 owner/route protocol

Page links live handles in _contextHandles; _revokeContexts clears private cells synchronously and clears links.
Session change, cache replacement, unreadable render/cache event and _denyAccess revoke before old private render.
Dispose only clears links and existing Page listeners; does not release route-owned handles or auto-pop.
Modal owns independent scope/cache/list/count listeners until route dispose, even after actual Page State unmounts.
Parent denial tested before modal mounts: readable cache remains true, but handle already revoked before first modal frame.
Read acknowledgement/current-owner stale refresh/row disappearance keep authorized informational context.
Scope/account/logout/generation/role/access denial/cache block revoke irreversibly; recovery requires a newly authorized handle.
Hide is not pop: safe state route remains mounted; Close/Back preserve Navigator semantics and repeated release stays safe.
Same-owner cache replacement may retain disabled legacy feed rows while new snapshot loads; old modal is revoked independently.
Silent cache mutation without event is only observable on subsequent rebuild/live check; no immediate-detection or zeroization claim.

## Tests và fresh verification22/10/2026

New files under test/features/notifications/presentation/pages/mh17/:
- mh17_modal_page_integration_test.dart195/400:12cases, opening/Close/Back/session/cache/denial/stale/ack.
- mh17_modal_page_lifetime_test.dart213/400:11cases, pre-mount denial, DI guard, Page dispose, late responses/captured callbacks.
- mh17_modal_integration_repository.dart77/150: canonical notification_only UUID/UTC fixtures +controlled repository.
- mh17_modal_integration_support.dart112/150: real Page/Navigator harness +route observer, no private Page hooks.
Before edits focused320PASS; new integration23PASS; all Page/session63PASS; final focused343PASS (320+23).
Selected safe shared/Preview regressions7PASS; analyzer PASS No issues found; format5files0changed; diff/LOC/links/hash PASS.
All commands use working source via installed Dart/flutter_tools.snapshot; no pub/dependency or SDK/source mirror changes.
Original320cases/assertions preserved byte-for-byte. No skips/removed assertions or protected production changes.
Attempts01/02 record mistaken new global-text oracle: same-owner legacy Page stale row mistaken for modal leak.
Final dedicated case keeps strict modal no-sheet/title/body checks AND asserts same-owner stale row actions disabled, then B replaces A.
Account/logout/denial cases retain global skipOffstage:false privacy assertions. Existing loading/stale behavior not changed to satisfy tests.
Initial3test lint infos fixed readable braces/null-aware list; final clean, no suppressions; logs preserved.
Independent Sol medium read-only review approves scoped diff/23cases, no blocker; reviewer did not execute tests.
372protected working inputs unchanged excluding explicitly authorized Page; prior artifacts and approved MH07/08/09 untouched.

## Remaining limits và STOP

No full suite/backend/Android/native acceptance. Selected Preview widget tests are not Preview/UI user approval.
ReadCoordinator342/350 sole approved exception unchanged; Page952/300,InteractionVM455/250,Tile185/180 debt remain separate.
F02 malformed nextCursor unresolved; no new live pagination behavior. F03/F05/F07/Auth/router/backend/Preview unchanged.
No Feed/Read/SessionBridge/Actions integration, no04C2. Next: user review bounded N07 integration before further composition.
STOP. No commit/push/reset/clean/checkout/stash/merge/delete or MH17 UI approval.
