import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// A map tile source independent of the Flutter rendering layer.
abstract interface class MapTileSource {
  String get attribution;

  Uri tileUri({required int zoom, required int x, required int y});

  Future<Uint8List> loadTile(Uri uri);

  Future<void> dispose();
}

/// OpenStreetMap's public raster tile endpoint.
///
/// This adapter intentionally does not prefetch a region.  The map requests
/// only the small tile grid visible around the saved destination.  Responses
/// are retained for this app session and respect the server's cache headers;
/// if no cache lifetime is supplied, a conservative seven-day in-memory
/// lifetime is used.  A production deployment should add a durable cache or
/// use an OSM-derived provider with a service agreement before scaling up.
final class OpenStreetMapTileSource implements MapTileSource {
  OpenStreetMapTileSource({
    http.Client? client,
    this.tileHost = 'tile.openstreetmap.org',
    this.userAgent = 'sports_store/0.1 (OpenStreetMap tile client)',
    this.fallbackCacheDuration = const Duration(days: 7),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final String tileHost;
  final String userAgent;
  final Duration fallbackCacheDuration;
  final Map<Uri, _CachedTile> _cache = <Uri, _CachedTile>{};
  bool _disposed = false;

  @override
  String get attribution => '© OpenStreetMap contributors';

  @override
  Uri tileUri({required int zoom, required int x, required int y}) {
    if (zoom < 0 || zoom > 19) {
      throw ArgumentError.value(zoom, 'zoom', 'must be between 0 and 19');
    }
    final side = 1 << zoom;
    if (y < 0 || y >= side) {
      throw ArgumentError.value(y, 'y', 'is outside the tile grid');
    }
    // Web Mercator wraps horizontally.  This also avoids a malformed URI
    // when the user pans across the antimeridian.
    final wrappedX = ((x % side) + side) % side;
    return Uri.https(tileHost, '/$zoom/$wrappedX/$y.png');
  }

  @override
  Future<Uint8List> loadTile(Uri uri) async {
    if (_disposed) throw StateError('Map tile source has been disposed');
    final cached = _cache[uri];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.bytes;
    }

    final response = await _client
        .get(
          uri,
          headers: <String, String>{
            // OSM explicitly requires an identifying User-Agent rather than a
            // generic library default.
            'User-Agent': userAgent,
            'Accept': 'image/png,image/*;q=0.8',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw MapTileLoadException(uri, response.statusCode);
    }
    final bytes = Uint8List.fromList(response.bodyBytes);
    final expiresAt = DateTime.now().add(_cacheDuration(response));
    _cache[uri] = _CachedTile(bytes, expiresAt);
    return bytes;
  }

  Duration _cacheDuration(http.Response response) {
    final cacheControl = response.headers['cache-control'];
    if (cacheControl != null) {
      final match = RegExp(r'max-age\s*=\s*(\d+)').firstMatch(cacheControl);
      final seconds = int.tryParse(match?.group(1) ?? '');
      if (seconds != null && seconds > 0) {
        return Duration(seconds: seconds);
      }
    }
    return fallbackCacheDuration;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cache.clear();
    if (_ownsClient) _client.close();
  }
}

final class _CachedTile {
  const _CachedTile(this.bytes, this.expiresAt);

  final Uint8List bytes;
  final DateTime expiresAt;
}

final class MapTileLoadException implements Exception {
  const MapTileLoadException(this.uri, this.statusCode);

  final Uri uri;
  final int statusCode;

  @override
  String toString() => 'Map tile request failed ($statusCode): $uri';
}
