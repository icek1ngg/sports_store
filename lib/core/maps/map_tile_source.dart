import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'map_tile_cache.dart';
import 'map_tile_cache_platform.dart'
    if (dart.library.io) 'map_tile_cache_io.dart'
    as platform_cache;

abstract interface class MapTileSource {
  String get attribution;
  Uri tileUri({required int zoom, required int x, required int y});
  Future<Uint8List> loadTile(Uri uri);
  Future<void> dispose();
}

abstract interface class MapTileAttribution {
  Uri get attributionUri;
}

/// Approved demo provider: visible HTTPS tiles, persistent bounded caching,
/// conditional revalidation, app identification or browser UA/Referer.
final class OpenStreetMapTileSource
    implements MapTileSource, MapTileAttribution {
  @override
  Uri get attributionUri => Uri.https('www.openstreetmap.org', '/copyright');
  OpenStreetMapTileSource({
    http.Client? client,
    this.tileHost = 'tile.openstreetmap.org',
    this.userAgent =
        'sports_store/0.1 (+https://github.com/icek1ngg/sports_store)',
    this.fallbackCacheDuration = const Duration(days: 7),
    MapTileCache? cache,
    DateTime Function()? clock,
    bool? web,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _cache = cache ?? platform_cache.createMapTileCache(),
       _clock = clock ?? DateTime.now,
       _web = web ?? kIsWeb;
  final http.Client _client;
  final bool _ownsClient;
  final String tileHost, userAgent;
  final Duration fallbackCacheDuration;
  final MapTileCache _cache;
  final DateTime Function() _clock;
  final bool _web;
  final _pending = <Uri, Future<Uint8List>>{};
  final _memory = <Uri, CachedMapTile>{};
  bool _disposed = false;
  @override
  String get attribution => '© OpenStreetMap contributors';
  @override
  Uri tileUri({required int zoom, required int x, required int y}) {
    if (zoom < 0 || zoom > 19) throw ArgumentError('Invalid map zoom');
    final side = 1 << zoom;
    if (y < 0 || y >= side) throw ArgumentError('Invalid tile row');
    return Uri.https(tileHost, '/$zoom/${((x % side) + side) % side}/$y.png');
  }

  @override
  Future<Uint8List> loadTile(Uri uri) {
    if (_disposed) return Future.error(StateError('Tile source disposed'));
    if (uri.scheme != 'https' ||
        uri.host != tileHost ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !RegExp(r'^/\d{1,2}/\d+/\d+\.png$').hasMatch(uri.path)) {
      return Future.error(ArgumentError('Unapproved tile URL'));
    }
    final parts = uri.pathSegments;
    final z = int.parse(parts[0]),
        x = int.parse(parts[1]),
        y = int.parse(parts[2].split('.').first);
    if (z > 19 || x >= (1 << z) || y >= (1 << z)) {
      return Future.error(ArgumentError('Invalid tile coordinate'));
    }
    return _pending.putIfAbsent(
      uri,
      () => _load(uri).whenComplete(() {
        _pending.remove(uri);
      }),
    );
  }

  Future<Uint8List> _load(Uri uri) async {
    CachedMapTile? cached;
    try {
      cached = await _cache.read(uri);
    } on Object {
      /* Storage failure is not a tile failure. */
    }
    final memory = _memory[uri];
    if (memory != null &&
        (cached == null || memory.expiresAt.isAfter(cached.expiresAt))) {
      cached = memory;
    }
    if (_disposed) throw StateError('Tile source disposed');
    if (cached != null && cached.expiresAt.isAfter(_clock())) {
      return cached.bytes;
    }
    final response = await _client
        .get(
          uri,
          headers: {
            if (!_web) 'User-Agent': userAgent,
            'Accept': 'image/png,image/*;q=0.8',
            if (!_web && cached?.etag != null) 'If-None-Match': cached!.etag!,
            if (!_web && cached?.lastModified != null)
              'If-Modified-Since': cached!.lastModified!,
          },
        )
        .timeout(const Duration(seconds: 15));
    if (_disposed) throw StateError('Tile source disposed');
    if ((response.statusCode != 200 && response.statusCode != 304) ||
        (response.statusCode == 304
            ? cached == null
            : response.bodyBytes.isEmpty)) {
      throw MapTileLoadException(uri, response.statusCode);
    }
    if (response.statusCode == 200 &&
        (response.bodyBytes.length > 1024 * 1024 ||
            (response.headers.containsKey('content-type') &&
                !response.headers['content-type']!.startsWith('image/')))) {
      throw MapTileLoadException(uri, response.statusCode);
    }
    final bytes = response.statusCode == 304
        ? cached!.bytes
        : Uint8List.fromList(response.bodyBytes);
    final lifetime =
        response.statusCode == 304 &&
            !response.headers.containsKey('cache-control') &&
            !response.headers.containsKey('expires')
        ? cached?.freshnessLifetime ?? fallbackCacheDuration
        : _cacheDuration(response);
    final entry = CachedMapTile(
      bytes: bytes,
      expiresAt: _clock().add(lifetime),
      freshnessLifetime: lifetime,
      etag: response.headers['etag'] ?? cached?.etag,
      lastModified: response.headers['last-modified'] ?? cached?.lastModified,
    );
    if (RegExp(r'(^|,)\s*no-store\b')
        .hasMatch(response.headers['cache-control'] ?? '')) {
      _memory.remove(uri);
      try {
        await _cache.remove(uri);
      } on Object {
        /* Best effort cache cleanup. */
      }
    } else {
      if (_memory.length >= 64) _memory.remove(_memory.keys.first);
      _memory[uri] = entry;
      try {
        await _cache.write(uri, entry);
      } on Object {
        /* Keep a valid tile renderable if disk is full. */
      }
    }
    return bytes;
  }

  Duration _cacheDuration(http.Response response) {
    final control = response.headers['cache-control'] ?? '';
    if (RegExp(r'(^|,)\s*no-cache\b').hasMatch(control)) return Duration.zero;
    final seconds = int.tryParse(
      RegExp(r'max-age\s*=\s*(\d+)').firstMatch(control)?.group(1) ?? '',
    );
    if (seconds != null) {
      final age = int.tryParse(response.headers['age'] ?? '') ?? 0;
      return Duration(seconds: (seconds - age).clamp(0, seconds));
    }
    final expires = _httpDate(response.headers['expires']);
    if (expires != null) {
      final remaining = expires.difference(_clock());
      return remaining.isNegative ? Duration.zero : remaining;
    }
    return fallbackCacheDuration;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _memory.clear();
    if (_ownsClient) _client.close();
  }
}

DateTime? _httpDate(String? value) {
  if (value == null) return null;
  final m = RegExp(
    r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  ).firstMatch(value);
  if (m == null) return null;
  final month =
      [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ].indexOf(m[2]!) +
      1;
  if (month == 0) return null;
  return DateTime.utc(
    int.parse(m[3]!),
    month,
    int.parse(m[1]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.parse(m[6]!),
  );
}

final class MapTileLoadException implements Exception {
  const MapTileLoadException(this.uri, this.statusCode);
  final Uri uri;
  final int statusCode;
  @override
  String toString() => 'Map tile request failed ($statusCode)';
}
