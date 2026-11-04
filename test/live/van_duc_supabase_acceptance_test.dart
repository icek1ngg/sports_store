import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/cart/data/repositories/supabase_cart_repository.dart';
import 'package:sports_store/features/cart/domain/models/cart_failure.dart';
import 'package:sports_store/features/catalog/data/repositories/supabase_catalog_repository.dart';
import 'package:sports_store/features/catalog/domain/models/catalog_query.dart';
import 'package:sports_store/features/checkout/data/repositories/pending_placement_store.dart';
import 'package:sports_store/features/checkout/data/repositories/supabase_checkout_repository.dart';
import 'package:sports_store/features/checkout/domain/models/checkout_failure.dart';
import 'package:sports_store/features/checkout/domain/models/placement_request.dart';
import 'package:sports_store/features/checkout/presentation/view_models/checkout_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';

// Opt-in real API tests. Credentials exist only in the host process environment;
// no admin key, persisted session, password fixture or cloud-wide cart read.
final _password = Platform.environment['SPORTS_ACCEPTANCE_PASSWORD'];
final _enabled = Platform.environment['SPORTS_LIVE_ACCEPTANCE'] == '1';

class _LiveHttpOverrides extends HttpOverrides {}

class _LiveClient extends http.BaseClient {
  _LiveClient(this.inner);
  final http.Client inner;
  int inFlight = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Avoid HTTP keep-alive idle timers inside the widget test's fake clock.
    // Requests still use the normal verified HTTPS transport.
    request.persistentConnection = false;
    inFlight++;
    try {
      final response = await inner.send(request);
      final bytes = await response.stream.toBytes();
      return http.StreamedResponse(
        Stream.value(bytes),
        response.statusCode,
        headers: response.headers,
        request: response.request,
      );
    } finally {
      inFlight--;
    }
  }

  @override
  void close() => inner.close();
}

class _LiveSession {
  _LiveSession(this.client, this.access, this.transport);
  final SupabaseClient client;
  final OperationalReadAccess access;
  final _LiveClient transport;

  Future<void> close() async {
    await access.dispose();
    try {
      await client.auth.signOut(scope: SignOutScope.local);
    } finally {
      await client.dispose();
      transport.close();
    }
  }
}

Future<_LiveSession> _login(String role) async {
  final config = jsonDecode(
    File('config/supabase.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final url = config['SUPABASE_URL'] as String;
  if (Uri.parse(url).host != 'bqoyfytmrtvjwrpshuhh.supabase.co') {
    fail('Cấu hình không phải project nghiệm thu đã chỉ định.');
  }
  // Flutter widget tests normally replace networking. This explicit client
  // uses verified HTTPS for the opt-in live test, without changing app clients.
  final transport = _LiveClient(
    IOClient(_LiveHttpOverrides().createHttpClient(null)),
  );
  final client = SupabaseClient(
    url,
    config['SUPABASE_PUBLISHABLE_KEY'] as String,
    httpClient: transport,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  OperationalReadAccess? access;
  try {
    await client.auth
        .signInWithPassword(email: '$role@gmail.com', password: _password!)
        .timeout(const Duration(seconds: 25));
    access = OperationalReadAccess(client);
    final session = _LiveSession(client, access, transport);
    final actualRole = await access.run(
      roles: {role},
      action: (identity) async => identity.role,
    );
    expect(actualRole, role);
    return session;
  } catch (error) {
    await access?.dispose();
    try {
      if (client.auth.currentSession != null) {
        await client.auth.signOut(scope: SignOutScope.local);
      }
    } finally {
      await client.dispose();
      transport.close();
    }
    fail('Không xác nhận được tài khoản $role: ${error.runtimeType}.');
  }
}

Future<void> _until(WidgetTester tester, String key) async {
  final deadline = DateTime.now().add(const Duration(seconds: 35));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byKey(ValueKey(key)).evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  fail('Màn thật chưa sẵn sàng: $key.');
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      220,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _settleNetwork(WidgetTester tester, _LiveSession session) async {
  var quietFrames = 0;
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 350));
    quietFrames = session.transport.inFlight == 0 ? quietFrames + 1 : 0;
    if (quietFrames == 3) return;
  }
  fail('Yêu cầu mạng của màn hình chưa kết thúc.');
}

void main() {
  final skip = !_enabled || _password == null;
  for (final role in ['customer', 'manager', 'shipper']) {
    test(
      'LIVE $role: đăng nhập, role máy chủ và quyền giỏ',
      () async {
        final session = await _login(role);
        try {
          final cart = SupabaseCartRepository(access: session.access);
          if (role == 'customer') {
            final items = await cart.getItems();
            expect(
              items,
              isNotEmpty,
              reason: 'Tài khoản nghiệm thu cần có giỏ đã chuẩn bị.',
            );
            final item = items.firstWhere((item) => item.canCheckout);
            await cart.setQuantity(
              variantId: item.variantId,
              quantity: item.quantity,
            );
            final after = await cart.getItems();
            expect(
              after
                  .firstWhere((row) => row.variantId == item.variantId)
                  .quantity,
              item.quantity,
            );
            final catalog = SupabaseCatalogRepository(access: session.access);
            final page = await catalog.getProducts(const CatalogQuery());
            expect(page.products, isNotEmpty);
            final detail = await catalog.getProduct(item.product!.id);
            expect(detail?.id, item.product!.id);
          } else {
            await expectLater(
              cart.getItems(),
              throwsA(
                isA<CartFailure>().having(
                  (error) => error.code,
                  'quyền',
                  CartFailureCode.permissionDenied,
                ),
              ),
            );
            final customerId = Platform.environment['SPORTS_TEST_CUSTOMER_ID'];
            expect(customerId, isNotNull);
            final rows = await session.client
                .from('cart_items')
                .select('variant_id')
                .eq('customer_id', customerId!);
            expect(
              rows,
              isEmpty,
              reason: 'Role khác không đọc được giỏ của customer thử.',
            );
          }
        } finally {
          await session.close();
        }
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  test(
    'LIVE MH16: từ chối ngoài Hà Nội và không tạo đơn',
    () async {
      final session = await _login('customer');
      try {
        final cart = SupabaseCartRepository(access: session.access);
        final item = (await cart.getItems()).firstWhere(
          (item) => item.canCheckout,
        );
        final request = PlacementRequest(
          requestId: const Uuid().v4(),
          items: [PlacementItem(variantId: item.variantId, quantity: 1)],
          recipientName: '[TEST] Kiểm tra vùng giao',
          recipientPhone: '0900000000',
          addressDetail: '[TEST] Vị trí ngoài Hà Nội',
          latitude: 10.77,
          longitude: 106.70,
        );
        final checkout = SupabaseCheckoutRepository(access: session.access);
        await expectLater(
          checkout.placeOrder(request),
          throwsA(
            isA<CheckoutFailure>().having(
              (error) => error.code,
              'vùng giao',
              CheckoutFailureCode.outsideServiceArea,
            ),
          ),
        );
        expect(
          (await checkout.lookupPlacementResult(request.requestId)).isNotFound,
          isTrue,
        );
      } finally {
        await session.close();
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'LIVE MH04 → MH05 → MH06 → MH16 và AppBar Back',
    (tester) async {
      final session = (await tester.runAsync(() => _login('customer')))!;
      addTearDown(() async {
        await _settleNetwork(tester, session);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(session.close);
      });
      final items = (await tester.runAsync(
        () => SupabaseCartRepository(access: session.access).getItems(),
      ))!;
      final item = items.firstWhere((item) => item.canCheckout);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseClientProvider.overrideWithValue(session.client),
            pendingPlacementStoreProvider.overrideWithValue(
              InMemoryPendingPlacementStore(),
            ),
            checkoutMapTilesEnabledProvider.overrideWithValue(false),
          ],
          child: const SportsStoreApp(),
        ),
      );
      await _until(tester, 'catalog-product-list');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SportsStoreApp)),
      );
      final router = container.read(appRouterProvider);
      router.push('/customer/products/${item.product!.id}');
      await _until(tester, 'catalog-cart-action');
      await _tap(tester, 'catalog-open-cart');
      await _until(tester, 'cart-checkout');
      expect(find.text('Dữ liệu giỏ hàng không hợp lệ.'), findsNothing);
      await _tap(tester, 'cart-checkout');
      await _until(tester, 'checkout-form');
      await _tap(tester, 'checkout-location');
      await _until(tester, 'checkout-location-confirm');
      await _tap(tester, 'checkout-location-confirm');
      await _settleNetwork(tester, session);
      await tester.tap(find.byType(BackButton).last);
      await _until(tester, 'cart-checkout');
      await _settleNetwork(tester, session);
      await tester.tap(find.byType(BackButton).last);
      await _until(tester, 'catalog-cart-action');
      await _settleNetwork(tester, session);
      await tester.tap(find.byType(BackButton).last);
      await _until(tester, 'catalog-product-list');
      await _settleNetwork(tester, session);
      expect(router.state.uri.path, '/customer/products');
      expect(tester.takeException(), isNull);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
