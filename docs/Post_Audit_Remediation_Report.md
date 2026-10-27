# Post Audit Remediation Report — MH07, MH08, MH09, MH17

Ngày 08/10/2026, revision 1.1. Đã sửa trực tiếp bốn Technical Specification hiện có; không tạo bộ đặc tả trùng. **5 finding FIXED, 3 PARTIALLY FIXED, 2 PENDING APPROVAL.** Toàn bộ bốn màn vẫn **NOT READY FOR IMPLEMENTATION end-to-end**, do shared contracts/owners chưa phê duyệt và runtime còn missing. Không sửa code, schema/migrations, cấu hình/dependencies, DOCX gốc hoặc hai audit reports lịch sử.

## 1. Input inventory và evidence boundary

| Input | Access và cách kiểm chứng |
|---|---|
| Nhóm 1_Docs.docx | Có thể đọc; hash original 04bf7c6428920741390588f5fa65737c5f878e1e77164ca7599c3b077633ed9c; DOCX extract 505 body blocks được đối chiếu lại các BR/CR/OR liên quan; giữ original nguyên byte |
| Four technical files | Main/data_API/tests/evidence đọc, đối chiếu audit locators và sửa tại chỗ; version1.1 |
| Independent audit + traceability | Đọc AUD01–10, correction/coverage/state scenarios, giữ nội dung lịch sử; không mặc định proposal của audit là approval |
| Codebase | Current SQL chain3migrations, shared docs,6Dart files, pubspec/lock/router/provider/theme; only `/` route, không business DTO/RPC/job/producers; source evidence không cloud deployment |
| UI07/08/09 | References từ source inventory/UI attachments, không thêm rules từ mock; MH17 vẫn Proposed Design |
| Full Business Report/minOS/NT exact | NOT VERIFIED; DOCX OR08 chỉ nhóm NT, không bổ sung giả wording/score |

Baseline repository HEAD 77b3623e863857237816752151067acae07f0d3d. Các path trong tài liệu relative project, các path mới chỉ PROPOSED. Source authority: business DOCX; implementation code; mock UI reference; remediation choices chưa signed là proposals. Baseline hashes được lưu trước mutation cho mọi file workspace ngoài generated build/.dart_tool/.git.

## 2. Finding-by-finding remediation

| Finding | Severity | Status | Correction / remaining gate |
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

Không đánh dấu FIXED cho AUD03/05/07 vì exact producer/error/projection fixtures phụ thuộc quyết định chưa ký. AUD01/02 được chuẩn bị decision records, không “resolved” bằng chọn recommendation. FIXED còn lại chỉ lỗi tài liệu cục bộ đã loại bỏ inconsistency, không ứng dụng PASS.

## 3. File/section delta và corrective evidence

| Existing file | Sections thay đổi | Bằng chứng/correction purpose |
|---|---|---|
| [Main spec](technical_specification_mh07_mh08_mh09_mh17.md) | §1 metadata; §7.2 receipt application; §9.2 event target draft; §12.2/12.5 cache/read epochs; §13.3 navigation + §13.4–13.6 sequences; §13.1/13.7 pending custody; §16 P4C/P5/P6; §19/history | CR07/08/09/BR36 consistent response ordering; BR32 typed target; OR05 dependency. No GPS/rebuy/voucher/OTP/new primary screen |
| [Data/API](technical_specification_mh07_mh08_mh09_mh17_data_api.md) | §3 nullable projection; §4.1–4.8 exact wire/role table; §5.2/5.3 normalized failure; OP-O08/OP-N04/05; §7.2 receipt gate; §8/8.1 candidate inspection; §9 full JSON; §10 gates | Exact existing21Order/11Item/9Notification fields; no ambiguous aliases; required-null instead omission. Full fixtures parse same field sets, error.current_order is reference. All aggregate/server maps remain PROPOSED DR04 |
| [Tests](technical_specification_mh07_mh08_mh09_mh17_tests.md) | T09-01/21–24; T17-24–27, §5.1 EV01–22; TX05/25–28; §7 explicit IDs/return mapping; §9 revision | Customer own API allowed != manager route; late receipts/read callbacks/stale state; all22event families planned; exact target/producers pending approval. No test PASS claim |
| [Evidence](technical_specification_mh07_mh08_mh09_mh17_evidence.md) | Opening scope, §7 historical label, §8 status/evidence map | Old review conclusion preserved as historical, audit verdict not rewritten; conflicts/assumptions remain pending and mapped to DRs |

New supporting files requested: [Technical Decision Log](Technical_Decision_Log.md), [Remaining Issues](Remaining_Issues.md), [Updated Implementation Readiness](Updated_Implementation_Readiness.md), file hiện tại. Không bản DOCX mới vì task yêu cầu kiểm soát Markdown artifacts.

## 4. Cross-document consistency review

| Concern | Main | Data/API | Tests | Decision/gate |
|---|---|---|---|---|
| Historical receipt outcome only | §7.2/12.5/13.4/13.5 | §4.3/4.8/7.3 | TX05/25/28 | Storage not selected DR01; local cache design fixed |
| Server auth before receipt replay, replay before state check | §13.4/13.5/14 | OP-O06–08/7.3 | T09-21–24/TX04/05/09/28 | DR01 + DR04 interfaces pending |
| Exactly one draft wire/schema, required-null | §10/12.2 | §4.6/4.7/5.3/9 | TX27/T09-21–24 | DR04 not approved; full raw fields verified |
| Typed events and independent read/navigation | §9.2–9.4/13.6 | OP-N04/05 | T17-23–27/EV01–22 | DR03 exact event×recipient targets pending |
| Custody/attempt/inspection source | §8.3/13.1/13.7 | OP-O07/8/8.1 | T09-07–14 | DR02 alternatives not executable |
| Roadmap dependency | P0→P1/P2→read UI→P4C→P5→P6→P7; P8 event integration follows gates | OP-O04/JOB then OP-O05–08 | Core and exception integration suites | OR05, no acceptance before confirm implementation |

Independent documentation reviewer gpt-5.6-sol / medium theo AGENTS.md đã đọc current artifacts và source, chỉ review không sửa file. Đã xử lý findings: P4C/P5 required core producers phải thực sự tồn tại trước core acceptance (P8 remaining producers); confirm không bắt buộc reason, reject có; bỏ unspecified capability reason codes khỏi exact draft; Customer confirmed_by=null trong safe aggregate và oracle T09-21. Không có approval contract mới từ reviewer.

Technical choices from audit were adjusted: no forced global registry; no automatic promotion of synced producer design; role privacy null fields explicit but pending signed allowlist; local epochs avoid inventing DB version. Original correct fee/reservation/max2/full COD/full return/separate lifecycles preserved.

## 5. Verification thực tế

| Check đã thực hiện | Kết quả | Giới hạn |
|---|---|---|
| Markdown file links + heading anchors / code fences | PASS: 8 updated/new documents, 43 relative internal links/anchors, no missing target/unbalanced fence | Không kiểm HTTP external link availability trong lượt này |
| JSON decoding | PASS: 10 fenced JSON blocks | Chỉ fixtures trong tài liệu; không API runtime |
| Full draft keysets/nullability/int money/FK sample totals | PASS: Order21keys, Item11keys, Notification9keys; list/detail/receipt/lookup đầy đủ; fee30.000, subtotal+fee, line price×qty/order relationship, exact10status counts | Non-null external-owner summaries chưa có signed fixtures, AUD03 vẫn PARTIALLY FIXED |
| Test ID uniqueness / references | PASS: 116 unique planned test IDs, không dangling explicit Test ID; traceability abbreviations expanded | Chưa thực thi unit/widget/integration/backend tests |
| Event family cross-reference | PASS: 22 main event-family rows ↔ EV01–22/T17-25, không mismatch event key | Exact role/fan-out/source/target fixtures DR03 chưa ký, AUD07 PARTIALLY FIXED |
| Dependency ordering | PASS: P4C core confirm/job/required persisted notifications trước P5 real core operations/producers; P6 remaining transitions, P8 remaining producers/MH17 | DoD chưa thực hiện, không acceptance trên mock preparing |
| Mermaid structural tool check | PASS chỉ control-block balance cho3sequence diagrams, 7 Mermaid source blocks có fences đầy đủ | Mermaid renderer/mmdc/package không có trong tools/runtime đã kiểm tra; full syntax/rendering NOT VERIFIED |
| Mermaid semantic/manual review | Đã đối chiếu7 diagrams với văn bản/state/API/permission/error branches; fixed replay/transport/read-failure/notification_only, navigation flow cũng tách own-content branch; pending custody alternatives gắn DR02 | Không tự gọi manual review là tool-rendered syntax PASS; DR02/DR03 vẫn còn approval gate |
| Duplicate/conflicting definitions | Rà exact keys, aliases, capability10bool, projection required-null, failure current_order reference, receipt cache application, event target, roadmap. Removed residual aliases/unspecified reason codes; review recheck4corrections không còn contradiction ở delta | Pending DR01–04 không được coi closed; không claim mọi future backend definition verified |
| Source evidence references | PASS source inspection: 32 existing inventory paths +23symbols in6Dartfiles/3migrations, business IDs recheck original DOCX505blocks/22media | PROPOSED paths/RPCs không phải existing-file checks; không cloud/runtime proof |
| Preservation boundary | PASS hash comparison: chỉ4existing spec docs thay đổi; mọi original source/migration/config/shared docs/audit files còn nguyên, DOCX SHA256 giữ nguyên; thêm đúng4requested docs | Generated build/.dart_tool/.git excluded khỏi content manifest; git status read-only được đối chiếu |
| Independent documentation review | gpt-5.6-sol / medium, read-only; xử lý4findings và recheck xác nhận4delta không còn contradiction | Reviewer không approve owner contracts, không test runtime hoặc certify full future implementation |


Các checks tài liệu không thay Flutter/app/backend tests. Không chạy flutter analyze/test/build, Supabase RPC, apply/reset migration, cloud query hoặc NFR benchmark. JSON validation không chứng minh real API response tương thích. Mermaid renderer chưa được xác nhận; kết quả cuối phân biệt tool check và manual review.

## 6. Priority và bàn giao nhóm

1. DR01 Orders/backend và impacted owners ký receipt/event protocol; DR02 Minh Đức/Inventory/Orders ký custody/task2/inspection.
2. DR04 signed exact aggregates/errors/role projections; DR03 producer fan-out/target/source/atomicity (với Returns/Chat/Delivery/COD/Checkout owners).
3. Auth session/routes/storage, return cutoff/owner APIs, server job deployment, identifier/image/shared UI baseline và authoritative NT/platform targets.
4. Sau approval cập nhật shared docs và toàn bộ sections/fixtures/diagrams/tests, re-audit compatibility trước production API adapters/actions. Local raw mappers/UI/read epoch/inbox adapter có thể bắt đầu với phạm vi hạn chế theo Readiness.

Danh sách còn lại không che giấu dependencies bằng fixtures hoặc phantom APIs. Không liên hệ/gửi thông báo tới thành viên nhóm; user dùng Decision Log để trao đổi/approval. Lượt remediation hoàn tất là hoàn tất edits/checks tài liệu, không tự đóng implementation blockers.

## 7. Revision hashes và preservation

| File | SHA256 trước remediation | SHA256 revision1.1 / preservation |
|---|---|---|
| `technical_specification_mh07_mh08_mh09_mh17.md` | `3bb914a362cf7efb5cebc70cf1a578080b4ab2b65929aeeba6e8915666256190` | `bed52bc9cd9ec85623170fce6c2798aca299840016a62405662e997f0a3e4adf` |
| `technical_specification_mh07_mh08_mh09_mh17_data_api.md` | `4d06ea533b7ea3d83f661b03adcbad7f38e990a282cf6408b7a9ff0ae2f31802` | `2fcc66217e9274a27797ae6f4480c35741c6ed36c97b9a9a4bf2d2ebcba910db` |
| `technical_specification_mh07_mh08_mh09_mh17_tests.md` | `e09345371a77023239c53dd7e3ba5dffad2f9b919a7ec71a97363d3d6baf2f46` | `194203d8756ba117f9e931d551ba60a99e90790d2a0c25bd0793551a2649e887` |
| `technical_specification_mh07_mh08_mh09_mh17_evidence.md` | `e32c63360a8babdc17617b17cceaf52c93d9f833284e486256842e184089f958` | `55b88e41457e1a4edc0b2dd304f5d93b77eb6f5dd8302566e973d9455e5dcd85` |
| `independent_technical_audit_mh07_mh08_mh09_mh17.md` | `060e13199d2366b7b732bdd9031f1161bc9061dd585a6d76885939b9b841f646` | `060e13199d2366b7b732bdd9031f1161bc9061dd585a6d76885939b9b841f646` (unchanged) |
| `independent_technical_audit_mh07_mh08_mh09_mh17_traceability.md` | `ffd748f5c1bc8a37762cd57b6f405ba8684c3a2a46e87e9e19309709cbfe3ebe` | `ffd748f5c1bc8a37762cd57b6f405ba8684c3a2a46e87e9e19309709cbfe3ebe` (unchanged) |


Baseline v1.0 + historical audit remain evidence in source hash register. Nội dung spec current revision không còn cùng hash với audit input; historical audit locators/line numbers áp dụng v1.0, dùng section locators cho revision1.1. Decision approval history chưa có entry mới.
