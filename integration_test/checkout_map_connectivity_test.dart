import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sports_store/core/maps/map_tile_source.dart';
import 'package:sports_store/features/checkout/presentation/widgets/checkout_design_widgets.dart';
import 'package:sports_store/features/checkout/presentation/widgets/checkout_location_picker.dart';

Future<void> _settleMap(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 30),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android loads and decodes one visible Hanoi tile over HTTPS', (
    tester,
  ) async {
    final source = OpenStreetMapTileSource();
    addTearDown(source.dispose);
    // One visible viewport tile, never an offline region download or prefetch.
    final bytes = await source.loadTile(
      source.tileUri(zoom: 13, x: 6504, y: 3606),
    );
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 256);
      expect(frame.image.height, 256);
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
  });

  testWidgets('Android saves the fixed-pin camera center after a real drag', (
    tester,
  ) async {
    CheckoutLocation? selected;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                child: StatefulBuilder(
                  builder: (context, setState) => Column(
                    children: [
                      CheckoutMapPreview(
                        latitude: selected?.latitude ?? 21.0285,
                        longitude: selected?.longitude ?? 105.8542,
                        showTiles: true,
                        hasSelection: selected != null,
                      ),
                      CheckoutLocationPicker(
                        buttonKey: const ValueKey('native-open-picker'),
                        hasInitialSelection: selected != null,
                        initialLatitude: selected?.latitude ?? 21.0285,
                        initialLongitude: selected?.longitude ?? 105.8542,
                        addressLabel: 'Hà Nội',
                        onPicked: (point) => setState(() => selected = point),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _settleMap(tester);
    expect(find.byKey(const ValueKey('checkout-map-error')), findsNothing);
    expect(
      find.byKey(const ValueKey('checkout-destination-pin')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('native-open-picker')));
    await _settleMap(tester);
    expect(find.byType(TextField), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('checkout-location-confirm')),
          )
          .onPressed,
      isNull,
    );
    const mapKey = ValueKey('checkout-location-map');
    final map = find.byKey(mapKey);
    final pin = find.byKey(const ValueKey('checkout-destination-pin'));
    expect(tester.getRect(pin).bottomCenter, tester.getCenter(map));
    final before = tester.widget<FlutterMap>(map).mapController!.camera.center;
    await tester.drag(map, const Offset(55, -40));
    await _settleMap(tester);
    expect(find.byKey(const ValueKey('checkout-map-error')), findsNothing);
    final intended = tester
        .widget<FlutterMap>(map)
        .mapController!
        .camera
        .center;
    expect(intended.latitude, isNot(before.latitude));
    expect(intended.longitude, isNot(before.longitude));
    expect(tester.getRect(pin).bottomCenter, tester.getCenter(map));
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('checkout-location-confirm')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('checkout-location-confirm')));
    await _settleMap(tester);
    expect(find.byType(Dialog), findsNothing);
    expect(selected!.latitude, closeTo(intended.latitude, 0.00000001));
    expect(selected!.longitude, closeTo(intended.longitude, 0.00000001));
    expect(
      find.byKey(const ValueKey('checkout-destination-pin')),
      findsOneWidget,
    );

    // Reopen at the actual saved point, then cancel without changing it.
    final saved = selected!;
    await tester.tap(find.byKey(const ValueKey('native-open-picker')));
    await _settleMap(tester);
    final reopened = tester
        .widget<FlutterMap>(find.byKey(mapKey))
        .mapController!
        .camera
        .center;
    expect(reopened.latitude, closeTo(saved.latitude, 0.00000001));
    expect(reopened.longitude, closeTo(saved.longitude, 0.00000001));
    await tester.tap(find.byKey(const ValueKey('checkout-location-cancel')));
    await _settleMap(tester);
    expect(selected!.latitude, saved.latitude);
    expect(selected!.longitude, saved.longitude);
    expect(tester.takeException(), isNull);
  });
}
