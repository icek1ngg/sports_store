import 'dart:typed_data';

/// Public map tiles only. Never store recipient/task/session data here.
class CachedMapTile {
  const CachedMapTile({
    required this.bytes,
    required this.expiresAt,
    this.etag,
    this.lastModified,
    this.freshnessLifetime,
  });
  final Uint8List bytes;
  final DateTime expiresAt;
  final String? etag;
  final String? lastModified;
  final Duration? freshnessLifetime;
}

abstract interface class MapTileCache {
  Future<CachedMapTile?> read(Uri tile);
  Future<void> write(Uri tile, CachedMapTile value);
  Future<void> remove(Uri tile);
}
