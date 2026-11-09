import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sports_store/features/checkout/presentation/widgets/checkout_address_section.dart';

// Uses a public Hanoi place and visible map tiles only. No login/order RPC.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android searches a real address, confirms and adjusts its center pin',
    (tester) async {
      CheckoutAddressDraft? draft;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(
                  child: CheckoutAddressSection(
                    enabled: true,
                    showTiles: true,
                    onChanged: (value) => draft = value,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('checkout-destination-preview-map')),
        findsNothing,
      );

      Future<void> tapKey(String key) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final target = find.byKey(ValueKey(key));
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await tester.enterText(
        find.byKey(const ValueKey('checkout-address-search')),
        'Tràng Tiền',
      );
      await tapKey('checkout-address-search-button');
      for (var attempt = 0; attempt < 200; attempt++) {
        if (find.byType(ListTile).evaluate().isNotEmpty ||
            find
                .byKey(const ValueKey('checkout-address-search-error'))
                .evaluate()
                .isNotEmpty) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.byKey(const ValueKey('checkout-address-search-error')),
        findsNothing,
      );
      expect(find.byType(ListTile), findsWidgets);
      final result = find.byType(ListTile).first;
      await tester.ensureVisible(result);
      await tester.tap(result);
      await tester.pumpAndSettle();
      final detail = find.byKey(const ValueKey('checkout-address'));
      await tester.ensureVisible(detail);
      await tester.enterText(detail, 'Cổng chính');
      await tapKey('checkout-address-confirm');
      expect(draft!.latitude, isNotNull);
      expect(draft!.addressDetail, startsWith('Cổng chính, '));
      final before = draft!;
      await tapKey('checkout-location');
      expect(
        find.byKey(const ValueKey('checkout-location-latitude')),
        findsNothing,
      );
      final map = find.byKey(const ValueKey('checkout-location-map'));
      final confirm = find.byKey(const ValueKey('checkout-location-confirm'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 35),
      );
      await tester.drag(map, const Offset(50, -35));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 35),
      );
      expect(find.byKey(const ValueKey('checkout-map-error')), findsNothing);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(map, findsNothing);
      expect(draft!.latitude, isNull);
      await tapKey('checkout-address-confirm');
      expect(draft!.latitude, isNot(before.latitude));
      expect(draft!.longitude, isNot(before.longitude));
      expect(draft!.addressDetail, before.addressDetail);
      final search = find.byKey(const ValueKey('checkout-address-search'));
      await tester.ensureVisible(search);
      await tester.enterText(search, 'Đường khác');
      await tester.pumpAndSettle();
      expect(draft!.latitude, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
