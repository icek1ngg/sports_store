import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/maps/flutter_map_tile_provider.dart';
import 'package:sports_store/core/maps/map_tile_source.dart';

class _Source implements MapTileSource {
  int loads = 0;
  int disposals = 0;
  Uri? lastUri;
  bool fail = false;
  bool corrupt = false;

  @override
  String get attribution => 'Test map';
  @override
  Uri tileUri({required int zoom, required int x, required int y}) =>
      Uri.https('map.example', '/$zoom/$x/$y.png');
  @override
  Future<Uint8List> loadTile(Uri uri) async {
    loads++;
    lastUri = uri;
    if (fail) throw StateError('Test tile unavailable');
    return corrupt
        ? Uint8List.fromList([1, 2, 3])
        : TileProvider.transparentImage;
  }

  @override
  Future<void> dispose() async => disposals++;
}

ImageProvider _image(FlutterMapTileProvider adapter) =>
    adapter.getImage(const TileCoordinates(6504, 3606, 13), TileLayer());

Future<bool> _resolve(WidgetTester tester, ImageProvider image) async =>
    (await tester.runAsync(() async {
      final result = Completer<bool>();
      final stream = image.resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          info.dispose();
          result.complete(true);
        },
        onError: (Object error, StackTrace? stackTrace) =>
            result.complete(false),
      );
      stream.addListener(listener);
      final success = await result.future.timeout(const Duration(seconds: 5));
      stream.removeListener(listener);
      await Future<void>.value();
      return success;
    }))!;

void main() {
  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('loads the shared source and reports image-cache hits', (
    tester,
  ) async {
    final source = _Source();
    var loaded = 0;
    final adapter = FlutterMapTileProvider(
      source: source,
      onTileLoaded: () => loaded++,
    );
    expect(await _resolve(tester, _image(adapter)), isTrue);
    expect(source.lastUri, Uri.https('map.example', '/13/6504/3606.png'));
    expect(source.loads, 1);
    expect(loaded, 1);
    expect(await _resolve(tester, _image(adapter)), isTrue);
    expect(source.loads, 1);
    expect(loaded, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('source identity and retry generation isolate image cache', (
    tester,
  ) async {
    final first = _Source();
    final second = _Source();
    expect(
      await _resolve(tester, _image(FlutterMapTileProvider(source: first))),
      isTrue,
    );
    expect(
      await _resolve(tester, _image(FlutterMapTileProvider(source: second))),
      isTrue,
    );
    expect(first.loads, 1);
    expect(second.loads, 1);
    expect(
      await _resolve(
        tester,
        _image(FlutterMapTileProvider(source: second, generation: 1)),
      ),
      isTrue,
    );
    expect(second.loads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('URI-only callback reports the decoded tile on cache hits', (
    tester,
  ) async {
    final source = _Source();
    final decoded = <Uri>[];
    final adapter = FlutterMapTileProvider(
      source: source,
      onTileLoadedUri: decoded.add,
    );
    expect(await _resolve(tester, _image(adapter)), isTrue);
    expect(await _resolve(tester, _image(adapter)), isTrue);
    expect(source.loads, 1);
    expect(decoded, [
      Uri.https('map.example', '/13/6504/3606.png'),
      Uri.https('map.example', '/13/6504/3606.png'),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('network failures report an error and explicit retry recovers', (
    tester,
  ) async {
    final source = _Source()..fail = true;
    var errors = 0;
    var loaded = 0;
    FlutterMapTileProvider adapter(int generation) => FlutterMapTileProvider(
      source: source,
      generation: generation,
      onTileError: (_) => errors++,
      onTileLoaded: () => loaded++,
    );
    expect(await _resolve(tester, _image(adapter(0))), isFalse);
    expect(errors, 1);
    expect(loaded, 0);
    expect(tester.takeException(), isNull);
    source.fail = false;
    expect(await _resolve(tester, _image(adapter(1))), isTrue);
    expect(source.loads, 2);
    expect(loaded, 1);
    expect(errors, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('corrupt tile bytes do not report successful image loading', (
    tester,
  ) async {
    final source = _Source()..corrupt = true;
    var errors = 0;
    var loaded = 0;
    expect(
      await _resolve(
        tester,
        _image(
          FlutterMapTileProvider(
            source: source,
            onTileError: (_) => errors++,
            onTileLoaded: () => loaded++,
          ),
        ),
      ),
      isFalse,
    );
    expect(errors, 1);
    expect(loaded, 0);
    expect(tester.takeException(), isNull);
  });

  test('disposing an adapter leaves the shared source owned by its caller', () {
    final source = _Source();
    FlutterMapTileProvider(source: source).dispose();
    expect(source.disposals, 0);
  });
}
