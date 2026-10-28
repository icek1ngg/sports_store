import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/notifications/presentation/widgets/mh17/notification_context_sheet.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_notification_theme.dart';

Widget _host(
  Widget child, {
  double width = 390,
  double scale = 1,
  EdgeInsets padding = EdgeInsets.zero,
}) {
  return MaterialApp(
    theme: OrderNotificationTheme.data(ThemeData(useMaterial3: true)),
    home: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(scale),
        padding: padding,
      ),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, height: 500, child: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders authorized strings and delegates close exactly once', (
    tester,
  ) async {
    var closeCalls = 0;
    await tester.pumpWidget(
      _host(
        Mh17NotificationContextSheet(
          title: 'Thông báo cửa hàng',
          body: 'Nội dung do parent cung cấp.',
          onClose: () => closeCalls++,
        ),
      ),
    );
    expect(find.text('Thông báo cửa hàng'), findsOneWidget);
    expect(find.text('Nội dung do parent cung cấp.'), findsOneWidget);
    expect(closeCalls, 0);
    await tester.tap(find.widgetWithText(TextButton, 'Đóng'));
    await tester.pumpAndSettle();
    expect(closeCalls, 1);
    expect(find.byType(Mh17NotificationContextSheet), findsOneWidget);
  });

  testWidgets(
    'null close callback disables button without implicit navigation',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _host(
            const Mh17NotificationContextSheet(title: 'Tiêu đề', body: 'Mô tả'),
          ),
        );
        expect(
          tester.widget<TextButton>(find.byType(TextButton)).onPressed,
          isNull,
        );
        expect(
          tester
              .getSemantics(find.byType(TextButton))
              .flagsCollection
              .isEnabled,
          Tristate.isFalse,
        );
        await tester.tap(find.byType(TextButton));
        await tester.pumpAndSettle();
        expect(find.text('Tiêu đề'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    },
  );

  testWidgets('unavailable and unknown content are displayed verbatim', (
    tester,
  ) async {
    const unavailable = 'Mục tiêu thông báo hiện chưa khả dụng.';
    await tester.pumpWidget(
      _host(
        const Mh17NotificationContextSheet(
          title: 'Loại thông báo chưa được nhận diện',
          body: 'Nội dung an toàn từ parent: <future_event> & cập nhật.',
          availabilityMessage: unavailable,
        ),
      ),
    );
    expect(find.text('Loại thông báo chưa được nhận diện'), findsOneWidget);
    expect(
      find.text('Nội dung an toàn từ parent: <future_event> & cập nhật.'),
      findsOneWidget,
    );
    expect(find.text(unavailable), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
  });

  testWidgets('heading semantics contain title once without duplicate label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      const title = 'Tiêu đề có thể tiếp cận';
      await tester.pumpWidget(
        _host(
          const Mh17NotificationContextSheet(
            title: title,
            body: 'Nội dung chi tiết',
            availabilityMessage: 'Chưa khả dụng',
          ),
        ),
      );
      final node = tester.getSemantics(find.text(title));
      expect(node.flagsCollection.isHeader, isTrue);
      expect(node.label, title);
      expect(find.bySemanticsLabel(title), findsOneWidget);
      expect(
        tester
            .getSemantics(find.text('Chưa khả dụng'))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('safe area keeps content above bottom system inset', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Mh17NotificationContextSheet(
          title: 'An toàn',
          body: 'Nội dung',
          onClose: () {},
        ),
        padding: const EdgeInsets.only(top: 24, bottom: 34),
      ),
    );
    final sheet = tester.getRect(find.byType(Mh17NotificationContextSheet));
    final scroll = tester.getRect(find.byType(SingleChildScrollView));
    expect(scroll.top, sheet.top + 24);
    expect(scroll.bottom, sheet.bottom - 34);
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.5, 2.0]) {
      testWidgets(
        'long content scrolls to close at width $width scale $scale',
        (tester) async {
          var closeCalls = 0;
          final title = List.filled(
            4,
            'Thông báo dài cần đọc đầy đủ',
          ).join(' ');
          final body = List.filled(
            35,
            'Nội dung dài được phép hiển thị.',
          ).join(' ');
          await tester.pumpWidget(
            _host(
              Mh17NotificationContextSheet(
                title: title,
                body: body,
                availabilityMessage: 'Mục tiêu hiện chưa khả dụng.',
                onClose: () => closeCalls++,
              ),
              width: width,
              scale: scale,
            ),
          );
          expect(find.text(title), findsOneWidget);
          expect(find.text(body), findsOneWidget);
          expect(find.byType(TextButton).hitTestable(), findsNothing);
          await tester.scrollUntilVisible(
            find.byType(TextButton),
            300,
            scrollable: find.byType(Scrollable),
            maxScrolls: 100,
          );
          await tester.pumpAndSettle();
          final buttonRect = tester.getRect(find.byType(TextButton));
          expect(buttonRect.width, greaterThanOrEqualTo(48));
          expect(buttonRect.height, greaterThanOrEqualTo(48));
          expect(find.byType(TextButton).hitTestable(), findsOneWidget);
          expect(buttonRect.right, lessThanOrEqualTo(width));
          await tester.tap(find.byType(TextButton));
          await tester.pumpAndSettle();
          expect(closeCalls, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('removal discards old context and remount renders new strings', (
    tester,
  ) async {
    var oldCloseCalls = 0;
    await tester.pumpWidget(
      _host(
        Mh17NotificationContextSheet(
          title: 'Thông báo cũ',
          body: 'Nội dung cũ được phép hiển thị',
          onClose: () => oldCloseCalls++,
        ),
      ),
    );
    await tester.pumpWidget(_host(const SizedBox.shrink()));
    expect(find.text('Thông báo cũ'), findsNothing);
    expect(find.text('Nội dung cũ được phép hiển thị'), findsNothing);
    await tester.pumpWidget(
      _host(
        const Mh17NotificationContextSheet(title: 'Thông báo mới', body: 'Mới'),
      ),
    );
    expect(find.text('Thông báo mới'), findsOneWidget);
    expect(find.text('Thông báo cũ'), findsNothing);
    expect(oldCloseCalls, 0);
    expect(tester.takeException(), isNull);
  });
}
