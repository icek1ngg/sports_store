import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_orders_page.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_providers.dart';

import '../../../../../fixtures/order_list_page_fixtures.dart';

const mh08ManagerScope = SessionScope(
  userId: '90000000-0000-4000-8000-000000000001',
  role: 'manager',
  generation: 1,
);

ProviderContainer createMh08Container(
  OrderListFixtureRepository repository, {
  SessionScope Function()? scopeFactory,
}) {
  return ProviderContainer(
    overrides: [
      scopeFactory == null
          ? featureSessionScopeProvider.overrideWithValue(mh08ManagerScope)
          : featureSessionScopeProvider.overrideWith((_) => scopeFactory()),
      orderRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

Future<void> finishMh08Test(
  WidgetTester tester,
  ProviderContainer container,
) async {
  container.dispose();
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.pump();
}

Widget mh08Host(
  ProviderContainer container,
  Widget child, {
  Size size = const Size(320, 900),
  bool largeText = false,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: largeText
              ? const TextScaler.linear(2)
              : TextScaler.noScaling,
        ),
        child: child,
      ),
    ),
  );
}

Future<void> pumpMh08Page(
  WidgetTester tester,
  ProviderContainer container,
  ManagerOrdersPage page,
) async {
  await tester.pumpWidget(mh08Host(container, page));
  await tester.pumpAndSettle();
}

Future<void> requestMh08LoadMoreIfVisible(WidgetTester tester) async {
  await tester.drag(find.byType(ListView).last, const Offset(0, -420));
  await tester.pump();
  final button = find.text('Tải thêm đơn hàng');
  if (button.evaluate().isNotEmpty) {
    await tester.ensureVisible(button);
    await tester.pump();
    if (button.evaluate().isNotEmpty) await tester.tap(button);
  }
  await tester.pumpAndSettle();
}
