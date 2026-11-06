# Hoàn thiện phạm vi Minh Đức — theo yêu cầu ngày 28/10/2026

## Phạm vi được giao bổ sung

Người dùng giao bổ sung primitive backend còn thiếu và hoàn thiện phần Minh Đức.
Không sửa UI MH15 của Sơn hoặc các màn của teammate. Phạm vi đang triển khai:

1. Manager nhận đủ pickup sau shipper handover, đối chiếu custody server;
   pickup returned_to_store/request under_inspection; chưa restock/refund.
2. Manager từ chối sau inspection, bắt buộc lý do; release toàn bộ hàng thực
   nhận thành immutable redelivery plan/request awaiting_redelivery.
3. Manager phân công redelivery; shipper thực nhận đủ rồi start riêng; success
   đóng rejected_after_inspection, failure giữ manager_action_required/custody.
4. MH11 redelivery actions và projection an toàn; MH18 điểm đến task thật.
5. SQL/quyền/rollback/idempotency/concurrency, widget/provider và live Auth/RPC
   nghiệm thu; cập nhật shared contracts theo implementation cuối.

Người dùng đã chốt (28/10/2026): phân công thông báo shipper; kết quả thông báo
chủ cửa hàng và customer của đơn, nội dung chung chỉ UUID. Redelivery miễn phí,
không COD mới, outbound attempts/stock/COD cũ giữ nguyên. Không tự giao lại sau
failure; không restock hoặc refund trong nhánh này. Đây là user approval, không
tuyên bố Sơn đã tích hợp UI/duyệt contract.

## Hiện trạng trước thay đổi

P08.1/P08.2 production pickup collect/fail/handover đã deploy, live UI + API
handover PASS; full Flutter 465 PASS/3 opt-in skipped. P08.3 chỉ có interface/
fixture rollback, chưa public RPC. MH18 route đang là placeholder. Các thay đổi
P08.1/P08.2/P08.3 chưa commit; giữ nguyên, không reset hoặc ghi đè `outputs/`.

## Trạng thái nghiệm thu

Phần bổ sung đã hoàn tất production: tám RPC trong migration
`20261028062908_p083_redelivery_production.sql` đã deploy, MH11 redelivery và
MH18 đã tích hợp. [Contract/biên bản redelivery](p083_production_redelivery.md)
và [MH18](p09_maps_acceptance.md) chứa file manifest và kiểm chứng chi tiết.

| Kiểm chứng cuối | Kết quả |
| --- | --- |
| Production SQL `node supabase/tests/run_redelivery_production.mjs p011_p083_prod_final` | PASS 22 migrations, RPC chain/ACL/role denial/proof/replay/rollback và race completion/failure |
| Shared SQL/concurrency regression `node supabase/tests/run_delivery_read_fixture.mjs p011_completion_regression_final` | PASS, fixture cleanup sạch |
| `flutter test --no-pub --concurrency=1 --reporter expanded` | 486 PASS, 4 live opt-in skipped; live chạy riêng bên dưới |
| `flutter analyze --no-pub` | No issues found |
| `flutter build web --no-pub` | PASS, artifact build/web; warning CupertinoIcons font ghi rõ trong biên bản |
| Live `--live --redelivery --ui` và `--live --redelivery --redelivery-failure --ui` qua run_live_pickup_handover.mjs | PASS real Auth/JWT, pickup + manager receipt/inspection + MH18 read/recheck + MH11 accept/start/outcome |
| Cloud audit sau cleanup | fixture Auth users/categories 0, disabled private triggers 0, migrations 22, production RPCs 8 |
| Security advisor mức ERROR | Exit 0, No issues found; không tuyên bố WARN/INFO đều sạch |

Luna workers chạm usage limit trong lúc làm; coordinator tiếp quản hoàn thiện,
debug, chạy checks/deploy. Reviewer Sol độc lập không còn blocking finding cho
backend và redelivery UI; không tuyên bố worker đã hoàn tất phần họ bỏ dở.

Không có commit/push mới trong lượt này, không reset database hoặc source.
Không sửa UI MH15/Sơn, MH17/Bảo, refund/restock hoặc tự giải quyết custody sau
redelivery failure. Đó là ranh giới owner/nghiệp vụ, không phải thao tác fake
thành công trong app. Không tuyên bố đã hoàn tất toàn bộ 20 màn hoặc đã nghiệm
thu thiết bị Android/iOS vật lý; ở đây là build web và widget dùng backend thật.
