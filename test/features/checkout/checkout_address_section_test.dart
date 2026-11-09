import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/checkout/presentation/view_models/checkout_address_providers.dart';
import 'package:sports_store/features/checkout/presentation/widgets/checkout_address_section.dart';

class _Addresses implements AddressSearchRepository {
  final queries = <String>[];
  bool fail = false;
  String label = 'Tràng Tiền, Hoàn Kiếm, Hà Nội';

  @override
  Future<List<AddressSuggestion>> search(String query) async {
    queries.add(query);
    if (fail) {
      throw const AddressSearchFailure(AddressSearchFailureCode.network);
    }
    return [
      AddressSuggestion(
        id: 'street',
        label: label,
        latitude: 21.03,
        longitude: 105.85,
      ),
    ];
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Addresses repository,
  ValueChanged<CheckoutAddressDraft> onChanged, {
  bool enabled = true,
  String initialAddress = '',
  double? initialLatitude,
  double? initialLongitude,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        addressSearchRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CheckoutAddressSection(
              enabled: enabled,
              showTiles: false,
              onChanged: onChanged,
              initialAddress: initialAddress,
              initialLatitude: initialLatitude,
              initialLongitude: initialLongitude,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

Future<void> _selectStreet(WidgetTester tester) async {
  await _enter(tester, 'checkout-address-search', 'Tràng Tiền');
  await _tap(tester, 'checkout-address-search-button');
  await _tap(tester, 'checkout-address-suggestion-street');
}

void main() {
  testWidgets(
    'address-first search confirms real coordinates and composed snapshot',
    (tester) async {
      final repository = _Addresses();
      CheckoutAddressDraft? draft;
      await _mount(tester, repository, (value) => draft = value);
      expect(
        find.byKey(const ValueKey('checkout-destination-preview-map')),
        findsNothing,
      );
      await _enter(tester, 'checkout-address-search', 'Tràng Tiền');
      expect(repository.queries, isEmpty);
      await _tap(tester, 'checkout-address-search-button');
      await _tap(tester, 'checkout-address-suggestion-street');
      expect(draft!.latitude, isNull);
      await _enter(tester, 'checkout-address', 'Số 12, ngõ 5');
      await _tap(tester, 'checkout-address-confirm');
      expect(draft, (
        addressDetail: 'Số 12, ngõ 5, Tràng Tiền, Hoàn Kiếm, Hà Nội',
        latitude: 21.03,
        longitude: 105.85,
      ));
      expect(repository.queries, ['Tràng Tiền']);
      expect(find.text('Đã xác nhận địa chỉ nhận hàng.'), findsOneWidget);
    },
  );

  testWidgets(
    'editing street or details invalidates confirmation and stale coordinates',
    (tester) async {
      final repository = _Addresses();
      CheckoutAddressDraft? draft;
      await _mount(tester, repository, (value) => draft = value);
      await _selectStreet(tester);
      await _enter(tester, 'checkout-address', 'Số 12');
      await _tap(tester, 'checkout-address-confirm');
      expect(draft!.latitude, 21.03);
      await _enter(tester, 'checkout-address', 'Số 14');
      expect(draft!.latitude, isNull);
      await _tap(tester, 'checkout-address-confirm');
      expect(draft!.addressDetail, startsWith('Số 14,'));
      await _enter(tester, 'checkout-address-search', 'Đường khác');
      expect(draft!.latitude, isNull);
      expect(draft!.addressDetail, isEmpty);
      expect(
        find.byKey(const ValueKey('checkout-selected-address')),
        findsNothing,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('checkout-address-confirm')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'search failure allows explicit manual address and fixed-pin fallback',
    (tester) async {
      final repository = _Addresses()..fail = true;
      CheckoutAddressDraft? draft;
      await _mount(tester, repository, (value) => draft = value);
      await _enter(tester, 'checkout-address-search', 'Đường Tràng Tiền');
      await _tap(tester, 'checkout-address-search-button');
      expect(
        find.byKey(const ValueKey('checkout-address-search-error')),
        findsOneWidget,
      );
      await _enter(
        tester,
        'checkout-address',
        'Số 1 Tràng Tiền, Hoàn Kiếm, Hà Nội',
      );
      await _tap(tester, 'checkout-location');
      expect(
        find.byKey(const ValueKey('checkout-location-latitude')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('checkout-location-longitude')),
        findsNothing,
      );
      final confirm = find.byKey(const ValueKey('checkout-location-confirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.drag(
        find.byKey(const ValueKey('checkout-location-map')),
        const Offset(50, -35),
      );
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(draft!.latitude, isNull);
      await _tap(tester, 'checkout-address-confirm');
      expect(draft!.latitude, isNotNull);
      expect(draft!.latitude, isNot(21.0285));
      expect(draft!.addressDetail, 'Số 1 Tràng Tiền, Hoàn Kiếm, Hà Nội');
      await _enter(tester, 'checkout-address', 'Số 12 phố khác, Hà Nội');
      expect(draft!.latitude, isNull);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('checkout-address-confirm')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pending snapshot is unchanged and locked without geocoding', (
    tester,
  ) async {
    final repository = _Addresses();
    CheckoutAddressDraft? draft;
    await _mount(
      tester,
      repository,
      (value) => draft = value,
      enabled: false,
      initialAddress: 'Địa chỉ nguyên bản từ yêu cầu cũ',
      initialLatitude: 21.03,
      initialLongitude: 105.85,
    );
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('checkout-address')),
    );
    expect(field.controller!.text, 'Địa chỉ nguyên bản từ yêu cầu cũ');
    expect(field.enabled, isFalse);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('checkout-location')),
          )
          .onPressed,
      isNull,
    );
    expect(draft, isNull);
    expect(repository.queries, isEmpty);
  });

  testWidgets(
    'combined address longer than the server limit cannot be confirmed',
    (tester) async {
      final repository = _Addresses()..label = List.filled(490, 'A').join();
      CheckoutAddressDraft? draft;
      await _mount(tester, repository, (value) => draft = value);
      await _selectStreet(tester);
      await _enter(tester, 'checkout-address', 'Số 12345, tầng 12');
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('checkout-address-confirm')),
            )
            .onPressed,
        isNull,
      );
      expect(draft!.latitude, isNull);
      expect(
        find.text('Địa chỉ tối đa 500 ký tự. Vui lòng rút ngắn phần chi tiết.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('address-first form remains usable at 320px and large text', (
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
    CheckoutAddressDraft? draft;
    await _mount(tester, _Addresses(), (value) => draft = value);
    await _selectStreet(tester);
    await _enter(tester, 'checkout-address', 'Số 12');
    await _tap(tester, 'checkout-address-confirm');
    expect(draft!.latitude, 21.03);
    expect(tester.takeException(), isNull);
  });
}
