> Historical revision1.1 preserved. Current authority/status superseded by [revision1.2](Implementation_Readiness_v1.2.md); pending labels below describe the earlier snapshot, not new owner approval gates.

# Remaining Issues — sau remediation MH07/MH08/MH09/MH17

Revision 1.1, 08/10/2026. Đây là work/gate register, không claim feature đã triển khai. [Decision Log](Technical_Decision_Log.md) là nơi lựa chọn/owners/closure; [Readiness](Updated_Implementation_Readiness.md) là giới hạn coding. AUD status khác runtime status: FIXED = lỗi tài liệu đã sửa, không PASS ứng dụng.

| Issue | Classification | Scope / impact | Owner và điều kiện đóng |
|---|---|---|---|
| AUD-01 / DR-01 | BLOCKED BY TEAM DECISION | Mutation receipt namespace/persistence/fingerprint/lookup/retention/system identity; không viết production transition/recovery theo alternatives | Orders + backend + affected producer/Auth owners; signed record 10 criteria |
| AUD-02 / DR-02 | BLOCKED BY TEAM DECISION | Exceptional cancel/custody/second attempt/receive-inspection MH09; task2 state/quantity không đoán | Minh Đức + Inventory + Orders + Checkout; signed pickup/custody/quantity contracts |
| AUD-03 remaining / DR-04 | BLOCKED BY MISSING CONTRACT | Wire draft đã có keys; safe reason/timeline projection, error discriminant/signatures/role sanitization chưa agreed | Orders/backend/Auth + projection owners; exact approved allow/deny/error fixtures |
| AUD-05/07 remaining / DR-03 | BLOCKED BY TEAM DECISION | Event producers/fan-out/root-child identity/sync atomicity/typed targets; 22 event families planned, fixtures chưa approved | Notifications + tất cả producer owners; exact event×recipient contract, no old-assignee leak/double assignment alert |
| I01 / DR-06 | BLOCKED BY MISSING CONTRACT | Auth session/role change/login route/protected storage; mọi protected screen runtime | Dung An + shared router; API/signals/storage proof and switch/expired-session tests |
| I02 Checkout | BLOCKED BY MISSING CONTRACT | Placement/reservation transaction + committed snapshots/UUID refresh; end-to-end core | Văn Đức + Inventory + Orders; atomic placement contract/tests/source |
| I03–I05 / DR-02 | BLOCKED BY MISSING CONTRACT | Assignment/pickup/attempt/COD server operations + summaries | Minh Đức/Inventory; signed read/write boundaries và true test fixtures |
| I06 / DR-05 | BLOCKED BY TEAM DECISION | Return cutoff precise, eligibility/read/routes/summary | Sơn + nhóm; preview/submit boundary, active return and actual goods contracts |
| I07 Chat | BLOCKED BY MISSING CONTRACT | Conversation open/get/route/read visibility/support recipient events | Dung An + Sơn; one/customer authorized interface, text-only, separate read state |
| DR-07 | BLOCKED BY MISSING CONTRACT | Server job identity/schedule/overdue deployment và measurement | Orders/backend; no client timer/automatic assignee |
| DR-08 | BLOCKED BY UNAVAILABLE EVIDENCE | Full report/NT exact, signed minimum OS/QA devices | Nhóm/platform; authoritative document/version+acceptance source |
| Cloud/runtime test evidence | BLOCKED BY UNAVAILABLE EVIDENCE | Chưa apply/test RPC/migration/build/renderer trong lượt docs; source foundation không chứng minh deployed features | Implementation owners; isolated backend/device tests và explicit environment evidence |
| Raw entity mapping/money/time/status/UI async behavior | READY FOR IMPLEMENTATION | Có thể viết Orders/Items/Notifications mappers theo existing SQL, formatter/enum/local read-only widgets và unit fakes; chưa full screen runtime | Bảo; recheck baseline, reuse shared provider/theme; no invented APIs |
| Cache epochs/historical receipt behavior | READY FOR IMPLEMENTATION | Local ViewModel protocol §12.5 + test-only repo interface fixture; production receipt transport vẫn blocked DR01/04 | Bảo; no receipt cache-write, late response/refresh failure/account-switch unit tests |
| MH17 raw inbox/read_at adapter foundation | READY FOR IMPLEMENTATION | Existing own notification query/count/PATCH fields/grants/trigger; integration Auth/producer/target still blocked | Bảo; dependency-injected session/client, no demo success on API error; real permission checks later |
| Rebuy/call/mark-all/human-code/image/theme extras | OPTIONAL / POSTPONED | Rebuy/call/mark-all chưa baseline; code/image/theme là documented proposals cần approval khi khác current-safe UI | Scope/owner approvals DR09/10; không thêm voucher/GPS/push/online payment |

Không đánh đồng “READY FOR IMPLEMENTATION” của mapper/widget/local protocol với một màn hình hoàn chỉnh. Các hợp đồng missing có thể thiết kế/approve trước khi code; source/API runtime phải tồn tại để nghiệm thu integration, không buộc nhóm triển khai trước mới được quyết định thiết kế.
