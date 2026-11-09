import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/catalog/domain/models/product_image.dart';
import 'package:sports_store/app/demo/data/local_demo_store.dart';
import 'package:sports_store/app/dev/data/local_commerce_store.dart';
import 'package:sports_store/features/catalog/domain/models/catalog_query.dart';
import 'package:sports_store/features/checkout/domain/models/checkout_failure.dart';
import 'package:sports_store/features/checkout/domain/models/placement_request.dart';
import 'package:sports_store/features/orders/domain/models/order_command.dart';
import 'package:sports_store/features/orders/domain/models/order_query.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalDemoStore orders;
  late LocalCommerceStore commerce;
  setUp(() {
    orders = LocalDemoStore();
    commerce = LocalCommerceStore(orders);
  });
  PlacementRequest request(
    int n, {
    int quantity = 1,
    double latitude = 21.0285,
    double longitude = 105.8542,
  }) => PlacementRequest(
    requestId: '90000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
    items: [
      PlacementItem(
        variantId: LocalCommerceStore.variantId(1),
        quantity: quantity,
      ),
    ],
    recipientName: 'Nguyễn Minh Anh',
    recipientPhone: '0901234567',
    addressDetail: '12 Phố Huế, Hà Nội',
    latitude: latitude,
    longitude: longitude,
  );
  Future<int> stock() async =>
      (await commerce.catalog.getProduct(LocalCommerceStore.productId(1)))!
          .availableQuantity;

  test('local product image ACK is memory-backed and role scoped', () async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ZkAAAAASUVORK5CYII=',
    );
    final image = SelectedProductImage.fromBytes(bytes);
    await expectLater(
      commerce.uploadImage(image, requestId: 'image-1'),
      throwsA(anything),
    );
    orders.switchAccount(DemoAccount.managerB);
    final ack = await commerce.uploadImage(image, requestId: 'image-1');
    expect(ack.previewUrl.startsWith('data:image/png;base64,'), isTrue);
    expect(await commerce.catalog.getImageUrl(ack.path), ack.previewUrl);
    expect(
      (await commerce.uploadImage(image, requestId: 'image-1')).path,
      ack.path,
    );
  });

  test('checkout and manager/customer views share ID, receipt, reservation and release', () async {
    await commerce.cart.setQuantity(
      variantId: LocalCommerceStore.variantId(1),
      quantity: 2,
    );
    expect(await stock(), 20); // cart does not reserve
    final r = request(1, quantity: 2);
    final result = await commerce.checkout.placeOrder(r);
    result.validateAgainst(r, customerId: LocalDemoStore.customerAId);
    expect(result.subtotalVnd, 900000);
    expect(result.totalCodVnd, 930000);
    expect(await commerce.cart.getItems(), isEmpty);
    expect(await stock(), 18);
    final replay = await commerce.checkout.placeOrder(r);
    expect(replay.replayed, isTrue);
    expect(replay.order.id, result.order.id);
    expect(await stock(), 18);
    orders.switchAccount(DemoAccount.managerB);
    final manager = await orders.orders.getManagerOrders(OrderQuery());
    expect(manager.items.any((e) => e.order.id == result.order.id), isTrue);
    final cmd = StableOrderCommand(
      requestId: '91000000-0000-4000-8000-000000000001',
      orderId: result.order.id,
      operation: OrderOperation.reject,
      reason: 'Không thể đáp ứng',
    );
    await orders.orders.reject(cmd);
    await orders.orders.reject(cmd);
    expect(await stock(), 20);
    orders.switchAccount(DemoAccount.customerA);
    final detail = await orders.orders.getOrderDetails(result.order.id);
    expect(detail.order.status, OrderStatus.rejected);
    expect(detail.timeline.last.reason, 'Không thể đáp ứng');
    expect(
      (await commerce.checkout.lookupPlacementResult(r.requestId)).isCommitted,
      isTrue,
    );
    orders.switchAccount(DemoAccount.customerC);
    expect(
      (await commerce.checkout.lookupPlacementResult(r.requestId)).isNotFound,
      isTrue,
    );
    await expectLater(
      orders.orders.getOrderDetails(result.order.id),
      throwsA(anything),
    );
  });

  test(
    'concurrent placements cannot oversell; changed key payload conflicts',
    () async {
      final results = await Future.wait(
        [request(2, quantity: 15), request(3, quantity: 15)].map((r) async {
          try {
            return await commerce.checkout.placeOrder(r);
          } catch (e) {
            return e;
          }
        }),
      );
      expect(results.whereType<CheckoutFailure>().length, 1);
      expect(await stock(), 5);
      final saved = results.firstWhere((v) => v is! CheckoutFailure) as dynamic;
      final key = saved.order.requestId as String;
      await expectLater(
        commerce.checkout.placeOrder(
          request(2, quantity: 1).copyWith(requestId: key),
        ),
        throwsA(
          isA<CheckoutFailure>().having(
            (f) => f.code,
            'code',
            CheckoutFailureCode.idempotencyConflict,
          ),
        ),
      );
    },
  );

  test(
    'catalog management shares canonical stock and preserves order snapshots',
    () async {
      final receipt = await commerce.checkout.placeOrder(request(4));
      orders.switchAccount(DemoAccount.managerB);
      final management = await commerce.catalog.loadManagement();
      final original = management.products.first;
      await commerce.catalog.saveProduct(
        original.withActive(false),
        requestId: 'save-1',
      );
      orders.switchAccount(DemoAccount.customerA);
      expect(await commerce.catalog.getProduct(original.id!), isNull);
      expect(
        (await commerce.catalog.getProducts(const CatalogQuery()))
            .products
            .length,
        5,
      );
      expect(
        (await orders.orders.getOrderDetails(receipt.order.id))
            .items
            .first
            .productName,
        original.name,
      );
      await expectLater(
        commerce.catalog.saveProduct(original, requestId: 'save-2'),
        throwsA(anything),
      );
    },
  );

  test('outside Hanoi, shipper writes and separate registered accounts fail closed', () async {
    await expectLater(
      commerce.checkout.placeOrder(
        request(5, latitude: 10.77, longitude: 106.69),
      ),
      throwsA(
        isA<CheckoutFailure>().having(
          (f) => f.code,
          'code',
          CheckoutFailureCode.outsideServiceArea,
        ),
      ),
    );
    expect(await stock(), 20);
    await commerce.cart.setQuantity(
      variantId: LocalCommerceStore.variantId(1),
      quantity: 1,
    );
    orders.switchLocalCustomer('92000000-0000-4000-8000-000000000001');
    expect(await commerce.cart.getItems(), isEmpty);
    expect(
      (await orders.orders.getCustomerOrders(OrderQuery())).items,
      isEmpty,
    );
    orders.switchAccount(DemoAccount.shipper);
    await expectLater(commerce.cart.getItems(), throwsA(anything));
    await expectLater(
      commerce.checkout.placeOrder(request(6)),
      throwsA(isA<CheckoutFailure>()),
    );
    await expectLater(
      orders.orders.getCustomerOrders(OrderQuery()),
      throwsA(anything),
    );
  });
}
