# MH17 — Behavior contract audit

Đây là bản đối chiếu, không thay đổi hợp đồng dùng chung. Nguồn normative:
[rev1.2 §9](../../technical_specification_mh07_mh08_mh09_mh17.md),
[OP-N01–05 và §11](../../technical_specification_mh07_mh08_mh09_mh17_data_api.md),
[CIN-09](../../Cross_Module_Integration_Contracts.md).
`ACTUAL` = source hiện tại; `TARGET` = contract; `EXTERNAL/UNVERIFIED` = cần owner/runtime evidence.

## Identity và dữ liệu

| Concept | ACTUAL | TARGET / limitation |
| --- | --- | --- |
| Canonical row | `NotificationItem.id`: validated UUID | Canonical server notification UUID, không dùng display order code |
| Owner | `recipientId`: validated UUID; foundation/interaction so current scope | Backend own-recipient RLS; Manager cũng chỉ có inbox riêng |
| Source | `eventId`, `subjectType`, `subjectId` | event canonical; type không phải event_type; subject xác định target |
| Nội dung | nonblank title/body plain Text | Server template sanitize; không phone/address/bank/evidence/token/reason tự do |
| Time | `createdAt`, nullable `readAt`, require UTC | Server timestamp; format Hanoi bằng shared formatter |
| Read | `isRead == readAt != null` | Không mark-unread; first server read timestamp giữ qua retry |
| Unknown type | preserve raw value/isSupported=false | Generic tile, fail-closed target; invalid UUID bị DTO reject |

Nine wire keys: `id,recipient_id,event_id,subject_type,subject_id,title,body,read_at,created_at`.
`read_at` phải có key dù null; thiếu key khác unread. Không tự thêm event type vào model hoặc sửa schema.
Allowlist actual: `order`, `delivery_task`, `cod`, `return_request`, `conversation`, `notification_only`.
`notification_only` contract dùng subject_id=event_id; model hiện validate UUID, chưa enforce quan hệ bằng nhau.

## Reads, filter, count, paging

- ACTUAL: `NotificationRepository.getPage(NotificationQuery)`; filters all/unread, default20/max100, cursor nullable/max2048.
- ACTUAL: foundation reject foreign recipient/read row trong unread query; page merge/dedup theo notification ID.
- ACTUAL: exact count lấy riêng từ `getUnreadCount()` qua `unreadCountFoundationProvider`; âm là unsupported.
- ACTUAL: badge không render khi unknown/zero; >99 chỉ hiện99+, semantics giữ số chính xác; không đếm visible list.
- TARGET: server keyset `(created_at DESC,id DESC)`, fetchlimit+1; opaque cursor gắn user/filter/limit, schema ở data/API §11.
- EXTERNAL: chưa có production adapter enforce cursor encoding/order/RLS; fake Preview dùng offset không phải canonical paging.
- Preview còn reuse cùng event/recipient cho nhiều rows và notification_only.subjectId khác eventId (F07); model-valid không phải producer-canonical.
- ACTUAL: filter change reset cursor; repeated cursor bị chặn; load-more error giữ rows và retry cùng cursor.
- ACTUAL: invalid_cursor ở trang sau dẫn refresh head; poll/refresh return về head và count, không nối head mới vào tail cũ.
- ACTUAL: epoch/query/request generations và current cache/scope/lifecycle loại late responses; một read inflight/query.
- GAP F02: domain page chưa kiểm tra empty/oversized nextCursor; đề xuất validation/reproducer riêng, không sửa task01.
- ACTUAL: list và count đọc riêng, eventually consistent; không có atomic list/count snapshot claim.
- ACTUAL: same-session stale data đọc được với thông báo stale; read/open bị khóa khi snapshot/head cache stale.
- TARGET: NFR foreground≤5s phải đo thật; ForegroundRefresh 3s là policy client, không phải evidence NFR đạt.

## Read acknowledgement

1. Load/filter/scroll không đổi read state. Explicit read hoặc tap bắt đầu `markRead(item)`.
2. Guard owner/session/cache; already-read current-owner row không gửi PATCH lần nữa.
3. Per-ID inflight requests dùng chung Future, pending là transient state, chưa phải read success.
4. Repository phải trả canonical updated row; zero-row PATCH là generic unavailable, không success.
5. VM kiểm canonical readAt non-null UTC; ack hook kiểm đúng ID/recipient/submittedScope/current readable cache.
6. Chỉ sau ack hợp lệ mới invalidate `notifications/` list/count; không trừ count hoặc đổi row optimistic.
7. Unread row chỉ biến mất khi canonical reload. Read fail giữ unconfirmed state, có retry.
8. ACTUAL markRead timeout15s → outcome_unknown; read providers/resolver10s. OP-N03 rev1.2 nêu10s: discrepancy cần owner chốt task sau.
9. TARGET timeout phải refetch authoritative row trước retry khi cần xác định outcome; VM hiện chưa có dedicated row-refetch recovery.

Ack hook không gửi PATCH và không chứng minh server trigger đã chạy; fake canonical row chỉ là client test evidence.
Server first timestamp/monotonic read_at có trong SQL source baseline, chưa kiểm deployed backend trong task01.
Không có mark-all-read contract/API/UI; HTML button và local-dot counter không được chuyển thành production logic.

## Typed navigation

`resolve(notificationId)` do target adapter re-read own row + current target permission; không nhận URL từ body.
Consumer kiểm available/screen/mode/entity UUID và role mapping trước `onNavigate(decision)`.

| Subject | Current role | Typed screen / entity contract | Integration status |
| --- | --- | --- | --- |
| order | Customer | customerOrder / order UUID → MH07 detail modal | typed consumer có; route callback ngoài MH17 |
| order | Manager | managerOrder / order UUID → MH09 | typed consumer có; callback ngoài MH17 |
| delivery_task | Shipper | shipperTask / task UUID → MH11, current assignee | resolver/target owner chưa tích hợp |
| delivery_task | Manager | managerOrder / authorized task→order UUID → MH09 | resolver phải map ID, không dùng task UUID làm order |
| cod | Manager/Shipper | cod / order UUID → MH12 | COD owner kiểm obligation, không raw orders fallback |
| return_request | Customer/Manager | customerReturn/managerReturn / return UUID → MH14/15 | Returns owner, external routes pending |
| conversation | Customer/Manager | conversation / conversation UUID → MH20 | Chat owner; Shipper denied |
| notification_only | mọi role own recipient | Context sheet trong MH17; không resolver/raw event/task query | actual implemented |

Các loại ngoài ma trận/unknown/missing target/callback/resolver → unavailable, ở MH17; không invent route.
Mode khác delivery_task của Manager phải giữ decision.entityId==notification.subjectId; Manager mapping là ngoại lệ có chủ đích.
Destination vẫn tự kiểm quyền lúc fetch; preflight không thay RLS. Không lấy cached PII làm fallback sau revoke/reassign.
ACTUAL tap unread mark-read độc lập resolver: valid navigation vẫn được phép khi read request thất bại.
Read thành công không bảo đảm navigation thành công; `notification_only` chỉ hiện context của current recipient.
Rapid repeated navigation chưa có dedicated in-flight serialization/coverage; không suy từ markRead dedup.
Central router hiện chỉ `/`; `/notifications` trong spec là intended contract, chưa production route.

## Session và privacy

- `SessionScope(userId,role,generation,roleResolved)` do trusted Auth adapter cung cấp; mặc định unresolved.
- Customer/Manager/Shipper chỉ được render own inbox; unknown role/unresolved/logout không query private reads.
- Scope đổi: page xóa rows/cursors/count provenance trước first frame; epoch cache mới, interaction state reset.
- Callback cũ chỉ publish khi cùng scope, cache identity và lifecycle; same-user new generation vẫn là scope mới.
- List/count access failure che cả feed và badge; explicit refresh chỉ recover sau cả hai resource fresh.
- Unauthenticated block cache toàn session; modal context theo dõi scope/access gate và không giữ private payload khi mất quyền.
- Session tests đã chạy, nhưng secure Auth mapping/backend RLS/old-account network integration chưa xác minh thật.
- Không cache riêng recipient/count trong extracted presentation components; không thêm subscriptions ngoài foundation owner.

## Event production và external ownership

| Responsibility | Owner / boundary |
| --- | --- |
| Read presentation/count/read ack client | Bảo, MH17 providers/VM/page; adapter OP-N01–03 còn thiếu |
| Own Orders confirm/reject/cancel/auto-confirm event policy | Orders + server job, own policy decided; producer chưa chứng minh runtime |
| order_placed | Checkout owner; CIN09 external offer chưa accepted |
| task assignment/delivery/failure/incidents | Deliveries; lock/assignment/attempt authority bên module owner |
| COD received | COD owner; obligation độc lập Returns |
| return/refund/pickup/redelivery | Returns + Deliveries; không bank/evidence trong notification |
| support_message_received | Chat; conversation recipient/permissions, không đồng nhất chat read với notification read |
| Persist/dedup/fanout | Trusted server transaction; frozen event/recipient manifest, no client insert/fanout |
| Push transport / destination screens | Ngoài MH17 UI; push không được giao; destination owners sở hữu route/access |

22 event families trong rev1.2 §9.2 là policy/offers, không enum mới và không phải đã có producers tích hợp.
Không dùng HTML “hỏa tốc”, “không vừa kích cỡ”, auto phân tuyến hoặc metric để tạo nghiệp vụ mới.
