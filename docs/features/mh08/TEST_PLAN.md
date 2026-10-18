# MH08 — Test plan

Task hiện tại MH08-04B3,16/10/2026; fresh100 affected/276 full PASS. Android cases xem [ANDROID_ACCEPTANCE](ANDROID_ACCEPTANCE.md).
Baseline186 PASS/analyze PASS là lịch sử do người dùng cung cấp, cũng có log MH07 cũ; không tái gắn là lượt hiện tại.
Kết quả focused hiện tại xem Verification trong [HANDOFF](HANDOFF.md).
Phần audit/component lưu lịch sử01/02; kết quả page integration03A ở cuối tài liệu.

## Audit và existing coverage

| ID | Kiểm tra / expected | Status MH08-01 |
| --- | --- | --- |
| A01 | HTML viewport390×844, DPR1, scrollWidth390, fonts loaded | PASS |
| A02 | Đo physical LOC, liệt kê page/test/shared vượt ngưỡng | PASS |
| A03 | 7 feature documents, links hợp lệ, docs≤200/HANDOFF≤100 | PASS |
| A04 | Source/test/Preview/MH07 và HTML không đổi so với source baseline | PASS |
| E01 | Counts từ canonical page, không loaded rows | PASS |
| E02 | Loading/unavailable có presentation đúng | PASS |
| E03 | Search +10 statuses, cursor reset | PASS |
| E04 | Confirm/reject dialog validate; không dispatch mutation | PASS |
| E05 | Thiếu callback detail phải unavailable | PASS |
| E06 | Next-page fail giữ rows; lost-access clear rows | PASS |
| E07 | Invalid cursor reset head; identical refresh vẫn paging | PASS |
| E08 | Existing responsive test không exception | PASS |
| E09 | Legacy multi-screen Preview tests qua stable DI | PASS |

E01–E08 map `test/features/orders/presentation/pages/manager_orders_page_test.dart`.
E09 map `test/visual_refinement/preview_app_test.dart`, harness `preview_app.dart`.
E09 **không chứng minh** main.dart đang mở được MH08; main import harness MH07.
Lượt01: **13 tests PASS** cho2 file trên, không sửa assertions/source tests.

## Coverage hiện tại

W01–W04 (components) → C01–C10 bên dưới; S01–S06/I01–I04 (query/paging/access/actions) → D01–D10.
I05–I06/G02–G03 (Preview/navigation/unavailable) → P01–P12. Các group này PASS trong full276 lượt04B2.
G01: MH07 source/fixture hashes giữ nguyên và full suite gồm customer/visual/keyboard regressions PASS.
X01/X02: semantics UUID/labels, reflow và48px targets PASS widget tests; full TalkBack/focus/audio vẫn NOT VERIFIED.

## Responsive matrix — MH08-04B3 rerun

Mỗi ô gồm top/bottom scroll + exception check + ảnh đối chiếu tại logical viewport.

| Viewport | Scale1.0 | Scale1.5 | Scale2.0 |
| --- | --- | --- | --- |
|320×844|PASS|PASS|PASS|
|360×844|PASS|PASS|PASS|
|390×844|PASS|PASS|PASS|
|412×844|PASS|PASS|PASS|
|844×390 landscape|PASS|PASS|PASS|

Mỗi case kiểm tra Vietnamese dài, horizontal chips, SafeArea, keyboard, actions/footer không che nhau.
Expected: không RenderFlex overflow, không exception, list/actions còn truy cập bằng scroll.
04A baseline FAIL K1;04B1/04B2/04B3 rerun15/15 PASS, giữ nguyên audit assertions và evidence04A.

## Android manual

Checklist15 bước và lệnh chạy nằm trong [MANUAL_REVIEW](MANUAL_REVIEW.md).
Task01/02 chưa chạy Android Emulator; user sẽ review sau task04.
Không đổi approval từ NOT YET APPROVED chỉ vì tests PASS.

## Commands theo checkpoint

```powershell
flutter test --no-pub test/features/orders/presentation/pages/manager_orders_page_test.dart test/features/orders/presentation/pages/mh08 test/features/orders/presentation/widgets/mh08
```

Sau khi MH08-02 tạo widget tests, chạy thêm đúng thư mục MH08 được tạo.
Final MH08-04: format changed Dart files, analyze/full tests/diff-check/LOC gate; không thêm backend tests giả.

## MH08-02 — component checkpoint

**45 component tests + 10 existing MH08 page tests = 55 PASS**, không sửa page/test cũ.
Artifact xuất bản: [verification](artifacts/mh08_02_verification.json); focused/analyze .log giữ local theo .gitignore, không cần để chạy tests.
4 test files mới và helper nằm trong `test/features/orders/presentation/widgets/mh08/`.

| ID | Test group / expected behavior | Status |
| --- | --- | --- |
| C01 | Header Barlow typography/refresh; disabled semantics; scale2 reflow | PASS |
| C02 | Search controlled value/change/clear/filter/error; external value giữ focus/selection | PASS |
| C03 | KPI chỉ2 authoritative counts; null=`—` và semantic chưa có dữ liệu | PASS |
| C04 | Đủ10 enum + all; scroll/select/toggle; callback null không dispatch | PASS |
| C05 | Buyer account khác recipient; null/blank fallback, matching name không duplicate | PASS |
| C06 | Snapshot name/variant/quantity; placeholder, thiếu preview không fetch catalog image | PASS |
| C07 | Integer VND + COD pill, null summary unknown, collected status giữ nguyên | PASS |
| C08 | Typed warning message/semantics đúng một lần; empty shrink; không raw code | PASS |
| C09 | Confirm/reject chỉ callbacks; eligibility độc lập, freshness/enabled/busy/null khóa action | PASS |
| C10 | Busy state nhìn thấy trực tiếp; không phát callback khi disabled | PASS |
| C11 | UUID đầy đủ trong tooltip/semantics; server Hanoi time, không DH-ID giả | PASS |
| C12 | Detail callback + reason thống nhất với missing/enabled/busy gates | PASS |
| C13 | Controls/sections/card/actions 320/390 × scale1/2, Vietnamese dài, không overflow/exception | PASS |
| C14 | Existing MH08 counters/search/filter/dialog/paging/error/regression, 10 tests | PASS |
| C15 | Format, analyze, diff/LOC/source hash protection | PASS |

Chỉ scope component đã được kiểm chứng. Ma trận full-screen phía trên, page session races, navigation,
TalkBack trên thiết bị, screenshot fidelity và Android manual vẫn NOT RUN cho task02.
Review độc lập phát hiện busy visibility/disabled reason/KPI semantics; đã sửa và thêm assertions, rerun PASS.
Không có provider/query timers/repository/network trong components; chưa tích hợp vào page/Preview.

## MH08- 03A — page integration checkpoint D

Checkpoint A55 PASS, B55 PASS (extraction/legacy UI), C70 PASS (integrated), D **246 full tests PASS**, analyze sạch.
Delta03A: giữ45 component +10 page cases cũ, thêm7 coordinator +8 integration cases =70 focused.
10 tên/cases cũ và business assertions giữ nguyên; chỉ cập nhật finder theo component composition.

| ID | Coverage thực sự đã chạy | Status |
| --- | --- | --- |
| D01 | 10 legacy cases split: render/loading/responsive, query/filter, actions, paging/access failures | PASS |
| D02 | Immediate editing,350ms debounce/trim/clear, Unicode201 không query, timer cancellation | PASS |
| D03 | Canonical counts/asOf không bị extra pages overwrite; stale khóa freshness | PASS |
| D04 | UUID dedup, duplicate cursor prevention/force retry, invalid cursor reset head | PASS |
| D05 | Old query/session head/next response bị bỏ; private failure clear rows/counters/cursors | PASS |
| D06 | Page provider wiring render components thật, capability false không mở dialog | PASS |
| D07 | Exact UUID navigation, không callback thì unavailable | PASS |
| D08 | Dialog source invalidation/expiry fail-closed, không disposed/deactivated WidgetRef exception | PASS |
| D09 | Full suite gồm MH07/customer visual-layout/keyboard/session regressions | PASS |
| D10 | Format/analyze/diff/owned LOC/source-protection checks | PASS |

Files: main test (render/loading/responsive); `pages/mh08/manager_orders_query_test.dart`, `actions_test.dart`,
`pagination_test.dart`, `manager_orders_coordinators_test.dart`, `manager_orders_integration_test.dart`, `mh08_page_test_support.dart`.
Full suite chạy `flutter test --no-pub --reporter expanded`, opt-in PNG output tắt; không sửa fixtures hay assertions màn khác.
Device TalkBack/manual, Preview entrypoint/return-refresh, backend connectivity và visual approval vẫn NOT RUN trong03A.
Không dùng kết quả246 để gọi baseline186 cũ là current count;03A total246,03B total265.

## MH08-03B — Preview checkpoint

`test/ui_preview/mh08_*`: **19 PASS** (8 repository +2 smoke +6 lifecycle +3 query/navigation).
`flutter analyze --no-pub`: sạch; full `flutter test --no-pub --reporter expanded`: **265 PASS**, gồm MH07 regressions.
PNG output tắt bằng `UI_VISUAL_OUTPUT=0`; không ghi đè assets approved.

| ID | Expected / thực sự đã kiểm tra | Status |
| --- | --- | --- |
| P01 | main thật default MH07; MH07→MH08→MH07 giữ một ProviderContainer, đúng role | PASS |
| P02 |10 rows/page3, query limit/cursor scoped, không duplicate, counts search-wide bỏ status | PASS |
| P03 | Full UUID/account normalized; partial UUID/product/recipient không match | PASS |
| P04 | Snapshot/COD/timeline/asOf nhất quán; failed typed warning, nullable projections | PASS |
| P05 |8 scenarios; loading800ms trước data, stale notice, private UI clear khi mất quyền/session | PASS |
| P06 | Lặp confirm/reject; blank reason blocked, submit unavailable, expiry khi modal mở fail-closed | PASS |
| P07 | MH09 exact UUID/stable scope; pop thêm1 canonical read, không thêm cursor request | PASS |
| P08 | Pop giữ editing/search/status và refresh exact family query; detail accepted invalidation giữ nguyên | PASS |
| P09 | Delayed list/detail response sau scope expiry/unauthorized không khôi phục private data | PASS |
| P10 | Next-page error giữ rows; retry nhận6 UUID unique, không đếm widgets lazy thành loaded rows | PASS |
| P11 | Format/analyze/diff/LOC;145 protected source hashes giữ nguyên, main là existing delta duy nhất | PASS |
| P12 | Android emulator: default/switch/search/clear/chips/pages/dialogs/navigation/scenarios/logcat | PASS |

Android P12 là runtime smoke trên Pixel5/API35 emulator, không phải visual acceptance/full responsive matrix.
Dialog expiry + delayed-response races kiểm chứng bằng widget tests, không claim đã thao tác các race đó bằng tay.
Android TalkBack, full320–412/landscape/text scaling và so ảnh viewport390×844: NOT RUN trong03B, dành04.

## MH08-04A — visual audit checkpoint

Fresh evidence: [VISUAL_AUDIT](VISUAL_AUDIT.md), `artifacts/visual_04a/`; HTML/Flutter390×844 font-loaded, DPR1.
Production UI/source, Preview03B/MH07 fixtures và HTML không thay đổi.

| ID | Thực sự đã chạy / expected | Result |
| --- | --- | --- |
| V01 | Fresh Chromium HTML + Flutter integrated page top/card/middle/bottom/dialogs/keyboard/states | PASS evidence |
| V02 |15 viewport/scale cases: no overflow/exception, pages10, chip gesture, long buyer/address,48px actions | PASS checks |
| V03 |15 cases SafeArea bottom + feed/footer tránh keyboard300 | PASS checks |
| V04 |15 cases KPI/total ẩn khi keyboard inset>0 theo UI_SPEC | FAIL K1/P1 |
| V05 | Reference390 state/dialog/geometry test | FAIL cùngK1;4 state captures đúng |
| V06 | Existing Preview19 + MH08 page/coordinator/component70 |89 PASS |
| V07 | Analyze/format/diff/physical LOC/protected hashes | PASS |
| V08 | Android Pixel5/API35 search/clear/chip scroll/pages/dialogs/MH09/back/scenarios/privacy/logcat | PASS smoke |
| V09 | TalkBack labels/keyboard focus sample, service bound rồi restore | PARTIAL; full swipe order/audio NOT VERIFIED |
| V10 | Android docked keyboard300/full responsive device matrix | NOT RUN; IME toolbar nổi, widget inset được kiểm tra |

Trong04A hai audit tests FAIL K1;04B1 đã PASS, không đổi assertions hoặc artifacts04A.
265 full-suite PASS là lịch sử03B; không fresh full rerun trong04A. Không claim full suite hiện tại xanh khi K1 còn mở.
Harness-only fixes đã loại import/I/O/query timing/hidden-chip gesture lỗi; không coi chúng là defects production.
Lệnh audit: `MH08_04A_OUTPUT=1`, chạy2 file `mh08_04a_{matrix,evidence}_test.dart` dưới `test/visual_refinement/`.
04A recommendation được thực hiện riêng ở04B1; P2 còn lại dành04B2, chờ duyệt.

## MH08-04B1 — K1 fixed
Root cause: Scaffold consume viewInsets trước controls; lấy bool visibility ở ancestor trước Scaffold.
Fix: Mh08KeyboardVisibility truyền derived bool, controls hide/restore KPI+total; Scaffold resize đúng1lần, SafeArea giữ nguyên.
Original2 audit tests: red2FAIL → green2PASS,15cases; không sửa test/source/evidence04A.
New2 lifecycle tests PASS:15 open/close/reopen cases, query/status/counts + pagination/read count không reset.
89 affected regressions PASS; fresh full suite **269 PASS**, analyze/format/diff/LOC/hash PASS.
Android APK chạy được; Gboard floating/toolbar, docked inset **NOT VERIFIED**. Không dùng floating làm bằng chứng docked.
Files LOC: layout74/180, controls65/180, lifecycle test274/400.290 protected baseline files giữ nguyên hash.
K1 đóng; P2 density vẫn mở. DỪNG04B1, chờ người dùng cho phép04B2; UI NOT YET APPROVED.

## MH08-04B2 — visual density checkpoint

| ID | Expected / thực sự đã chạy | Result |
| --- | --- | --- |
| R01 | Baseline components trước sửa; fonts-loaded390 card580h/y318 |45 PASS + renderer1 PASS |
| R02 | Buyer/recipient/address/phone,2 snapshots/variants/quantities/full UUID giữ nguyên; aggregate chỉ1lần | PASS |
| R03 | Tất cả10 status ở390/scale1 và320/scale2; decision/details≥48; existing disabled/busy/fresh gates | PASS |
| R04 | Canonical filtered total không thay All count; unknown không=0; keyboard hide; controls48px/reflow |3 new PASS |
| R05 | Original K1 audit2/15matrix + keyboard lifecycle2; query/status/pages/privacy/navigation | PASS |
| R06 | Real Preview font-loaded render390/320scale2/landscape; card476<580, full warnings/long content |1 new PASS |
| R07 | Affected page/components/Preview/original audits/new renderer |100 PASS |
| R08 | Full suite gồm MH07; analyze/format/diff/physical LOC/protected SHA-256 |276 PASS; gates PASS |
| R09 | Android/docked IME/full TalkBack ở04B2 | NOT RUN;04B3 |

3 card assertions mới ở `mh08_order_card_test.dart`;3 controls tests ở `mh08_density_controls_test.dart`.
Renderer: `test/visual_refinement/mh08_04b2_visual_test.dart`; `MH08_04B2_OUTPUT=1`, `MH08_04B2_PHASE=refined` để ghi ảnh riêng.
Reports/ảnh: `artifacts/visual_04b2/`; default output tắt, không ghi đè04A. Baseline320 sai DPR bị excluded; refined320 valid.
Chiều cao do renderer load fonts thật đo, không dùng Ahem để so với baseline fonts; không sửa original K1 tests.
