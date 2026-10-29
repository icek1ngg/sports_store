# P09.2 — Adapter maps tái sử dụng và cấu hình demo

## Quyết định provider được chốt

Ngày 28/10/2026 người dùng xác nhận **OSM raster tiles + Google Maps URL**, demo
Web và Android. Phase 0 trước đó vẫn ghi chưa chốt; ghi nhận quyết định ở mốc
này, không nói quyết định đã có từ trước hoặc Văn Đức đã tích hợp MH16.
Không Supabase RPC/migration/RLS, GPS, route engine, fee estimator hoặc picker
MH16 mới trong P09.2. Giữ nguyên thay đổi P09.1 chưa commit.

## Hợp đồng core cho MH18 và bàn giao Văn Đức

| Interface/value | Chức năng và ranh giới |
| --- | --- |
| `MapLocation(latitude,longitude)` | Coordinate-only immutable value, kiểm finite/range/Web Mercator. Không chứa PII, không chứng minh location thuộc Hà Nội hoặc được server chấp nhận. |
| `SavedDestination` | Snapshot recipient đã có, thêm getter location. Không copy Order hoặc Supabase model; không gửi recipient sang provider. |
| `MapDisplayAdapter.buildMap(location,recenterToken,height,onTileError)` | Read-only preview dùng coordinate, không phụ thuộc raster source ở public API. `RasterMapDisplayAdapter` sở hữu source qua Riverpod, chuyển đúng tọa độ sang renderer hiện hữu. |
| `MapTileSource` / `MapTileCache` | Test seam cho URI/bytes/error/lifecycle/cache. OSM implementation chỉ nhận HTTPS exact host/path/grid, không query/credential/port lạ. |
| `MapNavigationAdapter.openLocation(location)` | Coordinate-only handoff cho consumer MH16 tương lai; typed opened/unavailable/failed/invalidDestination. Không picker, không save, không gọi backend. |
| `MapDirectionsLauncher.openDirections(destination)` | Compatibility với MH18 hiện có: kiểm snapshot, ủy quyền Google launcher; screen vẫn phải recheck quyền theo P09.1 trước handoff. |
| `MapProviderConfiguration` và providers | Provider mặc định đã được user chốt; cấu hình UA public, adapter override được trong test. Không API key/secret. |

Ví dụ bàn giao cho MH16 (chỉ preview và interface; không triển khai picker):

```dart
final location = MapLocation(latitude: selectedLat, longitude: selectedLng);
final preview = ref.watch(mapDisplayAdapterProvider).buildMap(location: location);
// Sau thao tác người dùng, nếu cần mở app ngoài:
final result = await ref.read(mapNavigationAdapterProvider).openLocation(location);
```

`selectedLat/selectedLng` phải do MH16 có nguồn rõ ràng. Giá trị valid ở client
chỉ là tọa độ địa lý; checkout server vẫn bắt buộc kiểm Hà Nội/địa chỉ/phí. Không
lấy pin cửa hàng, 0,0 hoặc geocode đoán làm dữ liệu hợp lệ thay người dùng.

## Cấu hình, license, quota và privacy

- Tile URL approved: `https://tile.openstreetmap.org/{z}/{x}/{y}.png`; native UA
  mặc định `sports_store/0.1 (+https://github.com/icek1ngg/sports_store)`.
  Có thể cấu hình public identity bằng `--dart-define=MAP_USER_AGENT=...`
  (prefix sports_store/, không CR/LF), không đặt secret trong dart-define.
- Web dùng browser UA/Referer tự quản lý; không tự set forbidden header hoặc
  conditional header gây CORS preflight. `web/index.html` đặt
  strict-origin-when-cross-origin; hosting header/CDN không được override thành
  no-referrer hoặc strip Referer. Origin có thể được OSM thấy, không full route.
- Native dùng cache file trong app temporary directory qua `path_provider`
  2.1.6 (BSD-3-Clause), tối đa 64 files/16 MiB, serialize writes; hết budget loại
  file cũ. Web dùng browser HTTP cache, không duplicate PNG trong localStorage.
  Chỉ tile đang hiển thị, không offline download/prefetch vùng hoặc background job.
- Cache-Control/max-age/Age/Expires, ETag/Last-Modified và 304 được xử lý; không
  header đọc được thì fallback bảy ngày. No-cache revalidate; no-store không
  lưu; không tự gửi no-cache mặc định. Cache disk hỏng/đầy không che tile hợp lệ,
  có RAM fallback; OS có thể evict temp/cache. Cache native chỉ public map tiles
  + HTTP metadata; không task ID/name/phone/address/session. File name mã hóa
  tile z/x/y có thể cho thấy vùng đã xem, cache dùng chung public tiles qua các
  account/phiên, không log/hội tụ lịch sử GPS. Không coi base64 là mã hóa bảo mật.
- Map hiển thị attribution có liên kết copyright/license. Dữ liệu OSM thuộc
  ODbL; không tuyên bố mọi tile/dịch vụ OSM miễn phí không hạn mức. Tile service
  best-effort, không SLA/quota số request cố định bảo đảm, có thể chặn vì sử
  dụng quá mức. Demo không thay thế hợp đồng dịch vụ khi mở rộng triển khai.
- Google Maps URL có đúng `api=1&destination=lat,long`, không phone/name/address
  hoặc business IDs. Không API key vì không gọi Maps SDK/Routes API. OSM thấy
  vùng tile, Google thấy tọa độ người dùng chọn mở; dữ liệu đi tới dịch vụ ngoài
  theo quyết định provider đã được user chốt, không gửi evidence/bank/customer text.

Tài liệu primary được xác minh ngày 28/10/2026:

- [OSM Tile Usage Policy](https://operations.osmfoundation.org/policies/tiles/)
- [OSM copyright và ODbL](https://www.openstreetmap.org/copyright)
- [Google Maps URLs](https://developers.google.com/maps/documentation/urls/get-started)
- [url_launcher 6.3.3/configuration](https://pub.dev/packages/url_launcher/versions/6.3.3)
- [path_provider 2.1.6/platforms/license](https://pub.dev/packages/path_provider/versions/2.1.6)
- [Kotlin incremental compilation](https://kotlinlang.org/docs/gradle-compilation-and-caches.html)

## Nền tảng và dependency

Reuse `http` 1.6.0, `url_launcher` 6.3.3/Riverpod hiện có. Thêm/pin
`path_provider: 2.1.6` cho native cache; pub get cập nhật transitive dependencies
cần thiết, không upgrade toàn project. Thử nghiệm preferences-cache ban đầu đã
được loại bỏ; shared_preferences vẫn chỉ là transitive dependency trước đó.

Android: SDK 24+ theo plugin; release Internet permission đã có. Chỉ gọi
launchUrl trực tiếp, không canLaunchUrl/supportsLaunchMode nên không thêm query
intent hoặc quyền location. `android/gradle.properties` thêm kotlin.incremental=false
để tránh cache Kotlin crash khi Pub cache ở C: và checkout D: trên Windows;
giảm tốc incremental build, không đổi nghiệp vụ/runtime hoặc compile SDK.
Giữ flags/toolchain template khác. Build cần SDK/NDK/license cài sẵn theo plugin.

Web: conditional cache implementation không import dart:io/path_provider vào
renderer Web; browser HTTP cache/referrer thay native storage/header. Browser
có thể chặn popup dù launchUrl trả lỗi; phải gọi từ user gesture và giữ kết quả
typed, không báo mở thành công giả. Deployment cần HTTPS và kiểm request
Referer/CORS trong DevTools; build không tự chứng minh policy header của host.

## Kiểm chứng và giới hạn local

- `flutter pub remove shared_preferences --offline` (gỡ direct thử nghiệm),
  `flutter pub add path_provider:2.1.6`: dependency/lockfile thống nhất.
- `dart format lib/core/maps test/core/maps
  lib/features/deliveries/presentation/pages/delivery_task_map_page.dart`: PASS.
- `flutter test --no-pub test/core/maps`: **20 PASS** (latest). Gồm persistent
  file hit sau adapter recreation, stale disk/write failure, HTTP cache/304,
  coalescing, no-cache/no-store, quota/storage failure, parallel eviction,
  dispose pending, host/query guard, non-image/oversize, marker/recenter và
  URL coordinate-only/launcher failure. Fixtures không thay provider thành công.
- `flutter analyze --no-pub`: **No issues found** trên bản cuối.
- `flutter test --no-pub --concurrency=1 --reporter expanded`: **521 PASS,
  4 opt-in live skipped**. Giữ nguyên tests P09.1 và các feature khác.
- `flutter build web --no-pub`: PASS, build/web, Wasm dry run succeeded; warning
  font CupertinoIcons có sẵn được giữ rõ, không thêm package để che warning.
- `flutter build apk --debug --no-pub`: PASS sau Kotlin cache workaround,
  build/app/outputs/flutter-apk/app-debug.apk. Lần đầu/retry trước workaround
  failed do Kotlin incremental caches khác drive, không phải map API/RLS.
- Thử `flutter test --platform chrome --no-pub test/core/maps` không qua bước
  loading trong môi trường này và đã dừng; không báo Chrome runtime test PASS.
  Web compile/build và VM adapter/widget tests PASS không thay thế kiểm tra
  popup/Referer trên browser host thật hoặc dialer/navigation trên Android thật.

Không có thiết bị Android/iOS vật lý để nghiệm thu launcher ở lượt này, workspace
không target iOS. Không claim production traffic/quota hay Văn Đức đã dùng picker.
Không gọi Supabase hoặc sửa SQL/RLS. Source P09.1 và outputs/ giữ nguyên.

## File manifest và kết luận

P09.2 thay đổi `lib/core/maps/map_directions.dart`, `map_providers.dart`,
`map_tile_source.dart`, `saved_destination.dart`, `saved_destination_map.dart`;
thêm `map_location.dart`, `map_display_adapter.dart`,
`map_provider_configuration.dart`, `map_tile_cache.dart`,
`map_tile_cache_platform.dart`, `map_tile_cache_io.dart`. MH18 page chỉ đổi điểm
gọi renderer sang adapter, không thêm controls hoặc chỉnh business destination.

Tests: `test/core/maps/map_contract_test.dart`, `map_display_adapter_test.dart`,
`map_tile_adapter_test.dart`. Shared config: `pubspec.yaml`/lock,
`web/index.html` referrer, `android/gradle.properties` Kotlin incremental setting.
Docs: API contracts/screen mapping/provider biên bản; không ghi đè nội dung team.

Independent review không còn blocker; hardening stale disk/write failure đã
thêm test và sửa ưu tiên cache memory mới hơn. Full suite/build đã chạy lại trên
bản cuối. `git diff --check` exit 0, chỉ cảnh báo LF/CRLF.

**Hoàn tất scope P09.2** theo tiêu chí adapter tests và build demo Web/Android.
Không backend blocker hoặc API phụ thuộc teammate trong adapter này. Handoff
MH16 là interface sẵn dùng, chưa phải picker đã được Văn Đức nghiệm thu. Các
manual checks browser-host/thiết bị nêu trên vẫn cần trước phát hành cho người
dùng thật. Chưa commit/push các thay đổi P09.1/P09.2 trong lượt này.
