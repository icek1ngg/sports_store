# MH09-04B3 — Android runtime acceptance

Ngày 20/10/2026. **MH09-04B3 — RUNTIME VERIFIED WITH MANUAL CHECKS PENDING**.
Ngày 21/10/2026, user xác nhận: **"MH09 UI/Preview accepted at the current implemented scope."**
Không xác nhận backend end-to-end, real mutation success, full TalkBack audio/focus hoặc mọi native manual check PASS.
Backend/Auth/router vẫn thuộc owner bên ngoài; production/tests/Preview và evidence cũ được bảo vệ.

## Thiết bị và nguồn build

- Phát hiện lại Pixel_5 AVD, `emulator-5554`, Android API35, sdk_gphone64_x86_64.
- 1080×2340 portrait / 2340×1080 landscape, density440, DPR2.75; không phải HTML390/DPR1.
- Build mới từ working source04B2: `flutter run --no-pub --no-resident -d emulator-5554 -t tool/ui_preview/main.dart`.
- GRADLE_OPTS process-local: Kotlin incremental=false, compiler.execution.strategy=in-process.
- Build/install/launch **PASS**; package `com.example.sports_store`, version0.1.0/code1, targetSdk36.
- APK SHA256: `cb0fa351b4b0d754b7e9f92cef189094d51e28df5130304cd18a2e1e382894f5`.
- `sha256sum` installed base.apk khớp APK mới; sau emulator recovery vẫn khớp. Không tái dùng APK03B.
- [Build log](artifacts/visual_04b3/android_build_run.log), [provenance](artifacts/visual_04b3/build_provenance.json).
- [246 input hashes](artifacts/visual_04b3/source_snapshot.json), fingerprint working source `ac22b0b62af0c7d480046b1c2b68a04aa75ad4190a37e5eb41ccf7b056c428ad`.

## Kết quả thao tác runtime

Thao tác native bằng ADB touch/swipe/keyevent trên widget tree thật; không gọi Navigator trực tiếp.
Preview dùng fixture có nhãn DEMO, bundled Inter/Barlow; không Supabase/Auth production.

| Nhóm | Quan sát thực tế / phạm vi |
| --- | --- |
| Entrypoint | MH07 mặc định; selector MH08; card mở MH09 bằng full UUID; PASS cả sau cold recovery |
| Normal | UUID/status/timestamp; buyer khác recipient; 2 item snapshots; tổng1.960.000₫ đúng fixture |
| VA01–03 | Reject đọc rõ; headings hiện; hai nút normal cùng top và cao48dp; semantic flags kiểm tra tự động riêng |
| VA04 | Call/Chat cùng430×132px =156.36×48dp, gap8dp tại DPR2.75; disabled reasons rõ |
| VA05 | White rounded tiles; placeholder trung thực; name/variant/quantity/unit price/line total rõ, không ảnh catalog |
| Large | Cuộn thật tới item40 đầy đủ, sau đó COD/Returns/Timeline; hàng cuối không bị footer che |
| Long | Record9 tên/địa chỉ dài; font1/1.5/2 reflow, controls stack; cuộn tiếp được |
| Missing | Delivery/COD không có dữ liệu; không suy thành unassigned/uncollected; buyer thiếu vẫn giữ recipient |
| Lifecycles | Record5 Delivered; delivery thành công; COD shipper thu375.000₫, store0₫; Return Chờ duyệt riêng |
| Timeline | Sự kiện fixture thực + fallback được gắn nhãn; không sáu bước HTML giả |
| Capabilities | confirmOnly/rejectOnly/commandsDenied/exceptionalCancel hiển thị khác nhau; không suy từ status |
| External ops | Record3 operations: Phân công/Phân công lại disabled, dịch vụ chưa sẵn sàng; không mutation |
| Confirm | Modal đúng UUID; Tiếp tục trả unavailable; không success hay đổi status |
| Reject | Lý do rỗng bị chặn; lý do hợp lệ trả unavailable; đóng/mở lại rỗng |
| Cancel | Hủy ngoại lệ riêng; lý do rỗng bị chặn, hợp lệ vẫn unavailable |
| Error/retry | Error có Thử lại; tap khôi phục detail; PASS |
| Loading/stale | Refresh spinner/banner, actions disabled; hoàn tất800ms đọc lại; stale read-only |
| Privacy | expired/unauthorized/unresolved chặn dữ liệu riêng trong ảnh settled; không chứng minh mọi frame bằng ảnh |
| Account switch | Manager khác được authorize đọc lại; không coi việc manager mới thấy đơn là leak |

19 scene values đã chọn có sampling runtime; **không** phải19×mọi viewport/font hoặc mọi race manual.
Canonical/normal/large/missingDelivery/missingCod/emptyReturns/missingBuyer/loading/error/stale/expired/
unauthorized/unresolved/accountSwitch/confirmOnly/rejectOnly/commandsDenied/exceptionalCancel/operations.
Returns rỗng cũng quan sát ở pending/missingCod; emptyReturns trên record5 được chọn nhưng ảnh cuộn cuối chủ yếu là timeline.
Capability revoke khi dialog mở, late old-account response, same-frame deactivate và scope loss trong modal:
**automated regressions PASS**, không nhận là tất cả đã tái tạo bằng thao tác Android.
Call/Chat/COD/Return owner navigation chưa integrated trong Preview: unavailable/disabled, không có destination success runtime.
Callback ID contracts được automated regressions kiểm tra; không nhận đã mở owner module thật trên Android.

## Back và bàn phím — tách từng loại

| Kiểm tra | Kết quả |
| --- | --- |
| Header Quay lại | PASS, về MH08; hai chu kỳ giữ UUID query/filter cùng session |
| ADB KEYCODE_BACK trên route | PASS, chỉ pop MH09; query/filter còn, không thoát app |
| KEYCODE_BACK trên modal | PASS, đóng dialog; MH09 còn |
| KEYCODE_BACK khi IME mở | PASS, chỉ ẩn keyboard; dialog/reason còn |
| Native edge gesture qua ADB input swipe | PASS với navigation_mode2; về MH08, query còn |
| Physical finger gesture | **NOT VERIFIED**, không suy từ KEYCODE hoặc injected swipe |
| Canonical head/count refresh/cursor races | Automated Preview tests PASS; UI quan sát query/count, không đo số repository reads runtime |

Gboard LatinIME **docked thật portrait/font1**: full-width bottom, IME frame `[0,1507][1080,2340]`.
`mInputShown=true`, `mIsImeShowing=true`; field và Đóng/Tiếp tục trên keyboard, nhập/submit được.
[IME](artifacts/visual_04b3/android_reject_valid_docked.png), [unavailable](artifacts/visual_04b3/android_reject_unavailable_docked.png),
[Back chỉ ẩn IME](artifacts/visual_04b3/android_ime_back_result.png), [insets](artifacts/visual_04b3/ime_docked_display.log).
Không dùng synthetic viewInsets để kết luận docked IME.

## Font/orientation, TalkBack và giới hạn môi trường

Portrait font1/1.5/2 và landscape font1/1.5/2 đã chạy trên Android; header/full UUID/footer reflow.
Landscape2 scroll viewport rất thấp do debug bar/header/footer; cần gestures nằm trong body.
Một swipe trúng footer không cuộn; được giữ như raw attempt, không tính scroll PASS.
Landscape1.5 Reject dialog cuộn tới reason được, Đóng/Tiếp tục reachable trước IME.
Landscape + IME tiếp theo bị gián đoạn: **22:11:03 local Windows qemu host APPCRASH0xc0000005**.
[Windows events](artifacts/visual_04b3/emulator_host_events.json) xác nhận qemu-system-x86_64-headless.exe, không phải Dart stack.
STOP affected path; không sửa app. **Landscape+IME hoàn chỉnh / last-row landscape2 manual — NOT VERIFIED**.
Emulator cold recovery thành công; installed APK giữ nguyên SHA, MH07→MH08→MH09 hoạt động lại.

TalkBack bật bằng Android Settings → Use TalkBack → Allow, rồi tắt lại qua Settings → Turn off.
Service bound thực, touchExploration=true, thấy green focus ở Settings/DEMO/MH08 search.
Các capture cố focus riêng Back/recipient có transition/navigation nên không dùng làm PASS.
**FULL TALKBACK FOCUS/AUDIO — NOT VERIFIED**: chưa quan sát đầy đủ read order, heading announcement và audio VND.
Semantics tests có3heading riêng PASS; không đồng nhất với TalkBack âm thanh.
[Service](artifacts/visual_04b3/talkback_enabled.log), [green focus](artifacts/visual_04b3/android_talkback_next_focus.png).

Đã restore font1.0, autoRotation1/userRotation0, accessibilityEnabled0, Gboard và navigation mode ban đầu.
Enabled services từ `null` thành empty sau UI Turn off: đều không service hoạt động; không inject secure service setting.
[Before](artifacts/visual_04b3/device_before.json), [after](artifacts/visual_04b3/device_after.json).
AVD chạy headless cho acceptance; đã shutdown nhẹ sau restore, vì baseline chưa có Android device đang chạy.
User có thể mở Pixel_5 bằng Emulator UI hoặc dùng device thật cho manual checklist; APK mới còn trong AVD.
[Shutdown](artifacts/visual_04b3/emulator_shutdown.json); không đổi cấu hình AVD hoặc xóa dữ liệu.

## Regression và bảo toàn source

- Fresh baseline focused181 PASS; cuối focused **221 PASS**, full `flutter test --no-pub` **461 PASS**, không skip/weaken tests.
- Bao gồm MH07/MH08, K1 keyboard, component/page/action/session/owner/Preview navigation/scenarios, original04A/04B1/04B2.
- Original04A8/8,04B1 5/5,04B2 27/27; responsive matrix **15/15 PASS** là widget evidence, không native matrix15case.
- [Focused](artifacts/visual_04b3/focused_verified.log), [full](artifacts/visual_04b3/full_verified.log), [analyze](artifacts/visual_04b3/analyze_verified.log).
- Chạy ở exact-source isolated mirror để original audit fixed output không overwrite ảnh/log04A/04B1/04B2.
- Worker SDK attempt ban đầu không chạy xong; các log0byte `focused_221.log`/`full_461.log` không phải kết quả.
- Analyze no issues; diff/LOC/links/protected SHA xem [verification](artifacts/visual_04b3/verification.json).
- Không có Dart/source/test edits; Dart format changed files N/A. New PS/Node utility syntax checked.
- Baseline2992files;2990 protected unchanged, gồm MH07/MH08/MH09/Preview/shared/tests và toàn bộ old artifacts.
- PID4881 trước host crash; PID recovery xem [recovery](artifacts/visual_04b3/runtime_recovery.json).
- Không thấy app exception/overflow/deactivatedRef/disposedContainer trong hai log PID đã thu.
- [Log trước](artifacts/visual_04b3/runtime_pid.log), [log recovery](artifacts/visual_04b3/runtime_recovery_pid.log).
- Reboot mất buffer; log trước không bao phủ trọn phần font/TalkBack/cuối landscape. Không suy no-error cho mọi bước.

## Evidence và bàn giao user

[Manifest ảnh Android](artifacts/visual_04b3/runtime_manifest.json) chứa device/font/orientation/time/APK/source/image SHA.
Raw transition attempts giữ nguyên nhưng loại khỏi claim; actual XML banner ghi đè nhãn scene caller khi khác.
Product/payment/timeline capture đầu là **missingDelivery**, không gọi là canonical; nội dung snapshot vẫn đúng.
Helper sau recovery dùng unique XML path/chặn dump không hoàn tất, tránh đọc file dump cũ khi app đang boot.

- [Normal/contact/footer](artifacts/visual_04b3/android_normal_top_verified.png).
- [Products/payment](artifacts/visual_04b3/android_product_tiles.png).
- [Item40](artifacts/visual_04b3/android_item40_complete.png), [later sections](artifacts/visual_04b3/android_large_scroll_probe.png).
- [Independent lifecycles](artifacts/visual_04b3/android_delivered_lifecycles.png), [expired](artifacts/visual_04b3/android_expired.png).
- [Long font2](artifacts/visual_04b3/android_long_font2.png), [landscape2](artifacts/visual_04b3/android_landscape_font2.png).

Manual checklist còn lại sau acceptance UI/Preview trong phạm vi hiện tại:
1. Trên device ổn định: landscape/large text + docked Gboard; nhập lý do, scroll, submit unavailable, Close/Back/reopen.
2. TalkBack thực: nghe UUID/status/3heading/amount/disabled reasons; swipe focus đầy đủ, kiểm duplicate và privacy sau expiry.
3. Gesture Back bằng ngón tay: keyboard→dialog→route, đúng lớp, MH08 giữ query/filter.
4. User đã chấp nhận UI/Preview hiện tại; quyết định này không thay thế evidence cho các kiểm tra còn thiếu ở trên.
VA06/VA07 optional chưa triển khai; không backend mutations/RLS/concurrency acceptance; MH17-01 chỉ audit/docs.
