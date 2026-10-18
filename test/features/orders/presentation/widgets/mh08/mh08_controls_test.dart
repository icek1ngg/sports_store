import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sports_store/core/utils/display_formatters.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_header.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_kpi_strip.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_search_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_status_chips.dart';

import 'mh08_test_support.dart';

void main() {
  testWidgets('header exposes title, brand, refresh and disabled semantics', (
    tester,
  ) async {
    var refreshes = 0;
    await pumpMh08(
      tester,
      Mh08Header(title: 'ĐƠN HÀNG', onRefresh: () => refreshes++),
    );

    expect(find.text('VN ATHLETICS'), findsOneWidget);
    expect(find.text('ĐƠN HÀNG'), findsOneWidget);
    final brand = tester.widget<Text>(find.text('VN ATHLETICS'));
    final title = tester.widget<Text>(find.text('ĐƠN HÀNG'));
    expect(brand.style?.fontFamily, 'BarlowCondensed');
    expect(brand.style?.fontSize, 14);
    expect(title.style?.fontFamily, 'BarlowCondensed');
    expect(title.style?.fontSize, 28);

    final refreshButtonFinder = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Làm mới đơn hàng',
    );
    await tester.tap(refreshButtonFinder);
    expect(refreshes, 1);

    await pumpMh08(tester, const Mh08Header());
    final refreshButton = tester.widget<IconButton>(refreshButtonFinder);
    expect(refreshButton.onPressed, isNull);
    expect(
      tester.getSemantics(refreshButtonFinder),
      matchesSemantics(
        tooltip: 'Làm mới đơn hàng',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );

    await pumpMh08(tester, const Mh08Header(), width: 320, scale: 2);
    expect(find.text('ĐƠN HÀNG'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search is parent controlled and forwards every callback', (
    tester,
  ) async {
    final changed = <String>[];
    var clears = 0;
    var filters = 0;
    await pumpMh08(
      tester,
      Mh08SearchSection(
        value: 'DH-1',
        onChanged: changed.add,
        onClear: () => clears++,
        onFilter: () => filters++,
        errorText: 'Từ khóa không hợp lệ',
      ),
    );

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'DH-1',
    );
    expect(find.text('Từ khóa không hợp lệ'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('mh08-search-field')),
      'DH-12',
    );
    expect(changed, ['DH-12']);
    await tester.tap(find.byTooltip('Xóa tìm kiếm'));
    await tester.tap(find.byTooltip('Lọc theo trạng thái'));
    expect(clears, 1);
    expect(filters, 1);
  });

  testWidgets('search sync keeps its focus when parent value changes', (
    tester,
  ) async {
    final stateKey = GlobalKey<_ControlledSearchState>();
    await pumpMh08(tester, _ControlledSearch(key: stateKey));
    final field = find.byKey(const ValueKey('mh08-search-field'));
    await tester.tap(field);
    await tester.enterText(field, 'abc');
    await tester.pump();
    final focus = tester.binding.focusManager.primaryFocus;
    expect(focus, isNotNull);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'abc',
    );

    final controller = tester.widget<TextField>(field).controller!;
    controller.selection = const TextSelection.collapsed(offset: 2);
    stateKey.currentState!.setExternalValue('abcdef');
    await tester.pump();
    expect(controller.text, 'abcdef');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
    expect(identical(focus, tester.binding.focusManager.primaryFocus), isTrue);

    await tester.tap(find.byTooltip('Xóa tìm kiếm'));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(find.byTooltip('Xóa tìm kiếm'), findsNothing);
  });

  testWidgets(
    'KPI shows exactly two panels and em dashes for unavailable counts',
    (tester) async {
      await pumpMh08(
        tester,
        const Mh08KpiStrip(pendingCount: 12, shippingCount: null),
      );

      expect(find.text('Chờ xác nhận'), findsOneWidget);
      expect(find.text('Đang giao'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Trả hàng'), findsNothing);
    },
  );

  testWidgets(
    'status chips render all ten statuses and toggle selected status',
    (tester) async {
      final selected = <OrderStatus?>[];
      final counts = <OrderStatus, int>{
        for (final status in OrderStatus.values) status: status.index + 1,
      };
      await pumpMh08(
        tester,
        Mh08StatusChips(
          selectedStatus: OrderStatus.delivering,
          counts: counts,
          onSelected: selected.add,
        ),
      );

      for (final status in OrderStatus.values) {
        expect(find.text(orderStatusLabel(status)), findsOneWidget);
      }
      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);

      await tester.ensureVisible(find.text('Đang chuẩn bị'));
      await tester.tap(find.text('Đang chuẩn bị'));
      await tester.ensureVisible(find.text('Đang giao'));
      await tester.tap(find.text('Đang giao'));
      await tester.ensureVisible(find.text('Tất cả'));
      await tester.tap(find.text('Tất cả'));
      expect(selected, [OrderStatus.preparing, null, null]);
    },
  );

  testWidgets('status chips stay disabled without callback at compact scale', (
    tester,
  ) async {
    await pumpMh08(
      tester,
      const Mh08StatusChips(selectedStatus: OrderStatus.pendingConfirmation),
      width: 320,
      scale: 2,
    );

    expect(tester.takeException(), isNull);
    final selectedChip = find.ancestor(
      of: find.text('Chờ xác nhận'),
      matching: find.byType(FilterChip),
    );
    final chip = tester.widget<FilterChip>(selectedChip);
    expect(chip.selected, isTrue);
    expect(chip.onSelected, isNull);
    await tester.ensureVisible(find.text('Chờ xác nhận'));
    await tester.tap(find.text('Chờ xác nhận'));
  });

  testWidgets('controls reflow across compact widths and text scales', (
    tester,
  ) async {
    final counts = <OrderStatus, int>{
      for (final status in OrderStatus.values) status: status.index + 1,
    };
    for (final width in [320.0, 390.0]) {
      for (final scale in [1.0, 2.0]) {
        await pumpMh08(
          tester,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Mh08Header(onRefresh: () {}),
              const SizedBox(height: 8),
              Mh08SearchSection(value: '', onChanged: (_) {}, onFilter: () {}),
              const SizedBox(height: 8),
              const Mh08KpiStrip(pendingCount: 12, shippingCount: 8),
              const SizedBox(height: 8),
              Mh08StatusChips(counts: counts, onSelected: (_) {}),
            ],
          ),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('KPI unavailable count has explicit semantics', (tester) async {
    await pumpMh08(
      tester,
      const Mh08KpiStrip(pendingCount: null, shippingCount: 8),
    );

    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('mh08-kpi-value-Chờ xác nhận')),
      ),
      matchesSemantics(label: 'Chờ xác nhận: Chưa có dữ liệu'),
    );
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('mh08-kpi-value-Đang giao')),
      ),
      matchesSemantics(label: 'Đang giao: 8'),
    );
  });
}

class _ControlledSearch extends StatefulWidget {
  const _ControlledSearch({super.key});

  @override
  State<_ControlledSearch> createState() => _ControlledSearchState();
}

class _ControlledSearchState extends State<_ControlledSearch> {
  var _value = '';

  void setExternalValue(String value) {
    setState(() => _value = value);
  }

  @override
  Widget build(BuildContext context) {
    return Mh08SearchSection(
      value: _value,
      onChanged: (value) => setState(() => _value = value),
      onClear: () => setState(() => _value = ''),
    );
  }
}
