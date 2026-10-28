import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/maps/map_display_adapter.dart';
import 'package:sports_store/core/maps/map_location.dart';
import 'package:sports_store/core/maps/map_tile_source.dart';
import 'package:sports_store/core/maps/saved_destination_map.dart';

/// Test-only tile outage; no external requests or synthetic map success.
class _Tiles implements MapTileSource {
  final requested = <Uri>[];
  @override
  String get attribution => 'Test map licence';
  @override
  Future<void> dispose() async {}
  @override
  Future<Uint8List> loadTile(Uri uri) {
    requested.add(uri);
    return Future.error(StateError('Test outage'));
  }

  @override
  Uri tileUri({required int zoom, required int x, required int y}) =>
      Uri.https('tiles.invalid', '/$zoom/$x/$y.png');
}

void main() {
  testWidgets(
    'display adapter uses exact coordinate, marker and recenter token',
    (tester) async {
      final tiles = _Tiles();
      var errors = 0;
      const point = MapLocation(latitude: 21.028511, longitude: 105.804817);
      Widget app(int token) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: RasterMapDisplayAdapter(tileSource: tiles).buildMap(
              location: point,

              recenterToken: token,
              onTileError: (_) => errors++,
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(0));
      await tester.pumpAndSettle();
      final map = tester.widget<SavedDestinationMap>(
        find.byType(SavedDestinationMap),
      );
      expect(map.destination.location, point);
      expect(map.destination.phone, isNull);
      final marker = find.byKey(const ValueKey('map-destination-marker'));
      final center = tester.getCenter(marker);
      expect(center, const Offset(200, 160));
      expect(find.byKey(const ValueKey('map-attribution')), findsOneWidget);
      expect(tiles.requested, isNotEmpty);
      expect(errors, greaterThan(0));
      await tester.drag(find.byType(SavedDestinationMap), const Offset(30, 20));
      await tester.pumpAndSettle();
      expect(tester.getCenter(marker), isNot(center));
      await tester.pumpWidget(app(1));
      await tester.pumpAndSettle();
      expect(tester.getCenter(marker), center);
    },
  );
  testWidgets(
    'invalid coordinate shows error without tile requests or invented pin',
    (tester) async {
      final tiles = _Tiles();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RasterMapDisplayAdapter(tileSource: tiles).buildMap(
              location: const MapLocation(latitude: double.nan, longitude: 105),
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('map-destination-marker')),
        findsNothing,
      );
      expect(tiles.requested, isEmpty);
    },
  );
}
