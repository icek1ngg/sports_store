import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/notifications/domain/models/notification_query.dart';
import 'package:sports_store/features/notifications/presentation/widgets/mh17/notification_filters.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_notification_theme.dart';

Widget _host(Widget child, {double width = 390, double scale = 1}) {
  return MaterialApp(
    theme: OrderNotificationTheme.data(ThemeData(useMaterial3: true)),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

Finder _chip(String label) => find.widgetWithText(ChoiceChip, label);

void main() {
  testWidgets('defaults to all without running callbacks from build', (
    tester,
  ) async {
    var refreshCalls = 0;
    final changes = <NotificationFilter>[];
    await tester.pumpWidget(
      _host(
        Mh17NotificationFilters(
          onFilterChanged: changes.add,
          onRefresh: () => refreshCalls++,
        ),
      ),
    );

    expect(tester.widget<ChoiceChip>(_chip('Tất cả')).selected, isTrue);
    expect(tester.widget<ChoiceChip>(_chip('Chưa đọc')).selected, isFalse);
    expect(changes, isEmpty);
    expect(refreshCalls, 0);
  });

  testWidgets('one tap emits one value and selection waits for parent', (
    tester,
  ) async {
    final changes = <NotificationFilter>[];
    await tester.pumpWidget(
      _host(Mh17NotificationFilters(onFilterChanged: changes.add)),
    );
    await tester.tap(_chip('Chưa đọc'));
    await tester.pumpAndSettle();

    expect(changes, [NotificationFilter.unread]);
    expect(tester.widget<ChoiceChip>(_chip('Tất cả')).selected, isTrue);
    expect(tester.widget<ChoiceChip>(_chip('Chưa đọc')).selected, isFalse);

    await tester.pumpWidget(
      _host(
        Mh17NotificationFilters(
          selectedFilter: NotificationFilter.unread,
          onFilterChanged: changes.add,
        ),
      ),
    );
    expect(tester.widget<ChoiceChip>(_chip('Chưa đọc')).selected, isTrue);
    await tester.tap(_chip('Tất cả'));
    await tester.pumpAndSettle();
    expect(changes, [NotificationFilter.unread, NotificationFilter.all]);
  });

  testWidgets('selected state is exposed in semantics', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _host(
          Mh17NotificationFilters(
            selectedFilter: NotificationFilter.unread,
            onFilterChanged: (_) {},
          ),
        ),
      );

      expect(
        tester.getSemantics(_chip('Chưa đọc')).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        tester.getSemantics(_chip('Tất cả')).flagsCollection.isSelected,
        Tristate.isFalse,
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('null callbacks disable their own controls', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_host(const Mh17NotificationFilters()));
      expect(tester.widget<ChoiceChip>(_chip('Tất cả')).onSelected, isNull);
      expect(tester.widget<ChoiceChip>(_chip('Chưa đọc')).onSelected, isNull);
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
      expect(
        tester.getSemantics(_chip('Chưa đọc')).flagsCollection.isEnabled,
        Tristate.isFalse,
      );
      await tester.tap(_chip('Chưa đọc'));
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(_chip('Tất cả')).selected, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('refresh emits once per tap and busy disables refresh only', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      var refreshCalls = 0;
      final changes = <NotificationFilter>[];
      await tester.pumpWidget(
        _host(Mh17NotificationFilters(onRefresh: () => refreshCalls++)),
      );
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(refreshCalls, 1);

      await tester.pumpWidget(
        _host(
          Mh17NotificationFilters(
            onRefresh: () => refreshCalls++,
            onFilterChanged: changes.add,
            isRefreshing: true,
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byTooltip('Đang làm mới'), findsOneWidget);
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
      expect(
        tester.getSemantics(find.byType(IconButton)).flagsCollection.isEnabled,
        Tristate.isFalse,
      );
      await tester.tap(find.byType(IconButton));
      await tester.tap(_chip('Chưa đọc'));
      await tester.pump();
      expect(refreshCalls, 1);
      expect(changes, [NotificationFilter.unread]);
    } finally {
      handle.dispose();
    }
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.5, 2.0]) {
      testWidgets('fits width $width at scale $scale with 48dp targets', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(
            Mh17NotificationFilters(onFilterChanged: (_) {}, onRefresh: () {}),
            width: width,
            scale: scale,
          ),
        );
        final bounds = tester.getRect(find.byType(Mh17NotificationFilters));
        for (final control in [
          _chip('Tất cả'),
          _chip('Chưa đọc'),
          find.byType(IconButton),
        ]) {
          final rect = tester.getRect(control);
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(rect.left, greaterThanOrEqualTo(bounds.left));
          expect(rect.right, lessThanOrEqualTo(bounds.right));
          expect(control.hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
