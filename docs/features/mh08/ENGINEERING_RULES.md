# MH08 — Engineering rules

Áp dụng riêng MH08. Task hiện tại **MH08-03A**; MH08-01/02 đã được người dùng duyệt.
Page/state/components/test split trong namespace MH08; Preview/03B/04 vẫn ngoài scope.

## Scope và architecture

- Flutter + Riverpod, feature-first MVVM. Page compose; widget render và forward callbacks.
- Giữ models/DTO/repository signatures, `orderListFoundationProvider` identity và page API.
- Không gọi Supabase từ widget, không thêm API/SQL/backend/Auth/router production.
- MH07 đã APPROVED; không sửa UI/customer fixtures/behavior. Không chỉnh MH09/MH17.
- Reuse theme/formatters/async feed; card MH08 riêng qua hook `itemBuilder` đã tồn tại.
- Khi dùng hook phải truyền đầy đủ action/session/freshness/mutation gating; không infer permission từ status.
- Không duplicate models, formatters, state hay repository. Không thêm dependency nếu chưa cần.

## LOC hard limits

Đếm số dòng vật lý, gồm dòng trống/comment. Khoảng80% limit thì xem xét tách responsibility.

| Loại | Maximum LOC |
| --- | ---: |
| Page/coordinator | 300 |
| UI widget/section | 180 |
| ViewModel/controller | 250 |
| Repository adapter | 250 |
| Domain helper/formatter | 150 |
| Preview fixture | 250 |
| Test | 400 |
| Debug/utility script | 150 |
| Feature Markdown | 200 |
| HANDOFF | 100 |

- Không chia file tùy tiện hoặc giấu toàn bộ logic vào `part` để đạt số dòng.
- Trước sửa legacy: đo LOC, xác định responsibility, tách từng phần và chạy regression sau mỗi lượt.
- Page MH08 đã giảm768→288, main test480→122; mọi file mới/sửa03A phải tiếp tục giữ giới hạn.
- Shared legacy: feed436/card351/dialog204/theme254, fixture709, harness308, visual test654; chưa sửa ở MH08-01.
- Những số trên là inventory, **không phải exception đã duyệt**. Nếu buộc sửa file đó, tách an toàn hoặc xin quyết định.
- Không chỉnh generated/dependency, không refactor màn khác để kéo LOC xuống.
- Final report ghi LOC từng file mới/sửa và mọi vi phạm; không claim gate PASS khi còn vượt chưa duyệt.

## State ownership và lifecycle

- Read/session/cache ownership giữ foundation hiện có; state điều phối MH08 ở page/controller MH08.
- Controller nếu tách: query/debounce và pagination có trách nhiệm rõ, mỗi controller ≤250.
- Text/scroll controller và dialog lifetime có owner rõ; dispose timer/listener đúng chỗ.
- Giữ generation, canonical head, cursor dedup, invalid-cursor recovery, clear-private-data và capability recheck.
- UI xử lý loading/error/empty/stale; counts từ canonical server projection, không loaded rows.
- Scope preview ổn định trên Navigator; scenario đổi chỉ invalidate graph theo session generation.
- Không đọc deactivated WidgetRef/disposed container; kiểm tra mounted sau async và trước callback.
- Backend unavailable phải hiện unavailable; confirm/reject không báo success giả.

## Testing và task boundaries

- MH08-01: kiểm tra docs/links/LOC, reference viewport/fonts, source hashes; focused tests nếu chạy được.
- MH08-02: component tests; chưa sửa ViewModel nếu chưa cần.
- MH08-03A: page refactor/integration/test split; giữ search/filter/count/paging/session/capability.
- MH08-03B: Preview/fixtures/navigation, stable lifecycle + MH07 regressions.
- MH08-04: responsive matrix, interactions, screenshots cùng viewport; Android chỉ ghi PASS khi thật sự chạy.
- Final integration: `dart format`, `flutter analyze --no-pub`, `flutter test --no-pub`, `git diff --check`, LOC gate.
- Không sửa assertion để che fail. Không coi APK build là runtime/manual verification.
- Chạy focused tests trong mỗi task; full suite ở integration/final checkpoint.
- Approval do người dùng; không tự đặt APPROVED. Sau MH08 dừng, không chuyển màn/backend.

## Git safety và context

- Working tree dirty trước audit; bảo toàn thay đổi có sẵn. Không commit/push/reset/clean/checkout/merge.
- So sánh source với `artifacts/source_baseline.json`, không chỉ so với HEAD.
- Mỗi task có ID/goal/scope/allowed files/acceptance/verification trong README + HANDOFF.
- Preferred20–50k context; cố dưới60k; gần70k thì hoàn tất phần an toàn, handoff và dừng.
- Chỉ đọc README/HANDOFF/rules và source cần thiết; dùng rg/range reads, không dump cả repo/log.
- Không claim token usage chính xác khi môi trường không cung cấp.
- HANDOFF ≤100 LOC, cập nhật sau mỗi task; không lưu quyết định quan trọng chỉ trong chat.
- File source MH08 mới dùng thư mục `widgets/mh08/` / `view_models/mh08/`; chưa cần scoped AGENTS khi chưa tạo code.
