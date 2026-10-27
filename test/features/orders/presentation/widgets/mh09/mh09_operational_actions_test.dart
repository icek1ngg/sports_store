import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/domain/models/order_capabilities.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_operational_actions.dart';

import 'mh09_02b_test_support.dart';

OrderCapabilities _allOperations() => mh09Capabilities(
  assign: true,
  reassign: true,
  retry: true,
  earlyReturn: true,
  receive: true,
);

void main() {
  testWidgets(
    'no permitted operations produces no block of unavailable controls',
    (tester) async {
      await pumpMh09(tester, const Mh09OperationalActions());
      expect(find.byType(Card), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.textContaining('Chưa khả dụng'), findsNothing);
    },
  );

  for (final entry in <String, OrderCapabilities>{
    'Phân công': mh09Capabilities(assign: true),
    'Phân công lại': mh09Capabilities(reassign: true),
    'Giao lần hai': mh09Capabilities(retry: true),
    'Hoàn hàng sớm': mh09Capabilities(earlyReturn: true),
    'Nhận và kiểm tra hàng': mh09Capabilities(receive: true),
  }.entries) {
    testWidgets(
      '${entry.key} is visible but never executes an external action',
      (tester) async {
        await pumpMh09(
          tester,
          Mh09OperationalActions(capabilities: entry.value),
        );
        expect(find.byType(OutlinedButton), findsOneWidget);
        final button = find.widgetWithText(OutlinedButton, entry.key);
        expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
        final node = tester.getSemantics(button);
        final data = node.getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.flagsCollection.isEnabled, Tristate.isFalse);
        expect(data.hasAction(SemanticsAction.tap), isFalse);
        expect(data.label, contains('Chưa khả dụng.'));
        await tester.tap(button);
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pump();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('renders only the five existing Delivery and Inventory actions', (
    tester,
  ) async {
    await pumpMh09(
      tester,
      Mh09OperationalActions(capabilities: _allOperations()),
    );
    expect(find.byType(OutlinedButton), findsNWidgets(5));
    expect(
      find.text('Chưa khả dụng: Dịch vụ giao hàng chưa sẵn sàng.'),
      findsNWidgets(4),
    );
    expect(
      find.text('Chưa khả dụng: Quy trình kho chưa sẵn sàng.'),
      findsOneWidget,
    );
    for (final label in [
      'Hoàn tiền',
      'Đối soát COD',
      'Giao lần ba',
      'GPS',
      'OTP',
    ]) {
      expect(find.textContaining(label), findsNothing);
    }
  });

  testWidgets(
    'unrelated order and return capabilities do not introduce controls',
    (tester) async {
      await pumpMh09(
        tester,
        Mh09OperationalActions(
          capabilities: mh09Capabilities(
            confirm: true,
            reject: true,
            cancel: true,
            customerCancel: true,
            returnCreation: true,
          ),
        ),
      );
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(Card), findsNothing);
    },
  );

  testWidgets('a long parent-provided unavailable reason stays readable', (
    tester,
  ) async {
    final reason =
        'Hệ thống giao hàng đang chờ xác nhận tích hợp từ module phụ trách. ' *
        5;
    await pumpMh09(
      tester,
      Mh09OperationalActions(
        capabilities: mh09Capabilities(assign: true),
        unavailableReason: reason,
      ),
      width: 320,
      scale: 2,
    );
    expect(find.text('Chưa khả dụng: ${reason.trim()}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'blank parent reason falls back to the honest module dependency',
    (tester) async {
      await pumpMh09(
        tester,
        Mh09OperationalActions(
          capabilities: mh09Capabilities(receive: true),
          unavailableReason: '  ',
        ),
      );
      expect(
        find.text('Chưa khả dụng: Quy trình kho chưa sẵn sàng.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a capability revoked on rebuild removes the old control', (
    tester,
  ) async {
    await pumpMh09(
      tester,
      Mh09OperationalActions(capabilities: mh09Capabilities(assign: true)),
    );
    expect(find.text('Phân công'), findsOneWidget);
    await pumpMh09(tester, const Mh09OperationalActions());
    expect(find.text('Phân công'), findsNothing);
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'operations fit width$width scale$scale and remain disabled',
        (tester) async {
          await pumpMh09(
            tester,
            Mh09OperationalActions(capabilities: _allOperations()),
            width: width,
            scale: scale,
          );
          expect(tester.takeException(), isNull);
          final button = find.widgetWithText(
            OutlinedButton,
            'Nhận và kiểm tra hàng',
          );
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
          expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
        },
      );
    }
  }
}
