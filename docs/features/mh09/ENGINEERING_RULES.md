# MH09 — Engineering rules

Áp dụng từ MH09-01; task01 chỉ audit/docs/artifacts/utility. Không triển khai UI hoặc tự bắt đầu02.
MH07/MH08 USER APPROVED; MH09 NOT YET APPROVED. Owner Bảo; không tự chuyển MH17.

## Ownership và architecture

- Production page hiện hữu giữ public API `ManagerOrderDetailsPage`; future changes chỉ khi task tương ứng được giao.
- UI mới namespace `widgets/mh09/`; View render/forward callback; page điều phối; read state ở VM hiện có.
- Reuse Riverpod families/session/cache/Repository/domain/DTO/formatters, không tạo authority/cache song song.
- Không rewrite provider, models/DTO/contracts, Supabase/SQL/Auth/router trong visual task.
- Không Supabase calls trong widgets; không Provider/Bloc/GetX/navigation khác.
- Data/callback-only components; mọi quyền/freshness/action predicate do owner page/current provider quyết định.
- Four lifecycles độc lập; missing projection không phải pending/uncollected/closed; không fake refund/timeline.
- Shared theme/recipient/items/payment/timeline/dialog phục vụ approved screens: readonly.
- Tạo MH09-specific presentation dùng shared models thay vì sửa shared style hoặc copy model/formatter logic.
- Public lifecycle sections và timeline hiện có được compose nguyên trạng; no duplicated normalization.
- Không thêm widget trivial chỉ để đẩy LOC, không thêm dependency chỉ vì mock có icon/image/dialer.

## Physical LOC gates

Đếm comment/blank; file không có newline cuối vẫn tính dòng cuối. Gần80% thì lập extraction plan.

| File responsibility | Maximum |
| --- | ---: |
| Page/coordinator |300|
| UI widget/section |180|
| ViewModel/controller |250|
| Repository adapter |250|
| Domain/helper/formatter (DTO mapping trong audit xếp helper) |150|
| Preview fixture/harness |250|
| Test/support |400|
| Renderer/utility |150|
| Feature Markdown |200|
| HANDOFF |100|

Legacy page578/test440/lifecycle455/timeline358/dialog204/theme254 vượt limit, ghi inventory chứ không sửa task01.
Không claim toàn repo gate PASS; gate task01 chỉ tài liệu/utilities mới. Xem SOURCE_AUDIT cho dependency violations.
Future03A phải giảm page≤300/test≤400 trong scope MH09; không dùng Dart part hoặc sửa MH07/MH08 để đạt gate.
Nếu cần shared change, chứng minh dependency và đề xuất scoped alternative trước khi mở rộng task.

## State, freshness và actions

- `orderDetailsFoundationProvider(orderId)` giữ identity/autoDispose. Page không cache bản OrderDetails khác.
- Loading/error/empty/unavailable/stale/expired/denied có render rõ, không silently demo fallback.
- Empty projection khác empty whole detail: VM hiện `isEmpty=false`, detail không tồn tại là generic error.
- Confirm/reject/exceptional cancel cần current manager/session/cache/fresh canonical capability.
- Server status/custody/authorization/race/idempotency vẫn là authority; status không đủ bật action.
- Mutation hiện chưa integrated: giữ validation + unavailable, không fake receipt/success/local state transition.
- Receipt lịch sử chỉ resolve outcome + invalidate/refetch; không replace canonical order/projection.
- Không mutate Delivery/COD/Returns/Inventory state tại MH09; missing API thì disable + explanation.
- VND integers, fee30.000; timestamp server → Hanoi formatter; không dùng clock device cho eligibility.

## Dialog / navigation lifecycle

- Stable ProviderScope nằm trên Navigator, không reparent modal scope hoặc dựng app mới cho MH09.
- Mỗi dialog có owner, captured submittedScope/sourceCache; predicate recheck current capability khi mở và submit.
- Guard owner mounted/active trước mọi WidgetRef read sau async và trong callback giữ lâu hơn page.
- Dispose local reason/controller/listener; clear private reason/data khi session/role/account đổi.
- Giữ epoch/generation/current-token rejection, serialized refresh và late-response protection hiện có.
- Không truy cập deactivated WidgetRef/disposed container; thêm reproducer disposal trước sửa nếu nghi ngờ.
- MH08→detail exact UUID→pop giữ search/status, recheck scope/cache/mounted rồi canonical head/count refresh.
- Callback external đúng business ID: COD orderId, Returns returnId, Chat customerId, Call phone snapshot.
- Recheck destination permission lúc mở; no raw data leakage hoặc tự bypass shipper MH11.

## Testing và evidence

- Task01: render/manifest/fonts/source hash, LOC/links, baseline comparison, focused existing tests, diff check, utility syntax.
- Task02: isolated widgets + callback/semantics/long text/missing projection/financial labels tests.
- Task03A: existing + session/dialog disposal/current capability/late response/route-pop regression; split tests≤400.
- Task03B: stable Preview/repeated navigation/expiry/in-flight response/guarded callbacks/MH07/MH08 regression.
- Task04A: same-viewport screenshot pairs, dimensions/fonts/hash manifest, responsive widths×textScale matrix.
- Task04B: demonstrated defects only, Android launch/runtime/IME/targets/TalkBack; full regression before approval.
- Khi Dart thay đổi: dart format, flutter analyze, relevant tests; pub get chỉ nếu dependency được giao thay đổi.
- Không sửa tests để che baseline FAIL, không đánh dấu PASS cho plan/test ID chưa thực thi.
- Full276/analyze/Android MH08 là lịch sử; audit task01 ghi riêng fresh results và NOT RUN.

## Context, Git và handoff

- Preferred20–50k, aim<60k; gần estimated70k thì safe checkpoint, HANDOFF≤100 và dừng; không claim đo token chính xác.
- Minimal reads theo README; rg scoped + selected methods; không dump toàn SRS/source/log vào docs.
- Quyết định architecture phải nằm trong docs, không chỉ chat; mỗi task cập nhật evidence/HANDOFF.
- Trước task mới capture branch/status + working-file SHA-256; không coi HEAD là approved baseline.
- Dirty/untracked có sẵn không thuộc sở hữu task mới; không overwrite/delete hoặc reset/clean/stash/checkout/switch/merge.
- Không commit/push trong task01; chỉ thêm docs MH09 + render/audit scripts và artifacts mới.
- Verification tool01 dùng baseline01; future authorized production edits phải có baseline và allowed-file list mới.

## Definition of Done MH09-01

Actual source/API/dependencies/LOC discovered; four lifecycle/action/security audit có current/target/missing.
HTML thật hoặc blocker explicit; component boundaries/task roadmap/test map/docs/handoff hoàn chỉnh.
Approved/protected files giữ working SHA-256; no production/test/Preview edits; no unauthorized Git operation.
Checks ghi PASS/FAIL/NOT RUN chính xác; sau kế hoạch **STOP FOR USER REVIEW**.
UI MH09 chưa được duyệt, audit completion không cho phép tự chạy02/backend/MH17.
