import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sports_store/app/router/operational_route_guard.dart';
import 'package:sports_store/features/returns/data/models/return_request_dto.dart';
import 'package:sports_store/features/returns/data/repositories/supabase_return_request_repository.dart';
import 'package:sports_store/features/returns/domain/models/return_reason.dart';
import 'package:sports_store/features/returns/domain/models/return_request_context.dart';
import 'package:sports_store/features/returns/domain/models/return_request_failure.dart';
import 'package:sports_store/features/returns/domain/models/return_request_submission.dart';
import 'package:sports_store/features/returns/domain/repositories/return_request_repository.dart';
import 'package:sports_store/features/returns/domain/repositories/return_video_picker.dart';
import 'package:sports_store/features/returns/presentation/pages/return_request_flow_page.dart';
import 'package:sports_store/features/returns/presentation/view_models/return_request_providers.dart';

const _orderId = '11111111-1111-4111-8111-111111111111';
const _customerId = '22222222-2222-4222-8222-222222222222';

ReturnRequestContext _context({
  ReturnEligibility eligibility = ReturnEligibility.eligible,
}) => ReturnRequestContext(
  orderId: _orderId,
  orderStatus: 'delivered',
  deliveredAt: DateTime.utc(2026, 10, 1, 7, 30),
  items: const [
    ReturnContextItem(
      orderItemId: '33333333-3333-4333-8333-333333333333',
      productName: 'Áo Thể Thao Nam',
      variantLabel: 'Màu Đen / Size M',
      quantity: 2,
      unitPriceVnd: 260000,
    ),
  ],
  deliveryFeeVnd: 30000,
  totalPaidVnd: 550000,
  serverNow: DateTime.utc(2026, 10, 3, 7, 30),
  returnDeadline: DateTime.utc(2026, 10, 8, 7, 30),
  canSubmitReturn: eligibility == ReturnEligibility.eligible,
  eligibility: eligibility,
);

class _FakeRepository implements ReturnRequestRepository {
  _FakeRepository({ReturnEligibility eligibility = ReturnEligibility.eligible})
    : context = _context(eligibility: eligibility);

  final ReturnRequestContext context;
  final uploads = <String>[];
  final commands = <ReturnRequestCommand>[];
  final submitFailures = <ReturnRequestFailure>[];

  @override
  Future<ReturnRequestContext> loadContext(String orderId) async => context;

  @override
  Future<String> uploadVideo({
    required String orderId,
    required String requestId,
    required ReturnVideoFile video,
  }) async {
    uploads.add(requestId);
    return '$_customerId/$orderId/$requestId.${video.extension}';
  }

  @override
  Future<ReturnRequestReceipt> submit(ReturnRequestCommand command) async {
    commands.add(command);
    if (submitFailures.isNotEmpty) throw submitFailures.removeAt(0);
    return ReturnRequestReceipt(
      returnRequestId: '44444444-4444-4444-8444-444444444444',
      orderId: command.orderId,
      status: 'pending_review',
      submittedAt: DateTime.utc(2026, 10, 3, 8),
      replayed: false,
    );
  }
}

class _FakePicker implements ReturnVideoPicker {
  ReturnVideoFile? next = ReturnVideoFile(
    name: 'mo-kien.mp4',
    bytes: Uint8List.fromList(List.filled(2048, 1)),
    mimeType: 'video/mp4',
  );
  ReturnVideoPickFailure? failure;

  @override
  Future<ReturnVideoFile?> pickVideo() async {
    if (failure != null) throw failure!;
    return next;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeRepository repository,
  _FakePicker picker, {
  ValueChanged<String>? onOpenReturn,
}) async {
  tester.view.physicalSize = const Size(390, 884);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        returnRequestRepositoryProvider.overrideWith((ref) => repository),
        returnVideoPickerProvider.overrideWithValue(picker),
      ],
      child: MaterialApp(
        home: ReturnRequestFlowPage(
          orderId: _orderId,
          onExit: () {},
          onOpenReturn: onOpenReturn ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _visible(WidgetTester tester, Finder finder, String scroll) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .descendant(
          of: find.byKey(ValueKey(scroll)),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _goToStep2(WidgetTester tester, String reasonWire) async {
  final reason = find.byKey(ValueKey('mh13-reason-$reasonWire'));
  await _visible(tester, reason, 'mh13-scroll');
  await tester.tap(reason);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('mh13-submit')));
  await tester.pumpAndSettle();
}

Future<void> _fillStep2(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('mh13-description')),
    '  Áo bị   bung chỉ ở vai trái khi mở kiện. ',
  );
  final pick = find.byKey(const ValueKey('mh13-pick-video'));
  await _visible(tester, pick, 'mh13-details-scroll');
  await tester.tap(pick);
  await tester.pumpAndSettle();
  for (final (key, value) in [
    ('mh13-bank-name', 'Vietcombank'),
    ('mh13-account-number', '0123 4567 89'),
    ('mh13-account-holder', 'nguyen van a'),
  ]) {
    final field = find.byKey(ValueKey(key));
    await _visible(tester, field, 'mh13-details-scroll');
    await tester.enterText(field, value);
  }
  await tester.pump();
}

void main() {
  testWidgets('step 2 keeps input when going back to step 1', (tester) async {
    final repository = _FakeRepository();
    await _pump(tester, repository, _FakePicker());

    expect(find.text('Đơn #$_orderId'), findsOneWidget);
    await _goToStep2(tester, 'wrong_item');
    expect(find.text('Bước 2/2'), findsOneWidget);
    expect(find.text('Giao sai sản phẩm'), findsOneWidget);
    expect(find.text('Gửi yêu cầu trả hàng'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('mh13-description')),
      'Nhận sai màu áo so với đơn.',
    );

    await tester.tap(find.byKey(const ValueKey('mh13-change-reason')));
    await tester.pumpAndSettle();
    expect(find.text('Bước 1/2'), findsOneWidget);
    expect(find.text('Tiếp tục'), findsOneWidget);
    expect(find.text('Gửi yêu cầu trả hàng'), findsNothing);

    await _goToStep2(tester, 'defective');
    expect(find.text('Sản phẩm bị lỗi hoặc hư hỏng'), findsOneWidget);
    expect(find.text('Nhận sai màu áo so với đơn.'), findsOneWidget);
    expect(repository.commands, isEmpty);
  });

  testWidgets('send validates every field before any network call', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await _pump(tester, repository, _FakePicker());
    await _goToStep2(tester, 'defective');

    await tester.tap(find.byKey(const ValueKey('mh13-send')));
    await tester.pumpAndSettle();
    expect(find.text('Nhập tối thiểu 10 ký tự.'), findsOneWidget);
    expect(find.text('Cần video quay lúc mở kiện hàng.'), findsOneWidget);
    expect(repository.uploads, isEmpty);
    expect(repository.commands, isEmpty);
  });

  testWidgets('submits normalized command once and shows success', (
    tester,
  ) async {
    final repository = _FakeRepository();
    String? opened;
    await _pump(
      tester,
      repository,
      _FakePicker(),
      onOpenReturn: (id) => opened = id,
    );
    await _goToStep2(tester, 'defective');
    await _fillStep2(tester);

    await tester.tap(find.byKey(const ValueKey('mh13-send')));
    await tester.pumpAndSettle();

    expect(repository.uploads, hasLength(1));
    expect(repository.commands, hasLength(1));
    final command = repository.commands.single;
    expect(command.reason, ReturnReason.defective);
    expect(command.description, 'Áo bị bung chỉ ở vai trái khi mở kiện.');
    expect(command.accountNumber, '0123456789');
    expect(command.accountHolder, 'NGUYEN VAN A');
    expect(command.requestId, repository.uploads.single);
    expect(
      command.videoObjectPath,
      '$_customerId/$_orderId/${command.requestId}.mp4',
    );
    expect(find.byKey(const ValueKey('mh13-success')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mh13-done')));
    expect(opened, '44444444-4444-4444-8444-444444444444');
  });

  testWidgets('ambiguous failure retries with the same key, no re-upload', (
    tester,
  ) async {
    final repository = _FakeRepository()
      ..submitFailures.add(
        const ReturnRequestFailure(ReturnRequestFailureCode.network),
      );
    await _pump(tester, repository, _FakePicker());
    await _goToStep2(tester, 'defective');
    await _fillStep2(tester);

    await tester.tap(find.byKey(const ValueKey('mh13-send')));
    await tester.pumpAndSettle();
    expect(
      find.text('Không thể kết nối. Vui lòng kiểm tra mạng và gửi lại.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('mh13-send')));
    await tester.pumpAndSettle();
    expect(repository.uploads, hasLength(1));
    expect(repository.commands, hasLength(2));
    expect(
      repository.commands.first.requestId,
      repository.commands.last.requestId,
    );
    expect(find.byKey(const ValueKey('mh13-success')), findsOneWidget);
  });

  testWidgets('definitive failure starts a new request next time', (
    tester,
  ) async {
    final repository = _FakeRepository()
      ..submitFailures.add(
        const ReturnRequestFailure(ReturnRequestFailureCode.videoRequired),
      );
    await _pump(tester, repository, _FakePicker());
    await _goToStep2(tester, 'defective');
    await _fillStep2(tester);

    await tester.tap(find.byKey(const ValueKey('mh13-send')));
    await tester.pumpAndSettle();
    expect(
      find.text('Không xác nhận được video mở kiện. Vui lòng chọn lại video.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('mh13-send')));
    await tester.pumpAndSettle();
    expect(repository.uploads, hasLength(2));
    expect(
      repository.commands.first.requestId,
      isNot(repository.commands.last.requestId),
    );
  });

  testWidgets('rejected video file is reported and not attached', (
    tester,
  ) async {
    final picker = _FakePicker()
      ..failure = const ReturnVideoPickFailure(
        'Video cần có dung lượng từ 1 byte đến 100 MB.',
      );
    await _pump(tester, _FakeRepository(), picker);
    await _goToStep2(tester, 'defective');
    final pick = find.byKey(const ValueKey('mh13-pick-video'));
    await _visible(tester, pick, 'mh13-details-scroll');
    await tester.tap(pick);
    await tester.pumpAndSettle();
    expect(
      find.text('Video cần có dung lượng từ 1 byte đến 100 MB.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mh13-video-selected')), findsNothing);
  });

  testWidgets('order with an active return cannot start a new one', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeRepository(eligibility: ReturnEligibility.activeReturnExists),
      _FakePicker(),
    );
    expect(
      find.text('Đơn này đã có yêu cầu trả hàng đang được xử lý.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mh13-submit')), findsNothing);
  });

  group('server contract mapping', () {
    test('business markers need the exact code and message', () {
      ReturnRequestFailureCode map(String code, String message) =>
          mapReturnRequestError(
            PostgrestException(message: message, code: code),
          ).code;

      expect(
        map('PT409', 'ACTIVE_RETURN_EXISTS'),
        ReturnRequestFailureCode.activeReturnExists,
      );
      expect(
        map('PT409', 'RETURN_WINDOW_EXPIRED'),
        ReturnRequestFailureCode.returnWindowExpired,
      );
      expect(
        map('PT422', 'VIDEO_REQUIRED'),
        ReturnRequestFailureCode.videoRequired,
      );
      expect(
        map('PT404', 'ORDER_NOT_FOUND'),
        ReturnRequestFailureCode.orderNotFound,
      );
      expect(
        map('42501', 'PERMISSION_DENIED'),
        ReturnRequestFailureCode.permissionDenied,
      );
      expect(
        map('42501', 'AUTH_REQUIRED'),
        ReturnRequestFailureCode.sessionExpired,
      );
      expect(
        map('PGRST202', 'Could not find the function'),
        ReturnRequestFailureCode.backendUnavailable,
      );
      expect(
        map('XX000', 'ACTIVE_RETURN_EXISTS'),
        ReturnRequestFailureCode.unexpected,
      );
    });

    test('context and receipt parse strictly', () {
      final context = returnRequestContextFromJson({
        'order_id': _orderId,
        'order_status': 'delivered',
        'delivered_at': '2026-10-01T07:30:00+00:00',
        'subtotal_vnd': 520000,
        'delivery_fee_vnd': 30000,
        'total_paid_vnd': 550000,
        'items': [
          {
            'order_item_id': '33333333-3333-4333-8333-333333333333',
            'product_name': 'Áo',
            'variant_label': 'Đen / M',
            'quantity': 2,
            'unit_price_vnd': 260000,
            'line_total_vnd': 520000,
            'product_image_url': 'http://insecure.example/a.png',
          },
        ],
        'server_now': '2026-10-03T07:30:00+00:00',
        'return_deadline': '2026-10-08T07:30:00+00:00',
        'can_submit_return': true,
        'eligibility_reason': null,
        'active_return': null,
      });
      expect(context.eligibility, ReturnEligibility.eligible);
      expect(context.items.single.quantity, 2);
      expect(context.items.single.imageUrl, isNull, reason: 'HTTPS only');

      const command = ReturnRequestCommand(
        orderId: _orderId,
        requestId: '55555555-5555-4555-8555-555555555555',
        reason: ReturnReason.defective,
        description: 'Áo bị rách khi mở kiện.',
        videoObjectPath: 'a/b/c.mp4',
        bankName: 'VCB',
        accountNumber: '0123456789',
        accountHolder: 'A',
      );
      expect(
        () => returnRequestReceiptFromJson({
          'return_request_id': '44444444-4444-4444-8444-444444444444',
          'order_id': _orderId,
          'request_id': '66666666-6666-4666-8666-666666666666',
          'status': 'pending_review',
          'submitted_at': '2026-10-03T08:00:00+00:00',
          'replayed': false,
        }, command: command),
        throwsFormatException,
      );
    });

    test('route guard accepts only /customer/orders/<uuid>/return', () {
      final ok = OperationalRouteLocation.parse(
        Uri.parse('/customer/orders/$_orderId/return'),
      );
      expect(ok.protected && ok.customerOnly && !ok.invalidId, isTrue);
      for (final path in [
        '/customer/orders/not-a-uuid/return',
        '/customer/orders/$_orderId/return/extra',
      ]) {
        final location = OperationalRouteLocation.parse(Uri.parse(path));
        expect(location.invalidId, isTrue, reason: path);
      }
      // The canonical app also exposes the separate customer order detail.
      // It is guarded by FourScreenRouteBoundary and repository ownership,
      // rather than being interpreted as a malformed return-request route.
      final detail = OperationalRouteLocation.parse(
        Uri.parse('/customer/orders/$_orderId'),
      );
      expect(detail.invalidId, isFalse);
      expect(detail.protected, isFalse);
    });
  });
}
