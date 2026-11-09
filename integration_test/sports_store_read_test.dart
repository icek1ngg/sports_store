import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sports_store/main.dart' as app;
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/auth/presentation/view_models/auth_providers.dart';
import 'package:sports_store/features/cod/presentation/view_models/cod_providers.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_providers.dart';
import 'package:sports_store/features/notifications/domain/models/notification_query.dart';
import 'package:sports_store/features/notifications/presentation/providers/notification_providers.dart';
import 'package:sports_store/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:sports_store/features/orders/domain/models/order_page.dart';
import 'package:sports_store/features/orders/domain/models/order_query.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_providers.dart';
import 'package:sports_store/features/orders/presentation/pages/mh09/mh09_detail_body.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_action_dialog.dart';

import 'catalog_cart_live_test.dart' show CatalogLiveIntegrationBinding;

/// Real production entrypoint and authenticated repositories. This runner never
/// places an order, edits a cart, marks a notification or invokes a mutation.
void main() {
  final binding = CatalogLiveIntegrationBinding.ensureInitialized();
  testWidgets(
    'canonical Supabase app authenticates two QA identities and reads',
    (tester) async {
      final credentials = await binding.credentials.timeout(
        const Duration(minutes: 2),
      );
      final evidence = <String, dynamic>{};
      binding.reportData = {'read_only': true, 'operations': evidence};
      String? previousUser;
      String? previousOrder;
      String? previousNotification;
      String? previousRole;
      try {
        await app.main();
        await tester.pump();
        await _wait(
          tester,
          () => find.byType(SportsStoreApp).evaluate().isNotEmpty,
        );
        for (final prefix in ['CATALOG_TEST', 'CATALOG_TEST_SECONDARY']) {
          final fields = find.byType(TextFormField);
          await _wait(tester, () => fields.evaluate().length == 2);
          await tester.ensureVisible(fields.at(0));
          await tester.enterText(fields.at(0), credentials['${prefix}_EMAIL']!);
          await tester.ensureVisible(fields.at(1));
          await tester.enterText(
            fields.at(1),
            credentials['${prefix}_PASSWORD']!,
          );
          final login = find.widgetWithText(FilledButton, 'Đăng nhập');
          await tester.ensureVisible(login);
          await tester.tap(login);
          final container = _container(tester);
          await _wait(
            tester,
            () =>
                container.read(featureSessionScopeProvider).canReadPrivateData,
          );
          final scope = container.read(featureSessionScopeProvider);
          final profile = container.read(currentProfileProvider).asData?.value;
          final auth = container.read(authSessionProvider).asData?.value;
          final client = container.read(supabaseClientProvider);
          expect(
            client.auth.currentUser?.email?.toLowerCase() ==
                credentials['${prefix}_EMAIL']!.toLowerCase(),
            isTrue,
            reason: 'The authenticated identity must match the submitted QA identity.',
          );
          expect(profile?.id, scope.userId);
          expect(profile?.role.name, scope.role);
          expect(auth?.userId, scope.userId);
          if (previousUser != null) expect(scope.userId, isNot(previousUser));
          final role = scope.role!;
          final label =
              '${prefix == 'CATALOG_TEST' ? 'first' : 'second'}_$role';
          String? readNotificationId;
          String? readNotificationOrder;
          _record(evidence, label, 'auth_scope', 'PASS');
          final expectedRole = prefix == 'CATALOG_TEST'
              ? const String.fromEnvironment('QA_FIRST_ROLE')
              : const String.fromEnvironment('QA_SECOND_ROLE');
          if (expectedRole.isNotEmpty && role != expectedRole) {
            evidence['$label/requested_role'] = {
              'status': 'BLOCKED',
              'code': 'server_profile_role_mismatch',
            };
          }
          if (role == 'customer' &&
              previousRole == 'customer' &&
              previousOrder != null &&
              previousNotification != null) {
            await _read(
              tester,
              evidence,
              label,
              'foreign_records_denied',
              () async {
                if (previousOrder != null) {
                  AppFailure? denied;
                  try {
                    await container
                        .read(orderRepositoryProvider)!
                        .getOrderDetails(previousOrder!);
                  } on AppFailure catch (failure) {
                    denied = failure;
                  }
                  expect(denied?.code, AppFailure.forbiddenOrUnavailable);
                }
                if (previousNotification != null) {
                  final rows = await client
                      .from('notifications')
                      .select('id')
                      .eq('id', previousNotification!);
                  expect(rows, isEmpty);
                }
              },
            );
          }
          GoRouter router() => container.read(appRouterProvider);

          if (role == 'customer') {
            for (final path in [
              '/customer/home',
              '/customer/products',
              '/customer/cart',
              '/customer/checkout',
              '/customer/orders',
            ]) {
              router().go(path);
              await _wait(tester, () => router().state.uri.path == path);
              await tester.pump(const Duration(milliseconds: 300));
              expect(find.byType(NavigationBar), findsOneWidget);
            }
          } else {
            router().go(
              role == 'manager' ? '/manager/orders' : '/shipper/tasks',
            );
            await tester.pump(const Duration(milliseconds: 300));
          }

          await _read(
            tester,
            evidence,
            label,
            'notifications_all_unread_count',
            () async {
              final repository = container.read(
                notificationRepositoryProvider,
              )!;
              final all = await repository.getPage(NotificationQuery());
              for (final row in all.items) {
                if (row.isRead && row.subjectType.rawValue == 'order') {
                  readNotificationId = row.id;
                  readNotificationOrder = row.subjectId;
                  break;
                }
              }
              if (previousUser == null && all.items.isNotEmpty) {
                previousNotification = all.items.first.id;
              }
              final unread = await repository.getPage(
                NotificationQuery(filter: NotificationFilter.unread),
              );
              final count = await repository.getUnreadCount();
              expect(count, greaterThanOrEqualTo(unread.items.length));
              expect(
                all.items.every((row) => row.recipientId == scope.userId),
                isTrue,
              );
              expect(
                unread.items.every(
                  (row) => row.recipientId == scope.userId && !row.isRead,
                ),
                isTrue,
              );
              if (all.nextCursor != null) {
                final next = await repository.getPage(
                  NotificationQuery(cursor: all.nextCursor),
                );
                expect(
                  next.items.every(
                    (row) =>
                        row.recipientId == scope.userId &&
                        !all.items.any((before) => before.id == row.id),
                  ),
                  isTrue,
                );
                _record(evidence, label, 'notifications_pagination', 'PASS');
              } else {
                _record(
                  evidence,
                  label,
                  'notifications_pagination',
                  'NOT_EXERCISED',
                );
              }
            },
          );
          router().push('/notifications');
          await _wait(
            tester,
            () => router().state.uri.path == '/notifications',
          );
          expect(find.byType(NavigationBar), findsOneWidget);
          await _wait(
            tester,
            () => find
                .widgetWithText(ChoiceChip, 'Chưa đọc')
                .evaluate()
                .isNotEmpty,
          );
          await tester.tap(find.widgetWithText(ChoiceChip, 'Chưa đọc'));
          await tester.pump(const Duration(milliseconds: 600));
          expect(
            tester
                .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Chưa đọc'))
                .selected,
            isTrue,
          );
          await tester.tap(find.widgetWithText(ChoiceChip, 'Tất cả'));
          await tester.pump(const Duration(milliseconds: 600));
          _record(evidence, label, 'notification_filters_ui', 'PASS');
          if (readNotificationId != null &&
              (role == 'manager' || role == 'customer')) {
            final tile = find.byKey(ValueKey<String>(readNotificationId!));
            final inboxScroll = find
                .descendant(
                  of: find.byType(NotificationsScreen),
                  matching: find.byType(Scrollable),
                )
                .first;
            await _wait(tester, () => inboxScroll.evaluate().isNotEmpty);
            await tester.scrollUntilVisible(
              tile,
              250,
              scrollable: inboxScroll,
              maxScrolls: 40,
            );
            await tester.ensureVisible(tile);
            await tester.tap(tile);
            await _wait(
              tester,
              () =>
                  router().state.uri.path ==
                  '/$role/orders/$readNotificationOrder',
            );
            await _wait(
              tester,
              () => role == 'manager'
                  ? find.byType(Mh09DetailBody).evaluate().isNotEmpty
                  : find.text(readNotificationOrder!).evaluate().isNotEmpty,
            );
            await tester.pump(const Duration(milliseconds: 300));
            router().pop();
            await _wait(
              tester,
              () => router().state.uri.path == '/notifications',
            );
            _record(evidence, label, 'read_notification_target_back', 'PASS');
          } else {
            _record(
              evidence,
              label,
              'read_notification_target_back',
              'NOT_EXERCISED',
            );
          }
          router().pop();
          await tester.pump(const Duration(milliseconds: 300));

          if (role == 'customer' || role == 'manager') {
            await _read(
              tester,
              evidence,
              label,
              'orders_list_detail',
              () async {
                final repository = container.read(orderRepositoryProvider)!;
                final OrderPage page = role == 'customer'
                    ? await repository.getCustomerOrders(OrderQuery())
                    : await repository.getManagerOrders(OrderQuery());
                if (role == 'customer') {
                  expect(
                    page.items.every(
                      (row) => row.order.customerId == scope.userId,
                    ),
                    isTrue,
                  );
                }
                if (page.items.isEmpty) {
                  _record(evidence, label, 'order_detail', 'NOT_EXERCISED');
                } else {
                  final selected = role == 'manager'
                      ? page.items.firstWhere(
                          (row) => row.capabilities.canReject,
                          orElse: () => page.items.first,
                        )
                      : page.items.first;
                  final id = selected.order.id;
                  if (previousUser == null) previousOrder = id;
                  final details = await repository.getOrderDetails(id);
                  expect(details.order.id, id);
                  if (role == 'customer') {
                    expect(details.order.customerId, scope.userId);
                  }
                  router().push('/$role/orders/$id');
                  await _wait(
                    tester,
                    () => router().state.uri.path == '/$role/orders/$id',
                  );
                  await _wait(
                    tester,
                    () => role == 'manager'
                        ? find.byType(Mh09DetailBody).evaluate().isNotEmpty
                        : find.text(id).evaluate().isNotEmpty,
                  );
                  expect(find.byType(NavigationBar), findsOneWidget);
                  if (role == 'manager') {
                    final reject = find.byKey(
                      const ValueKey('mh09-action-reject'),
                    );
                    final canOpen =
                        reject.evaluate().isNotEmpty &&
                        tester.widget<ButtonStyleButton>(reject).onPressed !=
                            null;
                    if (canOpen) {
                      await tester.ensureVisible(reject);
                      await tester.tap(reject);
                      await tester.pump(const Duration(milliseconds: 300));
                      await tester.enterText(
                        find.byKey(const ValueKey('order-action-reason')),
                        'QA read-only dialog lifecycle',
                      );
                    }
                    for (var cycle = 0; cycle < 3; cycle++) {
                      await tester.pump(const Duration(seconds: 31));
                      expect(find.byType(Mh09DetailBody), findsOneWidget);
                      expect(router().state.uri.path, '/manager/orders/$id');
                      if (canOpen) {
                        expect(find.byType(OrderActionDialog), findsOneWidget);
                      }
                    }
                    if (canOpen) {
                      expect(
                        find.text('QA read-only dialog lifecycle'),
                        findsOneWidget,
                      );
                      await tester.tap(find.text('Đóng'));
                      await tester.pump(const Duration(milliseconds: 300));
                    }
                    _record(
                      evidence,
                      label,
                      'dialog_background_cycles',
                      canOpen ? 'PASS' : 'NOT_EXERCISED',
                    );
                    _record(
                      evidence,
                      label,
                      'detail_background_cycles',
                      'PASS',
                    );
                  }
                  router().pop();
                  await tester.pump(const Duration(milliseconds: 300));
                  _record(evidence, label, 'order_detail', 'PASS');
                }
                _record(evidence, label, 'orders_pagination', 'NOT_EXERCISED');
              },
            );
          } else if (role == 'shipper') {
            await _read(tester, evidence, label, 'shipper_tasks_cod', () async {
              await container.read(deliveryRepositoryProvider).listTasks();
              await container.read(codRepositoryProvider).listCollections();
            });
            router().go('/cod');
            await _wait(tester, () => router().state.uri.path == '/cod');
          }
          previousUser = scope.userId;
          previousRole = role;
          router().go('/$role/account');
          final logout = find.byKey(const ValueKey('account-logout'));
          await _wait(tester, () => logout.evaluate().isNotEmpty);
          if (role == 'manager') {
            final accountRouter = router();
            for (var cycle = 0; cycle < 3; cycle++) {
              router().go('/manager/orders');
              await tester.pump(const Duration(milliseconds: 500));
              router().go('/manager/account');
              await _wait(tester, () => logout.evaluate().isNotEmpty);
            }
            expect(router(), same(accountRouter));
            _record(evidence, label, 'account_repeated_visits', 'PASS');
          }
          await tester.ensureVisible(logout);
          await tester.tap(logout);
          await _wait(
            tester,
            () =>
                fields.evaluate().length == 2 &&
                !container.read(featureSessionScopeProvider).canReadPrivateData,
          );
          expect(find.byType(NavigationBar), findsNothing);
          _record(evidence, label, 'logout_private_scope_cleared', 'PASS');
        }
      } finally {
        credentials.clear();
        binding.reportData = {'read_only': true, 'operations': evidence};
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SportsStoreApp)));

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('QA app route/session did not reach its expected state before timeout.');
}

Future<void> _read(
  WidgetTester tester,
  Map<String, dynamic> evidence,
  String role,
  String operation,
  Future<void> Function() action,
) async {
  try {
    // WidgetTester.runAsync reports an exception to the framework and returns
    // null; capture inside its callback so a failed read is never labelled PASS.
    Object? failure;
    await tester.runAsync(() async {
      try {
        await action().timeout(const Duration(minutes: 3));
      } catch (error) {
        failure = error;
      }
    });
    if (failure != null) throw failure!;
    _record(evidence, role, operation, 'PASS');
  } catch (error) {
    if (error is TestFailure) rethrow;
    evidence['$role/$operation'] = {
      'status': 'BLOCKED',
      'code': error is AppFailure ? error.code : 'read_or_contract_failure',
    };
  }
}

void _record(
  Map<String, dynamic> evidence,
  String role,
  String operation,
  String status,
) {
  evidence['$role/$operation'] = {'status': status};
  // Report operation labels only: never identity fields, credentials or rows.
  debugPrint('$role $operation $status');
}
