import 'dart:async';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sports_store/core/maps/map_tile_source.dart';
import 'package:sports_store/core/maps/map_tile_cache_io.dart';
import 'package:sports_store/core/maps/map_tile_cache.dart';

class _UnavailableCache implements MapTileCache {
  @override
  Future<CachedMapTile?> read(Uri tile) async =>
      throw StateError('Test disk failure');
  @override
  Future<void> write(Uri tile, CachedMapTile value) async =>
      throw StateError('Test quota failure');
  @override
  Future<void> remove(Uri tile) async => throw StateError('Test disk failure');
}

class _StaleWriteFailingCache extends _UnavailableCache {
  @override
  Future<CachedMapTile?> read(Uri tile) async => CachedMapTile(
    bytes: Uint8List.fromList([0]),
    expiresAt: DateTime.utc(2020),
  );
}

void main() {
  test(
    'new memory tile wins over stale disk when persistent write fails',
    () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response.bytes(
          [2],
          200,
          headers: {'cache-control': 'max-age=300'},
        );
      });
      final source = OpenStreetMapTileSource(
        client: client,
        cache: _StaleWriteFailingCache(),
      );
      final uri = source.tileUri(zoom: 1, x: 0, y: 0);
      expect(await source.loadTile(uri), [2]);
      expect(await source.loadTile(uri), [2]);
      expect(calls, 1);
      await source.dispose();
      client.close();
    },
  );
  test(
    'storage failures keep a valid fetched image renderable in session',
    () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response.bytes(
          [1, 2],
          200,
          headers: {'cache-control': 'max-age=3600'},
        );
      });
      final source = OpenStreetMapTileSource(
        client: client,
        cache: _UnavailableCache(),
      );
      final uri = source.tileUri(zoom: 1, x: 0, y: 0);
      expect(await source.loadTile(uri), [1, 2]);
      expect(await source.loadTile(uri), [1, 2]);
      expect(requests, 1);
      await source.dispose();
      client.close();
    },
  );
  test('late network tile is rejected when adapter was disposed', () async {
    final ready = Completer<void>(), response = Completer<http.Response>();
    final client = MockClient((_) {
      ready.complete();
      return response.future;
    });
    final source = OpenStreetMapTileSource(
      client: client,
      cache: _UnavailableCache(),
    );
    final pending = source.loadTile(source.tileUri(zoom: 1, x: 0, y: 0));
    final expectation = expectLater(pending, throwsStateError);
    await ready.future;
    await source.dispose();
    response.complete(http.Response.bytes([1], 200));
    await expectation;
    client.close();
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory cacheDirectory;
  setUp(() async {
    cacheDirectory = await Directory.systemTemp.createTemp(
      'p092_tile_adapter_',
    );
    addTearDown(() async {
      for (final file in await cacheDirectory.list().toList()) {
        if (file is File) await file.delete();
      }
      await cacheDirectory.delete();
    });
  });
  FileMapTileCache cache() =>
      FileMapTileCache(directory: () async => cacheDirectory);
  test('parallel native cache writes remain bounded', () async {
    final store = FileMapTileCache(
      directory: () async => cacheDirectory,
      maxFiles: 2,
      maxBytes: 4096,
    );
    await Future.wait(
      List.generate(
        6,
        (i) => store.write(
          Uri.parse('https://tiles.invalid/3/$i/1.png'),
          CachedMapTile(
            bytes: Uint8List.fromList([i]),
            expiresAt: DateTime.utc(2026, 11),
          ),
        ),
      ),
    );
    expect((await cacheDirectory.list().toList()).length, 2);
  });
  test(
    'no-cache retains validators and requires revalidation even after 304',
    () async {
      var calls = 0;
      final client = MockClient((r) async {
        calls++;
        if (calls == 1) {
          return http.Response.bytes(
            [2],
            200,
            headers: {'cache-control': 'no-cache', 'etag': '"v"'},
          );
        }
        expect(r.headers['if-none-match'], '"v"');
        return http.Response('', 304);
      });
      final source = OpenStreetMapTileSource(
        client: client,
        cache: cache(),
        web: false,
      );
      final uri = source.tileUri(zoom: 1, x: 0, y: 0);
      await source.loadTile(uri);
      await source.loadTile(uri);
      await source.loadTile(uri);
      expect(calls, 3);
      await source.dispose();
      client.close();
    },
  );
  test(
    'HTML and oversized 200 responses are rejected before caching',
    () async {
      var large = false;
      final client = MockClient(
        (_) async => large
            ? http.Response.bytes(List.filled(1024 * 1024 + 1, 1), 200)
            : http.Response(
                '<html>upstream error</html>',
                200,
                headers: {'content-type': 'text/html'},
              ),
      );
      final source = OpenStreetMapTileSource(client: client, cache: cache());
      final uri = source.tileUri(zoom: 1, x: 0, y: 0);
      await expectLater(
        source.loadTile(uri),
        throwsA(isA<MapTileLoadException>()),
      );
      large = true;
      await expectLater(
        source.loadTile(uri),
        throwsA(isA<MapTileLoadException>()),
      );
      expect(await cache().read(uri), isNull);
      await source.dispose();
      client.close();
    },
  );
  test(
    'persistent cache survives adapter disposal and uses app identification',
    () async {
      var calls = 0;
      final client = MockClient((r) async {
        calls++;
        expect(r.headers['user-agent'], contains('sports_store/'));
        expect(r.headers.containsKey('cache-control'), isFalse);
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'cache-control': 'max-age=3600', 'etag': '"one"'},
        );
      });
      final a = OpenStreetMapTileSource(
        cache: cache(),
        client: client,
        web: false,
      );
      final uri = a.tileUri(zoom: 3, x: 2, y: 3);
      expect(await a.loadTile(uri), [1, 2, 3]);
      await a.dispose();
      final b = OpenStreetMapTileSource(
        cache: cache(),
        client: client,
        web: false,
      );
      expect(await b.loadTile(uri), [1, 2, 3]);
      expect(calls, 1);
      await b.dispose();
      client.close();
    },
  );
  test('expired ETag and Last-Modified revalidate once with 304', () async {
    var now = DateTime.utc(2026, 10, 28);
    var calls = 0;
    final client = MockClient((r) async {
      calls++;
      if (calls == 1) {
        return http.Response.bytes(
          [4],
          200,
          headers: {
            'cache-control': 'max-age=1',
            'etag': '"v1"',
            'last-modified': 'Tue, 27 Oct 2026 00:00:00 GMT',
          },
        );
      }
      expect(r.headers['if-none-match'], '"v1"');
      expect(r.headers['if-modified-since'], isNotNull);
      return http.Response('', 304, headers: {'cache-control': 'max-age=300'});
    });
    final source = OpenStreetMapTileSource(
      cache: cache(),
      client: client,
      clock: () => now,
      web: false,
    );
    final uri = source.tileUri(zoom: 1, x: 0, y: 0);
    await source.loadTile(uri);
    now = now.add(const Duration(seconds: 2));
    expect(await source.loadTile(uri), [4]);
    expect(await source.loadTile(uri), [4]);
    expect(calls, 2);
    await source.dispose();
    client.close();
  });
  test(
    'Expires cache and request coalescing respect native disposal',
    () async {
      final pending = Completer<http.Response>();
      var calls = 0;
      var now = DateTime.utc(2026, 10, 28);
      final client = MockClient((_) {
        calls++;
        return pending.future;
      });
      final source = OpenStreetMapTileSource(
        cache: cache(),
        client: client,
        clock: () => now,
      );
      final uri = source.tileUri(zoom: 1, x: 0, y: 0);
      final a = source.loadTile(uri), b = source.loadTile(uri);
      await Future<void>.delayed(Duration.zero);
      pending.complete(
        http.Response.bytes(
          [8],
          200,
          headers: {'expires': 'Wed, 28 Oct 2026 01:00:00 GMT'},
        ),
      );
      expect(await a, [8]);
      expect(await b, [8]);
      expect(calls, 1);
      now = now.add(const Duration(minutes: 30));
      expect(await source.loadTile(uri), [8]);
      expect(calls, 1);
      await source.dispose();
      await expectLater(source.loadTile(uri), throwsStateError);
      client.close();
    },
  );
  test('web relies on browser UA/Referer and failure is testable', () async {
    final client = MockClient((r) async {
      expect(r.headers.containsKey('user-agent'), isFalse);
      expect(r.headers.containsKey('referer'), isFalse);
      return http.Response('unavailable', 503);
    });
    final source = OpenStreetMapTileSource(
      cache: cache(),
      client: client,
      web: true,
    );
    await expectLater(
      source.loadTile(source.tileUri(zoom: 1, x: 0, y: 0)),
      throwsA(isA<MapTileLoadException>()),
    );
    await expectLater(
      source.loadTile(Uri.parse('https://elsewhere.invalid/1/0/0.png')),
      throwsArgumentError,
    );
    await expectLater(
      source.loadTile(
        Uri.parse('https://tile.openstreetmap.org/1/0/0.png?phone=secret'),
      ),
      throwsArgumentError,
    );
    await source.dispose();
    client.close();
  });
  test(
    'no-store does not persist and no-cache requests revalidation',
    () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response.bytes(
          [1],
          200,
          headers: {'cache-control': 'no-store'},
        );
      });
      final source = OpenStreetMapTileSource(cache: cache(), client: client);
      final uri = source.tileUri(zoom: 1, x: 0, y: 0);
      await source.loadTile(uri);
      await source.loadTile(uri);
      expect(calls, 2);
      await source.dispose();
      client.close();
    },
  );
}
