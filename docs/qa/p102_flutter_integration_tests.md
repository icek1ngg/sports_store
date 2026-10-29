# P10.2 — Flutter widget/provider/integration QA

Ngày 28/10/2026. Chỉ tests và biên bản QA. Không thêm business action hoặc
thay runtime/RPC/RLS/dependencies/router. Thay đổi P10.1 đang có được giữ riêng.

## Files P10.2

- Thêm `test/features/deliveries/integration/outbound_cod_flow_test.dart`:
  transport HTTP fixture được gắn nhãn, dùng Supabase repositories/providers và
  pages production trong cùng container. Prewarm COD uncollected/held=0 → MH11
  xác nhận đủ hàng/550.000 → authoritative refresh MH10 → held COD=550.000 →
  đổi session sang manager/MH12 full receipt → trở lại shipper/tab reconciled/
  held=0. Không override repository để trả fake production success. Fixture
  vẫn là mô hình offline, không chứng minh transaction database.
- Thêm `test/features/deliveries/integration/outbound_failure_return_flow_test.dart`:
  production shipper repositories/providers + HTTP fixture, fail1 → manager
  retry boundary → task2 cùng holder → accept/start/fail2 → report handover.
  Đổi shipper sau custody bị từ chối, task/list sau failed đều che destination,
  không gọi COD/receipt/restock. Manager RPC response là fixture boundary,
  không tuyên bố MH09 đã chạy production.
- Mở rộng `test/features/deliveries/redelivery_widget_test.dart`: hai stateful
  composition tests từ assigned qua ba dialog/action và authoritative reads
  tới success hoặc manager_action_required. Giữ read pending ở từng bước để
  chứng minh UI không chuyển trạng thái từ ACK/optimistic state; exact items,
  UUID request khác nhau, legal buttons và zero-COD UI. Bảo toàn tiền/attempt
  do SQL suite chứng minh, không dùng counter bất biến trong fake làm bằng chứng.
- Mở rộng `test/app/router/operational_navigation_test.dart`: hai test
  **TEST-ONLY MH17 handoff** tới task/map. Sau khi đã đọc contact có quyền,
  mở fixture link cũ sau thu hồi → fresh task UUID read → redirect `/`, không
  MH11/MH18 outlet/PII. Không dựng lại màn, resolver hoặc repository của Bảo.
- Tài liệu: biên bản này và liên kết `docs/screen_mapping.md`.

## Coverage hiện có đã chạy lại

| Khu vực | Tests chính | Trạng thái/phạm vi |
| --- | --- | --- |
| Mapper/null/money/time/DTO allowlists | delivery_mapper_test, delivery_task_details_test, delivery_map_missing_coordinates_test, cod_mapper_test, cod_collection_page_test | Có kiểm malformed/null/range, integer VND, timestamps và restricted snapshots. |
| Repository/provider/session | delivery_repository_test, delivery_provider_test, cod_repository_test, cod_provider_test, cod_read_refresh_test | RPC/body thật qua SDK transport fixture; session đổi/denied/stale/network, không fallback dữ liệu giả. |
| MH10 | delivery_task_list_page_test, delivery_task_list_view_model_test, delivery_task_query_test, delivery_task_list_navigation_test | Loading/empty/error, ba kind, combined search/filter, pagination/counts server-side, query race và giữ filters khi quay lại. |
| MH11 outbound | outbound_task_actions_*, outbound_completion_*, outbound_failure_*, delivery_reporting_* | Role/state buttons, confirmation, full 550.000, timeout giữ request ID, conflicting actions, refetch/caches. |
| MH11 pickup | return_pickup_repository_test, return_pickup_production_test, return_pickup_widget_test | Collect exact plan → handover report đã có composition test; no COD/outbound cap, privacy và denied/error. |
| MH11 redelivery | redelivery_repository_test, redelivery_state_test, redelivery_widget_test | Assigned → accept/refetch → start/refetch → success/fail/refetch; free/zero COD, no outbound cap. |
| MH12 | shipper_cod_*, manager_cod_*, cod_receipt_repository_test | Own scope, manager filter mới, two groups, held total, full receipt, duplicate taps, role/account switch và retry ID. |
| MH18 | delivery_task_map_*, map_* | Marker tọa độ lưu, nullable-location text fallback, tile/launch failures, call chỉ dialer, copy recheck, pause/resume/late response/assignment/session revocation. |
| Deep links | operational_navigation_test, delivery_task_detail_navigation_test | Roles/UUID/unsafe redirects, task/map denied, pop recheck, logout, revoked fixture notification target. |

Các test có hậu tố fixture và transport mocks là offline acceptance của
composition/contract; không đồng nghĩa Auth/JWT/RLS, stock/transaction production.
P10.1 SQL QA trước đó giữ bằng chứng database, không chạy lại rồi ghi là Flutter.

## Lệnh và kết quả

```powershell
dart format test/features/deliveries/integration/outbound_cod_flow_test.dart test/features/deliveries/integration/outbound_failure_return_flow_test.dart test/features/deliveries/redelivery_widget_test.dart test/app/router/operational_navigation_test.dart
flutter analyze --no-pub
flutter test --no-pub test/features/deliveries/integration test/features/deliveries/redelivery_widget_test.dart test/app/router/operational_navigation_test.dart
flutter test --no-pub --concurrency=1
flutter build web --no-pub
git diff --check
```

- Format PASS; analyze **No issues found**; composition bundle **27 PASS**.
- Full suite tuần tự: **1.450 PASS / 4 opt-in skipped**, exit 0 sau 7 phút
  15 giây. Đây là kết quả chạy lại cuối cùng, không cộng số partial của lượt OOM.
- `flutter test --no-pub` mặc định đã thử nhưng **FAIL do Dart VM Out of
  memory** khi chạy cùng build/live runner; một số preview/visual cases không
  hoàn tất. Log `supabase/.temp/p102_full.log`. Không sửa màn Bảo để né lỗi;
  chạy lại riêng với concurrency=1, log `p102_full_serial.log`.
- Web build **PASS**, `build/web`; warning CupertinoIcons có sẵn, không thêm
  dependency ngoài scope để che warning. Log `p102_web.log`.
- `flutter devices`: Windows/Chrome/Edge; không có Android kết nối. Widget
  runner không phải chứng minh phone dialer/maps app hoặc OS recents thực tế.

## Các lượt live đã thực thi trong P10.2

Project cấu hình `bqoyfytmrtvjwrpshuhh`; chỉ Auth accounts/rows fixture có UUID
riêng. Service-role credential chỉ ở memory cho Auth Admin, không đưa vào
Flutter/source/log. Flutter dùng publishable key + JWT người dùng kiểm thử.
Không reset DB, deploy migration hay sửa dữ liệu người dùng sẵn có.

| Lệnh thực tế | Kết quả |
| --- | --- |
| `node supabase/tests/run_live_outbound_ui.mjs --live --complete` | **PASS**: UI MH11 accept/start/completion, authoritative MH10 và held COD 550.000; replay, wrong shipper, một result/event. Cleanup PASS. |
| `node supabase/tests/run_live_outbound_ui.mjs --live --complete --cod` | **PASS**: COD prerequisite được tạo bằng RPC outbound thật; MH12 UI shipper/manager, own scope, >100 records/pagination/counts, full receipt/lost ACK retry cùng key, manager race, account isolation, refund independence. Cleanup PASS. |
| `node supabase/tests/run_live_pickup_handover.mjs --live --ui --redelivery` | **PASS**: actual pickup UI collect/handover, manager receive/inspection primitives, redelivery UI accept/start/success; không COD mới hoặc đổi tồn gốc. Cleanup PASS. |
| `node supabase/tests/run_live_pickup_handover.mjs --live --ui --redelivery --redelivery-failure` | **PASS**: cùng prerequisite chain, redelivery UI thất bại giữ manager_action_required/custody; COD/tồn không đổi. Cleanup PASS. |

Bốn opt-in test files đã được thực thi qua **6 lượt widget real-network**
ở các runner trên; default offline suite skip bốn files là đúng cấu hình,
không coi skip là PASS. Hai runner pickup còn kiểm wrong shipper/manager denial,
exact ACK/concurrent replay và event/notification deduplication. Runner báo
Node DEP0190 về child shell launch; command/flags đều cố định, credential không
được chèn vào argv. Không sửa runner ngoài phạm vi tests mới để che warning.

Logs ignored: `p102_live_mh11_completion.log`, `p102_live_outbound_cod.log`,
`p102_live_redelivery_success.log`, `p102_live_redelivery_failure.log` dưới
`supabase/.temp/`. Mỗi runner exit 0 và đã báo cleanup fixture accounts/rows.

## Những phần không được coi là hoàn tất liên nhóm

1. **MH17 production wiring còn chặn.** `notificationRouteBuilderProvider`
   ở central router mặc định null; `notificationRepositoryProvider` và
   `notificationTargetResolverProvider` mặc định null;
   `featureSessionScopeProvider` mặc định unresolved. `main.dart` chưa bind
   chúng. Cần Bảo/Dung An phối hợp builder, trusted session scope, repository,
   typed target resolver và central navigator. Test mới chỉ nghiệm thu
   destination guard có quyền của Minh Đức bằng fixture handoff rõ nhãn,
   không claim đã nhấn thông báo production thật.
2. **Chuỗi failed outbound liên nhóm.** Luồng provider/SDK fixture đã chạy
   fail1 → task2 cùng holder → fail2 → shipper report. Thay shipper sau nhận
   hàng phải bị chặn theo contract đã chốt, không thay chính sách để khớp
   chữ “reassignment”. MH09 manager decision UI và manager receipt/inspection/
   restock cho failed-outbound return không được tạo trong P10.2. Report không
   nghĩa là store đã nhận/kiểm tra/nhập tồn. Không báo live E2E của chuỗi này
   chỉ dựa trên fixture hoặc các SQL cases tách rời của P10.1.
3. **Android thật và instantaneous revoke** vẫn là giới hạn P09.4: chưa có
   device, chưa xác minh external launcher/recents; foreground task quyền được
   đọc lại 15 giây, không có realtime invalidation feed bảo đảm tức thì.

Code/test trong ownership đã được bổ sung; **chưa ký nghiệm thu P10.2 toàn
bộ ứng dụng liên nhóm** do các mục trên. Không có RPC/migration/API signature
mới, không widen RLS/fake backend success, không sửa UI/features của teammate.
Không commit/push ở lượt này. Các changes P10.1, artifacts MH09 và `outputs/`
được giữ nguyên.

Review độc lập đã rà các composition tests và xác nhận các sửa cuối: manager
phải có query mới với shipper scope null sau đổi session; fixture từ chối
scope sai; prewarm COD=0 phải đổi thành 550.000 nhờ invalidation; task2/list
đều mất PII sau fail2; không dùng counter fake bất biến làm chứng cứ tài chính.
