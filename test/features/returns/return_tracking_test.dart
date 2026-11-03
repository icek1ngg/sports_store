import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sports_store/app/router/operational_route_guard.dart';
import 'package:sports_store/features/returns/data/models/return_tracking_dto.dart';
import 'package:sports_store/features/returns/data/repositories/supabase_return_request_repository.dart';
import 'package:sports_store/features/returns/domain/models/return_reason.dart';
import 'package:sports_store/features/returns/domain/models/return_request_failure.dart';
import 'package:sports_store/features/returns/domain/models/return_request_submission.dart';
import 'package:sports_store/features/returns/domain/models/return_tracking.dart';
import 'package:sports_store/features/returns/domain/repositories/return_tracking_repository.dart';
import 'package:sports_store/features/returns/presentation/pages/return_tracking_page.dart';
import 'package:sports_store/features/returns/presentation/view_models/return_tracking_view_model.dart';
import 'package:sports_store/features/returns/presentation/view_models/return_tracking_timeline.dart';

const _returnId = '77777777-7777-4777-8777-777777777777';
const _orderId = '11111111-1111-4111-8111-111111111111';

ReturnTracking _tracking(
  ReturnRequestStatus status, {
  ReturnPickupAssignment? pickup,
  ReturnRefundRecord? refund,
}) {
  final submitted = DateTime.utc(2026, 10, 3, 3, 15);
  return ReturnTracking(
    returnId: _returnId,
    returnCode: _returnId,
    orderId: _orderId,
    orderCode: _orderId,
    status: status,
    reason: ReturnReason.defective,
    submittedAt: submitted,
    refreshedAt: DateTime.utc(2026, 10, 3, 5),
    events: [
      ReturnTrackingEvent(
        kind: ReturnTrackingEventKind.submitted,
        occurredAt: submitted,
      ),
      if (status != ReturnRequestStatus.pendingReview)
        ReturnTrackingEvent(
          kind: ReturnTrackingEventKind.pickupApproved,
          occurredAt: DateTime.utc(2026, 10, 3, 4, 30),
        ),
    ],
    items: const [],
    merchandiseVnd: 520000,
    deliveryFeeVnd: 30000,
    pickupAddress: '25 Nguyễn Chí Thanh, Hà Nội',
    pickup: pickup,
    refund: refund,
  );
}

/// Stands in for the server: tests change [status]/[failure] between reads.
class _ServerFake implements ReturnTrackingRepository {
  ReturnRequestStatus status = ReturnRequestStatus.pendingReview;
  ReturnPickupAssignment? pickup;
  ReturnRequestFailure? failure;
  int loads = 0;

  @override
  Future<ReturnTracking> load(String returnId) async {
    loads++;
    if (failure != null) throw failure!;
    return _tracking(status, pickup: pickup);
  }

  @override
  Future<void> submitAdditionalInfo({
    required String returnId,
    required String requestId,
    required String description,
    ReturnVideoFile? video,
  }) async {}
}

Future<void> _pump(WidgetTester tester, _ServerFake server) async {
  tester.view.physicalSize = const Size(390, 884);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        returnTrackingRepositoryProvider.overrideWith((ref) => server),
      ],
      child: MaterialApp(
        home: ReturnTrackingPage(returnId: _returnId, onBack: () {}),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Finder _status(String label) => find.descendant(
  of: find.byKey(const ValueKey('mh14-status')),
  matching: find.text(label),
);

/// One ForegroundRefresh tick (3 s) plus the async read.
Future<void> _tick(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('status transitions', () {
    testWidgets('approval appears while the screen stays open', (tester) async {
      final server = _ServerFake();
      await _pump(tester, server);
      expect(_status('Chờ duyệt'), findsOneWidget);
      expect(find.byKey(const ValueKey('mh14-step-review')), findsOneWidget);
      expect(find.text('2. Chờ cửa hàng duyệt'), findsOneWidget);

      // Manager approves pickup on the server; no navigation happens.
      server.status = ReturnRequestStatus.awaitingReturnPickup;
      await _tick(tester);

      expect(_status('Chờ lấy hàng'), findsOneWidget);
      expect(find.text('2. Đã duyệt lấy hàng'), findsOneWidget);
      expect(find.text('Chưa phân công người lấy hàng'), findsOneWidget);

      // Assignment shows only the assigned person, with a call action.
      server.pickup = const ReturnPickupAssignment(
        shipperName: 'Shipper Thử Nghiệm',
        shipperPhone: '0900000014',
      );
      await _tick(tester);
      expect(find.text('Shipper Thử Nghiệm'), findsOneWidget);
      expect(find.text('Chưa có lịch hẹn'), findsOneWidget);
      expect(find.byKey(const ValueKey('mh14-call')), findsOneWidget);
    });

    testWidgets('reload button fetches the latest state', (tester) async {
      final server = _ServerFake();
      await _pump(tester, server);
      server.status = ReturnRequestStatus.awaitingReturnPickup;
      await tester.tap(find.byKey(const ValueKey('mh14-refresh')));
      await tester.pump();
      await tester.pump();
      expect(_status('Chờ lấy hàng'), findsOneWidget);
    });

    testWidgets('closed requests stop polling', (tester) async {
      final server = _ServerFake()..status = ReturnRequestStatus.refunded;
      await _pump(tester, server);
      final loads = server.loads;
      await _tick(tester);
      await _tick(tester);
      expect(server.loads, loads);
    });
  });

  group('connection loss', () {
    testWidgets('keeps the last confirmed data, labeled, and recovers', (
      tester,
    ) async {
      final server = _ServerFake()
        ..status = ReturnRequestStatus.awaitingReturnPickup;
      await _pump(tester, server);
      expect(_status('Chờ lấy hàng'), findsOneWidget);

      server.failure = const ReturnRequestFailure(
        ReturnRequestFailureCode.network,
      );
      await _tick(tester);
      expect(find.byKey(const ValueKey('mh14-stale')), findsOneWidget);
      expect(find.textContaining('Không thể kết nối.'), findsOneWidget);
      expect(_status('Chờ lấy hàng'), findsOneWidget);

      server
        ..failure = null
        ..status = ReturnRequestStatus.returningToStore;
      await tester.tap(find.text('Thử lại'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('mh14-stale')), findsNothing);
      expect(_status('Đang chuyển về'), findsOneWidget);
    });

    testWidgets('first load failure offers retry without fake data', (
      tester,
    ) async {
      final server = _ServerFake()
        ..failure = const ReturnRequestFailure(
          ReturnRequestFailureCode.network,
        );
      await _pump(tester, server);
      expect(find.byKey(const ValueKey('mh14-load-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('mh14-status')), findsNothing);

      server.failure = null;
      await tester.tap(find.text('Thử lại'));
      await tester.pump();
      await tester.pump();
      expect(_status('Chờ duyệt'), findsOneWidget);
    });
  });

  group("another customer's request", () {
    testWidgets('is reported as not found and shows nothing', (tester) async {
      final server = _ServerFake()
        ..failure = const ReturnRequestFailure(
          ReturnRequestFailureCode.returnNotFound,
        );
      await _pump(tester, server);
      expect(
        find.text('Không tìm thấy yêu cầu trả hàng của bạn.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('mh14-status')), findsNothing);
    });

    testWidgets('losing access clears data instead of showing it stale', (
      tester,
    ) async {
      final server = _ServerFake();
      await _pump(tester, server);
      expect(_status('Chờ duyệt'), findsOneWidget);

      server.failure = const ReturnRequestFailure(
        ReturnRequestFailureCode.returnNotFound,
      );
      await _tick(tester);
      expect(find.byKey(const ValueKey('mh14-status')), findsNothing);
      expect(find.byKey(const ValueKey('mh14-stale')), findsNothing);
      expect(
        find.text('Không tìm thấy yêu cầu trả hàng của bạn.'),
        findsOneWidget,
      );

      // No further polling after access was revoked.
      final loads = server.loads;
      await _tick(tester);
      expect(server.loads, loads);
    });

    test('server marker maps to returnNotFound only with exact code', () {
      expect(
        mapReturnRequestError(
          const PostgrestException(message: 'RETURN_NOT_FOUND', code: 'PT404'),
        ).code,
        ReturnRequestFailureCode.returnNotFound,
      );
      expect(
        mapReturnRequestError(
          const PostgrestException(message: 'RETURN_NOT_FOUND', code: 'XX000'),
        ).code,
        ReturnRequestFailureCode.unexpected,
      );
    });

    test('route guard accepts only /customer/returns/<uuid>', () {
      final ok = OperationalRouteLocation.parse(
        Uri.parse('/customer/returns/$_returnId'),
      );
      expect(ok.protected && ok.customerOnly && !ok.invalidId, isTrue);
      for (final path in [
        '/customer/returns/abc',
        '/customer/returns',
        '/customer/returns/$_returnId/x',
      ]) {
        expect(
          OperationalRouteLocation.parse(Uri.parse(path)).invalidId,
          isTrue,
          reason: path,
        );
      }
    });
  });

  group('server mapping', () {
    Map<String, Object?> json(String status, {Map<String, Object?>? extra}) => {
      'return_id': _returnId,
      'order_id': _orderId,
      'status': status,
      'reason': 'defective',
      'submitted_at': '2026-10-03T03:15:00+00:00',
      'decision_reason': null,
      'decision_at': null,
      'received_at_store': null,
      'inspected_at': null,
      'closed_at': null,
      'merchandise_vnd': 520000,
      'delivery_fee_vnd': 30000,
      'pickup_address': '25 Nguyễn Chí Thanh, Hà Nội',
      'items': <Object?>[],
      'pickup': null,
      'redelivery': null,
      'refund': null,
      'refund_bank_name': 'Vietcombank',
      'refund_account_masked': '••••6789',
      'server_now': '2026-10-03T05:00:00+00:00',
      ...?extra,
    };

    test('pending maps with full UUID codes and no invented data', () {
      final t = returnTrackingFromJson(json('pending_review'));
      expect(t.status, ReturnRequestStatus.pendingReview);
      expect(t.returnCode, _returnId);
      expect(t.orderCode, _orderId);
      expect(t.pickup, isNull);
      expect(t.refund, isNull);
      expect(t.infoRequest, isNull);
      expect(t.events.map((e) => e.kind), [ReturnTrackingEventKind.submitted]);
    });

    test('approved + assigned derives events from server timestamps', () {
      final t = returnTrackingFromJson(
        json(
          'awaiting_return_pickup',
          extra: {
            'decision_at': '2026-10-03T04:30:00+00:00',
            'pickup': {
              'status': 'assigned',
              'assigned_at': '2026-10-03T04:45:00+00:00',
              'collected_at': null,
              'completed_at': null,
              'person': {'name': 'Shipper Thử Nghiệm', 'phone': '0900000014'},
            },
          },
        ),
      );
      expect(t.events.map((e) => e.kind), [
        ReturnTrackingEventKind.submitted,
        ReturnTrackingEventKind.pickupApproved,
        ReturnTrackingEventKind.pickupAssigned,
      ]);
      expect(t.pickup?.shipperName, 'Shipper Thử Nghiệm');
      expect(t.pickup?.scheduledAt, isNull);
    });

    test('refund exists only when the server returns the record', () {
      final awaiting = returnTrackingFromJson(
        json(
          'awaiting_refund',
          extra: {'inspected_at': '2026-10-06T03:05:00+00:00'},
        ),
      );
      expect(awaiting.refund, isNull);

      final done = returnTrackingFromJson(
        json(
          'refunded',
          extra: {
            'refund': {
              'amount_vnd': 550000,
              'refunded_at': '2026-10-06T09:45:00+00:00',
              'has_transfer_evidence': true,
            },
          },
        ),
      );
      expect(done.refund?.amountVnd, 550000);
      expect(done.events.last.kind, ReturnTrackingEventKind.refunded);
    });

    test('missing field is rejected, not defaulted', () {
      final broken = json('pending_review')..remove('server_now');
      expect(() => returnTrackingFromJson(broken), throwsFormatException);
    });
  });

  group('timeline per state', () {
    List<(String, ReturnStepState)> steps(ReturnTracking t) => [
      for (final s in buildReturnTimeline(t)) (s.key, s.state),
    ];

    test('pending: review is current, the rest upcoming without time', () {
      final t = _tracking(ReturnRequestStatus.pendingReview);
      final built = buildReturnTimeline(t);
      expect(steps(t), [
        ('submitted', ReturnStepState.done),
        ('review', ReturnStepState.current),
        ('pickup', ReturnStepState.upcoming),
        ('inspection', ReturnStepState.upcoming),
        ('result', ReturnStepState.upcoming),
      ]);
      expect(built.skip(1).every((s) => s.occurredAt == null), isTrue);
    });

    test('initial rejection ends the timeline', () {
      final t = _tracking(ReturnRequestStatus.initiallyRejected);
      expect(steps(t), [
        ('submitted', ReturnStepState.done),
        ('review', ReturnStepState.stopped),
      ]);
    });

    test('awaiting refund is current, never shown as refunded', () {
      final t = _tracking(ReturnRequestStatus.awaitingRefund);
      final result = buildReturnTimeline(t).last;
      expect(result.state, ReturnStepState.current);
      expect(result.title, 'Chờ cửa hàng chuyển khoản');
      expect(result.detail, ReturnStepDetail.refundPending);
    });

    test('refunded only with a recorded transfer', () {
      final t = _tracking(
        ReturnRequestStatus.refunded,
        refund: ReturnRefundRecord(
          amountVnd: 550000,
          refundedAt: DateTime.utc(2026, 10, 6, 9, 45),
          hasTransferEvidence: true,
        ),
      );
      final result = buildReturnTimeline(t).last;
      expect(result.state, ReturnStepState.done);
      expect(result.title, 'Đã hoàn tiền');
    });

    test('rejected after inspection shows free redelivery', () {
      final t = _tracking(ReturnRequestStatus.awaitingRedelivery);
      final built = buildReturnTimeline(t);
      expect(built[3].state, ReturnStepState.stopped);
      expect(built.last.title, 'Giao lại hàng miễn phí');
      expect(built.last.state, ReturnStepState.current);
      expect(built.last.description, contains('không thu thêm tiền COD'));
    });
  });
}
