import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_kpi_strip.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_list_controls.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_page_layout.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_status_chips.dart';

import '../../../../../fixtures/order_list_page_fixtures.dart';
import 'mh08_test_support.dart';

void main() {
  Widget controls({bool keyboardVisible = false, bool unknown = false}) {
    return Mh08KeyboardVisibility(
      visible: keyboardVisible,
      child: Mh08ListControls(
        searchValue: '',
        onSearchChanged: (_) {},
        onClear: () {},
        onStatusSelected: (_) {},
        selectedStatus: OrderStatus.pendingConfirmation,
        page: unknown
            ? null
            : listFixturePage(
                totalCount: 3,
                counts: listFixtureCounts(pending: 8, delivering: 2),
              ),
      ),
    );
  }

  testWidgets('canonical filtered total shares strip without replacing All', (
    tester,
  ) async {
    await pumpMh08(tester, controls());
    expect(
      find.descendant(
        of: find.byType(Mh08StatusChips),
        matching: find.text('3 đơn hàng'),
      ),
      findsOneWidget,
    );
    expect(find.text('10'), findsOneWidget);
    expect(find.text('Tất cả'), findsOneWidget);
    expect(find.byType(FilterChip), findsNWidgets(11));
    final number = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('mh08-kpi-value-Chờ xác nhận')),
        matching: find.byType(Text),
      ),
    );
    expect(number.style?.fontFamily, 'BarlowCondensed');
  });

  testWidgets('unknown canonical counts stay unknown and hide with keyboard', (
    tester,
  ) async {
    await pumpMh08(tester, controls(unknown: true));
    expect(find.text('Đang cập nhật số lượng đơn'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('0 đơn hàng'), findsNothing);
    await pumpMh08(tester, controls(unknown: true, keyboardVisible: true));
    expect(find.byType(Mh08KpiStrip), findsNothing);
    expect(find.text('Đang cập nhật số lượng đơn'), findsNothing);
    expect(find.byType(Mh08StatusChips), findsOneWidget);
  });

  testWidgets('compact controls retain 48px targets and scalable labels', (
    tester,
  ) async {
    for (final width in [320.0, 390.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        await pumpMh08(tester, controls(), width: width, scale: scale);
        expect(tester.takeException(), isNull);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('mh08-search-field')))
              .height,
          greaterThanOrEqualTo(48),
        );
        for (final element in find.byType(FilterChip).evaluate()) {
          final size = tester.getSize(find.byWidget(element.widget));
          expect(size.height, greaterThanOrEqualTo(48));
          expect(size.width, greaterThanOrEqualTo(48));
        }
        expect(find.text('3 đơn hàng'), findsOneWidget);
      }
    }
  });
}
