import 'map_tile_cache.dart';

/// Browsers own the durable HTTP cache and conditional request semantics.
/// Do not duplicate image bodies in localStorage or override browser headers.
MapTileCache createMapTileCache() => _BrowserHttpCache();

class _BrowserHttpCache implements MapTileCache {
  @override
  Future<CachedMapTile?> read(Uri tile) async => null;
  @override
  Future<void> write(Uri tile, CachedMapTile value) async {}
  @override
  Future<void> remove(Uri tile) async {}
}
