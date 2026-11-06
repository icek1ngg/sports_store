# P06.1–P06.4 — Nghiệm thu live ngày 27/10/2026

**PASS** trên project `bqoyfytmrtvjwrpshuhh` (PostgreSQL17.11). Đây là
Flutter widget/UI dùng repository production, Auth/password JWT thật và
PostgREST/RPC thật; không phải điện thoại vật lý hay tiền mặt thực tế.
Các kết luận “chưa deploy/chưa nghiệm thu cloud” trong handoff P06 cũ được
thay thế trong phạm vi dưới đây. Không suy ra MH17/returns/P07 đã hoàn tất.

## Dữ liệu và cách chạy

- Một đơn 520.000 +30.000 phí được tạo riêng và đi qua RPC production
  assign → accept → start → complete, sinh khoản collected550.000 thật trên DB.
- Thêm fixture có nhãn rõ cho kiểm tra đọc: 101 khoản collected130.000 của
  shipper A, một received130.000, một uncollected130.000 và một collected130.000
  của shipper B. Các fixture này không được coi là đã đi qua checkout/delivery.
- Tổng 105 orders/COD thử; shipper A có 102 collected, buộc UI page size100
  phải load-more. Own held13.680.000; manager global ít nhất13.810.000.
- Hai manager, hai shipper, một customer được tạo qua Auth Admin auto-confirm,
  không gửi mail. Role do SQL admin fixture đặt, không lấy user_metadata.
  Service key chỉ trong RAM của Node setup/cleanup, không vào Flutter/file/log.
- Flutter dùng publishable key và JWT riêng của từng tài khoản. Không override
  repository/state bằng fake success; chỉ override shared client trong test.

Lệnh mặc định sau khi có CLI2.122.0 trong npm cache và CLI login:

```powershell
node supabase/tests/run_live_outbound_ui.mjs --live --complete --cod
```

Lượt nghiệm thu dùng fallback `LIVE_SQL_BRIDGE_DIR` trong
`supabase/.temp/p06_sql_bridge`: runner gửi SQL setup/assert/cleanup, coordinator
thực hiện qua connector Supabase `execute_sql` rồi trả rows thật. Đây là handoff
có điều phối, không tự chạy nếu không có consumer. File bridge chỉ chứa SQL/
UUID/counts; không chứa mật khẩu/token/API key. Đường dẫn phải trong workspace
temp được ignore; request được xóa cả khi timeout. Cleanup được bật trước seed
để ACK bị mất không bỏ sót dữ liệu đã commit.

## Kết quả theo phase

| Phase | Bằng chứng live |
| --- | --- |
| P06.1 | JWT shipper chỉ thấy own rows; customer bị deny; shipper B không lọc sang A; manager global và order/shipper scope đúng; cursor limit7 đọc đủ104 own records không trùng, totals/counts không phụ thuộc page; uncollected và received không tính held. |
| P06.2 | CodRoutePage shipper thật: collected100→102 bằng load-more, hai nhóm rõ ràng, không action manager; sau receipt primary chuyển sang received, held A13.680.000→13.130.000; B chỉ giữ130.000 và không thấy primary của A. |
| P06.3 | Shipper gọi receipt trực tiếp bị42501; partial amount và uncollected bịPT409; full550.000 do manager thực hiện; replay cùng actor/key/payload trả ACK cũ; mismatch bịIDEMPOTENCY_CONFLICT; hai manager đồng thời trên khoản B chỉ một thành công, bên thua STATE_CONFLICT. |
| P06.4 | CodRoutePage manager thật: global smoke, combined UUID shipper/order filters, empty incompatible scope, clear và refresh; dialog read-only550.000, checkbox bắt buộc, same-frame double tap không pop MH12/không ghi hai lần; received group và held/list/count cập nhật authoritative. |

Lost ACK được kiểm thử trên UI: transparent HTTP wrapper đợi response thật
sau RPC commit, drain response rồi ném ClientException **một lần**. UI hiện
lỗi/thử lại; request body gồm request_id của hai lần gửi giống hệt. Không
thay backend response bằng success tự tạo. Hậu kiểm ledger/event xác nhận
retry không thu/nhận tiền lần hai.

Cùng Supabase client/ProviderScope được đổi shipper A → manager → A → B;
role branch, danh sách, tab và dữ liệu riêng tư được đọc lại theo session mới.
Hai receipt thành công (primary và race order B) cho hậu kiểm:

```text
receipts=2, events=2, notifications=2, full_receipts=true
received_amount=collected_amount=expected_amount
received_by != null, received_at=handed_over_at
```

Fixture return/refund được chuyển awaiting_refund → refunded bằng SQL setup;
đọc qua JWT/RPC trước và sau cho COD rows/amount không thay đổi. Không giả đã
triển khai return/refund RPC hoặc đã upload video/evidence.

## Kiểm tra bổ sung và sửa lỗi

- `cod_collection_list.sql` và `cod_receipt.sql` thực hiện qua connector cloud:
  **PASS**, final ROLLBACK. Bao phủ RLS/role, amount, receipt concurrency contract,
  rollback khi notification lỗi và COD độc lập refund. SQL claims được đặt
  bằng set_config, được bổ sung bằng JWT thật ở luồng UI/API phía trên.
- `flutter test --no-pub`: **358 PASS, 2 opt-in live tests skipped**. Live COD
  test được chạy riêng với environment của runner: **1 PASS** (73 giây).
- `flutter analyze --no-pub`: No issues found.
- `flutter test --no-pub test/features/cod/manager_cod_panel_test.dart`:6PASS.
- `dart format` các tệp Dart thay đổi và `git diff --check`: PASS.
- 12 migration cloud khớp local; không migration/API/RLS/grants mới trong lượt này.

Sửa runtime duy nhất: dialog manager có local one-shot latch cho Confirm và
Cancel, chống hai tap trước frame pop luôn route bên dưới. Regression test
thực hiện hai tap trên dialog thuộc route được push, xác nhận một write và
MH12 vẫn mở. Review độc lập không còn finding material sau sửa.

Các lần chưa đạt không được tính PASS: timeout DNS/mạng trường, selector lazy
list/offscreen/multiple Scrollable, truy vấn hậu kiểm nhầm event_id là cột
ledger (thực tế nằm trong response JSON), và fake-async socket reuse lúc đổi
account. Test hiện cuộn đúng outer list, dùng deterministic shipper scope,
không giả định primary nằm trang đầu, đóng connection sau request để tránh
socket callback thuộc vùng async cũ. Truy vấn ledger đã sửa lấy
`response->>'event_id'`; hậu kiểm cuối dùng dữ liệu DB thật.

Sau người dùng bật VPN, lượt PASS dùng DNS/kết nối bình thường, không ghim IP.
Runner có HTTPS transport riêng và fallback IP test-only (TLS/SNI theo hostname,
không badCertificateCallback/rejectUnauthorized=false). Một lần thử raw TCP
factory trước đó không đúng TLS đã bị dừng, sửa thành SecureSocket.secure và
probe verified TLS401; không dùng lần đó làm bằng chứng nghiệm thu.

## Cleanup và phạm vi còn lại

Setup/cleanup chỉ nhắm UUID sinh cho run. Cleanup ledger tạm ngừng USER
append-only trigger trong cùng transaction rồi bật lại trước commit; không tắt
RLS/FK hay reset database. Auth deletion được retry giới hạn, 404 coi đã xóa.
Một lượt mạng lỗi ở bước Auth cleanup được dọn bổ sung bằng admin SQL theo
đúng5UUID/email-prefix của run. Không xóa tài khoản hay đơn khác.

Kiểm tra cloud cuối: profiles=0, orders=0, COD=0, returns=0, receipts=0,
notifications=0, live test Auth users=0; **3 sản phẩm có sẵn giữ nguyên**.

Tệp thay đổi:

- `lib/features/cod/presentation/widgets/manager_cod_panel.dart`
- `test/features/cod/manager_cod_panel_test.dart`
- `test/live/live_cod_ui_test.dart` (mới)
- `supabase/tests/run_live_outbound_ui.mjs`
- `supabase/tests/live_https_transport.mjs` (mới)
- Handoff này và phần kết quả P06 cuối bốn docs contracts.

P06.1–P06.4 đã nghiệm thu theo API/UI/live JWT trong phạm vi trên. Chưa test
điện thoại vật lý, tiền mặt ngoài đời hoặc renderer/deep link MH17 của Bảo;
notification đã persist theo contract. Thiết bị khác cập nhật bằng refresh/
poll theo thiết kế, chưa có nghiệm thu hai điện thoại cùng mở song song.
Không commit/push trong lượt nghiệm thu này.
