import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sports_store/core/utils/display_formatters.dart';
import 'package:sports_store/features/orders/domain/models/order_item.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_items_section.dart';

import '../features/orders/presentation/widgets/mh09/mh09_test_support.dart';

Finder _tileFor(OrderItem item) => find
    .ancestor(
      of: find.byKey(ValueKey<String>(item.id)),
      matching: find.byType(DecoratedBox),
    )
    .first;

BoxDecoration _tileDecoration(WidgetTester tester, Finder tile) {
  return tester.widget<DecoratedBox>(tile).decoration as BoxDecoration;
}

OrderItem _itemWithAttributes({
  int index = 1,
  String productName = 'Giày chạy bộ snapshot',
  String variantLabel = 'Đen / EU 42',
  int quantity = 2,
  int unitPriceVnd = 3450000,
}) {
  final suffix = index.toString().padLeft(12, '0');
  return OrderItem(
    id: '60000000-0000-4000-8000-$suffix',
    orderId: '10000000-0000-4000-8000-000000000001',
    productId: '70000000-0000-4000-8000-$suffix',
    variantId: '80000000-0000-4000-8000-$suffix',
    productName: productName,
    variantLabel: variantLabel,
    attributes: const {'source': 'MH08 preview'},
    unitPriceVnd: unitPriceVnd,
    quantity: quantity,
    lineTotalVnd: unitPriceVnd * quantity,
    createdAt: DateTime.utc(2026, 10, 8, 3, 32),
  );
}

void main() {
  testWidgets('zero items keep the major heading and no tile', (tester) async {
    await pumpMh09(tester, Mh09ItemsSection(items: const []));

    expect(find.text('Sản phẩm trong đơn'), findsOneWidget);
    expect(find.text('0 dòng sản phẩm'), findsOneWidget);
    expect(find.text('Không có dòng sản phẩm'), findsOneWidget);
    expect(find.byType(DecoratedBox), findsNothing);
  });

  testWidgets('one tile preserves all snapshot fields and attributes', (
    tester,
  ) async {
    final item = _itemWithAttributes();
    final section = Mh09ItemsSection(items: [item]);
    await pumpMh09(tester, section);

    expect(section.items, hasLength(1));
    expect(
      section.items.single.attributes,
      containsPair('source', 'MH08 preview'),
    );
    expect(identical(section.items.single, item), isTrue);
    expect(find.byKey(ValueKey<String>(item.id)), findsOneWidget);
    expect(find.text('1 dòng sản phẩm'), findsOneWidget);
    expect(find.text(item.productName), findsOneWidget);
    expect(find.text('Biến thể: ${item.variantLabel}'), findsOneWidget);
    expect(find.text('Số lượng: ${item.quantity}'), findsOneWidget);
    expect(
      find.text('Đơn giá: ${formatVnd(item.unitPriceVnd)}'),
      findsOneWidget,
    );
    expect(
      find.text('Thành tiền: ${formatVnd(item.lineTotalVnd)}'),
      findsOneWidget,
    );
    expect(find.text('MH08 preview'), findsNothing);
    expect(
      tester.getSize(find.bySemanticsLabel('Không có ảnh sản phẩm')),
      const Size(64, 64),
    );

    final name = tester.widget<Text>(find.text(item.productName));
    final total = tester.widget<Text>(
      find.text('Thành tiền: ${formatVnd(item.lineTotalVnd)}'),
    );
    expect(name.style?.fontWeight, FontWeight.w600);
    expect(total.style?.fontWeight, FontWeight.w700);
  });

  testWidgets('two tiles retain UUID order, radius and twelve pixel gap', (
    tester,
  ) async {
    final first = _itemWithAttributes(
      index: 1,
      productName: 'Áo thi đấu câu lạc bộ có tên dài ' * 2,
      variantLabel: 'Xanh navy / XXL / phiên bản sân khách',
    );
    final second = _itemWithAttributes(
      index: 2,
      productName: 'Bóng đá luyện tập chống thấm nước',
      variantLabel: 'Size 5',
      quantity: 3,
      unitPriceVnd: 120000,
    );
    await pumpMh09(tester, Mh09ItemsSection(items: [first, second]));

    final firstTile = _tileFor(first);
    final secondTile = _tileFor(second);
    final firstRect = tester.getRect(firstTile);
    final secondRect = tester.getRect(secondTile);
    final firstDecoration = _tileDecoration(tester, firstTile);
    final secondDecoration = _tileDecoration(tester, secondTile);

    expect(find.byKey(ValueKey<String>(first.id)), findsOneWidget);
    expect(find.byKey(ValueKey<String>(second.id)), findsOneWidget);
    expect(find.text(first.productName), findsOneWidget);
    expect(find.text(second.productName), findsOneWidget);
    expect(firstRect.top, lessThan(secondRect.top));
    expect(secondRect.top - firstRect.bottom, closeTo(12, .01));
    expect(secondRect.left, closeTo(firstRect.left, .01));
    for (final decoration in [firstDecoration, secondDecoration]) {
      expect(decoration.color, Colors.white);
      expect(
        decoration.borderRadius!.resolve(TextDirection.ltr),
        BorderRadius.circular(16),
      );
    }
    expect(find.byType(Divider), findsNothing);
    expect(
      find.text('Thành tiền: ${formatVnd(first.lineTotalVnd)}'),
      findsOneWidget,
    );
    expect(
      find.text('Thành tiền: ${formatVnd(second.lineTotalVnd)}'),
      findsOneWidget,
    );
  });

  testWidgets('long VND values remain complete and formatted', (tester) async {
    final item = _itemWithAttributes(quantity: 2, unitPriceVnd: 999999999);
    await pumpMh09(tester, Mh09ItemsSection(items: [item]));

    expect(find.text('Đơn giá: ${formatVnd(999999999)}'), findsOneWidget);
    expect(find.text('Thành tiền: ${formatVnd(1999999998)}'), findsOneWidget);
  });

  testWidgets('forty valid tiles remain in the parent scroll order', (
    tester,
  ) async {
    final items = [
      for (var index = 1; index <= 40; index++)
        _itemWithAttributes(
          index: index,
          productName: 'Sản phẩm snapshot $index',
          variantLabel: 'Màu $index / EU 4$index',
          quantity: 1,
          unitPriceVnd: 100000 + index,
        ),
    ];
    await pumpMh09(tester, Mh09ItemsSection(items: items));

    expect(find.text('40 dòng sản phẩm'), findsOneWidget);
    expect(find.byKey(ValueKey<String>(items.first.id)), findsOneWidget);
    expect(find.byKey(ValueKey<String>(items.last.id)), findsOneWidget);
    for (final item in items) {
      expect(_tileFor(item), findsOneWidget);
    }

    final scrollable = find.byType(SingleChildScrollView);
    await tester.drag(scrollable, const Offset(0, -50000));
    await tester.pumpAndSettle();
    expect(find.text('Sản phẩm snapshot 40'), findsOneWidget);
    expect(find.text('Biến thể: Màu 40 / EU 440'), findsOneWidget);
  });

  for (final width in [320.0, 390.0, 412.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('reflows at width $width and text scale $scale', (
        tester,
      ) async {
        final item = _itemWithAttributes(
          productName: 'Tên sản phẩm snapshot rất dài ' * 4,
          variantLabel: 'Màu đen / kích thước cực lớn / bản giới hạn',
          quantity: 12,
        );
        await pumpMh09(
          tester,
          Mh09ItemsSection(items: [item]),
          width: width,
          scale: scale,
        );

        expect(find.byKey(ValueKey<String>(item.id)), findsOneWidget);
        expect(find.bySemanticsLabel('Không có ảnh sản phẩm'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('reflows in landscape at text scale $scale', (tester) async {
      final item = _itemWithAttributes(
        productName: 'Tên sản phẩm landscape rất dài ' * 3,
        variantLabel: 'Đen / EU 42 / phiên bản giới hạn',
      );
      await pumpMh09(
        tester,
        Mh09ItemsSection(items: [item]),
        width: 844,
        height: 390,
        scale: scale,
      );

      expect(find.byKey(ValueKey<String>(item.id)), findsOneWidget);
      expect(
        find.text('Thành tiền: ${formatVnd(item.lineTotalVnd)}'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
