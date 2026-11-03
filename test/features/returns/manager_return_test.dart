import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sports_store/app/router/operational_route_guard.dart';
import 'package:sports_store/features/returns/data/models/manager_return_dto.dart';
import 'package:sports_store/features/returns/data/models/return_tracking_dto.dart';
import 'package:sports_store/features/returns/data/repositories/supabase_return_request_repository.dart';
import 'package:sports_store/features/returns/domain/models/manager_return.dart';
import 'package:sports_store/features/returns/domain/models/return_request_failure.dart';
import 'package:sports_store/features/returns/domain/repositories/manager_return_repository.dart';
import 'package:sports_store/features/returns/presentation/pages/manager_return_detail_page.dart';
import 'package:sports_store/features/returns/presentation/pages/manager_returns_page.dart';
import 'package:sports_store/features/returns/presentation/view_models/manager_return_view_models.dart';

const _returnId = '15150000-0000-4000-8000-0000000000aa';
const _orderId = '15150000-0000-4000-8000-0000000000bb';
const _itemId = '15150000-0000-4000-8000-0000000000cc';
const _shipperId = '15150000-0000-4000-8000-0000000000dd';

Map<String, Object?> _detailJson({String status = 'pending_review'}) => {
  'return_id': _returnId,
  'order_id': _orderId,
  'status': status,
  'reason': 'defective',
  'description': 'Đường may ở vai áo bị bung khi mở kiện hàng.',
  'submitted_at': '2026-11-02T03:58:48.986112+00:00',
  'decision_reason': null,
  'decision_at': null,
  'closed_at': null,
  'customer': {'name': 'Nguyễn Minh Anh', 'phone': '0912345678'},
  'recipient': {
    'name': 'Nguyễn Minh Anh',
    'phone': '0912345678',
    'address': '25 Nguyễn Chí Thanh, Hà Nội',
  },
  'delivered_at': '2026-11-01T03:59:20.98369+00:00',
  'subtotal_vnd': 550000,
  'delivery_fee_vnd': 30000,
  'total_vnd': 580000,
  'order_items': [
    {
      'order_item_id': _itemId,
      'product_name': 'Áo thể thao Performance Core',
      'variant_label': 'Đen / M',
      'quantity': 2,
      'unit_price_vnd': 275000,
      'line_total_vnd': 550000,
      'image_url': null,
    },
  ],
  'return_items': <Object?>[],
  'video_paths': ['owner/order/v.mp4'],
  'bank': {
    'bank_name': 'Vietcombank',
    'account_number': '0011004392819',
    'account_holder': 'NGUYEN MINH ANH',
  },
  'pickup_task': null,
  'shippers': [
    {'shipper_id': _shipperId, 'name': 'Shipper Hùng', 'phone': '0900000001'},
  ],
  'server_now': '2026-11-02T05:00:00+00:00',
};

ManagerReturnDetail _detail({String status = 'pending_review'}) =>
    managerReturnDetailFromJson(_detailJson(status: status));

/// Stands in for the server; tests script failures per call.
class _Fake implements ManagerReturnRepository {
  _Fake({String status = 'pending_review'}) : detail = _detail(status: status);

  ManagerReturnDetail detail;
  final approveKeys = <String>[];
  final rejectReasons = <String>[];
  final failures = <ReturnRequestFailure>[];
  int loads = 0;

  /// The server starts denying reads (role revoked / other account).
  bool denyLoads = false;

  @override
  Future<ManagerReturnList> list({
    ReturnRequestStatus? status,
    String? query,
  }) async => managerReturnListFromJson({
    'items': [
      if (status == null || status == detail.status)
        {
          'return_id': _returnId,
          'order_id': _orderId,
          'status': detail.status.wireValue,
          'reason': 'defective',
          'submitted_at': '2026-11-02T03:58:48.986112+00:00',
          'customer_name': 'Nguyễn Minh Anh',
          'total_vnd': 580000,
          'line_count': 1,
          'first_item_name': 'Áo thể thao Performance Core',
        },
    ],
    'counts': {detail.status.wireValue: 1},
    'server_now': '2026-11-02T05:00:00Z',
  });

  @override
  Future<ManagerReturnDetail> load(String returnId) async {
    loads++;
    if (denyLoads) {
      throw const ReturnRequestFailure(
        ReturnRequestFailureCode.permissionDenied,
      );
    }
    return detail;
  }

  @override
  Future<Uri> videoUrl(String objectPath) async =>
      Uri.parse('https://example.invalid/v.mp4');

  @override
  Future<void> approveCollection({
    required String returnId,
    required String requestId,
    required List<ManagerCollectionLine> lines,
    required String shipperId,
  }) async {
    approveKeys.add(requestId);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (failures.isNotEmpty) throw failures.removeAt(0);
    detail = _detail(status: 'awaiting_return_pickup');
  }

  @override
  Future<void> reject({
    required String returnId,
    required String requestId,
    required String reason,
  }) async {
    rejectReasons.add(reason);
    if (failures.isNotEmpty) throw failures.removeAt(0);
    detail = _detail(status: 'initially_rejected');
  }

  final calls = <String>[];
  final uploads = <String>[];
  final commandKeys = <String>[];
  List<ManagerInspectionLine>? acceptedLines;
  int? refundedAmount;

  Future<void> _record(String name, String key) async {
    calls.add(name);
    commandKeys.add(key);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (failures.isNotEmpty) throw failures.removeAt(0);
  }

  @override
  Future<Uri> evidenceUrl(ManagerEvidenceKind kind, String objectPath) async =>
      Uri.parse('https://example.invalid/$objectPath');

  @override
  Future<String> uploadEvidence({
    required String returnId,
    required ManagerEvidenceKind kind,
    required String objectName,
    required ManagerEvidenceFile file,
  }) async {
    uploads.add('${kind.name}/$returnId/$objectName');
    return '$returnId/$objectName';
  }

  @override
  Future<void> requestInfo({
    required String returnId,
    required String requestId,
    required String message,
  }) => _record('requestInfo', requestId);

  @override
  Future<void> receive({
    required String returnId,
    required String taskId,
    required String requestId,
    required List<ManagerReturnItem> items,
  }) => _record('receive', requestId);

  @override
  Future<void> acceptInspection({
    required String returnId,
    required String requestId,
    required List<ManagerInspectionLine> lines,
    required List<String> evidencePaths,
  }) {
    acceptedLines = lines;
    return _record('accept', requestId);
  }

  @override
  Future<void> rejectInspection({
    required String returnId,
    required String requestId,
    required String reason,
    required List<String> evidencePaths,
  }) => _record('rejectInspection', requestId);

  @override
  Future<void> recordRefund({
    required String returnId,
    required String requestId,
    required int amountVnd,
    required DateTime transferredAt,
    required String evidencePath,
  }) {
    refundedAmount = amountVnd;
    return _record('refund', requestId);
  }

  @override
  Future<void> assignRedelivery({
    required String returnId,
    required String requestId,
    required String shipperId,
  }) => _record('redelivery', requestId);
}

const _evidence = ManagerEvidenceFile(
  name: 'bien-lai.JPG',
  bytes: [1, 2, 3],
  mimeType: 'image/jpeg',
);

Map<String, Object?> _phase2Json(String status) => {
  ..._detailJson(status: status),
  'inspection_started_at': '2026-11-02T06:00:00Z',
  'inspected_at': status == 'awaiting_refund' ? '2026-11-02T07:00:00Z' : null,
  'inspection_evidence_paths': <Object?>[],
  'refund': null,
  'info_requests': <Object?>[],
  'redelivery_task': null,
  'return_items': [
    {
      'return_item_id': _shipperId.replaceAll('dd', 'ee'),
      'order_item_id': _itemId,
      'name': 'Áo thể thao Performance Core — Đen / M',
      'quantity_to_collect': 2,
      'quantity_collected': 2,
      'sellable_quantity': 0,
      'damaged_quantity': 0,
    },
  ],
  'pickup_task': {
    'task_id': '15150000-0000-4000-8000-0000000000ff',
    'status': status == 'returning_to_store'
        ? 'in_transit'
        : 'returned_to_store',
    'shipper_id': _shipperId,
    'shipper_name': 'Shipper Hùng',
    'shipper_phone': null,
    'assigned_at': '2026-11-02T04:00:00Z',
    'completed_at': null,
    'failure_reason': null,
    'handover_reported': true,
  },
};

Future<ProviderContainer> _container(_Fake fake) async {
  final container = ProviderContainer(
    overrides: [managerReturnRepositoryProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);
  container.listen(managerReturnDetailProvider(_returnId), (_, _) {});
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return container;
}

void main() {
  group('DTO', () {
    test('parses the detail returned by get_manager_return_request', () {
      final d = _detail();
      expect(d.status, ReturnRequestStatus.pendingReview);
      expect(d.submittedAt.millisecond, 986);
      expect(d.orderItems.single.quantity, 2);
      expect(d.bank!.accountNumber, '0011004392819');
      expect(d.shippers.single.shipperId, _shipperId);
      expect(d.availableActions, {
        ManagerReturnAction.approveCollection,
        ManagerReturnAction.reject,
        ManagerReturnAction.requestInfo,
      });
    });

    test('waiting and closed requests offer no actions', () {
      for (final s in [
        'awaiting_return_pickup',
        'initially_rejected',
        'rejected_after_inspection',
        'refunded',
      ]) {
        expect(_detail(status: s).availableActions, isEmpty, reason: s);
      }
    });

    test('rejects malformed payloads instead of guessing', () {
      final noVideo = _detailJson()..['video_paths'] = <Object?>[];
      expect(() => managerReturnDetailFromJson(noVideo), throwsFormatException);
      final badStatus = _detailJson()..['status'] = 'approved';
      expect(() => managerReturnDetailFromJson(badStatus), throwsA(anything));
      expect(
        () => managerReturnListFromJson({
          'items': <Object?>[],
          'counts': {'pending_review': -1},
          'server_now': '2026-11-02T05:00:00Z',
        }),
        throwsFormatException,
      );
    });

    test('ACK must match operation, request, key and state', () {
      final ack = {
        'operation': 'approve_return_collection',
        'return_request_id': _returnId,
        'request_id': _itemId,
        'return_status': 'awaiting_return_pickup',
      };
      requireReturnAck(
        ack,
        operation: 'approve_return_collection',
        returnId: _returnId,
        requestId: _itemId,
        status: 'awaiting_return_pickup',
      );
      expect(
        () => requireReturnAck(
          ack,
          operation: 'approve_return_collection',
          returnId: _returnId,
          requestId: _shipperId,
          status: 'awaiting_return_pickup',
        ),
        throwsFormatException,
      );
    });

    test('server markers map to typed failures', () {
      ReturnRequestFailureCode code(String c, String m) =>
          mapReturnRequestError(PostgrestException(message: m, code: c)).code;
      expect(
        code('PT409', 'STATE_CONFLICT'),
        ReturnRequestFailureCode.stateConflict,
      );
      expect(
        code('PT409', 'ITEMS_MISMATCH'),
        ReturnRequestFailureCode.itemsMismatch,
      );
      expect(
        code('PT409', 'INVALID_SHIPPER'),
        ReturnRequestFailureCode.invalidShipper,
      );
      expect(
        code('42501', 'PERMISSION_DENIED'),
        ReturnRequestFailureCode.permissionDenied,
      );
      expect(
        code('PGRST202', 'x'),
        ReturnRequestFailureCode.backendUnavailable,
      );
    });
  });

  group('detail view model', () {
    final lines = [
      const ManagerCollectionLine(orderItemId: _itemId, quantity: 1),
    ];

    test('approves once, then reloads the confirmed state', () async {
      final fake = _Fake();
      final c = await _container(fake);
      final vm = c.read(managerReturnDetailProvider(_returnId).notifier);
      final results = await Future.wait([
        vm.approveCollection(lines: lines, shipperId: _shipperId),
        vm.approveCollection(lines: lines, shipperId: _shipperId), // double tap
      ]);
      expect(results, [true, false]);
      expect(fake.approveKeys, hasLength(1));
      final state = c.read(managerReturnDetailProvider(_returnId));
      expect(state.detail!.status, ReturnRequestStatus.awaitingReturnPickup);
      expect(state.notice, contains('Chờ lấy hàng'));
    });

    test('unknown outcome keeps the key so a retry cannot act twice', () async {
      final fake = _Fake()
        ..failures.add(
          const ReturnRequestFailure(ReturnRequestFailureCode.network),
        );
      final c = await _container(fake);
      final vm = c.read(managerReturnDetailProvider(_returnId).notifier);
      expect(
        await vm.approveCollection(lines: lines, shipperId: _shipperId),
        isFalse,
      );
      expect(
        await vm.approveCollection(lines: lines, shipperId: _shipperId),
        isTrue,
      );
      expect(fake.approveKeys, hasLength(2));
      expect(fake.approveKeys.toSet(), hasLength(1));
    });

    test('a different plan gets a new key', () async {
      final fake = _Fake()
        ..failures.add(
          const ReturnRequestFailure(ReturnRequestFailureCode.network),
        );
      final c = await _container(fake);
      final vm = c.read(managerReturnDetailProvider(_returnId).notifier);
      await vm.approveCollection(lines: lines, shipperId: _shipperId);
      await vm.approveCollection(
        lines: [const ManagerCollectionLine(orderItemId: _itemId, quantity: 2)],
        shipperId: _shipperId,
      );
      expect(fake.approveKeys.toSet(), hasLength(2));
    });

    test('state conflict shows the message and reloads', () async {
      final fake = _Fake()
        ..failures.add(
          const ReturnRequestFailure(ReturnRequestFailureCode.stateConflict),
        );
      final c = await _container(fake);
      final before = fake.loads;
      final vm = c.read(managerReturnDetailProvider(_returnId).notifier);
      await vm.approveCollection(lines: lines, shipperId: _shipperId);
      final state = c.read(managerReturnDetailProvider(_returnId));
      expect(state.actionFailure?.code, ReturnRequestFailureCode.stateConflict);
      expect(fake.loads, greaterThan(before));
    });

    test('reject sends the normalized reason', () async {
      final fake = _Fake();
      final c = await _container(fake);
      final vm = c.read(managerReturnDetailProvider(_returnId).notifier);
      expect(await vm.reject('  Video   không thể hiện lỗi  '), isTrue);
      expect(fake.rejectReasons.single, 'Video không thể hiện lỗi');
      expect(
        c.read(managerReturnDetailProvider(_returnId)).detail!.status,
        ReturnRequestStatus.initiallyRejected,
      );
    });

    test('lost access clears the private snapshot', () async {
      final fake = _Fake();
      final c = await _container(fake);
      expect(c.read(managerReturnDetailProvider(_returnId)).detail, isNotNull);
      fake.denyLoads = true;
      await c.read(managerReturnDetailProvider(_returnId).notifier).refresh();
      final state = c.read(managerReturnDetailProvider(_returnId));
      expect(state.detail, isNull);
      expect(
        state.loadFailure?.code,
        ReturnRequestFailureCode.permissionDenied,
      );
    });
  });

  group('route guard', () {
    test('return management routes are manager-only', () {
      final list = OperationalRouteLocation.parse(
        Uri.parse('/manager/returns'),
      );
      expect(list.managerOnly, isTrue);
      expect(list.invalidId, isFalse);
      final detail = OperationalRouteLocation.parse(
        Uri.parse('/manager/returns/$_returnId'),
      );
      expect(detail.managerOnly && !detail.invalidId, isTrue);
      expect(
        OperationalRouteLocation.parse(Uri.parse('/manager/returns/abc'))
            .invalidId,
        isTrue,
      );
      expect(
        OperationalRouteLocation.parse(
          Uri.parse('/manager/returns/$_returnId/x'),
        ).invalidId,
        isTrue,
      );
    });
  });

  group('resolution (phase 2)', () {
    ManagerReturnDetail phase2(String status) =>
        managerReturnDetailFromJson(_phase2Json(status));

    test('each status offers only its own actions', () {
      expect(phase2('returning_to_store').availableActions, {
        ManagerReturnAction.receive,
      });
      expect(phase2('under_inspection').availableActions, {
        ManagerReturnAction.acceptInspection,
        ManagerReturnAction.rejectInspection,
        ManagerReturnAction.requestInfo,
      });
      expect(phase2('awaiting_refund').availableActions, {
        ManagerReturnAction.recordRefund,
      });
      expect(phase2('awaiting_redelivery').availableActions, {
        ManagerReturnAction.assignRedelivery,
      });
      expect(phase2('refunded').availableActions, isEmpty);
    });

    test('an open info request blocks inspection decisions', () {
      final json = _phase2Json('under_inspection')
        ..['info_requests'] = [
          {
            'message': 'Quay rõ đường may',
            'requested_at': '2026-11-02T06:30:00Z',
            'response_text': null,
            'response_video_path': null,
            'responded_at': null,
          },
        ];
      final d = managerReturnDetailFromJson(json);
      expect(d.openInfoRequest, isNotNull);
      expect(d.availableActions, isEmpty);
    });

    test('receive waits for the shipper handover report', () {
      final json = _phase2Json('returning_to_store');
      (json['pickup_task']! as Map)['handover_reported'] = false;
      expect(managerReturnDetailFromJson(json).availableActions, isEmpty);
    });

    test('MH14 reads the latest information request', () {
      expect(returnInfoRequestFromJson({'info_request': null}), isNull);
      final open = returnInfoRequestFromJson({
        'info_request': {
          'message': 'Quay rõ đường may',
          'requested_at': '2026-11-02T06:30:00.123456+00:00',
          'responded_at': null,
        },
      })!;
      expect(open.isOpen, isTrue);
      expect(open.requestedAt.millisecond, 123);
    });

    test('phase-1 payloads still map (phase-2 keys optional)', () {
      final d = _detail(status: 'awaiting_return_pickup');
      expect(d.infoRequests, isEmpty);
      expect(d.refund, isNull);
    });

    test('accept uploads evidence under the command key, once', () async {
      final fake = _Fake()..detail = phase2('under_inspection');
      fake.failures.add(
        const ReturnRequestFailure(ReturnRequestFailureCode.network),
      );
      final c = await _container(fake);
      final vm = c.read(managerReturnDetailProvider(_returnId).notifier);
      final lines = [
        ManagerInspectionLine(
          returnItemId: fake.detail.returnItems.single.returnItemId,
          sellableQuantity: 1,
          damagedQuantity: 1,
        ),
      ];
      expect(
        await vm.acceptInspection(lines: lines, evidence: [_evidence]),
        isFalse,
      );
      expect(
        await vm.acceptInspection(lines: lines, evidence: [_evidence]),
        isTrue,
      );
      // Same key both times → same object name, nothing duplicated.
      expect(fake.commandKeys.toSet(), hasLength(1));
      expect(fake.uploads.toSet(), hasLength(1));
      expect(fake.uploads.toSet().single, endsWith('-0.jpg'));
      expect(fake.acceptedLines!.single.damagedQuantity, 1);
    });

    test('refund always sends merchandise + original delivery fee', () async {
      final fake = _Fake()..detail = phase2('awaiting_refund');
      final c = await _container(fake);
      final vm = c.read(managerReturnDetailProvider(_returnId).notifier);
      await vm.recordRefund(
        transferredAt: DateTime.utc(2026, 11, 2, 8),
        evidence: _evidence,
      );
      expect(fake.refundedAmount, 580000);
      expect(fake.uploads.single, startsWith('refund/'));
    });
  });

  group('widgets', () {
    Future<_Fake> pumpDetail(
      WidgetTester tester, {
      String status = 'pending_review',
    }) async {
      final fake = _Fake(status: status);
      await tester.binding.setSurfaceSize(const Size(390, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [managerReturnRepositoryProvider.overrideWithValue(fake)],
          child: MaterialApp(
            home: ManagerReturnDetailPage(
              returnId: _returnId,
              onBack: () {},
              openUrl: (_) async {},
              onCall: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return fake;
    }

    testWidgets('pending request shows approve and reject only', (
      tester,
    ) async {
      await pumpDetail(tester);
      expect(find.text('Quản lý yêu cầu trả hàng'), findsOneWidget);
      expect(find.byKey(const ValueKey('mh15-approve')), findsOneWidget);
      expect(find.byKey(const ValueKey('mh15-reject')), findsOneWidget);
      expect(find.text('0011004392819'), findsOneWidget);
      expect(find.textContaining('MH15'), findsNothing);
    });

    testWidgets('awaiting pickup shows no decision buttons', (tester) async {
      await pumpDetail(tester, status: 'awaiting_return_pickup');
      expect(find.byKey(const ValueKey('mh15-approve')), findsNothing);
      expect(find.byKey(const ValueKey('mh15-reject')), findsNothing);
      expect(find.textContaining('Chờ shipper lấy hàng'), findsOneWidget);
    });

    testWidgets('approve sheet requires a shipper, then approves', (
      tester,
    ) async {
      final fake = await pumpDetail(tester);
      await tester.tap(find.byKey(const ValueKey('mh15-approve')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mh15-approve-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Chọn shipper.'), findsOneWidget);
      expect(fake.approveKeys, isEmpty);

      await tester.tap(find.byKey(const ValueKey('mh15-shipper')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Shipper Hùng').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mh15-approve-confirm')));
      await tester.pumpAndSettle();
      expect(fake.approveKeys, hasLength(1));
      expect(find.byKey(const ValueKey('mh15-approve')), findsNothing);
    });

    testWidgets('reject needs a reason and explicit confirmation', (
      tester,
    ) async {
      final fake = await pumpDetail(tester);
      await tester.tap(find.byKey(const ValueKey('mh15-reject')));
      await tester.pumpAndSettle();
      final submit = find.byKey(const ValueKey('mh15-reject-submit'));
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('mh15-reject-confirm-check')));
      await tester.pump();
      await tester.tap(submit);
      await tester.pump();
      expect(find.text('Nhập lý do (tối thiểu 5 ký tự).'), findsOneWidget);
      expect(fake.rejectReasons, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('mh15-reject-reason')),
        'Video không thể hiện lỗi',
      );
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(fake.rejectReasons, ['Video không thể hiện lỗi']);
    });

    testWidgets('list shows rows and opens the detail', (tester) async {
      final fake = _Fake();
      String? opened;
      await tester.binding.setSurfaceSize(const Size(390, 884));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [managerReturnRepositoryProvider.overrideWithValue(fake)],
          child: MaterialApp(
            home: ManagerReturnsPage(onOpen: (id) async => opened = id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chờ duyệt (1)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mh15-row-$_returnId')));
      await tester.pumpAndSettle();
      expect(opened, _returnId);
    });
  });
}
