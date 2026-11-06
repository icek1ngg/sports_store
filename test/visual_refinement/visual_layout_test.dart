// Regression layout matrix. Opt-in PNG output: UI_VISUAL_OUTPUT=1.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/read_retry_policy.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/orders/domain/models/order_page.dart';
import 'package:sports_store/features/orders/domain/models/order_details.dart';
import 'package:sports_store/features/orders/data/models/order_dto.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/domain/models/order_capabilities.dart';
import 'package:sports_store/features/orders/presentation/pages/customer_orders_page.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_orders_page.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_providers.dart';
import 'package:sports_store/features/notifications/data/models/notification_dto.dart';
import 'package:sports_store/features/notifications/domain/models/notification_item.dart';
import 'package:sports_store/features/notifications/domain/models/notification_page.dart';
import 'package:sports_store/features/notifications/domain/models/notification_query.dart';
import 'package:sports_store/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sports_store/features/notifications/presentation/pages/notifications_page.dart';
import 'package:sports_store/features/notifications/presentation/view_models/notification_providers.dart';

import '../fixtures/order_list_page_fixtures.dart';
import '../fixtures/order_notification_fixtures.dart';

const output = 'docs/visual_refinement_artifacts';
final boundaryKey = GlobalKey();
final records = <Map<String, Object?>>[];
const customer = SessionScope(
  userId: fixtureCustomerId,
  role: 'customer',
  generation: 1,
);
const manager = SessionScope(
  userId: fixtureManagerId,
  role: 'manager',
  generation: 1,
);

class DelayedDetails extends OrderListFixtureRepository {
  final pendingDetails = Completer<OrderDetails>();
  @override
  Future<OrderDetails> getOrderDetails(String id) => pendingDetails.future;
}

OrderDetails lifecycleDetails() {
  final json = fixtureOrderDetailsJson()
    ..['order'] = {
      ...fixtureOrderJson(
        status: 'delivered',
        confirmedAt: '2026-10-08T03:40:00Z',
        source: 'manager',
        confirmedBy: fixtureManagerId,
        deliveredAt: '2026-10-08T06:00:00Z',
      ),
      'delivery_attempt_count': 1,
    }
    ..['as_of'] = '2026-10-08T07:30:00Z'
    ..['history_complete'] = false
    ..['capabilities'] = fixtureCapabilitiesJson(canCancelCustomer: false)
    ..['delivery_summary'] = {
      'task_id': fixtureTaskId,
      'kind': 'outbound',
      'task_status': 'delivered',
      'assigned_shipper_id': fixtureShipperId,
      'assigned_shipper_name': 'Shipper minh họa',
      'assigned_at': '2026-10-08T03:50:00Z',
      'accepted_at': '2026-10-08T03:55:00Z',
      'started_at': '2026-10-08T04:00:00Z',
      'completed_at': '2026-10-08T06:00:00Z',
      'amount_to_collect_vnd': 3480000,
      'attempt_count': 1,
      'latest_attempt': {
        'id': fixtureAttemptId,
        'task_id': fixtureTaskId,
        'order_id': fixtureOrderId,
        'attempt_number': 1,
        'task_kind': 'outbound',
        'result': 'success',
        'reason': null,
        'occurred_at': '2026-10-08T06:00:00Z',
        'shipper_id': fixtureShipperId,
      },
      'failure_reason': null,
    }
    ..['cod_summary'] = {
      'order_id': fixtureOrderId,
      'shipper_id': fixtureShipperId,
      'status': 'collected',
      'expected_amount_vnd': 3480000,
      'collected_amount_vnd': 3480000,
      'received_amount_vnd': 0,
      'collected_at': '2026-10-08T06:00:00Z',
      'collected_by': fixtureShipperId,
      'handed_over_at': null,
      'received_at': null,
      'received_by': null,
    }
    ..['return_summaries'] = [
      {
        'return_id': fixtureReturnId,
        'order_id': fixtureOrderId,
        'status': 'pending_review',
        'submitted_at': '2026-10-08T07:00:00Z',
        'closed_at': null,
        'decision_reason': null,
        'is_active': true,
        'can_submit_return': false,
        'eligibility_reason': 'active_return',
        'return_deadline': null,
      },
    ];
  return OrderDetailsDto.fromJson(json).domain;
}

class Inbox implements NotificationRepository {
  String mode = 'data';
  int markReadCalls = 0;
  Completer<NotificationPage>? pending;
  final items = List.generate(
    3,
    (index) => NotificationDto.fromJson({
      ...fixtureNotificationJson(),
      'id': '50000000-0000-4000-8000-00000000000${index + 1}',
      'title': index == 0
          ? 'Đơn hàng đã được xác nhận'
          : index == 1
          ? 'Giao hàng chưa thành công'
          : 'Thông báo có tiêu đề dài cần xuống dòng trên màn hình nhỏ và khi người dùng tăng cỡ chữ',
      'body': index == 2
          ? 'Nội dung dài để kiểm tra khả năng đọc: đơn hàng được xử lý theo trạng thái hiện tại. Mở mục thông báo để xem thông tin được phép truy cập.'
          : 'Mở đơn để xem trạng thái và thông tin hiện tại.',
      'read_at': index == 1 ? '2026-10-08T04:00:00Z' : null,
    }).domain,
  );
  @override
  Future<NotificationPage> getPage(NotificationQuery query) async {
    if (mode == 'loading') return (pending ??= Completer()).future;
    if (mode == 'error') throw const AppFailure(code: AppFailure.network);
    return NotificationPage(
      items: mode == 'empty'
          ? []
          : items
                .where(
                  (x) => query.filter == NotificationFilter.all || !x.isRead,
                )
                .toList(),
      nextCursor: null,
      unreadCount: null,
      asOf: null,
    );
  }

  @override
  Future<int> getUnreadCount() async => mode == 'empty' ? 0 : 124;
  @override
  Future<NotificationItem> markRead(String id) async {
    markReadCalls++;
    throw const AppFailure(code: AppFailure.externalDependencyUnavailable);
  }
}

OrderPage orders() => listFixturePage(
  items: [
    listFixtureSummary(
      capabilities: listFixtureCapabilities(
        canCancelCustomer: true,
        canConfirm: true,
        canReject: true,
      ),
    ),
    listFixtureSummary(
      id: listFixtureSecondOrderId,
      status: OrderStatus.delivered,
    ),
  ],
  counts: listFixtureCounts(pending: 1, delivered: 1),
);

Widget screen(String id) => switch (id) {
  'mh07' => const CustomerOrdersPage(enablePolling: false),
  'mh08' => const ManagerOrdersPage(enablePolling: false),
  'mh09' => const ManagerOrderDetailsPage(
    orderId: listFixtureOrderId,
    enablePolling: false,
  ),
  _ => const NotificationsPage(enablePolling: false),
};

Future<void> mount(
  WidgetTester tester,
  String id,
  double width,
  double scale,
  OrderListFixtureRepository repository,
  Inbox inbox, {
  SessionScope? scope,
  double height = 800,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        featureSessionScopeProvider.overrideWithValue(
          scope ?? (id == 'mh07' || id == 'mh17' ? customer : manager),
        ),
        orderRepositoryProvider.overrideWithValue(repository),
        notificationRepositoryProvider.overrideWithValue(inbox),
        readRetryPolicyProvider.overrideWithValue(
          const ReadRetryPolicy(backoffs: []),
        ),
      ],
      child: RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: screen(id),
        ),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  await tester.pump();
  final error = tester.takeException();
  final boundary =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  if (Platform.environment['UI_VISUAL_OUTPUT'] == '1') {
    await tester.runAsync(() async {
      await Directory(output).create(recursive: true);
      final bitmap = await boundary.toImage(pixelRatio: 1);
      final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      bitmap.dispose();
    });
  }
  final appBars = find.byType(AppBar);
  final viewportSizes = tester
      .renderObjectList<RenderObject>(find.byType(Viewport))
      .whereType<RenderBox>()
      .map((box) => {'width': box.size.width, 'height': box.size.height})
      .toList();
  records.add({
    'image': '$name.png',
    'exception': error?.toString(),
    'appbar': appBars.evaluate().isEmpty
        ? null
        : tester.getSize(appBars.first).height,
    'viewports': viewportSizes,
  });
  expect(error, isNull, reason: 'Layout exception: $name');
}

Future<void> bottom(WidgetTester tester) async {
  final scrolls = find.byType(Scrollable);
  if (scrolls.evaluate().isEmpty) return;
  final vertical = tester
      .stateList<ScrollableState>(scrolls)
      .where((state) => state.axisDirection == AxisDirection.down)
      .toList();
  if (vertical.isEmpty) return;
  vertical.sort(
    (a, b) => b.position.maxScrollExtent.compareTo(a.position.maxScrollExtent),
  );
  final position = vertical.first.position;
  for (var i = 0; i < 6; i++) {
    position.jumpTo(position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> dispose(WidgetTester tester, Inbox inbox) async {
  if (inbox.pending != null && !inbox.pending!.isCompleted) {
    inbox.pending!.complete(
      NotificationPage(
        items: [],
        nextCursor: null,
        unreadCount: null,
        asOf: null,
      ),
    );
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'))).load();
    await (FontLoader('BarlowCondensed')
          ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-Bold.ttf')))
        .load();
  });
  testWidgets('render fixture-only UI review evidence', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
      tester.view.resetViewInsets();
    });
    for (final id in ['mh07', 'mh08', 'mh09', 'mh17']) {
      for (final width in [320.0, 360.0, 390.0, 412.0]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          final repository = OrderListFixtureRepository(
            customerPage: orders(),
            managerPage: orders(),
            details: listFixtureDetails(
              capabilities: listFixtureCapabilities(
                canCancelCustomer: true,
                canConfirm: true,
                canReject: true,
              ),
            ),
          );
          final inbox = Inbox();
          await mount(tester, id, width, scale, repository, inbox);
          final prefix =
              '${id}_${width.toInt()}_s${scale.toString().replaceAll('.', '_')}';
          await capture(tester, '${prefix}_top');
          await bottom(tester);
          await capture(tester, '${prefix}_bottom');
          await dispose(tester, inbox);
        }
      }
      for (final state in ['loading', 'empty', 'error', 'stale']) {
        if (id == 'mh09' && state == 'empty') continue;
        final repository = OrderListFixtureRepository(
          customerPage: orders(),
          managerPage: orders(),
          details: listFixtureDetails(
            capabilities: listFixtureCapabilities(
              canCancelCustomer: true,
              canConfirm: true,
              canReject: true,
            ),
          ),
        );
        final inbox = Inbox();
        final pending = Completer<OrderPage>();
        if (state == 'loading' && id != 'mh09') {
          repository.customerPageLoader = (_) => pending.future;
          repository.managerPageLoader = (_) => pending.future;
        }
        if (state == 'empty') {
          repository.customerPage = listFixturePage(items: []);
          repository.managerPage = listFixturePage(items: []);
        }
        if (state == 'error') {
          repository.customerFailure = const AppFailure(
            code: AppFailure.network,
          );
          repository.managerFailure = const AppFailure(
            code: AppFailure.network,
          );
          repository.detailFailure = const AppFailure(code: AppFailure.network);
        }
        if (id == 'mh17' && state != 'stale') inbox.mode = state;
        if (state == 'loading' && id == 'mh09') {
          repository.detailFailure = const AppFailure(
            code: AppFailure.externalDependencyUnavailable,
          );
        }
        await mount(tester, id, 320, 1, repository, inbox);
        if (state == 'stale') {
          repository.customerFailure = const AppFailure(
            code: AppFailure.network,
          );
          repository.managerFailure = const AppFailure(
            code: AppFailure.network,
          );
          repository.detailFailure = const AppFailure(code: AppFailure.network);
          inbox.mode = 'error';
          final refresh = find.byTooltip(
            id == 'mh09'
                ? 'Tải lại'
                : id == 'mh17'
                ? 'Làm mới'
                : 'Làm mới đơn hàng',
          );
          await tester.tap(refresh);
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
        await capture(
          tester,
          '${id}_320_${state == 'loading' && id == 'mh09' ? 'dependency_unavailable' : state}',
        );
        if (id == 'mh17' && state == 'stale') {
          await tester.tap(find.text(inbox.items.first.title));
          await tester.pumpAndSettle();
          await capture(tester, 'mh17_320_stale_tap');
          records.add({
            'interaction': 'tap unread notification while stale',
            'mark_read_calls': inbox.markReadCalls,
          });
          expect(inbox.markReadCalls, 0);
        }
        if (!pending.isCompleted) pending.complete(listFixturePage(items: []));
        await dispose(tester, inbox);
      }
      for (final scope in [
        const SessionScope.unresolved(),
        const SessionScope(userId: null, role: null, generation: 2),
      ]) {
        final inbox = Inbox();
        await mount(
          tester,
          id,
          320,
          1,
          OrderListFixtureRepository(),
          inbox,
          scope: scope,
        );
        await capture(
          tester,
          '${id}_320_${scope.roleResolved ? 'expired' : 'session_loading'}',
        );
        await dispose(tester, inbox);
      }
    }
    // Dialog flow at the smallest width; production command transport stays unavailable.
    for (final id in ['mh07', 'mh08', 'mh09']) {
      final repository = OrderListFixtureRepository(
        customerPage: orders(),
        managerPage: orders(),
        details: listFixtureDetails(
          capabilities: listFixtureCapabilities(
            canCancelCustomer: true,
            canConfirm: true,
            canReject: true,
          ),
        ),
      );
      final inbox = Inbox();
      await mount(tester, id, 320, 1, repository, inbox);
      if (id == 'mh09') await bottom(tester);
      final button = find.text(
        id == 'mh07'
            ? 'Hủy đơn'
            : id == 'mh08'
            ? 'Từ chối'
            : 'Từ chối đơn',
      );
      if (button.evaluate().isNotEmpty) {
        await tester.ensureVisible(button.first);
        await tester.pump();
        await tester.tap(button.first);
        await tester.pumpAndSettle();
        await capture(tester, '${id}_320_dialog');
        final submit = find.byKey(const ValueKey('order-action-submit'));
        await tester.tap(submit);
        await tester.pumpAndSettle();
        await capture(tester, '${id}_320_dialog_submit');
        if (id != 'mh07') {
          await tester.enterText(
            find.byKey(const ValueKey('order-action-reason')),
            'Lý do kiểm thử giao diện',
          );
          await tester.tap(submit);
          await tester.pumpAndSettle();
          await capture(tester, '${id}_320_dialog_unavailable');
        }
      }
      await dispose(tester, inbox);
    }
    for (final width in [320.0, 360.0, 390.0, 412.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        final repository = OrderListFixtureRepository(
          customerPage: orders(),
          details: listFixtureDetails(),
        );
        final inbox = Inbox();
        await mount(tester, 'mh07', width, scale, repository, inbox);
        await tester.tap(find.text(listFixtureOrderId).first);
        await tester.pumpAndSettle();
        final prefix =
            'mh07_detail_${width.toInt()}_s${scale.toString().replaceAll('.', '_')}';
        await capture(tester, '${prefix}_top');
        await bottom(tester);
        await capture(tester, '${prefix}_bottom');
        await dispose(tester, inbox);
      }
    }
    final delayed = DelayedDetails();
    final delayedInbox = Inbox();
    await mount(tester, 'mh09', 320, 1, delayed, delayedInbox);
    await capture(tester, 'mh09_320_loading');
    delayed.pendingDetails.complete(listFixtureDetails());
    await dispose(tester, delayedInbox);
    for (final scale in [1.0, 1.5, 2.0]) {
      final inbox = Inbox();
      await mount(
        tester,
        'mh09',
        320,
        scale,
        OrderListFixtureRepository(details: lifecycleDetails()),
        inbox,
      );
      for (final section in ['Giao hàng', 'Đối soát COD', 'Yêu cầu trả hàng']) {
        await tester.ensureVisible(find.text(section));
        await tester.pumpAndSettle();
        await capture(
          tester,
          'mh09_320_s${scale.toString().replaceAll('.', '_')}_lifecycle_${section == 'Giao hàng'
              ? 'delivery'
              : section == 'Đối soát COD'
              ? 'cod'
              : 'returns'}',
        );
      }
      await dispose(tester, inbox);
      final externalInbox = Inbox();
      await mount(
        tester,
        'mh09',
        320,
        scale,
        OrderListFixtureRepository(
          details: listFixtureDetails(
            status: OrderStatus.preparing,
            capabilities: const OrderCapabilities(
              canCancelCustomer: false,
              canConfirm: false,
              canReject: false,
              canCancelExceptional: false,
              canAssign: true,
              canReassign: false,
              canArrangeSecondAttempt: false,
              canRequestEarlyReturn: false,
              canReceiveUndelivered: false,
              canOpenReturnCreation: false,
            ),
          ),
        ),
        externalInbox,
      );
      await bottom(tester);
      await capture(
        tester,
        'mh09_320_s${scale.toString().replaceAll('.', '_')}_assignment_disabled',
      );
      await dispose(tester, externalInbox);
    }
    for (final id in ['mh07', 'mh08', 'mh09', 'mh17']) {
      for (final scale in [1.0, 1.5, 2.0]) {
        final inbox = Inbox();
        await mount(
          tester,
          id,
          800,
          scale,
          OrderListFixtureRepository(
            customerPage: orders(),
            managerPage: orders(),
            details: listFixtureDetails(
              capabilities: listFixtureCapabilities(
                canConfirm: true,
                canReject: true,
              ),
            ),
          ),
          inbox,
          height: 390,
        );
        await capture(tester, '${id}_landscape_s$scale');
        await bottom(tester);
        await capture(tester, '${id}_landscape_s${scale}_bottom');
        await dispose(tester, inbox);
      }
      final inbox = Inbox();
      await mount(
        tester,
        id,
        320,
        2,
        OrderListFixtureRepository(
          customerPage: orders(),
          managerPage: orders(),
          details: listFixtureDetails(
            capabilities: listFixtureCapabilities(
              canConfirm: true,
              canReject: true,
            ),
          ),
        ),
        inbox,
      );
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      await tester.pump();
      await capture(tester, '${id}_safe_area');
      if (id == 'mh07' || id == 'mh08') {
        await tester.showKeyboard(find.byType(TextField).first);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pump();
        await capture(tester, '${id}_keyboard_open');
        final search = tester.getRect(find.byType(TextField).first);
        expect(
          search.bottom,
          lessThanOrEqualTo(500),
          reason: 'Search remains above keyboard',
        );
        expect(search.top, greaterThanOrEqualTo(24));
        expect(
          find.byType(TextField).first.hitTestable(),
          findsOneWidget,
          reason: 'Search input must remain visible, not clipped by header',
        );
        tester.testTextInput.hide();
        tester.view.resetViewInsets();
        await tester.pump();
        await capture(tester, '${id}_keyboard_closed');
      }
      tester.view.resetPadding();
      await dispose(tester, inbox);
    }
    if (Platform.environment['UI_VISUAL_OUTPUT'] == '1') {
      await tester.runAsync(() async {
        await File('$output/render_manifest.json')
            .writeAsString(const JsonEncoder.withIndent('  ').convert(records));
      });
    }
  });
}
