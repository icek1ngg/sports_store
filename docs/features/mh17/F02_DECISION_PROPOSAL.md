# F02 — Malformed nextCursor decision proposal

Status: **PROPOSED, CHƯA APPROVED/IMPLEMENTED**. MH17-03A3-R design only.

## Contract và current behavior

Normative: [Notification Data/API](../../technical_specification_mh07_mh08_mh09_mh17_data_api.md) OP-N01 (551–566) và cursor contract §11 (1611).
Cursor opaque, gắn user/filter/limit; tối đa2048 ký tự; input cursor invalid/mismatch dùng invalid_cursor/reset-refetch.
Client không decode, trim, chế tạo hoặc diễn giải cursor thành offset.

Current NotificationPage cho phép nextCursor rỗng hoặc oversized.
NotificationQuery chuẩn hóa empty input thành null; >2048 bị reject.
FeedCoordinator bảo toàn raw nextCursor, kể cả malformed; hasMore dựa null, không dựa page length.
Do đó empty tail intent có thể thành head query; oversized intent có thể lỗi trước repository request.
Không coi đó là successful pagination hoặc normalization recovery hợp lệ.
Current failure/retry giữ accepted rows và active cursor; retry raw malformed cursor không tự chữa domain problem.

## Boundary nhỏ nhất được đề xuất

Protected `lib/features/notifications/presentation/view_models/notification_providers.dart`:
ở page foundation loader, sau repository.getPage và **trước cache/snapshot acceptance**,
reject `nextCursor != null && (nextCursor.isEmpty || nextCursor.length > 2048)` bằng existing unsupportedData mapping.
Giữ null, nonempty<=2048 nguyên bytes; không trim/decode/normalize; không thêm error code.
Malformed server response khác invalid request cursor: không đổi unsupportedData thành invalid_cursor giả để retry head thành công.
Adapter/server vẫn chịu trách nhiệm token canonical/ownership; validation này không chứng minh Base64URL hay authorization.

Không sửa NotificationPage/NotificationQuery hoặc coordinator trong proposal này.
Constructor validation sẽ đổi public domain behavior và phá2 coordinator characterization cases đang cố ý bảo toàn F02 raw input.
Foundation boundary giữ những unit cases đó nguyên vẹn, chặn malformed accepted snapshots trước live feed.
Không thêm provider/cache/repository authority mới; không fix F07 legacy offset fixtures.

## Tests bắt buộc khi được authorize riêng

- null cursor exhausted; valid lengths1 và2048 giữ nguyên bytes.
- empty và2049 response reject trước cache acceptance với existing unsupportedData.
- Malformed head hiển thị error, không publish hasMore/canonical success.
- Malformed tail giữ accepted rows; retry dùng đúng current intent, không đổi thành head query.
- Existing invalid_cursor input recovery không đổi.
- Session loss/foreign recipient vẫn fail closed, unread count không bị suy ra từ list.
- Domain constructor/Query và2 raw coordinator cases giữ nguyên assertions.

## Decision gate và risks

Cần owner approval cho protected foundation loader và unsupportedData classification, cùng bounded tests.
Phải precede live pagination integration; chưa có permission để thực hiện trong03A3-R.
Backward compatibility: trước đây malformed response có thể publish/attempt; sau fix sẽ fail closed sớm.
Valid API responses không đổi; producer/Preview không canonical có thể bộc lộ error và phải xử lý ở owner riêng.
Không dùng catch-all im lặng hoặc fake exhausted cursor để tránh lỗi.

F02 **UNRESOLVED**. F03 role matrix, F05 route multiplicity, F07 fixtures ngoài phạm vi.
Architecture R cũng đang BLOCKED do ReadCoordinator estimate257/250; proposal này không giải quyết LOC blocker.
