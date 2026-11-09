# Ánh xạ màn hình Sports Store

Tài liệu này là bản đối chiếu với source hiện có tại ngày 09/11/2026. Phạm vi
giữ đúng 20 màn hình MH01–MH20 của báo cáo nghiệp vụ; dialog, bottom sheet,
location picker và route chi tiết không làm tăng số màn hình.

## Cách đọc trạng thái

- **main** là entrypoint production tại
  [lib/main.dart](../lib/main.dart). App khởi tạo Supabase và dùng router
  production tại [lib/app/router/app_router.dart](../lib/app/router/app_router.dart).
- **main_dev** là entrypoint local tại
  [lib/main_dev.dart](../lib/main_dev.dart). FullDevApp trong
  [lib/app/dev/dev_app.dart](../lib/app/dev/dev_app.dart) thay repository bằng
  bộ nhớ cục bộ; không khởi tạo Supabase. Một số adapter ghi nghiệp vụ được cố
  ý thay bằng LocalUnavailable*, nên thao tác thành công ở local không chứng
  minh RPC cloud đã hoạt động.
- **preview** là các entrypoint fixture trong
  [tool/ui_preview](../tool/ui_preview). Chúng phục vụ review UI/acceptance
  cục bộ. Riêng [tool/ui_preview/prm_main.dart](../tool/ui_preview/prm_main.dart)
  chỉ chuyển tiếp sang lib/main.dart, không phải bộ fixture riêng.
- “Đã có trong source” chỉ nói về route, widget, provider, repository hoặc
  migration trong repository. Không được hiểu là migration đã chạy trên
  Supabase, Auth/Storage/PostgREST đã cấu hình đúng, hay test cloud đã pass.
  Tài liệu này không kết luận trạng thái deploy hoặc kết nối cloud.

## Chủ sở hữu theo phân công

| Chủ sở hữu | Màn hình |
| --- | --- |
| Dung An | MH01, MH02, MH03, MH19 |
| Văn Đức | MH04, MH05, MH06, MH16 |
| Bảo | MH07, MH08, MH09, MH17 |
| Minh Đức | MH10, MH11, MH12, MH18 |
| Sơn | MH13, MH14, MH15, MH20 |

## Entrypoint và dữ liệu

| Entrypoint | Router / nguồn dữ liệu | Dùng để kết luận |
| --- | --- | --- |
| main | [app_router.dart](../lib/app/router/app_router.dart), [production_feature_composition.dart](../lib/app/integration/production_feature_composition.dart), các Supabase repository | Cấu trúc production và điểm nối source |
| main_dev | [dev_router.dart](../lib/app/dev/dev_router.dart), [dev_app.dart](../lib/app/dev/dev_app.dart), LocalDemoStore | Luồng local, dữ liệu demo, hành vi fallback |
| Demo cũ | [demo_router.dart](../lib/app/router/demo_router.dart), [demo_app.dart](../lib/app/demo/demo_app.dart) | Fixture giới hạn, không phải route production |
| Preview | [tool/ui_preview](../tool/ui_preview) | Render/acceptance cục bộ theo fixture |

main_dev có thêm các đường dẫn tiện ích như /customer/home, /manager/...,
/shipper/cod và account child routes. Đây không phải hợp đồng route của main và
không được dùng để suy ra thêm màn hình MH01–MH20.

## Bảng ánh xạ MH01–MH20

| Mã / vai trò | Route production (main) và page | Nguồn / trạng thái đối chiếu |
| --- | --- | --- |
| **MH01**<br>Khách hàng / quản lý / shipper | / hoặc /login → LoginScreen | [login_screen.dart](../lib/features/auth/presentation/pages/login_screen.dart). main dùng Supabase Auth; main_dev dùng local auth. Route guard vẫn phải xác thực session trước khi vào vùng nghiệp vụ. |
| **MH02**<br>Khách hàng | /register → RegisterScreen | [register_screen.dart](../lib/features/auth/presentation/pages/register_screen.dart). Đăng ký source hiện có; quyền manager/shipper không do client chọn, profile server là nguồn quyền. |
| **MH03**<br>Quản lý | /manager/products → ProductManagementScreen | [product_management_screen.dart](../lib/features/catalog/presentation/pages/product_management_screen.dart). main nối catalog/product repository và mutation save_managed_product nếu backend cung cấp; main_dev dùng catalog local. |
| **MH04**<br>Khách hàng | /customer/products → ProductListPage | [product_list_page.dart](../lib/features/catalog/presentation/pages/product_list_page.dart). Có route production và repository catalog; main_dev/preview có thể dùng fixture local. |
| **MH05**<br>Khách hàng | /customer/products/:productId → ProductDetailsPage | [product_details_page.dart](../lib/features/catalog/presentation/pages/product_details_page.dart). productId đi qua route parameter; chi tiết biến thể/giá/tồn kho không phải màn hình mới. |
| **MH06**<br>Khách hàng | /customer/cart → CartPage | [cart_page.dart](../lib/features/cart/presentation/pages/cart_page.dart). Giỏ hàng đọc theo customer và không giữ chỗ tồn kho; nút sang checkout là route /customer/checkout. |
| **MH07**<br>Khách hàng | /customer/orders → CustomerOrdersPage | [customer_orders_page.dart](../lib/features/orders/presentation/pages/customer_orders_page.dart). main dùng [SupabaseOrderRepository](../lib/features/orders/data/repositories/supabase_order_repository.dart); xem chi tiết bằng bottom sheet trong page, không có route order-detail customer riêng. Capability can_open_return_creation hiện đã được đọc để mở MH13; source migration là [20261109124501_orders_return_creation_capability.sql](../supabase/migrations/20261109124501_orders_return_creation_capability.sql). |
| **MH08**<br>Quản lý | /manager/orders → ManagerOrdersPage | [manager_orders_page.dart](../lib/features/orders/presentation/pages/manager_orders_page.dart). Route và read repository đã có trong source. Các SQL Orders read/mutation liên quan có tệp mang nhãn source-only trong provenance lịch sử; xem thêm [database.md](database.md), không suy ra đã deploy. |
| **MH09**<br>Quản lý | /manager/orders/:orderId → ManagerOrderDetailsPage | [manager_order_details_page.dart](../lib/features/orders/presentation/pages/manager_order_details_page.dart). Mh09ActionFooter chỉ nối confirm/reject/manager-cancel qua OrderCommandController; customer-cancel được phát từ luồng MH07, không phải footer MH09. Khối Mh09OperationalActions chỉ hiển thị các nút phân công, phân công lại, giao lần hai, hoàn hàng sớm, nhận/kiểm tra hàng ở trạng thái disabled; chưa có callback mutation operational nối vào page. Deep link tới /cod và /manager/returns/:returnId có trong source. |
| **MH10**<br>Shipper | /shipper/tasks → DeliveryTaskListPage | [delivery_task_list_page.dart](../lib/features/deliveries/presentation/pages/delivery_task_list_page.dart). Read dùng operational repository có kiểm tra task được phép xem; main_dev đọc LocalOperations. Nhóm tab là bucket query, không phải enum trạng thái mới. |
| **MH11**<br>Shipper | /shipper/tasks/:taskId → DeliveryTaskDetailPage | [delivery_task_detail_page.dart](../lib/features/deliveries/presentation/pages/delivery_task_detail_page.dart). Có source cho outbound, retry/failure, return pickup và redelivery; route đọc đúng task hiện được cấp. main_dev thay các command/completion/failure/retry/pickup/redelivery bằng adapter unavailable, nên không dùng local preview để kết luận ghi cloud thành công. |
| **MH12**<br>Shipper / quản lý | /cod (tuỳ chọn ?orderId=UUID) → CodRoutePage | [cod_route_page.dart](../lib/features/cod/presentation/pages/cod_route_page.dart). main cho shipper đọc nghĩa vụ COD và manager xác nhận đã nhận đủ qua Supabase repository; main_dev có dữ liệu đọc local nhưng receipt adapter unavailable. /shipper/cod chỉ là route tiện ích của main_dev. |
| **MH13**<br>Khách hàng | /customer/orders/:orderId/return → ReturnRequestFlowPage | [return_request_flow_page.dart](../lib/features/returns/presentation/pages/return_request_flow_page.dart). Guard route chỉ kiểm tra customer role và UUID; không tự kiểm ownership. Context/submit RPC mới kiểm order ownership, delivered, hạn 7 ngày, item và video; source upload vào private Storage. MH07 đã có capability bridge để điều hướng vào đây. |
| **MH14**<br>Khách hàng | /customer/returns/:returnId → ReturnTrackingPage | [return_tracking_page.dart](../lib/features/returns/presentation/pages/return_tracking_page.dart). Đọc tracking theo return của customer, refresh/poll và phản hồi bổ sung nếu được phép; quyền đọc vẫn do server kiểm tra. |
| **MH15**<br>Quản lý | /manager/returns và /manager/returns/:returnId → ManagerReturnsPage, ManagerReturnDetailPage | [manager_returns_page.dart](../lib/features/returns/presentation/pages/manager_returns_page.dart), [manager_return_detail_page.dart](../lib/features/returns/presentation/pages/manager_return_detail_page.dart). Source có các bước review, yêu cầu bổ sung, duyệt pickup, nhận/kiểm tra, refund và redelivery. Trạng thái/action thực tế phải đối chiếu repository và migration; không coi việc có widget là bằng chứng cloud đã áp dụng. |
| **MH16**<br>Khách hàng | /customer/checkout → CheckoutPage | [checkout_page.dart](../lib/features/checkout/presentation/pages/checkout_page.dart). Chọn địa chỉ, tìm vị trí và location picker nằm trong MH16; không chuyển location picker thành MH18. Đặt hàng gọi server transaction và khi thành công vẫn ở MH16; người dùng mới điều hướng sang MH07. Phí giao nội địa Hà Nội là 30.000 VND theo contract. |
| **MH17**<br>Khách hàng / quản lý / shipper theo quyền | /notifications → NotificationsPage (typedef của NotificationsScreen) | [notifications_page.dart](../lib/features/notifications/presentation/pages/notifications_page.dart), [notifications_screen.dart](../lib/features/notifications/presentation/screens/notifications_screen.dart). Route production và notificationRepositoryProvider đã nối Supabase cho list/read/mark-read. notificationTargetResolverProvider mặc định là null, vì vậy tap deep-link tới order/task/COD/return/conversation hiện trả unavailable nếu composition không cung cấp resolver; danh sách thông báo không vì thế mà bị xem là “chưa tích hợp”. |
| **MH18**<br>Shipper | /shipper/tasks/:taskId/map → DeliveryTaskMapRoutePage / DeliveryTaskMapPage | [delivery_task_map_page.dart](../lib/features/deliveries/presentation/pages/delivery_task_map_page.dart). Là map của task đang được phép xem, destination lấy từ địa chỉ snapshot. Thiếu tọa độ thì không render/chỉ đường bằng tọa độ giả; Map reader vẫn có text fallback. Không có store pin hay shipper GPS tracking; app bar/back do shell shipper quản lý. |
| **MH19**<br>Khách hàng / quản lý | /chat → ConversationListScreen | [conversation_list_screen.dart](../lib/features/chat/presentation/pages/conversation_list_screen.dart). main dùng chat repository Supabase theo hợp đồng một conversation/customer; shipper bị từ chối. |
| **MH20**<br>Khách hàng / quản lý | /chat/:conversationId → ConversationDetailScreen | [conversation_detail_screen.dart](../lib/features/chat/presentation/pages/conversation_detail_screen.dart). conversationId là UUID route parameter; hỗ trợ text-only, read marker và idempotent client message theo repository. Route guard/server phải recheck customer hoặc manager hiện tại. |

## Route phụ và boundary

Các route sau hỗ trợ màn hình chính nhưng không tạo mã MH mới:

- /auth/confirm-email là callback xác nhận email của Auth.
- :productId, :orderId, :returnId, :taskId, :conversationId là parameter
  của màn hình tương ứng; production router yêu cầu UUID ở các route nghiệp vụ
  có kiểm tra strict.
- /customer/checkout?variant=... nhận biến thể từ MH05/MH06; location picker
  ở trong checkout.
- /customer/orders/:orderId/return và /customer/returns/:returnId là
  entry/detail của MH13–MH14.
- /manager/returns/:returnId, /shipper/tasks/:taskId/map và /cod?orderId=...
  là child/deep-link của MH15, MH18 và MH12.
- /chat/:conversationId là chi tiết MH20, không phải conversation thứ hai.

OperationalRouteGuard và _OperationalRouteBoundary recheck session, role,
ownership và task scope khi mở các route operational. Route guard chỉ bảo vệ
điều hướng; quyền đọc/ghi/RPC/Storage vẫn phải được backend enforce. Vì vậy
route xuất hiện không đồng nghĩa dữ liệu người dùng đã được phép truy cập.

## Luồng theo vai trò

| Vai trò | Luồng source chính |
| --- | --- |
| Khách hàng | MH01/MH02 → MH04 → MH05 → MH06 → MH16 (đặt hàng thành công vẫn ở MH16; người dùng điều hướng sang MH07) → MH07 → MH13/MH14; MH17 và MH19/MH20 theo quyền |
| Quản lý | MH01 → MH03 hoặc MH08 → MH09 → MH12/MH15; MH17 và MH19/MH20 theo quyền |
| Shipper | MH01 → MH10 → MH11 → MH18/MH12; MH17 chỉ khi backend cấp quyền, không tham gia chat |

Luồng trên là ánh xạ route/source, không phải báo cáo E2E đã chạy. Những bước
phụ thuộc migration/RPC/Storage phải được kiểm tra trên môi trường đích trước
khi nghiệm thu.

## Bằng chứng source và giới hạn xác minh

- Router production: [app_router.dart](../lib/app/router/app_router.dart).
- Composition production: [production_feature_composition.dart](../lib/app/integration/production_feature_composition.dart).
- Session/Auth lifecycle: [main.dart](../lib/main.dart) và
  [auth_startup_options.dart](../lib/core/config/auth_startup_options.dart).
- Orders read/mutation source: [supabase_order_repository.dart](../lib/features/orders/data/repositories/supabase_order_repository.dart).
- Notifications source: [supabase_notification_repository.dart](../lib/features/notifications/data/repositories/supabase_notification_repository.dart)
  và [notification_interaction_view_model.dart](../lib/features/notifications/presentation/providers/notification_interaction_view_model.dart).
- MH07 capability bridge: [20261109124501_orders_return_creation_capability.sql](../supabase/migrations/20261109124501_orders_return_creation_capability.sql).
- Một số migration Orders mang nhãn source-only hoặc “never deploy implicitly”
  như provenance lịch sử trong SQL; xem [database.md](database.md), không xem
  nhãn này là kết quả kiểm tra runtime:
  [20261107044955_orders_read_aggregates.sql](../supabase/migrations/20261107044955_orders_read_aggregates.sql),
  [20261107171621_orders_transactional_mutations.sql](../supabase/migrations/20261107171621_orders_transactional_mutations.sql)
  và [20261107221505_orders_internal_auth_identity_bridge.sql](../supabase/migrations/20261107221505_orders_internal_auth_identity_bridge.sql).

Trong phạm vi cập nhật tài liệu này chưa có kiểm tra kết nối Supabase, lịch sử
migration trên cloud, Auth/Storage policy thực tế hoặc bộ test backend. Khi
triển khai, cần chạy migration bằng quy trình được phê duyệt, kiểm tra quyền
theo role và ghi nhận kết quả test riêng; không đổi nhãn source thành “đã
deploy/đã pass” chỉ vì tệp tồn tại trong repository.
