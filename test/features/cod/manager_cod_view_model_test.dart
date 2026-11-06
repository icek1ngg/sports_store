import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/cod/domain/models/cod_collection.dart';
import 'package:sports_store/features/cod/domain/models/cod_collection_page.dart';
import 'package:sports_store/features/cod/domain/models/cod_collection_query.dart';
import 'package:sports_store/features/cod/domain/models/cod_receipt.dart';
import 'package:sports_store/features/cod/domain/repositories/cod_receipt_repository.dart';
import 'package:sports_store/features/cod/domain/repositories/cod_repository.dart';
import 'package:sports_store/features/cod/presentation/view_models/cod_providers.dart';
import 'package:sports_store/features/cod/presentation/view_models/manager_cod_view_model.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';

const _manager = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _shipperA = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _shipperB = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _orderA = '11111111-1111-4111-8111-111111111111';
const _orderB = '22222222-2222-4222-8222-222222222222';
const _requestA = '99999999-9999-4999-8999-999999999999';

class _ReadRepository implements CodRepository {
  final requests = <CodCollectionQuery>[];
  final responses =
      <FutureOr<CodCollectionPage> Function(CodCollectionQuery)>[];

  @override
  Future<CodCollectionPage> queryCollections(CodCollectionQuery query) async {
    requests.add(query);
    if (responses.isEmpty) throw StateError('missing COD read fixture');
    return responses.removeAt(0)(query);
  }

  @override
  Future<List<CodCollection>> listCollections({
    String? shipperId,
    String? orderId,
  }) => throw UnimplementedError();
}

class _ReceiptRepository implements CodReceiptRepository {
  final calls = <CodReceiptCommand>[];
  Future<CodReceipt> Function(CodReceiptCommand command)? handler;

  @override
  Future<CodReceipt> confirmReceipt(CodReceiptCommand command) {
    calls.add(command);
    final current = handler;
    if (current == null) throw StateError('missing COD receipt fixture');
    return current(command);
  }
}

OperationalSession _session(String userId, int generation) =>
    OperationalSession(userId: userId, generation: generation);

final _createdAt = DateTime.utc(2026, 10, 25, 8);

CodCollection _row({
  String orderId = _orderA,
  String shipperId = _shipperA,
  CodStatus status = CodStatus.collected,
  int receivedAmountVnd = 0,
  String? receivedBy,
  DateTime? receivedAt,
}) {
  final received = status == CodStatus.received;
  return CodCollection(
    orderId: orderId,
    orderCode: orderId,
    orderCodeSource: 'order_uuid',
    shipperId: shipperId,
    status: status,
    expectedAmountVnd: 550000,
    collectedAmountVnd: 550000,
    receivedAmountVnd: receivedAmountVnd,
    collectedBy: shipperId,
    receivedBy: received ? (receivedBy ?? _manager) : null,
    collectedAt: _createdAt,
    handedOverAt: received ? (receivedAt ?? _createdAt) : null,
    receivedAt: received ? (receivedAt ?? _createdAt) : null,
    createdAt: _createdAt,
    updatedAt: received ? (receivedAt ?? _createdAt) : _createdAt,
  );
}

CodCollectionPage _page(
  List<CodCollection> items, {
  int? all,
  int? uncollected,
  int? collected,
  int? received,
  int? filteredTotal,
  int outstandingVnd = 550000,
  String? nextCursor,
}) {
  final collectedCount =
      collected ??
      items.where((item) => item.status == CodStatus.collected).length;
  final receivedCount =
      received ??
      items.where((item) => item.status == CodStatus.received).length;
  final allCount = all ?? items.length;
  final uncollectedCount =
      uncollected ?? allCount - collectedCount - receivedCount;
  return CodCollectionPage(
    items: items,
    nextCursor: nextCursor,
    filteredTotal: filteredTotal ?? items.length,
    counts: CodCollectionCounts(
      all: allCount,
      uncollected: uncollectedCount,
      collected: collectedCount,
      received: receivedCount,
    ),
    outstandingVnd: outstandingVnd,
    asOf: _createdAt,
  );
}

CodReceipt _receipt({String orderId = _orderA, int amount = 550000}) =>
    CodReceipt(
      orderId: orderId,
      status: CodReceiptStatus.received,
      receivedAmountVnd: amount,
      receivedBy: _manager,
      receivedAt: _createdAt,
      handedOverAt: _createdAt,
      eventId: 'event-$orderId',
      notificationId: 'notification-$orderId',
    );

ProviderContainer _container({
  required _ReadRepository reads,
  required _ReceiptRepository receipts,
  Stream<OperationalSession>? sessions,
  String role = 'manager',
}) {
  final sessionOverride = sessions == null
      ? operationalSessionProvider.overrideWithValue(
          AsyncData(_session(_manager, 1)),
        )
      : operationalSessionProvider.overrideWith((ref) => sessions);
  return ProviderContainer(
    overrides: [
      codRepositoryProvider.overrideWithValue(reads),
      codReceiptRepositoryProvider.overrideWithValue(receipts),
      codReceiptRequestIdProvider.overrideWithValue(() => _requestA),
      codScreenRoleProvider.overrideWithValue(AsyncData(role)),
      sessionOverride,
    ],
  );
}

Future<void> _settle(ProviderContainer container, dynamic provider) async {
  for (var index = 0; index < 100; index++) {
    await Future<void>.delayed(Duration.zero);
    final state = container.read(provider);
    if (!state.isLoading && !state.isSubmitting) return;
  }
  fail('manager COD ViewModel did not settle');
}

void main() {
  test(
    'denied final list refresh after verified ACK releases the command',
    () async {
      final reads = _ReadRepository()
        ..responses.add((_) => _page([_row()]))
        ..responses.add(
          (_) => _page([
            _row(status: CodStatus.received, receivedAmountVnd: 550000),
          ]),
        )
        ..responses.add(
          (_) => throw const OperationalFailure(
            OperationalFailureCode.permissionDenied,
          ),
        );
      final receipts = _ReceiptRepository()..handler = (_) async => _receipt();
      final container = _container(reads: reads, receipts: receipts);
      final provider = managerCodViewModelProvider(null);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(() {
        subscription.close();
        container.dispose();
      });
      await _settle(container, provider);
      final vm = container.read(provider.notifier);
      await vm.confirmFullReceipt(
        collection: container.read(provider).items.single,
        receivedFullAmount: true,
        displayedAmountVnd: 550000,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      expect(container.read(provider).items, isEmpty);
      expect(container.read(provider).pendingCommand, isNull);
      expect(container.read(provider).requiresReadRetry, isFalse);
      expect(container.read(provider).lastReceipt, isNull);
      expect(
        container.read(provider).error?.code,
        OperationalFailureCode.permissionDenied,
      );
      await vm.retryReceipt();
      expect(receipts.calls, hasLength(1));
    },
  );

  test(
    'denied authoritative read after ACK redacts and never writes twice',
    () async {
      final reads = _ReadRepository()
        ..responses.add((_) => _page([_row()]))
        ..responses.add(
          (_) => throw const OperationalFailure(
            OperationalFailureCode.permissionDenied,
          ),
        );
      final receipts = _ReceiptRepository()..handler = (_) async => _receipt();
      final container = _container(reads: reads, receipts: receipts);
      final provider = managerCodViewModelProvider(null);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(() {
        subscription.close();
        container.dispose();
      });
      await _settle(container, provider);
      final vm = container.read(provider.notifier);
      await vm.confirmFullReceipt(
        collection: container.read(provider).items.single,
        receivedFullAmount: true,
        displayedAmountVnd: 550000,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      expect(container.read(provider).items, isEmpty);
      expect(container.read(provider).pendingCommand, isNull);
      expect(
        container.read(provider).error?.code,
        OperationalFailureCode.permissionDenied,
      );
      await vm.retryReceipt();
      expect(receipts.calls, hasLength(1));
    },
  );

  test(
    'hidden ACK then account switch releases deferred read and keep-alive',
    () async {
      final sessions = StreamController<OperationalSession>();
      final reads = _ReadRepository()..responses.add((_) => _page([_row()]));
      final ack = Completer<CodReceipt>();
      final receipts = _ReceiptRepository()..handler = (_) => ack.future;
      final container = _container(
        reads: reads,
        receipts: receipts,
        sessions: sessions.stream,
      );
      final provider = managerCodViewModelProvider(null);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await sessions.close();
      });
      sessions.add(_session(_manager, 1));
      await _settle(container, provider);
      final vm = container.read(provider.notifier);
      final submission = vm.confirmFullReceipt(
        collection: container.read(provider).items.single,
        receivedFullAmount: true,
        displayedAmountVnd: 550000,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      subscription.close();
      ack.complete(_receipt());
      await submission;
      expect(container.exists(provider), isTrue);
      sessions.add(_session('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 2));
      for (var index = 0; index < 5; index++) {
        await Future<void>.delayed(Duration.zero);
        await container.pump();
      }
      expect(container.exists(provider), isFalse);
      expect(reads.requests, hasLength(1));
      expect(receipts.calls, hasLength(1));
    },
  );

  test('loads manager scope with server counts and held total', () async {
    final reads = _ReadRepository()
      ..responses.add((query) {
        expect(query.statuses, [CodStatus.collected]);
        expect(query.shipperId, isNull);
        return _page(
          [_row()],
          all: 3,
          uncollected: 1,
          collected: 1,
          received: 1,
          outstandingVnd: 550000,
        );
      });
    final container = _container(reads: reads, receipts: _ReceiptRepository());
    final provider = managerCodViewModelProvider(null);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });

    await _settle(container, provider);
    final state = container.read(provider);
    expect(state.group, ManagerCodGroup.unreconciled);
    expect(state.items.single.status, CodStatus.collected);
    expect(state.counts?.all, 3);
    expect(state.filteredTotal, 1);
    expect(state.heldTotalVnd, 550000);
    expect(state.error, isNull);
  });

  test(
    'sends shipper/order filters to the server and never filters rows locally',
    () async {
      final reads = _ReadRepository()
        ..responses.add((_) => _page([_row()]))
        ..responses.add((query) {
          expect(query.shipperId, _shipperB);
          expect(query.orderId, _orderB);
          expect(query.statuses, [CodStatus.collected]);
          return _page([_row(orderId: _orderB, shipperId: _shipperB)]);
        });
      final container = _container(
        reads: reads,
        receipts: _ReceiptRepository(),
      );
      final provider = managerCodViewModelProvider(null);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() {
        subscription.close();
        container.dispose();
      });
      await _settle(container, provider);

      await container
          .read(provider.notifier)
          .setFilters(shipperId: _shipperB, orderId: _orderB);
      await _settle(container, provider);
      final state = container.read(provider);
      expect(state.shipperId, _shipperB);
      expect(state.orderId, _orderB);
      expect(state.items.single.orderId, _orderB);
    },
  );

  test('role denial clears rows and prevents receipt writes', () async {
    final reads = _ReadRepository();
    final receipts = _ReceiptRepository();
    final container = _container(
      reads: reads,
      receipts: receipts,
      role: 'shipper',
    );
    final provider = managerCodViewModelProvider(null);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });
    await _settle(container, provider);
    final state = container.read(provider);
    expect(state.items, isEmpty);
    expect(state.error?.code, OperationalFailureCode.permissionDenied);
    expect(container.read(provider.notifier).actionBlocked, isTrue);
    expect(receipts.calls, isEmpty);
  });

  test(
    'confirmation requires the full displayed amount and current snapshot',
    () async {
      final reads = _ReadRepository()..responses.add((_) => _page([_row()]));
      final receipts = _ReceiptRepository();
      final container = _container(reads: reads, receipts: receipts);
      final provider = managerCodViewModelProvider(null);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() {
        subscription.close();
        container.dispose();
      });
      await _settle(container, provider);
      final row = container.read(provider).items.single;
      final vm = container.read(provider.notifier);

      await vm.confirmFullReceipt(
        collection: row,
        receivedFullAmount: false,
        displayedAmountVnd: row.expectedAmountVnd,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      expect(receipts.calls, isEmpty);
      expect(
        container.read(provider).actionError,
        isA<CodReceiptFailure>().having(
          (failure) => failure.receiptCode,
          'receiptCode',
          CodReceiptFailureCode.amountMismatch,
        ),
      );
    },
  );

  test('repeated taps while submitting issue one receipt command', () async {
    final reads = _ReadRepository()
      ..responses.add((_) => _page([_row()]))
      ..responses.add(
        (_) => _page([
          _row(status: CodStatus.received, receivedAmountVnd: 550000),
        ]),
      )
      ..responses.add(
        (_) => _page([], all: 0, collected: 0, received: 0, outstandingVnd: 0),
      );
    final receipts = _ReceiptRepository();
    final completer = Completer<CodReceipt>();
    receipts.handler = (_) => completer.future;
    final container = _container(reads: reads, receipts: receipts);
    final provider = managerCodViewModelProvider(null);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });
    await _settle(container, provider);
    final vm = container.read(provider.notifier);
    final row = container.read(provider).items.single;
    final first = vm.confirmFullReceipt(
      collection: row,
      receivedFullAmount: true,
      displayedAmountVnd: 550000,
      sessionRevision: vm.sessionRevisionForConfirmation,
    );
    await Future<void>.delayed(Duration.zero);
    final second = vm.confirmFullReceipt(
      collection: row,
      receivedFullAmount: true,
      displayedAmountVnd: 550000,
      sessionRevision: vm.sessionRevisionForConfirmation,
    );
    expect(receipts.calls, hasLength(1));
    completer.complete(_receipt());
    await Future.wait([first, second]);
    expect(receipts.calls, hasLength(1));
    expect(container.read(provider).heldTotalVnd, 0);
    expect(container.read(provider).lastReceipt?.receivedAmountVnd, 550000);
  });

  test('timeout retry reuses the same request ID', () async {
    final reads = _ReadRepository()
      ..responses.add((_) => _page([_row()]))
      ..responses.add(
        (_) => _page([
          _row(status: CodStatus.received, receivedAmountVnd: 550000),
        ]),
      )
      ..responses.add(
        (_) => _page([], all: 0, collected: 0, received: 0, outstandingVnd: 0),
      );
    final receipts = _ReceiptRepository();
    var attempts = 0;
    receipts.handler = (command) async {
      attempts++;
      expect(command.requestId, _requestA);
      if (attempts == 1) {
        throw const OperationalFailure(OperationalFailureCode.network);
      }
      return _receipt();
    };
    final container = _container(reads: reads, receipts: receipts);
    final provider = managerCodViewModelProvider(null);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });
    await _settle(container, provider);
    final vm = container.read(provider.notifier);
    final row = container.read(provider).items.single;
    await vm.confirmFullReceipt(
      collection: row,
      receivedFullAmount: true,
      displayedAmountVnd: 550000,
      sessionRevision: vm.sessionRevisionForConfirmation,
    );
    expect(
      container.read(provider).actionError?.code,
      OperationalFailureCode.network,
    );
    expect(container.read(provider).pendingCommand?.requestId, _requestA);
    await vm.retryReceipt();
    expect(receipts.calls, hasLength(2));
    expect(receipts.calls[0].requestId, receipts.calls[1].requestId);
    expect(container.read(provider).lastReceipt, isNotNull);
  });

  test(
    'ACK followed by read failure retries read only and does not write twice',
    () async {
      final reads = _ReadRepository()
        ..responses.add((_) => _page([_row()]))
        ..responses.add(
          (_) => throw const OperationalFailure(OperationalFailureCode.network),
        )
        ..responses.add(
          (_) => _page([
            _row(status: CodStatus.received, receivedAmountVnd: 550000),
          ]),
        )
        ..responses.add(
          (_) =>
              _page([], all: 0, collected: 0, received: 0, outstandingVnd: 0),
        );
      final receipts = _ReceiptRepository()..handler = (_) async => _receipt();
      final container = _container(reads: reads, receipts: receipts);
      final provider = managerCodViewModelProvider(null);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() {
        subscription.close();
        container.dispose();
      });
      await _settle(container, provider);
      final vm = container.read(provider.notifier);
      final row = container.read(provider).items.single;
      await vm.confirmFullReceipt(
        collection: row,
        receivedFullAmount: true,
        displayedAmountVnd: 550000,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      expect(receipts.calls, hasLength(1));
      expect(container.read(provider).requiresReadRetry, isTrue);
      await vm.retryReceipt();
      expect(receipts.calls, hasLength(1));
      expect(container.read(provider).lastReceipt, isNotNull);
    },
  );

  test(
    'account switch clears prior rows before loading the new account',
    () async {
      final sessions = StreamController<OperationalSession>();
      final reads = _ReadRepository()
        ..responses.add((_) => _page([_row()]))
        ..responses.add((query) {
          expect(query.shipperId, _shipperA);
          expect(query.orderId, _orderA);
          return _page([_row()]);
        })
        ..responses.add((query) {
          expect(query.orderId, isNull);
          expect(query.shipperId, isNull);
          return _page([_row(orderId: _orderB, shipperId: _shipperB)]);
        });
      final container = _container(
        reads: reads,
        receipts: _ReceiptRepository(),
        sessions: sessions.stream,
      );
      final provider = managerCodViewModelProvider(null);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await sessions.close();
      });
      sessions.add(_session(_manager, 1));
      await _settle(container, provider);
      expect(container.read(provider).items.single.orderId, _orderA);

      await container
          .read(provider.notifier)
          .setFilters(shipperId: _shipperA, orderId: _orderA);
      await _settle(container, provider);
      expect(container.read(provider).shipperId, _shipperA);

      sessions.add(_session('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 2));
      await _settle(container, provider);
      expect(container.read(provider).shipperId, isNull);
      expect(container.read(provider).orderId, isNull);
      expect(container.read(provider).items, isNotEmpty);
      expect(container.read(provider).items.single.orderId, _orderB);
    },
  );

  test(
    'ordinary family disposal stops reads when the screen is closed',
    () async {
      final reads = _ReadRepository()..responses.add((_) => _page([_row()]));
      final container = _container(
        reads: reads,
        receipts: _ReceiptRepository(),
      );
      final provider = managerCodViewModelProvider(null);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      await _settle(container, provider);
      expect(reads.requests, hasLength(1));

      subscription.close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(container.exists(provider), isFalse);
      expect(reads.requests, hasLength(1));
      container.dispose();
    },
  );

  test(
    'pending timeout survives navigation and resumes with the same request ID',
    () async {
      final reads = _ReadRepository()
        ..responses.add((_) => _page([_row()]))
        ..responses.add(
          (_) => _page([
            _row(status: CodStatus.received, receivedAmountVnd: 550000),
          ]),
        )
        ..responses.add(
          (_) => _page(
            [],
            all: 1,
            uncollected: 0,
            collected: 0,
            received: 1,
            outstandingVnd: 0,
          ),
        );
      final receipts = _ReceiptRepository();
      var receiptCalls = 0;
      receipts.handler = (_) async {
        receiptCalls++;
        if (receiptCalls == 1) {
          throw const OperationalFailure(OperationalFailureCode.network);
        }
        return _receipt();
      };
      final container = _container(reads: reads, receipts: receipts);
      final provider = managerCodViewModelProvider(null);
      final firstSubscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      await _settle(container, provider);
      final vm = container.read(provider.notifier);
      final row = container.read(provider).items.single;
      await vm.confirmFullReceipt(
        collection: row,
        receivedFullAmount: true,
        displayedAmountVnd: 550000,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      final pendingId = container.read(provider).pendingCommand?.requestId;
      expect(pendingId, _requestA);
      firstSubscription.close();
      await Future<void>.delayed(Duration.zero);
      expect(container.exists(provider), isTrue);
      expect(container.read(provider).pendingCommand?.requestId, pendingId);

      final resumedSubscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      await container.read(provider.notifier).retryReceipt();
      expect(receiptCalls, 2);
      expect(receipts.calls[0].requestId, receipts.calls[1].requestId);
      expect(container.read(provider).lastReceipt, isNotNull);
      resumedSubscription.close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(container.exists(provider), isFalse);
      container.dispose();
    },
  );

  test(
    'account change releases a retained pending command without a hidden read',
    () async {
      final sessions = StreamController<OperationalSession>();
      final reads = _ReadRepository()..responses.add((_) => _page([_row()]));
      final receipts = _ReceiptRepository()
        ..handler = (_) async {
          throw const OperationalFailure(OperationalFailureCode.network);
        };
      final container = _container(
        reads: reads,
        receipts: receipts,
        sessions: sessions.stream,
      );
      final provider = managerCodViewModelProvider(null);
      var subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await sessions.close();
      });
      sessions.add(_session(_manager, 1));
      await _settle(container, provider);
      final vm = container.read(provider.notifier);
      final row = container.read(provider).items.single;
      await vm.confirmFullReceipt(
        collection: row,
        receivedFullAmount: true,
        displayedAmountVnd: 550000,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      subscription.close();
      await Future<void>.delayed(Duration.zero);
      expect(container.exists(provider), isTrue);
      final requestCount = reads.requests.length;

      // Re-enter the route before the account event. The hidden provider must
      // not observe a new account by issuing a read; once visible, the session
      // epoch may clear the retained command and start its normal fresh read.
      subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      sessions.add(_session('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 2));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(provider).pendingCommand, isNull);
      expect(reads.requests.length, greaterThanOrEqualTo(requestCount));
      subscription.close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(container.exists(provider), isFalse);
    },
  );

  test(
    'malformed receipt acknowledgement retains the frozen request ID',
    () async {
      final reads = _ReadRepository()
        ..responses.add((_) => _page([_row()]))
        ..responses.add(
          (_) => _page([
            _row(status: CodStatus.received, receivedAmountVnd: 550000),
          ]),
        )
        ..responses.add(
          (_) => _page(
            [],
            all: 1,
            uncollected: 0,
            collected: 0,
            received: 1,
            outstandingVnd: 0,
          ),
        );
      final receipts = _ReceiptRepository();
      var calls = 0;
      receipts.handler = (_) async {
        calls++;
        if (calls == 1) throw const CodReceiptAcknowledgementFailure();
        return _receipt();
      };
      final container = _container(reads: reads, receipts: receipts);
      final provider = managerCodViewModelProvider(null);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() {
        subscription.close();
        container.dispose();
      });
      await _settle(container, provider);
      final vm = container.read(provider.notifier);
      final row = container.read(provider).items.single;
      await vm.confirmFullReceipt(
        collection: row,
        receivedFullAmount: true,
        displayedAmountVnd: 550000,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      final state = container.read(provider);
      expect(state.actionError, isA<CodReceiptAcknowledgementFailure>());
      expect(state.pendingCommand?.requestId, _requestA);
      await vm.retryReceipt();
      expect(calls, 2);
      expect(receipts.calls[0].requestId, receipts.calls[1].requestId);
      expect(container.read(provider).lastReceipt, isNotNull);
    },
  );
}
