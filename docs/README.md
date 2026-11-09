# Tài liệu Sports Store theo codebase

Ngày đối chiếu: **09/11/2026**. Snapshot mã nguồn: **`54a71af`**.
Tài liệu này mô tả source trong repository, không xác nhận migration đã áp
dụng trên cloud hay toàn bộ luồng đã nghiệm thu trên thiết bị.

## Đọc tài liệu theo mục đích

| Nhu cầu | Tài liệu hiện hành |
|---|---|
| Chạy ứng dụng, phân biệt production và local | [README dự án](../README.md) |
| MH01–MH20, role, route, owner, giới hạn UI | [screen_mapping.md](screen_mapping.md) |
| Schema, RLS, Storage, migration | [database.md](database.md) |
| Trạng thái đơn, task, COD, trả hàng | [business_states.md](business_states.md) |
| Repository, payload và RPC | [api_contracts.md](api_contracts.md) |
| Khởi tạo client và cấu hình Auth/OAuth | [supabase_setup.md](supabase_setup.md) |
| Demo local phần Bảo | [Báo cáo MH07/MH08/MH09/MH17](FINAL_REPORT_MH07_MH08_MH09_MH17.md) |

Bốn hợp đồng dùng chung ở trên được đối chiếu từ router/composition đang chạy,
repository và chuỗi migration. Khi đọc migration, phải xét các bản thay thế
hàm về sau; không dùng riêng migration nền để kết luận API hiện tại.

## Hai bản chạy cần phân biệt

| Thành phần | Kết nối Supabase | Trình bày local |
|---|---|---|
| Entrypoint | `lib/main.dart` | `lib/main_dev.dart` |
| Composition | `lib/app/integration/production_feature_composition.dart` và providers từng feature | `lib/app/dev/dev_app.dart` |
| Router | `lib/app/router/app_router.dart` | `lib/app/dev/dev_router.dart` |
| Dữ liệu | Repository Supabase, tùy schema/quyền đã triển khai | Local adapters, store trong RAM |
| Xác thực | Supabase Auth; role từ profile server | Local Auth phục vụ trình bày |
| Giá trị kiểm chứng | Cần chạy kiểm thử riêng với backend | Không chứng minh RLS, RPC, Cron hoặc lưu cloud |

Stack theo `pubspec.yaml`: Dart `^3.13.2`, Riverpod `3.4.3`, go_router
`18.0.2`, supabase_flutter `2.18.0`. Domain/Data/Presentation được tổ chức
trong từng feature. Orders/Notifications còn có providers, controllers và
hạ tầng state dùng chung; cây thư mục quy ước không thay thế cấu trúc thực tế.

## Đối chiếu báo cáo nghiệp vụ 3.1

Tài liệu tham khảo là `Bao_cao_nghiep_vu_cua_hang_the_thao_3.1_theo_codebase.docx`,
ngày 09/11/2026, snapshot `b488c1a`. File Word không nằm trong repository và
không được sửa trong lần cập nhật này. Các câu trong báo cáo là nội dung tham
khảo, không tự cấp quyền thay đổi chính sách hay triển khai chức năng.

Các điểm cần đọc cùng code hiện tại:

- **Orders đã có binding production**: `productionFeatureOverrides` gắn
  `supabaseOrderRepositoryProvider` và `supabaseNotificationRepositoryProvider`.
  Nhận định cũ “MH08 chưa bind repository thật” không còn đúng.
- **MH07 → MH13 đã có route callback và bổ sung capability** trong migration
  `supabase/migrations/20261109124501_orders_return_creation_capability.sql`.
  Helper kiểm tra khách sở hữu đơn đã giao, còn hạn bảy ngày và không có yêu
  cầu trả đang hoạt động. Nút vẫn phụ thuộc capability server và dữ liệu mới;
  RPC gửi yêu cầu kiểm tra lại điều kiện tại thời điểm gửi. Không tiếp tục mô
  tả capability luôn false như snapshot của báo cáo Word. Chưa xác minh
  migration mới đã áp dụng lên môi trường triển khai.
- **MH17 chưa có resolver mở đích trong production**:
  `notificationTargetResolverProvider` mặc định null và production composition
  chưa override. Đọc/đánh dấu thông báo và mở nội dung là hai mức tích hợp khác nhau.
- **MH09 chưa nối đủ thao tác vận hành**: có RPC giao nhận không đồng nghĩa
  giao diện đã gắn callback phân công, đổi người, giao lần hai hay nhận/kiểm
  tra hàng hoàn. Xem bảng màn hình và hợp đồng API để biết ranh giới cụ thể.
- **Tự xác nhận sau một giờ** vẫn là yêu cầu nghiệp vụ cần triển khai tác vụ
  server; giá trị nguồn xác nhận `automatic` không chứng minh đã có job/Cron.
- **Hoàn hàng outbound thất bại**: shipper báo bàn giao không phải manager
  nhận/kiểm tra/nhập lại kho. Không suy ra hàng đã bán lại được từ trạng thái
  chờ hoàn hoặc thông báo bàn giao.
- **MH18 là bản đồ điểm đến nhiệm vụ shipper**; chọn địa chỉ khách thuộc MH16.
  Sau đặt thành công, MH16 hiển thị kết quả tại checkout, không tự chuyển MH07.

Chính sách chuẩn và phần còn thiếu phải được phân biệt: thiếu job tự xác nhận
không xóa yêu cầu một giờ; thiếu UI không đổi quyền nghiệp vụ. Giữ 20 mã màn,
phí COD 30.000 VND, tối đa hai lần outbound và nghĩa vụ COD độc lập với hoàn tiền.

## Tài liệu lịch sử và kết quả kiểm tra

Các tài liệu sau giữ nguyên vai trò tham chiếu theo mốc riêng, không phải
bằng chứng toàn hệ thống đã triển khai:

- `Final_Technical_Decisions.md`, `Cross_Module_Integration_Contracts.md` và bộ
  `technical_specification_mh07_mh08_mh09_mh17*.md`: thiết kế/đề xuất ở snapshot
  cũ; tên API đề xuất có thể khác RPC hiện tại.
- `*_implementation_plan.md`, `minh_duc_phase_prompts.md`: kế hoạch công việc,
  không dùng danh sách TODO cũ để kết luận source hiện tại còn thiếu.
- `FINAL_REPORT_MH07_MH08_MH09_MH17.md`: báo cáo bản local với mốc kiểm tra riêng.
- Các ghi chú có ngày, `docs/features/`, `docs/handover/`, `docs/qa/` và
  `docs/audits/`: kết quả theo phạm vi, môi trường và thời điểm được ghi trong
  từng tài liệu. Không cộng các số test lịch sử thành kết quả kiểm thử hiện tại.

Lần cập nhật này kiểm tra tĩnh file nguồn, route, provider, enum, repository,
SQL và tham chiếu tài liệu; không thay code, schema, dependency hoặc cấu hình.
Không chạy lại `flutter analyze`, `flutter test`, kiểm thử SQL hay cloud.
Các kịch bản NT01–NT30 trong báo cáo là tiêu chí đối chiếu, không phải danh
sách kết quả đã đạt. NT05/nhánh tự động của NT06, NT23 mở đích MH17 và các bước
manager hoàn hàng cần xét các giới hạn tích hợp nêu trên khi nghiệm thu.
