# MH17 — Manual review và acceptance checklist

Ngày 21/10/2026. **AUDIT READY FOR PLAN REVIEW; MH17 NOT USER APPROVED**.
Task01 không launch Android/Preview, không sửa production/tests/Preview và không tạo Flutter visual comparison mới.

## Reference đã xem

- [Original HTML](../../ui_mocks/MH17_Notifications.html), source SHA trước/sau trùng.
- [Fresh primary390×844/DPR1](artifacts/html_reference/primary_390x844.png).
- [Fresh full page390×1243](artifacts/html_reference/full_page_390.png).
- [Manifest](artifacts/html_reference/render_manifest.json): Chromium155, seven font specs loaded, no request failure, images0.
- [Historical Flutter360/text1](../../visual_refinement_artifacts/mh17_360_s1_0_top.png) đã xem để hiểu working conventions.
- [Historical manifest](../../ui_review_artifacts/render_manifest.json) và prior images vẫn giữ nguyên; không xác nhận khớp current source.

Historical Flutter image cho thấy AppBar/badge99+, All/Unread/refresh, wrapped cards, explicit mark-read, Hanoi timestamps.
Ảnh có fixture/type/content khác HTML; không pixel-compare historical360 với fresh HTML390 hoặc gọi đây là Android evidence.
Current implementation được audit bằng source và67 test mới; current Flutter screenshot fidelity **NOT VERIFIED**.

## Quan sát visual và policy conflicts

| Quan sát | Phân loại / xử lý đề xuất |
| --- | --- |
| HTML header “Don Hang”, cart/avatar, bottom Đơn hàng selected | shell reference; không thêm routes hoặc copy header title vào MH17 |
| “Đọc tất cả” + JS đếm unread dots | unsupported business behavior; production hiện đúng khi không có nút |
| Cần duyệt/Đang giao/COD metric strip | dashboard-like content ngoài MH17 contract; không implement |
| Categories orders/shipping/returns/system | không query contract; giữ All/Unread |
| HTML card radius computed0 vs Flutter16 | visual discrepancy cần plan decision, không tự replace tile |
| HTML body clamp2 vs Flutter full wrap | giữ khả năng đọc; nếu truncate tương lai cần full accessible context |
| Relative labels/hardcoded “Vừa xong” | không canonical timestamp; giữ Hanoi formatter và truthful freshness |
| “hỏa tốc”, “không vừa kích cỡ”, auto phân tuyến | fixture text trái/ngoài business scope; không dùng làm canonical fixtures |
| HTML không empty/error/loading/load-more state | future Flutter captures từ contract, không fake HTML comparison |
| Tile parent+child semantics | actual TalkBack duplicate/focus/audio chưa được nghe, cần manual check |

Không có kết luận UI MH17 defect đã tái tạo trên Android. Static risks F02/F03/F05 xem SOURCE_AUDIT.

## Runtime/production limitations còn mở

- Repository/resolver defaults null; session unresolved; router chỉ root: chưa có live notifications route.
- No verified real list/count/mark-read response, source producer event hoặc target navigation success.
- Typed mapping consumer có nhưng positive/negative coverage chưa đủ mọi role/subject.
- Preview reference fake inbox dùng demo data và offset cursor; không canonical server pagination.
- Fake rows reuse event/recipient và notification_only subject chưa bằng eventId; không dùng làm producer acceptance fixtures.
- Current `tool/ui_preview/main.dart` chạy Mh08PreviewApp, không có launch claim MH17 từ entry này.
- No fresh Android build/install/rotation/native Back/TalkBack/focus/contrast/tap-target measurements trong task01.
- No≤5s freshness/real multi-account network/SQL allowed-denied/concurrency verification.
- MH09 acceptance chỉ current UI/Preview; backend/Auth/router external, full TalkBack và native manual gaps chưa đóng.

## Checklist cho user/engineer ở task sau

- [ ] Review scope: title/badge/All-Unread/cards/read action/count theo contract, không metrics/categories/mark-all.
- [ ] Review same-viewport current Flutter vs HTML các region được chọn; ghi intentional deviations.
- [ ] Long title/body/timestamp/type wrap đúng, không overflow320/360/390/412 và text1/1.5/2.
- [ ] Empty all khác empty unread; loading/error/retry/stale/loadmore rõ, không count0/success giả.
- [ ] Read chưa ack vẫn unread/count cũ; ack canonical reload; read fail vẫn cho navigation authorized.
- [ ] Typed targets đúng business ID/current role; unsupported/missing/denied ở MH17 với generic message.
- [ ] Account switch/logout/expiry: không frame row/badge/context/pending/private IDs từ account cũ.
- [ ] Late old-session futures không publish; rapid repeated navigation không mở trùng/route sai account.
- [ ] Native Android font/orientation/Back/tap/scroll/cutout và last-row reachable.
- [ ] TalkBack thực: read order/exact count/unread state/selected filter/time/pending/retry/Close; kiểm duplicate audio.
- [ ] Backend owners cung cấp verified reads/ack/RLS/current-target permission và safe producer payloads riêng.
- [ ] User quyết định MH17 acceptance sau evidence task phù hợp, không đánh dấu trong audit01.

Checklist chưa thực thi để trống; HTML/font render và67 focused PASS không tự check các mục runtime.
