import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/checkout/data/repositories/pending_placement_store.dart';
import 'package:sports_store/features/checkout/presentation/view_models/checkout_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/catalog/catalog_repository_test.dart'
    show productId, productRow, variantId, variantRow;
import '../../features/support/operational_supabase_fixture.dart';

const _recipient = '[THỬ NGHIỆM] Khách hàng A';
const _phone = '0901234567';
const _address = 'Số 1 phố Tràng Tiền, Hoàn Kiếm, Hà Nội';
const _latitude = 21.03;
const _longitude = 105.85;

/// Isolated SDK transport; the application uses its production router,
/// ViewModels and repositories. No cloud sessions, orders or stock are changed.
class _CustomerFixture {
  late final SupabaseClient client;
  String role = 'customer';
  Completer<void>? profileGate;
  bool profileNetworkFailure = false;
  int profileReads = 0;
  final placements = <Map<String, dynamic>>[];

  Future<void> initialize() async {
    client = await fixtureClient(_respond);
  }

  Future<http.Response> _respond(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/profiles')) {
      profileReads++;
      await profileGate?.future;
      if (profileNetworkFailure) {
        throw http.ClientException(
          'Isolated profile network failure',
          request.url,
        );
      }
      return jsonResponse(request, [
        {'role': role},
      ]);
    }
    if (path.endsWith('/categories')) {
      final offset = request.url.queryParameters['offset'] ?? '0';
      return jsonResponse(
        request,
        offset == '0' ? [productRow()['categories']] : [],
      );
    }
    if (path.endsWith('/products')) {
      return jsonResponse(request, [productRow()]);
    }
    if (path.endsWith('/product_variants')) {
      final after = request.url.queryParameters['id'];
      return jsonResponse(
        request,
        after?.startsWith('gt.') == true ? [] : [variantRow()],
      );
    }
    if (path.endsWith('/cart_items')) {
      final after = request.url.queryParameters['variant_id'];
      return jsonResponse(
        request,
        after?.startsWith('gt.') == true
            ? []
            : [
                {
                  'customer_id': client.auth.currentUser!.id,
                  'variant_id': variantId,
                  'quantity': 2,
                  'product_variants': variantRow()..['products'] = productRow(),
                },
              ],
      );
    }
    if (path.endsWith('/rpc/place_order')) {
      final payload = Map<String, dynamic>.from(
        jsonDecode(request.body) as Map,
      );
      placements.add(payload);
      return jsonResponse(request, {
        'ok': true,
        'data': _receipt(payload),
        'error': null,
      });
    }
    if (path.endsWith('/logout')) return jsonResponse(request, null);
    throw StateError('Unexpected customer fixture endpoint: $path');
  }

  Map<String, Object?> _receipt(Map<String, dynamic> payload) {
    const orderId = '60000000-0000-4000-8000-000000000001';
    const stamp = '2026-10-28T10:00:00Z';
    return {
      'order': {
        'id': orderId,
        'customer_id': client.auth.currentUser!.id,
        'request_id': payload['p_request_id'],
        'status': 'pending_confirmation',
        'recipient_name': payload['p_recipient_name'],
        'recipient_phone': payload['p_recipient_phone'],
        'address_detail': payload['p_address_detail'],
        'latitude': payload['p_latitude'],
        'longitude': payload['p_longitude'],
        'subtotal_vnd': 1380000,
        'delivery_fee_vnd': 30000,
        'total_cod_vnd': 1410000,
        'delivery_attempt_count': 0,
        'placed_at': stamp,
        'confirmed_at': null,
        'source': null,
        'confirmed_by': null,
        'delivered_at': null,
        'cancel_reason': null,
        'created_at': stamp,
        'updated_at': stamp,
      },
      'items': [
        {
          'id': '70000000-0000-4000-8000-000000000001',
          'order_id': orderId,
          'product_id': productId,
          'variant_id': variantId,
          'product_name': 'Giày chạy bộ',
          'variant_label': 'Đen / 40',
          'attributes': {'size': '40'},
          'unit_price_vnd': 690000,
          'quantity': 2,
          'line_total_vnd': 1380000,
          'created_at': stamp,
        },
      ],
      'event_id': '80000000-0000-4000-8000-000000000001',
      'replayed': false,
    };
  }
}

class _App {
  const _App(this.fixture, this.container, this.router);
  final _CustomerFixture fixture;
  final ProviderContainer container;
  final GoRouter router;

  void refreshSession() =>
      container.read(operationalReadAccessProvider).refreshSession();
}

Future<_App> _openCheckout(WidgetTester tester) async {
  final fixture = _CustomerFixture();
  await tester.runAsync(fixture.initialize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(fixture.client),
        pendingPlacementStoreProvider.overrideWithValue(
          InMemoryPendingPlacementStore(),
        ),
        checkoutMapTilesEnabledProvider.overrideWithValue(false),
      ],
      child: const SportsStoreApp(),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(SportsStoreApp)),
  );
  final router = container.read(appRouterProvider);
  addTearDown(() async {
    final gate = fixture.profileGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(fixture.client.dispose);
  });

  router.go('/customer/products');
  await _until(tester, () => _visible('catalog-product-list'));
  unawaited(router.push('/customer/cart'));
  await _until(tester, () => _visible('cart-checkout'));
  await _tap(tester, 'cart-checkout');
  await _until(tester, () => _visible('checkout-name'));
  expect(router.state.uri.path, '/customer/checkout');
  await _enter(tester, 'checkout-name', _recipient);
  await _enter(tester, 'checkout-phone', _phone);
  await _enter(tester, 'checkout-address', _address);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  return _App(fixture, container, router);
}

Future<void> _selectLocation(WidgetTester tester) async {
  await _tap(tester, 'checkout-location');
  await _until(tester, () => _visible('checkout-location-confirm'));
  await _enter(tester, 'checkout-location-latitude', '$_latitude');
  await _enter(tester, 'checkout-location-longitude', '$_longitude');
  await _tap(tester, 'checkout-location-confirm');
  await tester.pumpAndSettle();
}

Future<void> _expectField(WidgetTester tester, String key, String value) async {
  await _show(tester, key);
  expect(
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text,
    value,
  );
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var index = 0; index < 250; index++) {
    if (done()) return;
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Customer route did not reach the expected state.');
}

bool _visible(String key) => find.byKey(ValueKey(key)).evaluate().isNotEmpty;

Future<void> _show(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) {
    final scrollable = find.byType(Scrollable).first;
    final scrollState = tester.state<ScrollableState>(scrollable);
    scrollState.position.jumpTo(scrollState.position.minScrollExtent);
    await tester.pump();
    await tester.scrollUntilVisible(finder, 180, scrollable: scrollable);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _show(tester, key);
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump();
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  await _show(tester, key);
  await tester.enterText(find.byKey(ValueKey(key)), value);
}

void main() {
  testWidgets(
    'same-user session recheck preserves checkout form and selected coordinates',
    (tester) async {
      final app = await _openCheckout(tester);
      await _selectLocation(tester);
      final readsBefore = app.fixture.profileReads;
      app.refreshSession();
      await _until(
        tester,
        () =>
            app.fixture.profileReads > readsBefore && _visible('checkout-form'),
      );
      expect(app.router.state.uri.path, '/customer/checkout');
      await _expectField(tester, 'checkout-name', _recipient);
      await _expectField(tester, 'checkout-phone', _phone);
      await _expectField(tester, 'checkout-address', _address);
      await _tap(tester, 'checkout-submit');
      await _until(tester, () => _visible('checkout-success'));
      expect(app.fixture.placements, hasLength(1));
      final payload = app.fixture.placements.single;
      expect(payload['p_recipient_name'], _recipient);
      expect(payload['p_recipient_phone'], _phone);
      expect(payload['p_address_detail'], _address);
      expect(payload['p_latitude'], closeTo(_latitude, .000001));
      expect(payload['p_longitude'], closeTo(_longitude, .000001));
      expect(payload['p_items'], [
        {'variant_id': variantId, 'quantity': 2},
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'delayed same-user authorization hides checkout until rechecked',
    (tester) async {
      final app = await _openCheckout(tester);
      final guard = app.container.read(operationalRouteGuardProvider);
      expect(
        guard.decisionFor(Uri.parse('/customer/products/$productId'))?.allowed,
        isTrue,
      );
      for (final path in [
        '/customer/products/not-a-uuid',
        '/customer/profile',
        '/cod',
        '/shipper/tasks/$productId',
      ]) {
        expect(
          guard.decisionFor(Uri.parse(path)),
          isNull,
          reason: 'Customer authorization must not authorize $path.',
        );
      }
      final gate = Completer<void>();
      app.fixture.profileGate = gate;
      final readsBefore = app.fixture.profileReads;
      app.refreshSession();
      await _until(
        tester,
        () =>
            app.fixture.profileReads > readsBefore &&
            _visible('navigation-checking-access'),
      );
      expect(find.byKey(const ValueKey('checkout-form')), findsNothing);
      expect(find.byKey(const ValueKey('checkout-submit')), findsNothing);
      expect(guard.decisionFor(Uri.parse('/customer/checkout')), isNull);
      expect(app.fixture.placements, isEmpty);
      gate.complete();
      await _until(tester, () => _visible('checkout-form'));
      expect(app.router.state.uri.path, '/customer/checkout');
      await _expectField(tester, 'checkout-name', _recipient);
      await _expectField(tester, 'checkout-phone', _phone);
      await _expectField(tester, 'checkout-address', _address);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed session recheck offers retry and preserves the form', (
    tester,
  ) async {
    final app = await _openCheckout(tester);
    app.fixture.profileNetworkFailure = true;
    app.refreshSession();
    await _until(tester, () => _visible('navigation-access-error'));
    expect(
      find.byKey(const ValueKey('navigation-checking-access')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('checkout-form')), findsNothing);
    expect(find.byKey(const ValueKey('checkout-submit')), findsNothing);
    expect(app.fixture.placements, isEmpty);

    app.fixture.profileNetworkFailure = false;
    await tester.tap(find.widgetWithText(TextButton, 'Thử lại'));
    await tester.pump();
    await _until(tester, () => _visible('checkout-form'));
    expect(app.router.state.uri.path, '/customer/checkout');
    await _expectField(tester, 'checkout-name', _recipient);
    await _expectField(tester, 'checkout-phone', _phone);
    await _expectField(tester, 'checkout-address', _address);
    expect(app.fixture.placements, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('popping refreshed checkout keeps cart and catalog usable', (
    tester,
  ) async {
    final app = await _openCheckout(tester);
    final readsBefore = app.fixture.profileReads;
    app.refreshSession();
    await _until(
      tester,
      () => app.fixture.profileReads > readsBefore && _visible('checkout-form'),
    );
    await tester.pumpAndSettle();
    expect(app.router.state.uri.path, '/customer/checkout');

    app.router.pop();
    await _until(tester, () => _visible('cart-checkout'));
    await tester.pumpAndSettle();
    expect(app.router.state.uri.path, '/customer/cart');
    expect(
      find.byKey(const ValueKey('navigation-checking-access')),
      findsNothing,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('cart-checkout')))
          .onPressed,
      isNotNull,
    );

    app.router.pop();
    await _until(tester, () => _visible('catalog-product-$productId'));
    await tester.pumpAndSettle();
    expect(app.router.state.uri.path, '/customer/products');
    await _tap(tester, 'catalog-open-cart');
    await _until(tester, () => _visible('cart-checkout'));
    expect(app.router.state.uri.path, '/customer/cart');
    expect(app.fixture.placements, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('session recheck hides and restores an open location picker', (
    tester,
  ) async {
    final app = await _openCheckout(tester);
    await _tap(tester, 'checkout-location');
    await _until(tester, () => _visible('checkout-location-confirm'));
    await _enter(tester, 'checkout-location-latitude', '$_latitude');
    await _enter(tester, 'checkout-location-longitude', '$_longitude');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    final gate = Completer<void>();
    app.fixture.profileGate = gate;
    final readsBefore = app.fixture.profileReads;
    app.refreshSession();
    await _until(
      tester,
      () =>
          app.fixture.profileReads > readsBefore &&
          _visible('navigation-checking-access'),
    );
    expect(find.byKey(const ValueKey('checkout-location-map')), findsNothing);
    expect(
      find.byKey(const ValueKey('checkout-location-confirm')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('checkout-location-map'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('checkout-location-confirm'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(app.fixture.placements, isEmpty);

    gate.complete();
    await _until(tester, () => _visible('checkout-location-confirm'));
    expect(app.router.state.uri.path, '/customer/checkout');
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('checkout-location-latitude')),
          )
          .controller!
          .text,
      '$_latitude',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('checkout-location-longitude')),
          )
          .controller!
          .text,
      '$_longitude',
    );
    await _tap(tester, 'checkout-location-confirm');
    await _until(tester, () => _visible('checkout-form'));
    await _show(tester, 'checkout-location');
    expect(find.text('21.030000'), findsOneWidget);
    expect(find.text('105.850000'), findsOneWidget);
    await _expectField(tester, 'checkout-name', _recipient);
    expect(tester.takeException(), isNull);
  });

  for (final action in ['account switch', 'logout']) {
    testWidgets('$action removes checkout PII from the protected stack', (
      tester,
    ) async {
      final app = await _openCheckout(tester);
      await _selectLocation(tester);
      await _tap(tester, 'checkout-location');
      await _until(tester, () => _visible('checkout-location-confirm'));
      if (action == 'account switch') {
        await tester.runAsync(
          () => recoverFixtureSession(app.fixture.client, shipperB),
        );
      } else {
        await tester.runAsync(
          () => app.fixture.client.auth.signOut(scope: SignOutScope.local),
        );
      }
      await _until(tester, () => app.router.state.uri.path == '/');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('checkout-page'), skipOffstage: false),
        findsNothing,
      );
      expect(find.text(_recipient, skipOffstage: false), findsNothing);
      expect(find.text(_address, skipOffstage: false), findsNothing);
      expect(
        find.byKey(
          const ValueKey('checkout-location-map'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(app.fixture.placements, isEmpty);

      if (action == 'logout') {
        await tester.runAsync(
          () => recoverFixtureSession(app.fixture.client, shipperB),
        );
        await tester.pumpAndSettle();
      }
      app.router.go('/customer/checkout');
      await _until(tester, () => _visible('checkout-name'));
      await _expectField(tester, 'checkout-name', '');
      await _expectField(tester, 'checkout-phone', '');
      await _expectField(tester, 'checkout-address', '');
      await _show(tester, 'checkout-location');
      expect(find.text('21.030000'), findsNothing);
      expect(find.text('105.850000'), findsNothing);
      expect(find.text('Chưa chọn'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('same-user role revocation blocks the checkout after recheck', (
    tester,
  ) async {
    final app = await _openCheckout(tester);
    final readsBefore = app.fixture.profileReads;
    app.fixture.role = 'shipper';
    app.refreshSession();
    await _until(
      tester,
      () =>
          app.fixture.profileReads > readsBefore &&
          app.router.state.uri.path == '/',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('checkout-page'), skipOffstage: false),
      findsNothing,
    );
    expect(app.fixture.placements, isEmpty);
    app.router.go('/customer/checkout');
    await tester.pumpAndSettle();
    expect(app.router.state.uri.path, '/');
    expect(find.byKey(const ValueKey('checkout-submit')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
