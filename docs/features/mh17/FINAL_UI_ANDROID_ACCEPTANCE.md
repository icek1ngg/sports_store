# MH17 — Final UI & Android acceptance

Ngày 26/10/2026. **READY FOR USER UI ACCEPTANCE** trong phạm vi UI/client đã kiểm tra.
MH17 UI vẫn **NOT USER APPROVED**. Không xác nhận backend/production router hay full TalkBack audio PASS.

## Phạm vi và thiết bị

- Screen thật và providers/owners hiện tại; không refactor kiến trúc, không đổi business logic/theme.
- Pixel_5 `emulator-5554`, Android API35, 1080×2340, density440; APK debug mới từ working source.
- Launcher mới `tool/ui_preview/mh17_acceptance_main.dart` reuse `UiPreviewApp`, nhãn DEMO luôn hiện.
- F07 fixtures vẫn noncanonical; offset cursor và dữ liệu minh họa không phải backend/API evidence.
- [Build cuối](artifacts/final_acceptance/android_after_fix_build.log); [verification](artifacts/final_acceptance/verification.json).
- Lần build đầu lỗi Kotlin incremental cache; retry bằng project properties, không clean/xóa cache/đổi dependency.

## Kết quả thực tế

| Hạng mục | Bằng chứng và giới hạn |
| --- | --- |
| All/Unread | Android tap thật, selected state và empty riêng; widget/session regression PASS |
| Badge/read | Android fixture badge2→1 sau mark-read, head refresh; không backend mutation; exact count/99+ có tests |
| Tiles/pagination | Native tải page2, đọc hàng cuối; cuộn320dp/font2 tới cuối; retry/cursor/F02 có regression |
| Loading/error/retry | Android error; controlled Screen loading/error→explicit retry→empty PASS và có ảnh mới |
| Stale | Android cùng query refresh lỗi vẫn giữ rows, banner stale, read action bị gỡ; captured callbacks có tests |
| Navigation | Native báo mục tiêu chưa khả dụng khi Preview thiếu resolver/callback; typed positive/negative có tests, chưa production router |
| Context | Native notification_only, Close và Android Back; N07 account/cache/disposal/late/session-loss regression PASS |
| Session expired | Native scenario expired không còn rows/badge; A→B/late/first-frame/cache/modal privacy bằng automated tests |
| Responsive | Flutter12 tổ hợp320/360/390/412 ×1/1.5/2, long text + scroll-to-last PASS; Android12 ảnh cùng width/font settings |
| Accessibility | Widget48dp target/label guidelines và keyboard Tab→Space đổi Unread PASS; native filter/refresh132px/2.75=48dp |
| Theme | Inter/Barlow/MaterialIcons thật, không redesign; MH07/08/09/17 Preview theme tests PASS; shared theme/Orders source không sửa |

[Ảnh Android cuối](artifacts/final_acceptance/android/mh17_final.png),
[modal](artifacts/final_acceptance/android/final_context.png),
[stale](artifacts/final_acceptance/android/stale_retained.png),
[320/font2 cuộn cuối](artifacts/final_acceptance/android/narrow_large_scrolled.png).
[Android matrix](artifacts/final_acceptance/native_matrix.json) dùng DPR2, height844dp; chrome hệ thống/Preview chiếm phần chiều cao.
Font scale Android API35 không đồng nhất hoàn toàn với TextScaler.linear của widget tests.
Đã xem cả12 ảnh native matrix; không thấy overflow trong content MH17. Nội dung dài cần cuộn là chủ đích.
Một số ảnh lúc đổi font có chrome/clip tạm thời; ảnh settled cuối và cuộn320/font2 không còn hiện tượng đó.
Ảnh Flutter harness có debug banner; Preview/native debug banner tắt. Không coi banner harness là lỗi UI production.

## Lỗi được sửa tối thiểu

Cây accessibility Android xác nhận title/type tile bị ghép hai lần. Đã thêm ExcludeSemantics chỉ quanh hai Text đã có trong label cha.
Giữ nguyên hình ảnh, body/time, unread label, nút read riêng và gesture. Không đổi policy F05.
[Test tái hiện FAIL trước sửa](artifacts/final_acceptance/semantics_reproduction.log), test mới kiểm tra mỗi title/type đúng một lần và read không gọi open.
[Tree sau sửa](artifacts/final_acceptance/android_after_fix_tree.xml) xác nhận native label đã hết lặp title; APK đã rebuild/install lại.

## TalkBack và giới hạn

TalkBack15 có sẵn, đã bật/bind service; keyboard/input focus bằng Tab tới refresh đã quan sát, có tree và ảnh.
Service dump ghi touchExplorationEnabled=false; chưa chứng minh TalkBack accessibility focus/traversal.
Không có kênh nghe/đánh giá audio: phát âm tiếng Việt, đọc lặp bằng âm thanh, TalkBack traversal/gestures **CHƯA XÁC MINH**.
Đã khôi phục TalkBack tắt, font1, density/size gốc. Không đánh đồng widget semantics với TalkBack audio.
Native toolbar Preview không cung cấp trigger session-loss trong modal; ca này PASS bằng Screen/Navigator widget tests, chưa tái tạo manual Android.
Silent same-cache block cần signal/rebuild để render recheck; không tuyên bố polling có thể phát hiện mọi thay đổi bộ nhớ không thông báo.
Pending read-control tap có thể tới outer open, rapid opens không bị serialize: characterization hiện hành/F05, không đổi trong acceptance.
F03/F05/F07 vẫn pending; server RLS, backend mutations, production target permissions/router chưa được xác minh.

## Verification cuối

441 MH17 focused PASS (426 baseline +15 acceptance cases); Page/session89 + selected7 =96 PASS sau sửa.
Analyzer PASS; format/diff/links/protected SHA kiểm tra trong verification. Không sửa original assertions.
Ảnh/log mới dùng thư mục `artifacts/final_acceptance/`; mọi evidence cũ và approved working source ngoài allowlist giữ nguyên.
User quyết định nghiệm thu UI tiếp theo; không tự gắn USER APPROVED.
