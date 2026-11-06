// Explicitly injected test repositories; no runtime demo or fake write adapter.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/cod/domain/models/cod_collection.dart';
import 'package:sports_store/features/cod/domain/models/cod_collection_page.dart';
import 'package:sports_store/features/cod/domain/models/cod_collection_query.dart';
import 'package:sports_store/features/cod/domain/models/cod_receipt.dart';
import 'package:sports_store/features/cod/domain/repositories/cod_repository.dart';
import 'package:sports_store/features/cod/domain/repositories/cod_receipt_repository.dart';
import 'package:sports_store/features/cod/presentation/pages/cod_route_page.dart';
import 'package:sports_store/features/cod/presentation/view_models/cod_providers.dart';
import 'package:sports_store/features/cod/presentation/widgets/manager_cod_panel.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';

const _manager = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _shipper = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _order = '11111111-1111-4111-8111-111111111111';
const _request = '99999999-9999-4999-8999-999999999999';
final _time = DateTime.utc(2026, 10, 25, 12);

class _Role extends Notifier<String> {
  @override
  String build() => 'manager';
  void change(String value) => state = value;
}

final _role = NotifierProvider<_Role, String>(_Role.new);

class _BackendFixture implements CodRepository, CodReceiptRepository {
  final queries = <CodCollectionQuery>[];
  final commands = <CodReceiptCommand>[];
  bool received = false;
  bool failExactRead = false;
  Future<void> Function()? onWrite;

  CodCollection get row => CodCollection(
    orderId: _order,
    orderCode: _order,
    orderCodeSource: 'order_uuid',
    shipperId: _shipper,
    status: received ? CodStatus.received : CodStatus.collected,
    expectedAmountVnd: 550000,
    collectedAmountVnd: 550000,
    receivedAmountVnd: received ? 550000 : 0,
    collectedBy: _shipper,
    receivedBy: received ? _manager : null,
    collectedAt: _time.subtract(const Duration(hours: 1)),
    receivedAt: received ? _time : null,
    handedOverAt: received ? _time : null,
    createdAt: _time.subtract(const Duration(hours: 2)),
    updatedAt: _time,
  );
  @override
  Future<CodCollectionPage> queryCollections(CodCollectionQuery query) async {
    queries.add(query);
    if (received && failExactRead && query.statuses.isEmpty) {
      failExactRead = false;
      throw const OperationalFailure(OperationalFailureCode.network);
    }
    final scoped =
        (query.orderId == null || query.orderId == _order) &&
        (query.shipperId == null || query.shipperId == _shipper);
    final selected =
        scoped &&
        (query.statuses.isEmpty || query.statuses.contains(row.status));
    return CodCollectionPage(
      items: selected ? [row] : [],
      nextCursor: null,
      filteredTotal: selected ? 1 : 0,
      counts: CodCollectionCounts(
        all: scoped ? 1 : 0,
        uncollected: 0,
        collected: scoped && !received ? 1 : 0,
        received: scoped && received ? 1 : 0,
      ),
      outstandingVnd: scoped && !received ? 550000 : 0,
      asOf: _time,
    );
  }

  @override
  Future<List<CodCollection>> listCollections({
    String? shipperId,
    String? orderId,
  }) async => [row];
  @override
  Future<CodReceipt> confirmReceipt(CodReceiptCommand command) async {
    commands.add(command);
    await onWrite?.call();
    received = true;
    return CodReceipt(
      orderId: _order,
      status: CodReceiptStatus.received,
      receivedAmountVnd: 550000,
      receivedBy: _manager,
      receivedAt: _time,
      handedOverAt: _time,
      eventId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      notificationId: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
    );
  }
}

Widget _app(
  _BackendFixture backend, {
  int Function()? generate,
  TextScaler? scaler,
  bool routed = false,
}) => ProviderScope(
  overrides: [
    operationalSessionProvider.overrideWith(
      (ref) => Stream.value(
        const OperationalSession(userId: _manager, generation: 1),
      ),
    ),
    codScreenRoleProvider.overrideWith((ref) => AsyncData(ref.watch(_role))),
    codRepositoryProvider.overrideWithValue(backend),
    codReceiptRepositoryProvider.overrideWithValue(backend),
    codReceiptRequestIdProvider.overrideWithValue(() {
      generate?.call();
      return _request;
    }),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: scaler ?? TextScaler.noScaling),
      child: child!,
    ),
    home: routed
        ? Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const ValueKey('open-cod-route'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      key: ValueKey('cod-detail-route'),
                      body: CodRoutePage(),
                    ),
                  ),
                ),
                child: const Text('Open COD'),
              ),
            ),
          )
        : const Scaffold(body: CodRoutePage()),
  ),
);

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key), skipOffstage: false);
  // The panel is a single, vertically scrolling MH12 surface.  In the
  // default 800x600 test viewport the record action can sit just below the
  // viewport even after the first layout pass.  Give the list a chance to
  // reveal it before tapping; this keeps the test exercising the real button
  // rather than using an off-screen tap or a direct callback.
  await tester.pumpAndSettle();
  final panel = find.byKey(const ValueKey('manager-cod-panel'));
  // The filter action is already in the form viewport. Avoid moving the
  // lazy list here so the two filter fields remain mounted for a combined
  // search assertion immediately after validation.
  if (key == 'manager-cod-apply' && target.evaluate().isNotEmpty) {
    await tester.tap(target, warnIfMissed: false);
    await tester.pumpAndSettle();
    return;
  }
  for (var attempt = 0; attempt < 10 && target.evaluate().isEmpty; attempt++) {
    if (panel.evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 40));
      continue;
    }
    await tester.drag(panel, const Offset(0, -240), warnIfMissed: false);
    await tester.pumpAndSettle();
  }
  expect(target, findsOneWidget, reason: 'missing action $key');
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) =>
    _tap(tester, 'manager-cod-open-$_order');
Future<void> _agree(WidgetTester tester) =>
    _tap(tester, 'manager-cod-received-full');

void main() {
  testWidgets(
    'same MH12 route, exact UUID filters and guarded full backend amount',
    (tester) async {
      final backend = _BackendFixture();
      await tester.pumpWidget(_app(backend));
      await tester.pumpAndSettle();
      expect(find.byType(CodRoutePage), findsOneWidget);
      expect(find.byType(ManagerCodPanel), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('manager-cod-order-filter')),
        'DH001',
      );
      await _tap(tester, 'manager-cod-apply');
      expect(find.textContaining('Nhập UUID'), findsOneWidget);
      expect(backend.queries, hasLength(1));
      await tester.enterText(
        find.byKey(const ValueKey('manager-cod-order-filter')),
        _order,
      );
      await tester.enterText(
        find.byKey(const ValueKey('manager-cod-shipper-filter')),
        _shipper,
      );
      await _tap(tester, 'manager-cod-apply');
      expect(backend.queries.last.orderId, _order);
      expect(backend.queries.last.shipperId, _shipper);
      await _open(tester);
      final amount = find.byKey(
        const ValueKey('manager-cod-confirm-amount'),
        skipOffstage: false,
      );
      expect(amount, findsOneWidget);
      expect(tester.widget<Text>(amount).data, '550.000 đ');
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('manager-cod-confirm')),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        findsNothing,
      );
      await _tap(tester, 'manager-cod-cancel');
      expect(backend.commands, isEmpty);
    },
  );

  testWidgets(
    'confirmation blocks duplicate taps and reads updated totals and groups',
    (tester) async {
      final backend = _BackendFixture();
      final gate = Completer<void>();
      backend.onWrite = () => gate.future;
      await tester.pumpWidget(_app(backend, routed: true));
      await tester.tap(find.byKey(const ValueKey('open-cod-route')));
      await tester.pumpAndSettle();
      await _open(tester);
      await _agree(tester);
      await tester.tap(find.byKey(const ValueKey('manager-cod-confirm')));
      await tester.tap(
        find.byKey(const ValueKey('manager-cod-confirm')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(backend.commands, hasLength(1));
      expect(find.byKey(const ValueKey('cod-detail-route')), findsOneWidget);
      final open = find.byKey(const ValueKey('manager-cod-open-$_order'));
      expect(tester.widget<FilledButton>(open).onPressed, isNull);
      gate.complete();
      await tester.pumpAndSettle();
      expect(backend.commands.single.requestId, _request);
      expect(backend.commands.single.receivedAmountVnd, 550000);
      await tester.ensureVisible(
        find.byKey(const ValueKey('manager-cod-held-total')),
      );
      expect(find.text('0 đ'), findsOneWidget);
      expect(find.byKey(const ValueKey('manager-cod-empty')), findsOneWidget);
      await _tap(tester, 'manager-cod-reconciled');
      expect(backend.queries.last.statuses, [CodStatus.received]);
      await tester.ensureVisible(
        find.byKey(ValueKey('manager-cod-record-$_order')),
      );
      expect(find.text('Cửa hàng đã nhận tiền'), findsOneWidget);
      expect(open, findsNothing);
    },
  );

  testWidgets(
    'timeout freezes request ID; ACK read failure retries read only',
    (tester) async {
      final backend = _BackendFixture()..failExactRead = true;
      var writes = 0, ids = 0;
      backend.onWrite = () async {
        if (writes++ == 0) throw TimeoutException('fixture lost response');
      };
      await tester.pumpWidget(_app(backend, generate: () => ++ids));
      await tester.pumpAndSettle();
      await _open(tester);
      await _agree(tester);
      await _tap(tester, 'manager-cod-confirm');
      expect(find.textContaining('Chưa xác định kết quả'), findsOneWidget);
      await _tap(tester, 'manager-cod-action-retry');
      expect(backend.commands, hasLength(2));
      expect(backend.commands.first, same(backend.commands.last));
      expect(ids, 1);
      expect(find.text('Đọc lại kết quả'), findsOneWidget);
      await _tap(tester, 'manager-cod-action-retry');
      expect(backend.commands, hasLength(2));
      await tester.ensureVisible(
        find.byKey(const ValueKey('manager-cod-held-total')),
      );
      expect(find.text('0 đ'), findsOneWidget);
    },
  );

  testWidgets('denied receipt surfaces error without successful state', (
    tester,
  ) async {
    final backend = _BackendFixture()
      ..onWrite = () async => throw const OperationalFailure(
        OperationalFailureCode.permissionDenied,
      );
    await tester.pumpWidget(_app(backend));
    await tester.pumpAndSettle();
    await _open(tester);
    await _agree(tester);
    await _tap(tester, 'manager-cod-confirm');
    expect(backend.received, false);
    expect(find.textContaining('không có quyền'), findsWidgets);
    expect(find.byKey(ValueKey('manager-cod-open-$_order')), findsNothing);
  });

  testWidgets('role switch redacts and closes a manager confirmation dialog', (
    tester,
  ) async {
    final backend = _BackendFixture();
    await tester.pumpWidget(_app(backend));
    await tester.pumpAndSettle();
    await _open(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CodRoutePage)),
    );
    container.read(_role.notifier).change('shipper');
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ManagerCodPanel), findsNothing);
    expect(find.byKey(const ValueKey('manager-cod-confirm')), findsNothing);
    expect(backend.commands, isEmpty);
  });

  testWidgets('narrow large text layout has no overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(_BackendFixture(), scaler: const TextScaler.linear(1.8)),
    );
    await tester.pumpAndSettle();
    await _open(tester);
    expect(tester.takeException(), isNull);
  });
}
