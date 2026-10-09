> Historical revision1.1 preserved. Current authority/status superseded by [revision1.2](Implementation_Readiness_v1.2.md); pending labels below describe the earlier snapshot, not new owner approval gates.

# Updated Implementation Readiness — MH07, MH08, MH09, MH17

Ngày 08/10/2026, documentation revision 1.1. **NOT READY FOR IMPLEMENTATION cho giao trọn bộ bốn màn end-to-end.** Remediation đã sửa các lỗi tài liệu cục bộ; không có owner approval, source/RPC/job/producer implementation hoặc runtime test mới. Đánh giá này phân biệt chuẩn bị cục bộ với giao coding agent toàn bộ không phải tự đoán interface.

## Mức sẵn sàng từng màn và shared dependencies

| Scope | Phần đủ xác định để bắt đầu coding | Phần còn blocked | Full-screen decision |
|---|---|---|---|
| MH07 | Raw Order/Item parsing, enum/VND/Hanoi formatting, async cards/modal UI, query generation/cache epoch, test-only fake data có nhãn | Auth DR06; safe list/detail/search/count/errors DR04; cancel receipt DR01; Returns eligibility/cutoff/routes DR05; UUID/image UX DR09 | NOT READY FOR IMPLEMENTATION full flow; local foundations ready |
| MH08 | Manager read UI/status labels/local search input/filter layout, action dialog validation, stale cache/state rules/tests | Auth/role; exact aggregate/counters/errors DR04; manual/job confirm DR01/07; reject/release receipt; delivery warning producer contract DR03 | NOT READY FOR IMPLEMENTATION full flow; read-only widgets/local protocol ready |
| MH09 | Snapshot items/payment no discount, four distinct lifecycle rendering, audit presentation no fabricated actor/steps, local refresh logic | DR01/04 mutations/projection/errors; DR02 custody/assignment/retry/inspection; COD/Returns/Chat owner contracts; manager route/Auth | NOT READY FOR IMPLEMENTATION full flow; entity/UI layers ready |
| MH17 | Existing 9-field Notification mapper, own list/count/markRead adapter draft, async center/read epoch/notification_only branch unit tests | Auth session/route; DR03 exact targets/recipients/producers/atomicity; DR01 event identity; owner target routes/current auth; event fixture evidence | READY WITH CONDITIONS cho inbox foundation, NOT READY FOR IMPLEMENTATION toàn notification flow |
| Order shared model | 21-field Order,11-field Item, exact SQL enums and integer money VERIFIED IN CODEBASE | Aggregate DTO §4.6 draft DR04 approval; aliases đã bỏ nhưng backend not implemented | READY FOR IMPLEMENTATION raw entity mapping only |
| OrderRepository/read APIs | Một draft wire/key/required-null dictionary, full list/detail examples | Signatures/search/count/cursors/role allowlist/error transport DR04 chưa ký; RPCs missing | BLOCKED BY MISSING CONTRACT |
| Transition/receipt/job | Normative auth→receipt→state protocol, epoch integration và races có oracle | Namespace/storage/fingerprint/retention DR01, job server identity/deployment DR07 | BLOCKED BY TEAM DECISION / MISSING CONTRACT |
| Delivery/Inventory boundary | Business invariants và candidate quantity constraints rõ | Historical custody/source/task2 path/inspection closure DR02 chưa ký | BLOCKED BY TEAM DECISION |
| Notification producers/targets | 22 typed-target draft rows và event test family matrix | Exact fan-out, old assignee, source/child atomicity DR03 | BLOCKED BY TEAM DECISION |
| Application test/NFR evidence | Test-plan oracle đã sửa, full case IDs và dependencies | Tests chỉ planned; full NT exact/minOS/platform/backend/device evidence absent | BLOCKED BY UNAVAILABLE EVIDENCE |

## Trạng thái AUD-01 đến AUD-10

| Finding | Severity | Remediation status | Kết quả và phần còn thiếu |
|---|---|---|---|
| AUD-01 | BLOCKER | PENDING APPROVAL | Receipt namespace/storage/replay/retention chưa được owners ký; DR-01 |
| AUD-02 | BLOCKER | PENDING APPROVAL | Custody/retry/inspection còn alternatives, không bật actions; DR-02 |
| AUD-03 | MAJOR | PARTIALLY FIXED | Exact wire draft/required-null keys/full examples/client failure đã sửa; role visibility/error transport/signatures chờ ký; DR-04 |
| AUD-04 | MAJOR | FIXED | Historical receipt không cache-write; epochs/serialized refresh/stale read-only + tests; Không còn decision gate cho correction cục bộ |
| AUD-05 | MAJOR | PARTIALLY FIXED | Đã có typed target draft từng recipient; fan-out/source identity/producer atomicity chưa ký; DR-03 + DR-01 |
| AUD-06 | MAJOR | FIXED | Tách manager route deny và shared detail own Customer allow, other Customer/shipper deny; Runtime suite vẫn cần DR-04/API thật |
| AUD-07 | MAJOR | PARTIALLY FIXED | 22 event-family fixtures/test oracles/traceability; exact recipient fixture và owner evidence chờ ký; DR-03 + DR-01 |
| AUD-08 | MAJOR | FIXED | Cancel/manager sequence: auth→receipt replay→precondition; transport loss sau commit và same-key recovery; Persistence triển khai phụ thuộc DR-01, sơ đồ hành vi đã sửa độc lập |
| AUD-09 | MINOR | FIXED | Notification-only không target fetch; read failure không khóa authorized navigation; Typed event integration vẫn DR-03 |
| AUD-10 | MINOR | FIXED | P4C core confirm/job trước P5 delivery/COD; P6 phần transitions còn lại; Contract gates explicit trong roadmap |

**5 FIXED, 3 PARTIALLY FIXED, 2 PENDING APPROVAL, 0 UNRESOLVED.** FIXED của AUD04/06/08/09/10 nghĩa correction tài liệu hành vi/test oracle/sequence/roadmap độc lập đã xong; implementation luôn cần signed dependencies. Không đánh dấu AUD03/05/07 FIXED vì fixtures/mapping cuối vẫn phụ thuộc owners. AUD01/02 không chọn thay module owners.

## Điều kiện giao toàn bộ cho coding agent

1. Owners ký DR01/02/03/04, update shared api_contracts/database/business_states/screen_mapping cùng exact version; khóa namespace/persistence/lookup, custody/task2/inspection, notification event×recipient×target, safe projections/errors/request/response schema. Xóa alternatives không chọn khỏi executable contract, giữ history trong Decision Log.
2. Nhận Auth/session/role/route/protected persistence (DR06), committed Checkout snapshot, Deliveries/COD/Returns/Chat interfaces và return cutoff DR05. Agent phải biết exact params/return/errors/caller permissions, không gọi ViewModel module khác.
3. Resolve DR07 server job và DR09 identifier/image/theme baseline bằng approval phạm vi; optional rebuy/call/mark-all không chặn baseline nếu giữ postponed. Full NT/OS DR08 bổ sung để acceptance đủ traceability.
4. Re-audit examples/diagrams/state/test fixtures/roadmap sau approval. P4C confirm backend và persisted core notifications trước P5 real placed→delivery→COD; P5 cần owner core producers thực tế, P6 cancellation/rejection/receipt extensions sau core, P8 producers do owner thực hiện theo signed mapping.
5. Production integration được nghiệm thu riêng bằng real roles/session/source/migrations/tests/NFR measurements. Không sử dụng fixtures preparing hoặc fake receipts để claim real core flow hoàn thành.

Có thể giao coding agent **task cục bộ giới hạn** ngay với raw mappers/widgets/cache protocol/inbox adapter, nêu rõ pending API bindings và test-only fakes; không giao cả bốn màn với yêu cầu tự chọn DR01–04. Lượt hiện tại chỉ chỉnh sửa tài liệu, không coding các phần ready này.

[Decision Log](Technical_Decision_Log.md) • [Remaining Issues](Remaining_Issues.md) • [Remediation Report](Post_Audit_Remediation_Report.md).
