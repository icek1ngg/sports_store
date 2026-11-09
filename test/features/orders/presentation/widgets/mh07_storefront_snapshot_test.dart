import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/theme/storefront_theme.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/catalog/presentation/view_models/catalog_providers.dart';
import 'package:sports_store/features/catalog/presentation/widgets/catalog_image.dart';
import 'package:sports_store/features/orders/domain/models/order_item.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/domain/models/order_summary.dart';
import 'package:sports_store/features/orders/presentation/pages/customer_orders_page.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_providers.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh07_order_card.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_item_image.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_items_section.dart';

import '../../../../fixtures/order_list_page_fixtures.dart';

const _navy = 'asset:assets/images/order-snapshot-navy.png';

OrderItem _item(Map<String, Object?> attributes) => OrderItem(
  id: listFixtureItemId,
  orderId: listFixtureOrderId,
  productId: listFixtureProductId,
  variantId: listFixtureVariantId,
  productName: 'Áo chạy bộ Kalenji',
  variantLabel: 'Xanh navy / M',
  attributes: attributes,
  unitPriceVnd: 3450000,
  quantity: 1,
  lineTotalVnd: 3450000,
  createdAt: listFixtureTime,
);

OrderSummary _summary(
  Map<String, Object?> attributes, {
  OrderStatus status = OrderStatus.pendingConfirmation,
  bool canCancel = false,
}) {
  final base = listFixtureSummary(
    status: status,
    capabilities: listFixtureCapabilities(canCancelCustomer: canCancel),
  );
  return OrderSummary(
    order: base.order,
    itemPreview: [_item(attributes)],
    itemLineCount: 1,
    itemQuantityTotal: 1,
    customerDisplayName: base.customerDisplayName,
    deliverySummary: base.deliverySummary,
    codSummary: base.codSummary,
    returnSummary: base.returnSummary,
    warnings: base.warnings,
    capabilities: base.capabilities,
  );
}

Future<Uint8List> _bluePixel() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
      .drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint()..color = Colors.blue);
  final picture = recorder.endRecording();
  final image = await picture.toImage(1, 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  required List<String> requested,
  required Uint8List bytes,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Image signing/loading is allowed; fetching a current catalog entity is
        // not. Any new catalog lookup introduced into this order UI fails here.
        catalogRepositoryProvider.overrideWith(
          (ref) => throw StateError('Order photos must come from snapshots'),
        ),
        productImageProvider.overrideWith((ref, path) async {
          requested.add(path);
          return Uri.dataFromBytes(bytes, mimeType: 'image/png').toString();
        }),
      ],
      child: MaterialApp(
        home: StorefrontTheme(
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16), child: child),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (find.byType(CatalogProductImage).evaluate().isNotEmpty) {
    await tester.runAsync(
      () => precacheImage(
        MemoryImage(bytes),
        tester.element(find.byType(CatalogProductImage).first),
      ),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'MH07 renders its exact color snapshot and storefront amount without underline',
    (tester) async {
      final bytes = (await tester.runAsync(_bluePixel))!;
      final requested = <String>[];
      await _mount(
        tester,
        Mh07OrderCard(
          summary: _summary(const {
            'color': 'Xanh navy',
            'image_path': _navy,
            'image_paths': [_navy, 'https://example.invalid/current-blue.jpg'],
          }),
          onDetails: () {},
        ),
        requested: requested,
        bytes: bytes,
      );
      expect(requested, [_navy]);
      final image = tester.widget<CatalogProductImage>(
        find.byType(CatalogProductImage),
      );
      expect(image.imagePath, _navy);
      expect(image.fit, BoxFit.contain);
      final total = tester.widget<Text>(
        find.byKey(const ValueKey('mh07-order-total-$listFixtureOrderId')),
      );
      expect(total.data, '3.480.000 đ');
      expect(total.style!.decoration, TextDecoration.none);
      expect(total.style!.fontFamily, 'BarlowCondensed');
      expect(find.text('₫3.480.000'), findsNothing);
      expect(find.text('Xanh navy / M'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final path in [
    _navy,
    'https://images.example.test/order-navy.jpg',
    'orders/snapshots/order-navy.webp',
  ]) {
    testWidgets('order details use the same snapshot resolver for $path', (
      tester,
    ) async {
      final bytes = (await tester.runAsync(_bluePixel))!;
      final requested = <String>[];
      await _mount(
        tester,
        OrderItemsSection(
          items: [
            _item({
              'image_paths': [path],
            }),
          ],
        ),
        requested: requested,
        bytes: bytes,
      );
      expect(requested, [path]);
      final image = tester.widget<CatalogProductImage>(
        find.byType(CatalogProductImage),
      );
      expect(image.width, 64);
      expect(image.height, 64);
      expect(image.imagePath, path);
      expect(find.byType(OrderItemImagePlaceholder), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final attributes in <Map<String, Object?>>[
    const {},
    const {'image_path': 'asset:assets/images/../different-color.png'},
    const {
      'image_path': 'javascript:alert(1)',
      'image_paths': [null, 42],
    },
  ]) {
    testWidgets(
      'missing or invalid snapshot stays an honest placeholder: $attributes',
      (tester) async {
        final bytes = (await tester.runAsync(_bluePixel))!;
        final requested = <String>[];
        await _mount(
          tester,
          Mh07OrderCard(summary: _summary(attributes), onDetails: () {}),
          requested: requested,
          bytes: bytes,
        );
        expect(requested, isEmpty);
        expect(find.byType(OrderItemImagePlaceholder), findsOneWidget);
        expect(find.byType(CatalogProductImage), findsNothing);
        expect(find.bySemanticsLabel('Không có ảnh sản phẩm'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'customer page keeps access/repository path and shows STRIDE branding',
    (tester) async {
      final repository = OrderListFixtureRepository(
        customerPage: listFixturePage(
          items: const [],
          totalCount: 0,
          counts: listFixtureCounts(),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          featureSessionScopeProvider.overrideWithValue(
            const SessionScope(
              userId: listFixtureCustomerId,
              role: 'customer',
              generation: 1,
            ),
          ),
          orderRepositoryProvider.overrideWithValue(repository),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: CustomerOrdersPage(enablePolling: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('STRIDE'), findsOneWidget);
      expect(find.text('VN ATHLETICS'), findsNothing);
      expect(find.text('Bạn chưa có đơn hàng'), findsOneWidget);
      final theme = Theme.of(tester.element(find.text('STRIDE')));
      expect(theme.textTheme.bodyMedium!.fontFamily, 'Inter');
      expect(theme.colorScheme.primary, StorefrontTheme.ink);
      expect(tester.takeException(), isNull);
      container.dispose();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    '320px large text keeps pending cancellation and details callbacks',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final bytes = (await tester.runAsync(_bluePixel))!;
      var cancellations = 0;
      var details = 0;
      await _mount(
        tester,
        Mh07OrderCard(
          summary: _summary(const {}, canCancel: true),
          onDetails: () => details++,
          onCancel: () => cancellations++,
        ),
        requested: [],
        bytes: bytes,
      );
      await tester.ensureVisible(find.text('Hủy đơn'));
      await tester.tap(find.text('Hủy đơn'));
      expect(cancellations, 1);
      expect(details, 0);
      await tester.ensureVisible(find.text('Xem chi tiết'));
      await tester.tap(find.text('Xem chi tiết'));
      expect(details, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('delivered snapshot preserves the supplied return callback', (
    tester,
  ) async {
    final bytes = (await tester.runAsync(_bluePixel))!;
    var returns = 0;
    var details = 0;
    await _mount(
      tester,
      Mh07OrderCard(
        summary: _summary(const {}, status: OrderStatus.delivered),
        onDetails: () => details++,
        returnLabel: 'Xem yêu cầu trả hàng',
        onReturn: () => returns++,
      ),
      requested: [],
      bytes: bytes,
    );
    await tester.tap(find.text('Xem yêu cầu trả hàng'));
    expect(returns, 1);
    expect(details, 0);
    expect(tester.takeException(), isNull);
  });
}
