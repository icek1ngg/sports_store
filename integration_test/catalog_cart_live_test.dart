import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';

import '../tool/catalog_live/main.dart' as live_app;

const _demoProductId = '40000000-0000-4000-8000-000000000001';
const _demoVariantId = '50000000-0000-4000-8000-000000000001';
const _demoProductName = '[DEMO] Giày chạy bộ Daily Run';
const _demoPrice = '690.000 đ';
const _demoSubtotalQuantityTwo = '1.380.000 đ';
const _demoSubtotalQuantityThree = '2.070.000 đ';
const _credentialEnvelopeType = 'sports_store.acceptance_credentials.v1';
const _credentialKeys = <String>[
  'CATALOG_TEST_EMAIL',
  'CATALOG_TEST_PASSWORD',
  'CATALOG_TEST_SECONDARY_EMAIL',
  'CATALOG_TEST_SECONDARY_PASSWORD',
];

class CatalogLiveIntegrationBinding
    extends IntegrationTestWidgetsFlutterBinding {
  CatalogLiveIntegrationBinding._();

  static CatalogLiveIntegrationBinding? _instance;

  final Completer<Map<String, String>> _credentialsCompleter =
      Completer<Map<String, String>>();

  static CatalogLiveIntegrationBinding ensureInitialized() {
    if (_instance == null) {
      CatalogLiveIntegrationBinding._();
    }
    return _instance!;
  }

  Future<Map<String, String>> get credentials => _credentialsCompleter.future;

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
  }

  @override
  Future<Map<String, dynamic>> callback(Map<String, String> params) async {
    if (params['command'] == 'request_data') {
      final message = params['message'];
      if (message != null && message.isNotEmpty) {
        final envelope = _decodeEnvelope(message);
        if (envelope != null) {
          return _handleCredentialEnvelope(envelope);
        }
      }
    }

    // Preserve the standard request_data behavior for the final null-message
    // result request and for any unsupported driver message.
    return super.callback(params);
  }

  Map<String, dynamic>? _decodeEnvelope(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) return null;
      final envelope = Map<String, dynamic>.from(decoded);
      if (envelope['type'] != _credentialEnvelopeType ||
          envelope['version'] != 1) {
        return null;
      }
      return envelope;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _handleCredentialEnvelope(
    Map<String, dynamic> envelope,
  ) async {
    final rawCredentials = envelope['credentials'];
    final credentials = <String, String>{};
    if (rawCredentials is Map) {
      for (final key in _credentialKeys) {
        final value = rawCredentials[key];
        if (value is! String || value.isEmpty) {
          credentials.clear();
          return _credentialResponse('rejected');
        }
        credentials[key] = value;
      }
    } else {
      return _credentialResponse('rejected');
    }

    if (_credentialsCompleter.isCompleted) {
      credentials.clear();
      return _credentialResponse('rejected');
    }

    final deliveredCredentials = Map<String, String>.from(credentials);
    credentials.clear();
    _credentialsCompleter.complete(deliveredCredentials);
    return _credentialResponse('accepted');
  }

  Map<String, dynamic> _credentialResponse(String status) {
    return <String, dynamic>{
      'isError': false,
      'response': <String, String>{
        'message': jsonEncode(<String, String>{'status': status}),
      },
    };
  }
}

void main() {
  final binding = CatalogLiveIntegrationBinding.ensureInitialized();

  testWidgets(
    'real customer completes MH04 -> MH05 -> MH06 without reserving stock',
    (tester) async {
      final credentials = await binding.credentials.timeout(
        const Duration(minutes: 2),
        onTimeout: () => fail('Runtime credential handoff did not complete.'),
      );
      try {
        final email = _runtimeCredential(credentials, 'CATALOG_TEST_EMAIL');
        final password = _runtimeCredential(
          credentials,
          'CATALOG_TEST_PASSWORD',
        );
        final secondaryEmail = _runtimeCredential(
          credentials,
          'CATALOG_TEST_SECONDARY_EMAIL',
        );
        final secondaryPassword = _runtimeCredential(
          credentials,
          'CATALOG_TEST_SECONDARY_PASSWORD',
        );

        await live_app.main();
        await tester.pump();

        final client = Supabase.instance.client;
        final appElement = find.byType(SportsStoreApp);
        await _waitFor(tester, appElement, failure: 'Live app did not start.');
        final container = ProviderScope.containerOf(tester.element(appElement));
        final router = container.read(appRouterProvider);

        late String primaryUserId;
        try {
          await _login(tester, email, password);
          primaryUserId = _currentUserId(client);
          await _assertCartEmpty(tester, client, primaryUserId);
          final stockBefore = await _readStock(tester, client);

          await _searchAndFilterDemo(tester);
          await _openDemoDetails(tester);
          await _selectDemoVariantAndQuantity(tester);
          await _addToCart(tester);
          await _openCart(tester);

          await _expectCartQuantity(tester, 2);
          await _expectAmount(tester, _demoSubtotalQuantityTwo);
          await _expectCheckoutAvailable(tester);
          expect(
            find.text(_demoPrice),
            findsOneWidget,
            reason: 'MH06 should render the live unit price.',
          );

          final increase = find.byKey(
            const ValueKey('cart-increase-$_demoVariantId'),
          );
          await _waitFor(
            tester,
            increase,
            failure: 'Cart increase control missing.',
          );
          await _bringIntoView(tester, increase);
          await tester.tap(increase);
          await _expectCartQuantity(tester, 3);
          await _expectAmount(tester, _demoSubtotalQuantityThree);

          final decrease = find.byKey(
            const ValueKey('cart-decrease-$_demoVariantId'),
          );
          await _waitFor(
            tester,
            decrease,
            failure: 'Cart decrease control missing.',
          );
          await _bringIntoView(tester, decrease);
          await tester.tap(decrease);
          await _expectCartQuantity(tester, 2);
          await _expectAmount(tester, _demoSubtotalQuantityTwo);

          await _assertCartQuantity(tester, client, primaryUserId, 2);
          await _refreshAndReopenCart(tester, router);
          await _expectCartQuantity(tester, 2);
          await _expectAmount(tester, _demoSubtotalQuantityTwo);

          await _verifySecondaryAccountIsolation(
            tester,
            router,
            client,
            secondaryEmail,
            secondaryPassword,
            primaryUserId,
          );
          await _login(tester, email, password);
          primaryUserId = _currentUserId(client);
          await _openCartFromRouter(tester, router);
          await _expectCartQuantity(tester, 2);

          final remove = find.byKey(
            const ValueKey('cart-remove-$_demoVariantId'),
          );
          await _waitFor(
            tester,
            remove,
            failure: 'Cart remove control missing.',
          );
          await _bringIntoView(tester, remove);
          await tester.tap(remove);
          await _waitFor(
            tester,
            find.byKey(const ValueKey('cart-empty')),
            failure: 'Cart did not become empty after deletion.',
          );
          await _assertCartEmpty(tester, client, primaryUserId);

          final stockAfter = await _readStock(tester, client);
          expect(
            stockAfter.onHand,
            stockBefore.onHand,
            reason: 'Cart operations must not change backend on_hand.',
          );
          expect(
            stockAfter.reserved,
            stockBefore.reserved,
            reason: 'Cart operations must not change backend reserved.',
          );
        } finally {
          // The live tool disables persistence, but explicitly clear the local
          // session as well so a failed test cannot leave the emulator signed in.
          try {
            await tester.runAsync<void>(
              () => client.auth.signOut(scope: SignOutScope.local),
            );
          } catch (_) {
            // Keep the original test failure and do not expose auth details.
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      } finally {
        credentials.clear();
      }
    },
  );
}

String _runtimeCredential(Map<String, String> credentials, String name) {
  final value = credentials[name];
  if (value == null || value.isEmpty) {
    fail('Required runtime credential is missing.');
  }
  return value;
}

Future<void> _login(WidgetTester tester, String email, String password) async {
  final fields = find.byType(TextFormField);
  await _waitFor(tester, fields, failure: 'Login form did not appear.');
  final signIn = find.widgetWithText(FilledButton, 'Đăng nhập');
  await _waitForEnabledFilledButton(
    tester,
    signIn,
    failure: 'Login form did not become enabled.',
  );
  await _bringIntoView(tester, fields.at(0));
  await tester.enterText(fields.at(0), email);
  await _bringIntoView(tester, fields.at(1));
  await tester.enterText(fields.at(1), password);
  await _waitForEnabledFilledButton(
    tester,
    signIn,
    failure: 'Login action did not become enabled.',
  );
  await tester.tap(signIn);
  await _waitFor(
    tester,
    find.byKey(const ValueKey('catalog-product-list')),
    timeout: const Duration(minutes: 2),
    failure: 'Customer login did not reach the catalog.',
  );
}

Future<void> _waitForEnabledFilledButton(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
  required String failure,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (finder.evaluate().isNotEmpty) {
      await _bringIntoView(tester, finder);
      if (tester.widget<FilledButton>(finder).onPressed != null) return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail(failure);
}

Future<void> _searchAndFilterDemo(WidgetTester tester) async {
  final search = find.byKey(const ValueKey('catalog-search-field'));
  await _waitFor(tester, search, failure: 'Catalog search field missing.');
  await tester.enterText(search, '[DEMO]');
  await tester.testTextInput.receiveAction(TextInputAction.search);

  final card = find.byKey(const ValueKey('catalog-product-$_demoProductId'));
  await _waitForCatalogResult(
    tester,
    card,
    timeout: const Duration(minutes: 2),
    failure: 'Seeded DEMO product did not appear in search results.',
  );
  expect(find.text(_demoProductName), findsOneWidget);

  final shoes = find.widgetWithText(ChoiceChip, 'Giày');
  await _waitFor(tester, shoes, failure: 'Catalog category filter missing.');
  await _bringIntoView(tester, shoes);
  await tester.tap(shoes);
  await _waitForCatalogResult(
    tester,
    card,
    timeout: const Duration(minutes: 2),
    failure: 'DEMO product did not remain visible after category filtering.',
  );
}

Future<void> _openDemoDetails(WidgetTester tester) async {
  final card = find.byKey(const ValueKey('catalog-product-$_demoProductId'));
  await _bringIntoView(tester, card);
  await tester.tap(card);
  await _waitFor(
    tester,
    find.byKey(const ValueKey('catalog-product-details')),
    timeout: const Duration(minutes: 2),
    failure: 'MH05 did not open for the seeded DEMO product.',
  );
  expect(find.text(_demoProductName), findsOneWidget);
}

Future<void> _selectDemoVariantAndQuantity(WidgetTester tester) async {
  final variant = find.byKey(const ValueKey('catalog-variant-$_demoVariantId'));
  await _waitFor(tester, variant, failure: 'Seeded DEMO variant missing.');
  await _bringIntoView(tester, variant);
  await tester.tap(variant);
  await tester.pump();
  expect(find.text(_demoPrice), findsOneWidget);

  final increase = find.byKey(const ValueKey('catalog-quantity-increase'));
  await _waitFor(tester, increase, failure: 'MH05 quantity picker missing.');
  await _bringIntoView(tester, increase);
  final increaseButton = tester.widget<IconButton>(increase);
  if (increaseButton.onPressed == null) {
    fail('Seeded DEMO variant is not available for quantity two.');
  }
  await tester.tap(increase);
  await _waitForCatalogQuantity(tester, 2);
}

Future<void> _addToCart(WidgetTester tester) async {
  final add = find.byKey(const ValueKey('catalog-cart-action'));
  await _waitForEnabledOutlinedButton(
    tester,
    add,
    failure: 'MH05 add-to-cart action did not become enabled.',
  );
  await _bringIntoView(tester, add);
  await tester.tap(add);
  await _waitFor(
    tester,
    find.text('Đã thêm vào giỏ hàng.'),
    timeout: const Duration(minutes: 2),
    failure: 'MH05 did not confirm the real cart write.',
  );
}

Future<void> _waitForEnabledOutlinedButton(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(minutes: 2),
  required String failure,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (finder.evaluate().isNotEmpty) {
      await _bringIntoView(tester, finder);
      if (tester.widget<OutlinedButton>(finder).onPressed != null) return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail(failure);
}

Future<void> _openCart(WidgetTester tester) async {
  final openCart = find.byKey(const ValueKey('catalog-open-cart'));
  await _waitFor(tester, openCart, failure: 'Catalog cart action missing.');
  await _bringIntoView(tester, openCart);
  await tester.tap(openCart);
  await _waitFor(
    tester,
    find.byKey(const ValueKey('cart-page')),
    timeout: const Duration(minutes: 2),
    failure: 'MH06 did not open.',
  );
  await _waitFor(
    tester,
    find.byKey(const ValueKey('cart-item-$_demoVariantId')),
    timeout: const Duration(minutes: 2),
    failure: 'Added DEMO variant did not appear in MH06.',
  );
}

Future<void> _openCartFromRouter(WidgetTester tester, GoRouter router) async {
  router.go('/customer/cart');
  await _waitFor(
    tester,
    find.byKey(const ValueKey('cart-page')),
    timeout: const Duration(minutes: 2),
    failure: 'MH06 did not reopen.',
  );
  final refresh = find.byKey(const ValueKey('cart-refresh'));
  await _waitFor(tester, refresh, failure: 'Cart refresh action missing.');
  await _bringIntoView(tester, refresh);
  await tester.tap(refresh);
  await _waitForCartRefreshResult(
    tester,
    find.byKey(const ValueKey('cart-item-$_demoVariantId')),
    timeout: const Duration(minutes: 2),
    failure: 'Persisted DEMO cart row did not reappear.',
  );
}

Future<void> _refreshAndReopenCart(WidgetTester tester, GoRouter router) async {
  final refresh = find.byKey(const ValueKey('cart-refresh'));
  await _waitFor(tester, refresh, failure: 'Cart refresh action missing.');
  await _bringIntoView(tester, refresh);
  await tester.tap(refresh);
  await _waitForCartRefreshResult(
    tester,
    find.byKey(const ValueKey('cart-item-$_demoVariantId')),
    timeout: const Duration(minutes: 2),
    failure: 'Cart refresh did not restore the persisted row.',
  );
  router.go('/customer/products');
  await _waitForRoute(
    tester,
    router,
    '/customer/products',
    failure: 'Catalog route did not reopen after cart refresh.',
  );
  await _waitFor(
    tester,
    find.byKey(const ValueKey('catalog-product-list')),
    timeout: const Duration(minutes: 2),
    failure: 'Catalog did not reopen after cart refresh.',
  );
  await _openCartFromRouter(tester, router);
}

Future<void> _verifySecondaryAccountIsolation(
  WidgetTester tester,
  GoRouter router,
  SupabaseClient client,
  String email,
  String password,
  String primaryUserId,
) async {
  router.go('/');
  await _waitFor(
    tester,
    find.text('Đăng xuất / Đổi tài khoản'),
    failure: 'Live session account switch action missing.',
  );
  final primarySignOut = find.text('Đăng xuất / Đổi tài khoản');
  await _bringIntoView(tester, primarySignOut);
  await tester.tap(primarySignOut);
  await _waitFor(
    tester,
    find.byType(TextFormField),
    failure: 'Sign-out did not finish.',
  );
  await _login(tester, email, password);
  final secondaryUserId = _currentUserId(client);
  if (secondaryUserId == primaryUserId) {
    fail('Secondary integration account did not produce a different user.');
  }
  await _assertCartEmpty(tester, client, secondaryUserId);
  // RLS must hide the primary customer's row from the secondary customer.
  await _assertCartEmpty(tester, client, primaryUserId);
  router.go('/customer/cart');
  await _waitFor(
    tester,
    find.byKey(const ValueKey('cart-empty')),
    timeout: const Duration(minutes: 2),
    failure: 'Secondary account did not see its own empty cart.',
  );

  router.go('/');
  await _waitFor(
    tester,
    find.text('Đăng xuất / Đổi tài khoản'),
    failure: 'Secondary account switch action missing.',
  );
  final secondarySignOut = find.text('Đăng xuất / Đổi tài khoản');
  await _bringIntoView(tester, secondarySignOut);
  await tester.tap(secondarySignOut);
  await _waitFor(
    tester,
    find.byType(TextFormField),
    failure: 'Secondary sign-out did not finish.',
  );
}

Future<void> _expectCartQuantity(WidgetTester tester, int quantity) async {
  await _waitForQuantity(tester, quantity);
}

Future<void> _waitForCatalogQuantity(WidgetTester tester, int quantity) async {
  final value = find.byKey(const ValueKey('catalog-quantity-value'));
  await _waitFor(
    tester,
    find.descendant(of: value, matching: find.text('$quantity')),
    timeout: const Duration(minutes: 2),
    failure: 'MH05 quantity did not reach the expected value.',
  );
}

Future<void> _waitForQuantity(WidgetTester tester, int quantity) async {
  final value = find.byKey(const ValueKey('cart-quantity-$_demoVariantId'));
  await _waitFor(
    tester,
    find.descendant(of: value, matching: find.text('$quantity')),
    timeout: const Duration(minutes: 2),
    failure: 'Cart quantity did not reach the expected value.',
  );
}

Future<void> _expectAmount(WidgetTester tester, String amount) async {
  await _waitFor(
    tester,
    find.text(amount),
    timeout: const Duration(minutes: 2),
    failure: 'Cart subtotal did not reach the expected value.',
  );
}

Future<void> _expectCheckoutAvailable(WidgetTester tester) async {
  final checkout = find.byKey(const ValueKey('cart-checkout'));
  await _waitFor(tester, checkout, failure: 'Checkout action missing.');
  await _bringIntoView(tester, checkout);
  expect(
    tester.widget<FilledButton>(checkout).onPressed,
    isNotNull,
    reason: 'Giỏ hợp lệ phải mở được MH16.',
  );
  expect(
    find.text('Thanh toán khi nhận hàng. Phí giao hàng tại Hà Nội: 30.000 đ.'),
    findsOneWidget,
  );
}

String _currentUserId(SupabaseClient client) {
  final userId = client.auth.currentUser?.id;
  if (userId == null || userId.isEmpty) fail('Customer session is missing.');
  return userId;
}

Future<void> _assertCartEmpty(
  WidgetTester tester,
  SupabaseClient client,
  String userId,
) async {
  final rows = await _readCartRows(tester, client, userId);
  if (rows.isNotEmpty) {
    fail('Dedicated integration account cart must be empty before this step.');
  }
}

Future<void> _assertCartQuantity(
  WidgetTester tester,
  SupabaseClient client,
  String userId,
  int expected,
) async {
  final rows = await _readCartRows(tester, client, userId);
  if (rows.length != 1) fail('Backend cart did not contain one DEMO row.');
  final row = rows.single;
  if (row['customer_id'] != userId || row['variant_id'] != _demoVariantId) {
    fail(
      'Backend cart row did not belong to the current customer and DEMO variant.',
    );
  }
  expect(_readInteger(row['quantity']), expected);
}

Future<List<Map<String, dynamic>>> _readCartRows(
  WidgetTester tester,
  SupabaseClient client,
  String userId, {
  String? variantId,
}) async {
  final response = await _runBackend<dynamic>(tester, () async {
    var query = client
        .from('cart_items')
        .select('customer_id,variant_id,quantity')
        .eq('customer_id', userId);
    if (variantId != null) query = query.eq('variant_id', variantId);
    return await query;
  });
  if (response is! List) {
    fail('Backend cart verification returned invalid data.');
  }
  return response
      .map((raw) {
        if (raw is! Map) {
          fail('Backend cart verification returned invalid data.');
        }
        return Map<String, dynamic>.from(raw);
      })
      .toList(growable: false);
}

Future<_StockSnapshot> _readStock(
  WidgetTester tester,
  SupabaseClient client,
) async {
  final response = await _runBackend<dynamic>(
    tester,
    () => client
        .from('product_variants')
        .select('id,on_hand,reserved')
        .eq('id', _demoVariantId)
        .single(),
  );
  if (response is! Map) {
    fail('Backend stock verification returned invalid data.');
  }
  final row = Map<String, dynamic>.from(response);
  if (row['id'] != _demoVariantId) {
    fail('Backend stock row was not the DEMO variant.');
  }
  return _StockSnapshot(
    onHand: _readInteger(row['on_hand']),
    reserved: _readInteger(row['reserved']),
  );
}

int _readInteger(Object? value) {
  if (value is int) return value;
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  fail('Backend verification returned an invalid integer.');
}

Future<T> _runBackend<T>(
  WidgetTester tester,
  Future<T> Function() operation,
) async {
  try {
    final value = await tester.runAsync(operation);
    return value as T;
  } catch (_) {
    fail('Backend verification request failed.');
  }
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
  required String failure,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail(failure);
}

Future<void> _bringIntoView(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _waitForCatalogResult(
  WidgetTester tester,
  Finder card, {
  Duration timeout = const Duration(seconds: 30),
  required String failure,
}) async {
  await tester.pump();
  final loading = find.byKey(const ValueKey('catalog-products-loading'));
  if (loading.evaluate().isNotEmpty) {
    await _waitForGone(
      tester,
      loading,
      timeout: timeout,
      failure: 'Catalog did not finish loading.',
    );
  }
  await _waitFor(tester, card, timeout: timeout, failure: failure);
}

Future<void> _waitForCartRefreshResult(
  WidgetTester tester,
  Finder row, {
  Duration timeout = const Duration(seconds: 30),
  required String failure,
}) async {
  await tester.pump();
  final loading = find.byKey(const ValueKey('cart-loading'));
  if (loading.evaluate().isNotEmpty) {
    await _waitForGone(
      tester,
      loading,
      timeout: timeout,
      failure: 'Cart did not finish refreshing.',
    );
  }
  await _waitFor(tester, row, timeout: timeout, failure: failure);
}

Future<void> _waitForGone(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
  required String failure,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (finder.evaluate().isEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail(failure);
}

Future<void> _waitForRoute(
  WidgetTester tester,
  GoRouter router,
  String path, {
  required String failure,
}) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (router.routeInformationProvider.value.uri.path == path) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail(failure);
}

class _StockSnapshot {
  const _StockSnapshot({required this.onHand, required this.reserved});

  final int onHand;
  final int reserved;
}
