import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/domain/models/order_operation.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_action_footer.dart';

import 'mh09_02b_test_support.dart';

const _rejectKey = ValueKey<String>('mh09-action-reject');
const _confirmKey = ValueKey<String>('mh09-action-confirm');
const _cancelKey = ValueKey<String>('mh09-action-manager-cancel');

Mh09ActionFooter _footer({
  bool confirm = false,
  bool reject = false,
  bool cancel = false,
  bool fresh = true,
  bool inScope = true,
  bool busy = false,
  ValueChanged<OrderOperation>? onAction,
}) => Mh09ActionFooter(
  capabilities: mh09Capabilities(
    confirm: confirm,
    reject: reject,
    cancel: cancel,
  ),
  isActionStateFresh: fresh,
  canActInCurrentScope: inScope,
  isBusy: busy,
  onAction: onAction,
);

bool _hasSemanticTap(WidgetTester tester, Finder finder) {
  final data = tester.getSemantics(finder).getSemanticsData();
  return data.actions & SemanticsAction.tap.index != 0;
}

void _performSemanticTap(WidgetTester tester, Finder finder) {
  final node = tester.getSemantics(finder);
  node.owner!.performAction(node.id, SemanticsAction.tap);
}

void main() {
  testWidgets('default and non-footer capabilities stay hidden', (
    tester,
  ) async {
    await pumpMh09(tester, const Mh09ActionFooter());
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);

    await pumpMh09(
      tester,
      Mh09ActionFooter(
        capabilities: mh09Capabilities(assign: true, retry: true),
        isActionStateFresh: true,
        canActInCurrentScope: true,
        onAction: (_) {},
      ),
    );
    expect(find.byType(Mh09ActionFooter), findsOneWidget);
    expect(find.byKey(_rejectKey), findsNothing);
    expect(find.byKey(_confirmKey), findsNothing);
    expect(find.byKey(_cancelKey), findsNothing);
  });

  for (final entry in <String, Mh09ActionFooter>{
    'reject': _footer(reject: true, onAction: (_) {}),
    'confirm': _footer(confirm: true, onAction: (_) {}),
    'manager cancel': _footer(cancel: true, onAction: (_) {}),
  }.entries) {
    testWidgets('renders only the ${entry.key} capability', (tester) async {
      await pumpMh09(tester, entry.value);
      final expected = switch (entry.key) {
        'reject' => _rejectKey,
        'confirm' => _confirmKey,
        _ => _cancelKey,
      };
      expect(find.byKey(expected), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is OutlinedButton && widget.key != expected,
        ),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is FilledButton && widget.key != expected,
        ),
        findsNothing,
      );
    });
  }

  testWidgets('uses reject before confirm and keeps exceptional cancel apart', (
    tester,
  ) async {
    await pumpMh09(
      tester,
      _footer(reject: true, confirm: true, cancel: true, onAction: (_) {}),
      gutters: 0,
    );

    final reject = find.byKey(_rejectKey);
    final confirm = find.byKey(_confirmKey);
    final cancel = find.byKey(_cancelKey);
    expect(tester.getCenter(reject).dx, lessThan(tester.getCenter(confirm).dx));
    expect(find.text('HÀNH ĐỘNG NGOẠI LỆ'), findsOneWidget);
    expect(find.text('Từ chối đơn'), findsOneWidget);
    expect(find.text('Xác nhận đơn hàng'), findsOneWidget);
    expect(find.text('Hủy ngoại lệ'), findsOneWidget);
    for (final finder in [reject, confirm, cancel]) {
      expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
    }
  });

  for (final gate in <String, Mh09ActionFooter>{
    'freshness': _footer(
      reject: true,
      confirm: true,
      cancel: true,
      fresh: false,
      onAction: (_) {},
    ),
    'scope': _footer(
      reject: true,
      confirm: true,
      cancel: true,
      inScope: false,
      onAction: (_) {},
    ),
    'busy': _footer(
      reject: true,
      confirm: true,
      cancel: true,
      busy: true,
      onAction: (_) {},
    ),
    'callback': _footer(reject: true, confirm: true, cancel: true),
  }.entries) {
    testWidgets('$gate disables every visible action', (tester) async {
      await pumpMh09(tester, gate.value);
      for (final finder in [
        find.byKey(_rejectKey),
        find.byKey(_confirmKey),
        find.byKey(_cancelKey),
      ]) {
        final data = tester.getSemantics(finder).getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.flagsCollection.isEnabled, Tristate.isFalse);
        expect(_hasSemanticTap(tester, finder), isFalse);
      }
    });
  }

  testWidgets('dispatches exact operations without cross-dispatch', (
    tester,
  ) async {
    final operations = <OrderOperation>[];
    await pumpMh09(
      tester,
      _footer(
        reject: true,
        confirm: true,
        cancel: true,
        onAction: operations.add,
      ),
      gutters: 0,
    );

    await tester.tap(find.byKey(_rejectKey));
    await tester.tap(find.byKey(_confirmKey));
    await tester.tap(find.byKey(_cancelKey));
    expect(operations, [
      OrderOperation.reject,
      OrderOperation.confirm,
      OrderOperation.managerCancel,
    ]);
  });

  testWidgets('rebuild applies a newly disabled owner gate', (tester) async {
    var calls = 0;
    await pumpMh09(
      tester,
      _footer(reject: true, fresh: true, onAction: (_) => calls++),
    );
    await pumpMh09(
      tester,
      _footer(reject: true, fresh: false, onAction: (_) => calls++),
    );
    final reject = find.byKey(_rejectKey);
    expect(
      tester.getSemantics(reject).getSemanticsData().flagsCollection.isEnabled,
      Tristate.isFalse,
    );
    await tester.tap(reject);
    expect(calls, 0);
  });

  testWidgets('enabled actions expose labels, targets and semantic taps', (
    tester,
  ) async {
    var calls = 0;
    await pumpMh09(
      tester,
      _footer(
        reject: true,
        confirm: true,
        cancel: true,
        onAction: (_) => calls++,
      ),
      gutters: 0,
    );

    for (final entry in <Finder, String>{
      find.byKey(_rejectKey): 'Từ chối đơn',
      find.byKey(_confirmKey): 'Xác nhận đơn hàng',
      find.byKey(_cancelKey): 'Hủy ngoại lệ',
    }.entries) {
      final data = tester.getSemantics(entry.key).getSemanticsData();
      expect(data.label, entry.value);
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);
      expect(_hasSemanticTap(tester, entry.key), isTrue);
      expect(tester.getSize(entry.key).height, greaterThanOrEqualTo(48));
    }

    _performSemanticTap(tester, find.byKey(_rejectKey));
    await tester.pump();
    expect(calls, 1);
  });

  for (final size in [
    (320.0, 1.0, 844.0),
    (390.0, 1.0, 844.0),
    (320.0, 2.0, 844.0),
    (390.0, 2.0, 844.0),
    (844.0, 1.0, 390.0),
  ]) {
    testWidgets('reflows at ${size.$1}x${size.$3} scale${size.$2}', (
      tester,
    ) async {
      await pumpMh09(
        tester,
        _footer(reject: true, confirm: true, cancel: true, onAction: (_) {}),
        width: size.$1,
        height: size.$3,
        scale: size.$2,
        gutters: 0,
      );
      expect(tester.takeException(), isNull);
      for (final finder in [
        find.byKey(_rejectKey),
        find.byKey(_confirmKey),
        find.byKey(_cancelKey),
      ]) {
        expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
      }
    });
  }
}
