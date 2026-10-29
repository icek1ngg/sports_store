# MH08 — Git milestone19/10/2026

Người dùng đã chốt MH08 và yêu cầu commit/push trước khi bắt đầu MH09.
Approval hiện tại: **MH08 — USER APPROVED**. Không triển khai thêm MH09/MH17/Phase3.
Nhánh xuất bản: `feature/orders-notifications-phase2`, remote `origin`.

## Phạm vi xuất bản

- MH08 page/coordinators/components, tests, Preview manager fixtures/navigation.
- Feature docs, HTML reference và evidence01–04B3; giữ nguyên evidence lịch sử.
- `tool/ui_preview/main.dart` chọn Preview hiện tại, mặc định vẫn MH07.
- Shared `order_feed.dart`: chỉ hunk default horizontal padding16→20; MH07 truyền padding riêng.
- `manager_order_details_page.dart`: baseline hiện hữu cần cho MH08→MH09→Back; không chỉnh UI.
- `notification_interaction_view_model.dart`: baseline hiện hữu mà MH17 trong HEAD đã import nhưng chưa track.
  Thêm file nguyên trạng để đóng dependency compile; SHA-256 khớp các manifest MH08 trước đó.
- Không đưa dirty patches notifications, shared card/detail styling hay legacy multirole Preview vào commit.

## Kiểm tra snapshot trước commit

Snapshot được tạo từ Git index bằng `git write-tree`/`git archive`, không checkout/reset working tree.
Dependency dùng lockfile hiện có với `flutter pub get --offline`; không nâng package.
Đã chạy ngày19/10/2026 trên snapshot, không dùng kết quả working tree có thêm patch ngoài phạm vi:

| Kiểm tra | Kết quả |
| --- | --- |
| flutter analyze --no-pub | PASS, No issues found |
| MH08 components/page/coordinators/Preview/audits/lifecycle | 100 PASS |
| Original K1 responsive matrix | PASS,15/15 viewport/scale cases |
| Full flutter test --no-pub | 232 PASS,1 FAIL ở MH17 |
| MH17 failure chạy riêng | Reproduced: pending retry timer sau dispose |
| git diff --cached --check | PASS |
| Protected working source hashes | 166/167 nguyên trạng;1 utility chỉ xóa blank EOF |

Failure: `test/features/notifications/presentation/pages/notifications_page_test.dart`,
case `polling pagination refreshes the canonical head page`.
Page/test MH17 trong snapshot là bản HEAD; các dirty fixes MH17 không thuộc milestone này.
Không sửa/skip/weaken assertion để có full-suite xanh. Theo dõi riêng trong task MH17.
Kết quả276 PASS tại04B3 là lịch sử trên working tree rộng hơn, không phải snapshot xuất bản này.
Không chạy lại Android trong task Git; xem [ANDROID_ACCEPTANCE](ANDROID_ACCEPTANCE.md) cho evidence16/10.

## LOC và bảo vệ working tree

MH08-owned files vẫn trong giới hạn: page288/300, controller238/250,
widgets≤180, tests≤400 (largest399), docs≤200, HANDOFF≤100.
Hai baseline dependency ngoài ownership MH08: details page578LOC, notification VM455LOC;
được đưa nguyên trạng, không claim chúng đạt giới hạn code MH08 hoặc refactor ngoài scope.
Utility `mh08_04a_html_reference.cjs` chỉ bỏ blank EOF để diff-check sạch.
Không sửa source MH07, providers/domain/router/backend hay các dirty patches ngoài milestone.
Không force-push/merge/reset/clean/stash/switch; file untracked ngoài scope được giữ lại.

## Handoff

[README](README.md), [HANDOFF](HANDOFF.md), [MANUAL_REVIEW](MANUAL_REVIEW.md).
Docked Android IME/full TalkBack vẫn NOT VERIFIED; approval không đổi giới hạn này thành PASS.
Chỉ bắt đầu MH09 khi người dùng giao task tiếp theo.
