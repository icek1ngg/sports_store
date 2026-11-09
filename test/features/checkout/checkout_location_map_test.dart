import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sports_store/core/maps/map_providers.dart';
import 'package:sports_store/core/maps/map_tile_source.dart';
import 'package:sports_store/features/checkout/presentation/widgets/checkout_design_widgets.dart';
import 'package:sports_store/features/checkout/presentation/widgets/checkout_location_map.dart';
import 'package:sports_store/features/checkout/presentation/widgets/checkout_location_picker.dart';

class _TileSource implements MapTileSource {
  Completer<void>? gate;
  bool fail = false;
  final requested = <Uri>[];
  final gates = <Uri, Completer<void>>{};
  @override
  String get attribution => 'Test tiles';
  @override
  Uri tileUri({required int zoom, required int x, required int y}) =>
      Uri.https('map.example', '/$zoom/$x/$y.png');
  @override
  Future<Uint8List> loadTile(Uri uri) async {
    requested.add(uri);
    await gate?.future;
    await gates[uri]?.future;
    if (fail) throw StateError('Test network unavailable');
    return TileProvider.transparentImage;
  }

  @override
  Future<void> dispose() async {}
}

Widget _host(Widget child, {_TileSource? source, double width = 340}) =>
    ProviderScope(
      overrides: [
        if (source != null) mapTileSourceProvider.overrideWithValue(source),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );
const _confirmKey = ValueKey('checkout-location-confirm');
const _pinKey = ValueKey('checkout-destination-pin');
const _mapKey = ValueKey('checkout-location-map');

Future<void> _openPicker(
  WidgetTester tester, {
  bool waitForTiles = false,
}) async {
  await tester.tap(find.text('Chọn vị trí giao hàng trên bản đồ'));
  await tester.pump(const Duration(milliseconds: 350));
  if (waitForTiles) {
    await _settleDecodedTiles(tester);
  } else {
    await tester.pumpAndSettle();
  }
}

Future<void> _settleDecodedTiles(WidgetTester tester) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byKey(const ValueKey('checkout-map-loading')).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
}

Future<void> _decodeVisibleEdges(WidgetTester tester) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (tester
        .widgetList<RawImage>(find.byType(RawImage))
        .any((image) => image.image != null)) {
      return;
    }
  }
  fail('Expected an edge tile to decode while the center remains deferred');
}

FilledButton _confirm(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(_confirmKey));
FlutterMap _map(WidgetTester tester) =>
    tester.widget<FlutterMap>(find.byKey(_mapKey));

void main() {
  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('shared tiles expose loading until a tile image decodes', (
    tester,
  ) async {
    final source = _TileSource()..gate = Completer<void>();
    await tester.pumpWidget(
      _host(
        const CheckoutLocationMap(
          latitude: 21.0285,
          longitude: 105.8542,
          showTiles: true,
        ),
        source: source,
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('checkout-map-loading')), findsOneWidget);
    expect(source.requested, isNotEmpty);
    source.gate!.complete();
    await _settleDecodedTiles(tester);
    expect(find.byKey(const ValueKey('checkout-map-loading')), findsNothing);
    expect(find.byKey(const ValueKey('checkout-map-error')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tile failure is visible and explicit retry requests new images',
    (tester) async {
      final source = _TileSource()..fail = true;
      await tester.pumpWidget(
        _host(
          const CheckoutLocationMap(
            latitude: 21.0285,
            longitude: 105.8542,
            showTiles: true,
          ),
          source: source,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('checkout-map-error')), findsOneWidget);
      final before = source.requested.length;
      source.fail = false;
      await tester.tap(find.byKey(const ValueKey('checkout-map-retry')));
      await tester.pump();
      await _settleDecodedTiles(tester);
      expect(source.requested.length, greaterThan(before));
      expect(find.byKey(const ValueKey('checkout-map-error')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Hanoi preview does not imply a selected destination', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const CheckoutMapPreview(
          latitude: 21.0285,
          longitude: 105.8542,
          showTiles: false,
          hasSelection: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_pinKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full screen picker has fixed center pin and needs a real drag', (
    tester,
  ) async {
    CheckoutLocation? selected;
    await tester.pumpWidget(
      _host(
        CheckoutLocationPicker(
          showTiles: false,
          onPicked: (value) => selected = value,
        ),
      ),
    );
    await _openPicker(tester);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(_confirm(tester).onPressed, isNull);
    expect(
      find.text('Kéo bản đồ để đưa ghim đến đúng nơi nhận hàng'),
      findsOneWidget,
    );
    final pinRect = tester.getRect(find.byKey(_pinKey));
    final mapCenter = tester.getCenter(find.byKey(_mapKey));
    expect(pinRect.bottomCenter, mapCenter);
    final initial = _map(tester).mapController!.camera.center;
    await tester.drag(find.byKey(_mapKey), const Offset(65, -45));
    await tester.pumpAndSettle();
    final camera = _map(tester).mapController!.camera.center;
    expect(camera.latitude, isNot(initial.latitude));
    expect(camera.longitude, isNot(initial.longitude));
    expect(tester.getRect(find.byKey(_pinKey)).bottomCenter, mapCenter);
    expect(_confirm(tester).onPressed, isNotNull);
    await tester.tap(find.byKey(_confirmKey));
    await tester.pumpAndSettle();
    expect(selected!.latitude, closeTo(camera.latitude, 0.00000001));
    expect(selected!.longitude, closeTo(camera.longitude, 0.00000001));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'programmatic camera movement never silently selects a location',
    (tester) async {
      var selections = 0;
      await tester.pumpWidget(
        _host(
          CheckoutLocationMap(
            latitude: 21.0285,
            longitude: 105.8542,
            centerPin: true,
            hasSelection: false,
            showTiles: false,
            mapKey: _mapKey,
            onPicked: (_) => selections++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      _map(tester).mapController!.move(const LatLng(21.045, 105.812), 15);
      await tester.pumpAndSettle();
      expect(selections, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tap recenters the fixed pin and confirms the tapped point', (
    tester,
  ) async {
    CheckoutLocation? selected;
    await tester.pumpWidget(
      _host(
        CheckoutLocationPicker(
          showTiles: false,
          onPicked: (value) => selected = value,
        ),
      ),
    );
    await _openPicker(tester);
    await tester.tapAt(
      tester.getCenter(find.byKey(_mapKey)) + const Offset(45, -30),
    );
    await tester.pumpAndSettle();
    final point = _map(tester).mapController!.camera.center;
    expect(_confirm(tester).onPressed, isNotNull);
    await tester.tap(find.byKey(_confirmKey));
    await tester.pumpAndSettle();
    expect(selected!.latitude, closeTo(point.latitude, 0.00000001));
    expect(selected!.longitude, closeTo(point.longitude, 0.00000001));
    expect(tester.takeException(), isNull);
  });

  for (final initial in [
    (latitude: 999.0, longitude: 105.8542),
    (latitude: 89.0, longitude: 105.8542),
    (latitude: 21.0285, longitude: double.nan),
    (latitude: double.infinity, longitude: 999.0),
  ]) {
    testWidgets('invalid initial point $initial cannot be confirmed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          CheckoutLocationPicker(
            initialLatitude: initial.latitude,
            initialLongitude: initial.longitude,
            hasInitialSelection: true,
            showTiles: false,
            onPicked: (_) {},
          ),
        ),
      );
      await _openPicker(tester);
      final center = _map(tester).mapController!.camera.center;
      expect(center.latitude, 21.0285);
      expect(center.longitude, 105.8542);
      expect(_confirm(tester).onPressed, isNull);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'reopening preserves the saved point and provided address label',
    (tester) async {
      CheckoutLocation? selected = const CheckoutLocation(
        latitude: 21.045,
        longitude: 105.812,
      );
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => CheckoutLocationPicker(
              initialLatitude: selected!.latitude,
              initialLongitude: selected!.longitude,
              hasInitialSelection: true,
              addressLabel: '25 Nguyễn Chí Thanh, Hà Nội',
              showTiles: false,
              onPicked: (value) => setState(() => selected = value),
            ),
          ),
        ),
      );
      await _openPicker(tester);
      expect(find.text('25 Nguyễn Chí Thanh, Hà Nội'), findsOneWidget);
      expect(
        _map(tester).mapController!.camera.center.latitude,
        selected!.latitude,
      );
      await tester.drag(find.byKey(_mapKey), const Offset(-35, 25));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_confirmKey));
      await tester.pumpAndSettle();
      final saved = selected!;
      await _openPicker(tester);
      final reopened = _map(tester).mapController!.camera.center;
      expect(reopened.latitude, closeTo(saved.latitude, 0.00000001));
      expect(reopened.longitude, closeTo(saved.longitude, 0.00000001));
      expect(_confirm(tester).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancel preserves the caller and a disabled picker cannot open', (
    tester,
  ) async {
    var selections = 0;
    await tester.pumpWidget(
      _host(
        CheckoutLocationPicker(showTiles: false, onPicked: (_) => selections++),
      ),
    );
    await _openPicker(tester);
    await tester.drag(find.byKey(_mapKey), const Offset(35, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('checkout-location-cancel')));
    await tester.pumpAndSettle();
    expect(selections, 0);
    expect(find.byType(Dialog), findsNothing);
    await tester.pumpWidget(
      _host(
        CheckoutLocationPicker(
          enabled: false,
          showTiles: false,
          onPicked: (_) => selections++,
        ),
      ),
    );
    await tester.tap(find.text('Chọn vị trí giao hàng trên bản đồ'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'confirmation is disabled during a drag and final viewport loading',
    (tester) async {
      final source = _TileSource();
      await tester.pumpWidget(
        _host(
          CheckoutLocationPicker(hasInitialSelection: true, onPicked: (_) {}),
          source: source,
        ),
      );
      await _openPicker(tester, waitForTiles: true);
      expect(_confirm(tester).onPressed, isNotNull);
      source.gate = Completer<void>();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_mapKey)),
      );
      await gesture.moveBy(const Offset(60, -30));
      await tester.pump();
      expect(_confirm(tester).onPressed, isNull);
      await gesture.up();
      await tester.pump();
      expect(_confirm(tester).onPressed, isNull);
      expect(
        find.byKey(const ValueKey('checkout-map-loading')),
        findsOneWidget,
      );
      source.gate!.complete();
      await _settleDecodedTiles(tester);
      expect(_confirm(tester).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed final viewport disables confirm and retry preserves its dragged point',
    (tester) async {
      CheckoutLocation? selected;
      final source = _TileSource();
      await tester.pumpWidget(
        _host(
          CheckoutLocationPicker(
            hasInitialSelection: true,
            onPicked: (value) => selected = value,
          ),
          source: source,
        ),
      );
      await _openPicker(tester, waitForTiles: true);
      source.fail = true;
      await tester.drag(find.byKey(_mapKey), const Offset(-55, 35));
      await tester.pumpAndSettle();
      final intended = _map(tester).mapController!.camera.center;
      expect(find.byKey(const ValueKey('checkout-map-error')), findsOneWidget);
      expect(_confirm(tester).onPressed, isNull);
      source.fail = false;
      await tester.tap(find.byKey(const ValueKey('checkout-map-retry')));
      await tester.pump();
      await _settleDecodedTiles(tester);
      expect(_confirm(tester).onPressed, isNotNull);
      await tester.tap(find.byKey(_confirmKey));
      await tester.pumpAndSettle();
      expect(selected!.latitude, closeTo(intended.latitude, 0.00000001));
      expect(selected!.longitude, closeTo(intended.longitude, 0.00000001));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'decoded edge tiles cannot enable confirmation before the center tile',
    (tester) async {
      final source = _TileSource();
      // EPSG:3857 at Hanoi, native zoom15: this exact tile contains the pin.
      final centerUri = Uri.https('map.example', '/15/26019/14425.png');
      final centerGate = Completer<void>();
      source.gates[centerUri] = centerGate;
      await tester.pumpWidget(
        _host(
          CheckoutLocationPicker(hasInitialSelection: true, onPicked: (_) {}),
          source: source,
        ),
      );
      await tester.tap(find.text('Chọn vị trí giao hàng trên bản đồ'));
      await tester.pump(const Duration(milliseconds: 350));
      await _decodeVisibleEdges(tester);
      expect(source.requested, contains(centerUri));
      expect(_confirm(tester).onPressed, isNull);
      expect(
        find.byKey(const ValueKey('checkout-map-loading')),
        findsOneWidget,
      );
      centerGate.complete();
      await _settleDecodedTiles(tester);
      expect(_confirm(tester).onPressed, isNotNull);

      // Closing and reopening resolves the same URI through Flutter's cache.
      final requests = source.requested.length;
      await tester.tap(find.byKey(const ValueKey('checkout-location-cancel')));
      await tester.pumpAndSettle();
      await _openPicker(tester, waitForTiles: true);
      expect(_confirm(tester).onPressed, isNotNull);
      expect(source.requested.length, requests);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'camera center and rounded zoom cannot reuse a previously decoded center',
    (tester) async {
      final source = _TileSource();
      final ready = <bool>[];
      await tester.pumpWidget(
        _host(
          CheckoutLocationMap(
            latitude: 21.0285,
            longitude: 105.8542,
            showTiles: true,
            centerPin: true,
            mapKey: _mapKey,
            onPicked: (_) {},
            onReadyChanged: ready.add,
          ),
          source: source,
        ),
      );
      await _settleDecodedTiles(tester);
      expect(ready.last, isTrue);
      final center15 = Uri.https('map.example', '/15/26015/14423.png');
      final gate15 = Completer<void>();
      source.gates[center15] = gate15;
      _map(tester).mapController!.move(const LatLng(21.045, 105.812), 14.6);
      await tester.pump();
      await _decodeVisibleEdges(tester);
      expect(source.requested, contains(center15));
      expect(ready.last, isFalse);
      gate15.complete();
      await _settleDecodedTiles(tester);
      expect(ready.last, isTrue);

      // 14.4 rounds to native zoom14 rather than reusing the zoom15 image.
      final center14 = Uri.https('map.example', '/14/13007/7211.png');
      final gate14 = Completer<void>();
      source.gates[center14] = gate14;
      _map(tester).mapController!.move(const LatLng(21.045, 105.812), 14.4);
      await tester.pump();
      await _decodeVisibleEdges(tester);
      expect(source.requested, contains(center14));
      expect(ready.last, isFalse);
      gate14.complete();
      await _settleDecodedTiles(tester);
      expect(ready.last, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'callbacks from a replaced tile source cannot unlock the current center',
    (tester) async {
      final oldSource = _TileSource()..gate = Completer<void>();
      final currentSource = _TileSource();
      final currentCenter = Completer<void>();
      currentSource.gates[Uri.https('map.example', '/15/26019/14425.png')] =
          currentCenter;
      final ready = <bool>[];
      Widget host(_TileSource source) => _host(
        CheckoutLocationMap(
          latitude: 21.0285,
          longitude: 105.8542,
          showTiles: true,
          centerPin: true,
          onPicked: (_) {},
          onReadyChanged: ready.add,
        ),
        source: source,
      );
      await tester.pumpWidget(host(oldSource));
      await tester.pump();
      await tester.pumpWidget(host(currentSource));
      await _decodeVisibleEdges(tester);
      expect(ready.last, isFalse);
      oldSource.gate!.complete();
      await _decodeVisibleEdges(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(ready.last, isFalse);
      expect(
        find.byKey(const ValueKey('checkout-map-loading')),
        findsOneWidget,
      );
      currentCenter.complete();
      await _settleDecodedTiles(tester);
      expect(ready.last, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('full screen picker remains usable at 320px and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(
      _host(
        CheckoutLocationPicker(
          showTiles: false,
          addressLabel: '25 Nguyễn Chí Thanh, phường Láng, Hà Nội',
          onPicked: (_) {},
        ),
        width: 320,
      ),
    );
    await _openPicker(tester);
    expect(tester.getSize(find.byKey(_mapKey)).height, greaterThan(150));
    await tester.drag(find.byKey(_mapKey), const Offset(30, 25));
    await tester.pumpAndSettle();
    expect(_confirm(tester).onPressed, isNotNull);
    expect(
      tester.getRect(find.byKey(_confirmKey)).bottom,
      lessThanOrEqualTo(900),
    );
    expect(tester.takeException(), isNull);
  });
}
