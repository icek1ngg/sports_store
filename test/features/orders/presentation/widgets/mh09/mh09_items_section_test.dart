import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sports_store/core/utils/display_formatters.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_items_section.dart';

import 'mh09_test_support.dart';

void main() {
  testWidgets('empty snapshot is explicit and has no catalog image', (
    tester,
  ) async {
    await pumpMh09(tester, Mh09ItemsSection(items: const []));

    expect(find.text('Sản phẩm trong đơn'), findsOneWidget);
    expect(find.text('0 dòng sản phẩm'), findsOneWidget);
    expect(find.text('Không có dòng sản phẩm'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('one item exposes every immutable snapshot field', (
    tester,
  ) async {
    final item = mh09Item(
      productName: 'Giày chạy bộ snapshot đọc đầy đủ',
      variantLabel: 'Đen / EU 42',
      quantity: 2,
      unitPriceVnd: 3450000,
    );
    await pumpMh09(tester, Mh09ItemsSection(items: [item]));

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
    expect(find.bySemanticsLabel('Không có ảnh sản phẩm'), findsOneWidget);
    expect(find.byKey(ValueKey<String>(item.id)), findsOneWidget);
  });

  testWidgets('two items retain their UUID keys and readable long text', (
    tester,
  ) async {
    final first = mh09Item(
      index: 1,
      productName: 'Áo thi đấu câu lạc bộ có tên dài ' * 2,
      variantLabel: 'Xanh navy / XXL / phiên bản sân khách',
    );
    final second = mh09Item(
      index: 2,
      productName: 'Bóng đá luyện tập chống thấm nước',
      variantLabel: 'Size 5',
      quantity: 3,
      unitPriceVnd: 120000,
    );
    await pumpMh09(tester, Mh09ItemsSection(items: [first, second]));

    expect(find.text('2 dòng sản phẩm'), findsOneWidget);
    expect(find.byKey(ValueKey<String>(first.id)), findsOneWidget);
    expect(find.byKey(ValueKey<String>(second.id)), findsOneWidget);
    expect(find.text(first.productName), findsOneWidget);
    expect(find.text(second.productName), findsOneWidget);
    expect(
      find.text('Thành tiền: ${formatVnd(first.lineTotalVnd)}'),
      findsOneWidget,
    );
    expect(
      find.text('Thành tiền: ${formatVnd(second.lineTotalVnd)}'),
      findsOneWidget,
    );
  });

  testWidgets('large quantity and VND values remain readable', (tester) async {
    final item = mh09Item(quantity: 999999, unitPriceVnd: 999999999);
    await pumpMh09(tester, Mh09ItemsSection(items: [item]));

    expect(find.text('Số lượng: 999999'), findsOneWidget);
    expect(find.text('Đơn giá: ${formatVnd(999999999)}'), findsOneWidget);
    expect(
      find.text('Thành tiền: ${formatVnd(item.lineTotalVnd)}'),
      findsOneWidget,
    );
  });

  testWidgets(
    'forty rows stay in the parent scroll and the final row is reachable',
    (tester) async {
      final items = [
        for (var index = 1; index <= 40; index++)
          mh09Item(
            index: index,
            productName: 'Sản phẩm snapshot $index',
            variantLabel: 'Màu $index / EU 4$index',
          ),
      ];
      await pumpMh09(tester, Mh09ItemsSection(items: items));

      expect(find.text('40 dòng sản phẩm'), findsOneWidget);
      expect(find.text('Sản phẩm snapshot 1'), findsOneWidget);
      expect(find.byKey(ValueKey<String>(items[39].id)), findsOneWidget);
      final scrollable = find.byType(SingleChildScrollView);
      expect(scrollable, findsOneWidget);
      await tester.drag(scrollable, const Offset(0, -50000));
      await tester.pumpAndSettle();
      expect(find.text('Sản phẩm snapshot 40'), findsOneWidget);
      expect(find.text('Biến thể: Màu 40 / EU 440'), findsOneWidget);
    },
  );

  testWidgets('copies the input list while retaining item identity', (
    tester,
  ) async {
    final item = mh09Item();
    final source = [item];
    final widget = Mh09ItemsSection(items: source);
    source.clear();

    expect(widget.items, hasLength(1));
    expect(identical(widget.items.single, item), isTrue);
    await pumpMh09(tester, widget);
    expect(find.text(item.productName), findsOneWidget);
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('reflows at width $width and text scale $scale', (
        tester,
      ) async {
        await pumpMh09(
          tester,
          Mh09ItemsSection(
            items: [
              mh09Item(
                productName: 'Tên sản phẩm snapshot rất dài ' * 4,
                variantLabel: 'Màu đen / kích thước cực lớn / bản giới hạn',
                quantity: 12,
              ),
            ],
          ),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
