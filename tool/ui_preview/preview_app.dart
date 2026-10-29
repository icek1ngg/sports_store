// Debug-only UI harness. It reuses the feature contracts without initializing
// Auth or Supabase and never changes the production entrypoint.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/read_retry_policy.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/notifications/data/models/notification_dto.dart';
import 'package:sports_store/features/notifications/domain/models/notification_item.dart';
import 'package:sports_store/features/notifications/domain/models/notification_page.dart';
import 'package:sports_store/features/notifications/domain/models/notification_query.dart';
import 'package:sports_store/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sports_store/features/notifications/presentation/pages/notifications_page.dart';
import 'package:sports_store/features/notifications/presentation/view_models/notification_providers.dart';
import 'package:sports_store/features/orders/presentation/pages/customer_orders_page.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_orders_page.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_providers.dart';

import '../../test/fixtures/order_notification_fixtures.dart';
import 'mh07_preview_data.dart';

export 'mh07_preview_data.dart' show PreviewScenario, PreviewOrderRepository;

/// The provider scope is intentionally stable for the lifetime of the
/// preview. The navigator and its dialog routes are descendants of this
/// scope, so changing a scenario cannot dispose a scope while a route is live.
class UiPreviewApp extends StatefulWidget {
  const UiPreviewApp({this.showControls = true, super.key});

  final bool showControls;

  @override
  State<UiPreviewApp> createState() => _UiPreviewAppState();
}

class _UiPreviewAppState extends State<UiPreviewApp> {
  late final _PreviewEnvironment _environment;

  @override
  void initState() {
    super.initState();
    _environment = _PreviewEnvironment();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      // Do not key this scope by screen/scenario. Its container owns the
      // Navigator's provider graph and must outlive modal routes.
      key: const ValueKey('ui-preview-provider-scope'),
      overrides: [
        featureSessionScopeProvider.overrideWith((ref) => _environment.scope),
        orderRepositoryProvider.overrideWith((ref) => _environment.orders),
        notificationRepositoryProvider.overrideWith(
          (ref) => _environment.inbox,
        ),
        readRetryPolicyProvider.overrideWithValue(
          const ReadRetryPolicy(backoffs: []),
        ),
      ],
      child: _UiPreviewSurface(
        environment: _environment,
        showControls: widget.showControls,
      ),
    );
  }
}

class _PreviewEnvironment {
  _PreviewEnvironment()
    : orders = PreviewOrderRepository(),
      inbox = _PreviewInbox(PreviewScenario.data),
      scope = const SessionScope(
        userId: fixtureCustomerId,
        role: 'customer',
        generation: 1,
      );

  final PreviewOrderRepository orders;
  final _PreviewInbox inbox;
  SessionScope scope;
  int _generation = 1;

  void select({required String screen, required PreviewScenario scenario}) {
    orders.setScenario(scenario);
    inbox.setScenario(scenario);
    _generation++;
    final manager = screen == 'MH08' || screen == 'MH09';
    scope = scenario == PreviewScenario.expired
        ? SessionScope(userId: null, role: null, generation: _generation)
        : SessionScope(
            userId: manager ? fixtureManagerId : fixtureCustomerId,
            role: manager ? 'manager' : 'customer',
            generation: _generation,
          );
  }
}

class _UiPreviewSurface extends StatefulWidget {
  const _UiPreviewSurface({
    required this.environment,
    required this.showControls,
  });

  final _PreviewEnvironment environment;
  final bool showControls;

  @override
  State<_UiPreviewSurface> createState() => _UiPreviewSurfaceState();
}

class _UiPreviewSurfaceState extends State<_UiPreviewSurface> {
  String screen = 'MH07';
  PreviewScenario scenario = PreviewScenario.data;

  void _selectScreen(String value) {
    if (value == screen) return;
    setState(() => screen = value);
    _refreshProviderGraph();
  }

  void _selectScenario(PreviewScenario value) {
    if (value == scenario) return;
    setState(() => scenario = value);
    _refreshProviderGraph();
  }

  void _refreshProviderGraph() {
    widget.environment.select(screen: screen, scenario: scenario);
    // Invalidating the session provider rebuilds its dependents and gives
    // each foundation notifier a fresh cache namespace. The ProviderScope
    // itself remains mounted above MaterialApp/Navigator.
    ProviderScope.containerOf(
      context,
      listen: false,
    ).invalidate(featureSessionScopeProvider);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sports Store — UI Preview',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Builder(
        builder: (navigatorContext) => Scaffold(
          // The feature Scaffold owns keyboard insets. Applying them twice
          // shrinks MH07's body twice when the demo toolbar is present.
          resizeToAvoidBottomInset: false,
          appBar: widget.showControls ? _buildAppBar() : null,
          body: _buildBody(navigatorContext),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      toolbarHeight: 48,
      title: const Text(
        'DEMO UI · dữ liệu kiểm thử',
        style: TextStyle(fontSize: 12),
      ),
      actions: [
        PopupMenuButton<String>(
          initialValue: screen,
          tooltip: 'Chọn màn hình',
          onSelected: _selectScreen,
          itemBuilder: (_) => [
            'MH07',
            'MH08',
            'MH09',
            'MH17',
          ].map((id) => PopupMenuItem(value: id, child: Text(id))).toList(),
        ),
        PopupMenuButton<PreviewScenario>(
          initialValue: scenario,
          tooltip: 'Chọn trạng thái',
          onSelected: _selectScenario,
          itemBuilder: (_) => PreviewScenario.values
              .map(
                (value) => PopupMenuItem(value: value, child: Text(value.name)),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext navigatorContext) {
    switch (screen) {
      case 'MH07':
        return CustomerOrdersPage(
          enablePolling: false,
          showPreviewNavigation: true,
        );
      case 'MH08':
        return ManagerOrdersPage(
          enablePolling: false,
          onOpenOrder: (id) {
            Navigator.of(navigatorContext).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ManagerOrderDetailsPage(orderId: id, enablePolling: false),
              ),
            );
          },
        );
      case 'MH09':
        return const ManagerOrderDetailsPage(
          orderId: fixtureOrderId,
          enablePolling: false,
        );
      default:
        return const NotificationsPage(enablePolling: false);
    }
  }
}

class _PreviewInbox implements NotificationRepository {
  _PreviewInbox(this.scenario) {
    items = _buildItems();
  }

  PreviewScenario scenario;
  int pageReads = 0;
  late List<NotificationItem> items;

  void setScenario(PreviewScenario value) {
    if (scenario == value) return;
    scenario = value;
    pageReads = 0;
    items = _buildItems();
  }

  List<NotificationItem> _buildItems() => List.generate(
    3,
    (index) => NotificationDto.fromJson({
      ...fixtureNotificationJson(),
      'id': '50000000-0000-4000-8000-00000000000${index + 1}',
      'title': index == 0
          ? 'Đơn hàng đã được xác nhận'
          : index == 1
          ? 'Cập nhật đơn hàng'
          : 'Thông báo minh họa có tiêu đề dài để kiểm tra cỡ chữ và màn hình nhỏ',
      'body': 'Dữ liệu kiểm thử UI. Không có giao dịch hoặc thông báo thật.',
      'subject_type': index == 0 ? 'order' : 'notification_only',
      'read_at': index == 1 ? '2026-10-08T04:00:00Z' : null,
    }).domain,
  );

  @override
  Future<NotificationPage> getPage(NotificationQuery query) async {
    pageReads++;
    if (scenario == PreviewScenario.loading) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    if (scenario == PreviewScenario.error ||
        (scenario == PreviewScenario.stale && pageReads > 1)) {
      throw const AppFailure(code: AppFailure.network);
    }
    final filtered = scenario == PreviewScenario.empty
        ? <NotificationItem>[]
        : items
              .where(
                (item) =>
                    query.filter == NotificationFilter.all || !item.isRead,
              )
              .toList();
    final offset = query.cursor == null ? 0 : int.parse(query.cursor!);
    final page = filtered.skip(offset).take(2).toList();
    return NotificationPage(
      items: page,
      nextCursor: offset + page.length < filtered.length
          ? '${offset + page.length}'
          : null,
      unreadCount: null,
      asOf: null,
    );
  }

  @override
  Future<int> getUnreadCount() async {
    if (scenario == PreviewScenario.error) {
      throw const AppFailure(code: AppFailure.network);
    }
    return scenario == PreviewScenario.empty
        ? 0
        : items.where((item) => !item.isRead).length;
  }

  @override
  Future<NotificationItem> markRead(String id) async {
    final index = items.indexWhere((item) => item.id == id);
    if (index < 0) {
      throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
    }
    final acknowledged = NotificationDto.fromJson({
      ...items[index].toMap(),
      'read_at': '2026-10-08T05:00:00Z',
    }).domain;
    items[index] = acknowledged;
    return acknowledged;
  }
}
