# Trạng thái nghiệp vụ Sports Store

Bản này chuẩn hoá trạng thái theo source hiện có tại ngày 09/11/2026. Giá trị
wire trong Dart phải khớp enum và migration; nhãn tiếng Việt trong UI chỉ là
cách trình bày. Tài liệu không biến một enum, widget hoặc file migration thành
bằng chứng đã deploy hay đã pass test cloud.

## Phạm vi thực thi

- **main** là [lib/main.dart](../lib/main.dart), dùng Supabase và router
  production. Composition production nằm tại
  [lib/app/integration/production_feature_composition.dart](../lib/app/integration/production_feature_composition.dart).
- **main_dev** là [lib/main_dev.dart](../lib/main_dev.dart) và
  [lib/app/dev/dev_app.dart](../lib/app/dev/dev_app.dart): repository local,
  không khởi tạo Supabase. Các adapter mutation outbound, return pickup,
  redelivery, reporting và COD receipt được thay bằng LocalUnavailable*.
- **preview** trong [tool/ui_preview](../tool/ui_preview) là fixture UI/acceptance.
  Không dùng kết quả preview để kết luận RPC, RLS, Storage hoặc transaction cloud.
- Những gì ghi “có source” chỉ được kiểm chứng trong repository. Chưa kiểm tra
  lịch sử migration trên project Supabase, Auth/Storage policy thực tế, cron/task
  tự động hoặc bộ test backend trong lần cập nhật này.

## Nguồn chuẩn và quyền

| Hợp đồng | Source |
| --- | --- |
| Giá trị enum và parser Dart | [order_status.dart](../lib/features/orders/domain/models/order_status.dart), [delivery_task_query.dart](../lib/features/deliveries/domain/models/delivery_task_query.dart), [return_request_context.dart](../lib/features/returns/domain/models/return_request_context.dart), các model cùng thư mục domain |
| Enum/table/constraint nền | [20261006034251_sports_store_schema.sql](../supabase/migrations/20261006034251_sports_store_schema.sql) |
| Bảng sau khi đơn giản hoá schema | [20261006040019_simplify_sports_store.sql](../supabase/migrations/20261006040019_simplify_sports_store.sql) |
| Quyền người dùng | profile server và route/backend guard; client registration không được tự chọn manager/shipper |

AppRole hiện có ba giá trị: customer, manager, shipper. Role phải đến từ
profile/server-managed source, không dùng user-editable user_metadata làm nguồn
uỷ quyền. Route guard chỉ là lớp điều hướng; RLS, RPC và Storage policy vẫn
phải kiểm tra lại identity, ownership và scope.

## Enum chuẩn

### Đơn hàng

OrderStatus có đúng các giá trị:

| Wire value | Ý nghĩa trong luồng hiện tại |
| --- | --- |
| pending_confirmation | Đơn mới đặt, chờ xác nhận |
| preparing | Đã xác nhận, chuẩn bị hàng |
| awaiting_pickup | Đã có bước giao/đang chờ shipper nhận hoặc chờ lần giao tiếp theo |
| delivering | Đang giao outbound |
| awaiting_redelivery | Lần outbound đầu thất bại, chờ quyết định retry/hoàn |
| awaiting_store_return | Hàng outbound phải quay về cửa hàng để quản lý xử lý |
| delivered | Giao outbound thành công; return sau đó không đổi order thành cancelled |
| cancelled | Đơn bị huỷ theo operation được phép |
| rejected | Quản lý từ chối đơn ở bước xác nhận |
| undeliverable_returned | Hàng giao không thành công đã được cửa hàng nhận và kiểm tra |

OrderConfirmationSource là manager hoặc automatic. OrderOperation là confirm,
reject, customer_cancel, manager_cancel hoặc auto_confirm. automatic/auto_confirm
là giá trị hợp đồng có trong enum, nhưng hiện chưa có bằng chứng về cron, server
job hoặc function tự xác nhận sau một giờ trong các migration đang có. Không mô tả
auto-confirm là hành vi đã chạy; cần triển khai và kiểm chứng server task riêng.

### Giao hàng và lần thử

| Enum | Giá trị wire |
| --- | --- |
| DeliveryTaskKind | outbound, return_pickup, redelivery |
| DeliveryTaskStatus | pending_assignment, assigned, accepted, in_transit, delivered, failed, returned_to_store, cancelled, manager_action_required |
| DeliveryAttemptResult | success, failed |
| DeliveryTaskStateGroup | waiting, in_transit, completed, retry, failed |

DeliveryTaskStateGroup là bucket truy vấn của MH10, không thay thế
DeliveryTaskStatus. pending_assignment, failed, cancelled và
manager_action_required vẫn được tính trong ungrouped theo read model. retry và
failed có thể có count riêng nhưng không được tự coi là hai task khác nhau.

### COD

CodStatus có đúng ba giá trị: uncollected, collected, received.

### Đổi trả

| Enum | Giá trị wire |
| --- | --- |
| ReturnRequestStatus | pending_review, initially_rejected, awaiting_return_pickup, returning_to_store, under_inspection, awaiting_refund, refunded, rejected_after_inspection, awaiting_redelivery, redelivery_failed, manager_action_required |
| ReturnEligibility | eligible, not_delivered, active_return_exists, return_window_expired |
| ReturnReason | defective, wrong_item, missing_items |

redelivery_failed tồn tại trong enum contract. Luồng migration redelivery hiện tại
đưa lỗi cần xử lý về manager_action_required; không tự coi mọi record
redelivery_failed là đã đóng.

### Enum phụ dùng cho read model

- TimelineEntityType: order, delivery_task, cod, return_request.
- TimelineActorSource: manager, system, shipper, customer, unknown.
- TimelineSource: actual_event, snapshot_milestone.
- WarningCode: outbound_failure, custody_incident, return_active,
  external_dependency_unavailable, history_incomplete, goods_discrepancy,
  unknown.
- EligibilityReason: outside_window, not_delivered, active_return,
  unauthorized_or_unavailable, missing_contract.
- OutboundFailureReason: unreachable, reschedule, bad_address, refusal, other.
  OutboundFailureDisposition là manager_decision hoặc store_return_pending.

## Luồng đơn hàng và outbound

| Bước / điều kiện | Task | Order | Hiệu ứng bắt buộc |
| --- | --- | --- | --- |
| Quản lý xác nhận kiểm đủ hàng, đóng gói và phân công outbound | pending_assignment/assigned | preparing → awaiting_pickup | RPC `prepare_and_assign_delivery` ghi bằng chứng chuẩn bị và phân công trong một transaction; không tăng attempt, không xuất kho lần nữa. Gọi phân công trực tiếp không có bằng chứng chuẩn bị trong transaction bị chặn. |
| Shipper accept rồi start | assigned → accepted → in_transit | awaiting_pickup → delivering | Start mới tăng delivery_attempt_count; tối đa 2, không tăng khi chỉ đổi task/shipper |
| Giao thành công | in_transit → delivered | delivering → delivered | Ghi attempt success, người nhận và full COD; COD chuyển uncollected → collected |
| Lần 1 thất bại | in_transit → failed | delivering → awaiting_redelivery | Ghi reason và attempt failed; không tự trừ/tăng tồn kho, không thu/hoàn COD |
| Retry lần 1 | task retry/assigned | awaiting_redelivery → awaiting_pickup | Shipper đang giữ đủ hàng có thể yêu cầu giao lần hai cho chính mình. Manager cũng có thể quyết định giao lại hoặc hoàn sớm trước khi bắt đầu lần hai. Task mới không xuất kho lần nữa. |
| Hoàn sớm hoặc lần 2 thất bại | failed/return path | → awaiting_store_return | Hàng phải về cửa hàng; không tự restock |
| Quản lý nhận và kiểm tra hàng | task/store handling | awaiting_store_return → undeliverable_returned | Đây là bước nghiệp vụ còn thiếu trong luồng outbound. Source có thao tác shipper báo bàn giao, nhưng chưa có luồng manager hoàn chỉnh để nhận, kiểm tra, nhập lại hàng đủ điều kiện và kết thúc đơn. |

Các operation source chính nằm trong các migration
[assign_outbound_delivery_task](../supabase/migrations/20261024070151_assign_outbound_delivery_task.sql),
[accept_start_outbound_delivery](../supabase/migrations/20261026055651_accept_start_outbound_delivery.sql),
[complete_outbound_delivery](../supabase/migrations/20261026130645_complete_outbound_delivery.sql),
[fail_outbound_delivery](../supabase/migrations/20261027060030_fail_outbound_delivery.sql)
và [decide_outbound_retry](../supabase/migrations/20261027062118_decide_outbound_retry.sql).
Wrapper accept-and-start và retry cùng holder có thêm source tại
[20261102035050_accept_and_start_delivery_task.sql](../supabase/migrations/20261102035050_accept_and_start_delivery_task.sql)
và [20261101095549_shipper_retry_outbound_failure.sql](../supabase/migrations/20261101095549_shipper_retry_outbound_failure.sql).

MH09 hiện chỉ nối các order operation confirm/reject/cancel ở
[manager_order_details_page.dart](../lib/features/orders/presentation/pages/manager_order_details_page.dart).
Phân công, giao lần hai, hoàn hàng sớm và nhận/kiểm tra hàng vẫn là action
disabled ở UI; có migration/repository source không đồng nghĩa MH09 đã thực hiện
được các mutation đó.

## Return pickup và redelivery

Return pickup là DeliveryTaskKind riêng, không tự áp dụng giới hạn hai lần của
outbound và không làm phát sinh nghĩa vụ COD mới.

| Sự kiện | ReturnRequestStatus | DeliveryTaskStatus / ghi chú |
| --- | --- | --- |
| Submit hợp lệ | pending_review | Chưa có pickup |
| Manager duyệt pickup | awaiting_return_pickup | Có thể assign return_pickup |
| Shipper nhận đủ hàng thực tế | returning_to_store | Task chuyển theo flow pickup; chỉ nhận các item customer thực sự nhận |
| Shipper bàn giao tại store | returning_to_store | Handover là event; chưa phải manager receipt/inspection |
| Manager nhận hàng | under_inspection | Chuyển sau khi kiểm tra đầu vào |
| Chấp nhận sau inspection | awaiting_refund | Refund là bước riêng |
| Ghi refund và evidence | refunded | Không offset vào COD |
| Từ chối sau inspection | awaiting_redelivery | Tạo plan redelivery miễn phí, không thu COD lại |
| Redelivery thành công | rejected_after_inspection | Return được đóng theo flow hiện tại |
| Redelivery thất bại | manager_action_required | Chờ quyết định quản lý, không tự đóng |

Các source chính là
[return_pickup_tasks.sql](../supabase/migrations/20261027142031_return_pickup_tasks.sql),
[return_pickup_store_handover.sql](../supabase/migrations/20261028011128_return_pickup_store_handover.sql)
và [p083_redelivery_production.sql](../supabase/migrations/20261028062908_p083_redelivery_production.sql).
Handover của shipper không thay cho manager receive/inspection. Return sau giao
thành công không đổi OrderStatus delivered thành cancelled và không xoá nghĩa
vụ COD.

## COD và tiền

- Khi order được tạo, COD là uncollected và amount là tổng merchandise cộng phí
  giao được server tính.
- Chỉ giao outbound thành công với full amount khớp mới chuyển sang collected;
  shipper không được ghi partial reconciliation.
- Chỉ manager xác nhận collected → received cho đủ từng order. Không ghi nhận
  một phần và không trừ refund vào nghĩa vụ COD.
- Refund approved bao gồm full merchandise amount và phí giao ban đầu; manager
  chuyển tiền ngoài app rồi ghi evidence theo return contract.
- Amount là integer VND; timestamps nghiệp vụ là server instants. Client clock
  chỉ hiển thị, không quyết định deadline/state.

Read/mutation source của COD được nối qua các migration
[list_cod_collections.sql](../supabase/migrations/20261025064829_list_cod_collections.sql)
và [confirm_cod_received.sql](../supabase/migrations/20261025121908_confirm_cod_received.sql).
Việc có các file này không xác nhận function đã được apply trên project cloud.

## Quy tắc tạo đơn, tồn kho và snapshot

- Thêm item vào cart không reserve stock.
- place_order phải kiểm tra đủ tồn per variant và reserve atomically cho toàn
  bộ order; không mô phỏng transaction bằng chuỗi request Flutter.
- Order lưu snapshot product/variant/price, recipient và address tại thời điểm
  đặt. Catalog thay đổi sau đó không sửa order cũ.
- COD order chỉ giao trong Hà Nội; delivery fee cố định 30.000 VND; server kiểm
  tra service area và coordinates.
- Failed outbound không tự restock. Sau khi manager nhận và kiểm tra hàng hoàn, chỉ số lượng đủ điều kiện mới được nhập lại để bán. Hàng hỏng hoặc mất không tự tăng tồn có thể bán.
- Mutation, notification và message phải idempotent bằng request/event/client
  ID; đọc lại receipt sau lỗi mạng không được tự submit command lần nữa.

Checkout source là
[20261027005254_checkout_placement.sql](../supabase/migrations/20261027005254_checkout_placement.sql),
[20261027005305_hanoi_service_area.sql](../supabase/migrations/20261027005305_hanoi_service_area.sql)
và các lock/intent migration kế tiếp. UI checkout là MH16, không tách location
picker thành MH18.

## Return request và quyền dữ liệu

- Customer chỉ submit trong bảy ngày kể từ delivered_at, deadline được tính lại
  bằng server clock tại thời điểm submit.
- Boundary route MH13 chỉ kiểm tra customer role và UUID; ownership, delivered
  state, deadline và điều kiện item/video do context/submit RPC kiểm tra lại.
- Reason chỉ là defective, wrong_item hoặc missing_items; video evidence là
  bắt buộc và lưu private Storage.
- Mỗi order chỉ có một active return request. Submit không biến order delivered
  thành cancelled và không xoá COD obligation.
- Customer chỉ trả những hàng thực sự đã nhận; không yêu cầu trả item chưa giao.
- Bank details, payment evidence và refund data chỉ customer của order và manager
  được đọc theo backend policy.
- Approval pickup không phải approval refund; inspection và transfer evidence là
  các bước độc lập.

Source context/submit/tracking là
[submit_return_request.sql](../supabase/migrations/20261101080125_submit_return_request.sql),
[get_my_return_request.sql](../supabase/migrations/20261101090627_get_my_return_request.sql),
[manager_return_management.sql](../supabase/migrations/20261102050041_manager_return_management.sql)
và [return_management_resolution.sql](../supabase/migrations/20261102092824_return_management_resolution.sql).

## Thông báo, chat và read model

- Notification được lưu theo recipient; unique event/recipient dùng để deduplicate.
  Filter MH17 là all hoặc unread; read marker không cấp thêm quyền đọc.
- Subject target có thể là order, delivery_task, cod, return_request,
  conversation hoặc notification_only. Khi mở target phải recheck recipient,
  role, ownership và quyền hiện tại.
- notificationTargetResolverProvider mặc định null trong production source.
  Vì vậy list/read/mark-read có thể nối repository nhưng deep-link target vẫn
  trả unavailable nếu composition chưa cung cấp resolver.
- Chat chỉ text giữa customer và manager, một conversation/customer; shipper
  không tham gia. Message có client_message_id để idempotency; read marker
  không thay thế authorization.
- Timeline phân biệt actual_event và snapshot_milestone; cảnh báo
  external_dependency_unavailable/history_incomplete không được trình bày như
  một state transition thành công.

## Các điều không được suy ra

- Enum automatic hoặc auto_confirm không chứng minh auto-confirm job đã chạy.
- Route/page/repository có trong source không chứng minh migration/RPC đã deploy,
  policy đã đúng hoặc integration test đã pass.
- main_dev/preview dùng local fixture không chứng minh dữ liệu production.
- Nhãn disabled/unavailable ở UI cần được phân biệt: MH09 operational actions
  hiện disabled vì chưa nối callback; nhiều mutation trong main_dev là
  unavailable vì dev cố ý không giả lập backend.
- redelivery_failed trong enum không thay đổi thực tế rằng flow P083 hiện đưa
  failed redelivery về manager_action_required.
- Return sau delivered không được suy ra là order cancellation, COD settlement
  hoặc automatic restock.

## Migration và xác minh triển khai

Bộ migration nền và nghiệp vụ có trong source gồm:

- schema/access và simplify: [20261006034251_sports_store_schema.sql](../supabase/migrations/20261006034251_sports_store_schema.sql),
  [20261006034259_sports_store_access.sql](../supabase/migrations/20261006034259_sports_store_access.sql),
  [20261006040019_simplify_sports_store.sql](../supabase/migrations/20261006040019_simplify_sports_store.sql);
- delivery/COD/checkout: các file được dẫn ở trên trong thư mục
  [supabase/migrations](../supabase/migrations);
- returns: các file submit, pickup, manager resolution và redelivery được dẫn
  ở trên;
- Orders read/mutation/capability: [20261107044955_orders_read_aggregates.sql](../supabase/migrations/20261107044955_orders_read_aggregates.sql),
  [20261107171621_orders_transactional_mutations.sql](../supabase/migrations/20261107171621_orders_transactional_mutations.sql),
  [20261107171648_orders_mutation_capability_bridge.sql](../supabase/migrations/20261107171648_orders_mutation_capability_bridge.sql),
  [20261107221505_orders_internal_auth_identity_bridge.sql](../supabase/migrations/20261107221505_orders_internal_auth_identity_bridge.sql)
  và [20261109124501_orders_return_creation_capability.sql](../supabase/migrations/20261109124501_orders_return_creation_capability.sql).

Các migration Orders read/mutation/identity nêu trên mang nhãn source-only hoặc
không deploy ngầm lên shared Cloud như provenance lịch sử trong SQL; đối chiếu
tổng hợp tại [database.md](database.md). Đây không phải kết luận runtime.
Migration cuối thêm capability
can_open_return_creation cho MH07 và không thay việc submit RPC kiểm tra server.
Trong lần cập nhật này không chạy migration, không truy vấn cloud và không chạy
test backend; cần ghi nhận ba trạng thái riêng: source có, cloud đã apply, test
đã pass.
