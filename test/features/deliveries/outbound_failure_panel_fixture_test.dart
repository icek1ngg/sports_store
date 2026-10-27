// P07.3 TEST-ONLY widget coverage. This harness never calls a production
// page, repository, Supabase client, RPC or backend adapter.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';

import 'fixtures/delivery_dtos.dart';
import 'fixtures/failure_panel_fixture.dart';

DeliveryTaskDetails _details({
  String status = 'in_transit',
  String kind = 'outbound',
  int attempt = 1,
  bool timestamps = true,
}) {
  final json = currentTaskDto(
    kind: kind,
    status: status,
    order: orderId,
    returnRequest: kind == 'outbound' ? null : returnRequestId,
    amount: kind == 'outbound' ? 550000 : 0,
    itemSource: switch (kind) {
      'outbound' => 'order_snapshot',
      'return_pickup' => 'return_plan',
      'redelivery' => 'unavailable_redelivery_plan',
      _ => 'order_snapshot',
    },
    acceptedAt: timestamps && status != 'assigned'
        ? '2026-10-25T01:00:00Z'
        : null,
    startedAt: timestamps && status == 'in_transit'
        ? '2026-10-25T01:05:00Z'
        : null,
  )..['attempt_number'] = attempt;

  return DeliveryTaskDetails(
    task: DeliveryTaskDto.fromJson(json).toDomain(),
    items: const [],
  );
}

DeliveryTaskDetails _historyDetails() => DeliveryTaskDetails(
  task: DeliveryTaskDto.fromJson(
    maskedTaskDto(status: 'delivered', scope: 'history'),
  ).toDomain(),
  items: const [],
);

DeliveryTaskDetails _invalidAttemptDetails() => DeliveryTaskDetails(
  task: DeliveryTaskSnapshot(
    taskId: taskId,
    kind: DeliveryTaskKind.outbound,
    status: DeliveryTaskStatus.inTransit,
    attemptNumber: 3,
    scope: DeliverySnapshotScope.current,
    orderId: orderId,
    amountToCollectVnd: 550000,
    destination: const DeliveryDestination(
      name: 'Nguyễn Văn A',
      phone: '0900000000',
      address: 'Hà Nội',
      latitude: 21.028511,
      longitude: 105.804817,
    ),
    acceptedAt: DateTime.utc(2026, 10, 25, 1),
    startedAt: DateTime.utc(2026, 10, 25, 1, 5),
    itemSource: DeliveryItemSource.orderSnapshot,
  ),
  items: const [],
);

Widget _app({
  DeliveryTaskDetails? details,
  bool noDetails = false,
  bool eligible = true,
  bool busy = false,
  Object sessionRevision = 1,
  Future<void> Function(String reason, String? description)? onConfirmed,
  String? errorMessage,
  Future<void> Function()? onRetry,
  String retryLabel = 'Thử lại cùng yêu cầu',
  String? resultLabel,
  double textScale = 1,
}) => MaterialApp(
  theme: AppTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: FailurePanelFixture(
        details: noDetails ? null : details ?? _details(),
        eligible: eligible,
        busy: busy,
        sessionRevision: sessionRevision,
        onConfirmed: onConfirmed ?? (_, _) async {},
        errorMessage: errorMessage,
        onRetry: onRetry,
        retryLabel: retryLabel,
        resultLabel: resultLabel,
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('failure-open')));
  await tester.pumpAndSettle();
}

Future<void> _chooseReason(WidgetTester tester, String value) async {
  await tester.tap(find.byKey(const ValueKey('failure-reason')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(fixtureFailureReasons[value]!).last);
  await tester.pumpAndSettle();
}

Future<void> _disposeFixture(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('eligible current outbound attempt one and two can open', (
    tester,
  ) async {
    for (final attempt in [1, 2]) {
      await tester.pumpWidget(_app(details: _details(attempt: attempt)));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('failure-open')), findsOneWidget);
      await _open(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(const ValueKey('failure-reason')), findsOneWidget);
      expect(find.byKey(const ValueKey('failure-description')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('failure-cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await _disposeFixture(tester);
    }
  });

  testWidgets('reason choices are visible and cancel is side-effect free', (
    tester,
  ) async {
    final calls = <(String, String?)>[];
    await tester.pumpWidget(
      _app(
        onConfirmed: (reason, description) async {
          calls.add((reason, description));
        },
      ),
    );
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('failure-reason')));
    await tester.pumpAndSettle();
    for (final label in fixtureFailureReasons.values) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.text(fixtureFailureReasons['unreachable']!).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('failure-cancel')));
    await tester.pumpAndSettle();

    expect(calls, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('other requires a non-whitespace description and trims it', (
    tester,
  ) async {
    final calls = <(String, String?)>[];
    await tester.pumpWidget(
      _app(
        onConfirmed: (reason, description) async {
          calls.add((reason, description));
        },
      ),
    );
    await _open(tester);
    await _chooseReason(tester, 'other');

    await tester.enterText(
      find.byKey(const ValueKey('failure-description')),
      ' \t\n ',
    );
    await tester.tap(find.byKey(const ValueKey('failure-confirm')));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(
      find.text('Chọn lý do và nhập mô tả khi chọn Khác.'),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('failure-description')),
      '  Khách đổi lịch nhận  ',
    );
    tester.testTextInput.hide();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('failure-confirm')));
    await tester.pumpAndSettle();
    expect(calls, [('other', 'Khách đổi lịch nhận')]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('non-other reason permits an optional description', (
    tester,
  ) async {
    final calls = <(String, String?)>[];
    await tester.pumpWidget(
      _app(
        onConfirmed: (reason, description) async {
          calls.add((reason, description));
        },
      ),
    );
    await _open(tester);
    await _chooseReason(tester, 'refusal');
    await tester.tap(find.byKey(const ValueKey('failure-confirm')));
    await tester.pumpAndSettle();

    expect(calls, [('refusal', null)]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'ineligible kinds, scopes, states, attempts and timestamps do not open',
    (tester) async {
      final scenarios = <({String name, DeliveryTaskDetails? details})>[
        (name: 'other kind', details: _details(kind: 'return_pickup')),
        (name: 'history scope', details: _historyDetails()),
        (name: 'non transit state', details: _details(status: 'accepted')),
        (name: 'invalid attempt', details: _invalidAttemptDetails()),
        (name: 'missing details', details: null),
        (name: 'missing timestamps', details: _details(timestamps: false)),
      ];

      for (final scenario in scenarios) {
        await tester.pumpWidget(
          _app(
            details: scenario.details,
            noDetails: scenario.name == 'missing details',
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('failure-open')),
          findsNothing,
          reason: scenario.name,
        );
        expect(find.byType(AlertDialog), findsNothing);
        await _disposeFixture(tester);
      }
    },
  );

  testWidgets('busy and in-flight confirmation guard duplicate submissions', (
    tester,
  ) async {
    var busyCalls = 0;
    await tester.pumpWidget(
      _app(
        busy: true,
        onRetry: () async {
          busyCalls++;
        },
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('failure-open')), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('failure-retry')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('failure-retry')));
    expect(busyCalls, 0);

    final response = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      _app(
        onConfirmed: (_, _) async {
          calls++;
          await response.future;
        },
      ),
    );
    await tester.pump();
    await _open(tester);
    await _chooseReason(tester, 'unreachable');

    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('failure-confirm')),
    );
    confirm.onPressed!.call();
    confirm.onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(calls, 1);
    expect(find.byKey(const ValueKey('failure-open')), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    response.complete();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byKey(const ValueKey('failure-open')), findsOneWidget);
  });

  testWidgets('session revision change closes and redacts an open dialog', (
    tester,
  ) async {
    await tester.pumpWidget(_app(sessionRevision: 1));
    await _open(tester);
    await _chooseReason(tester, 'other');
    await tester.enterText(
      find.byKey(const ValueKey('failure-description')),
      'Thông tin riêng của tài khoản cũ',
    );

    await tester.pumpWidget(_app(sessionRevision: 2));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('failure-reason')), findsNothing);
    expect(find.byKey(const ValueKey('failure-description')), findsNothing);
    expect(find.text('Thông tin riêng của tài khoản cũ'), findsNothing);
  });

  testWidgets('role revocation closes an open dialog before confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(_app(eligible: true));
    await _open(tester);
    await _chooseReason(tester, 'refusal');
    await tester.enterText(
      find.byKey(const ValueKey('failure-description')),
      'Không được giữ lại sau khi quyền bị thu hồi',
    );

    await tester.pumpWidget(_app(eligible: false));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('failure-reason')), findsNothing);
    expect(find.byKey(const ValueKey('failure-description')), findsNothing);
    expect(find.byKey(const ValueKey('failure-open')), findsNothing);
  });

  testWidgets(
    'changed task snapshot closes the old dialog and never submits its draft',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _app(
          details: _details(attempt: 1),
          onConfirmed: (_, _) async {
            calls++;
          },
        ),
      );
      await _open(tester);
      await _chooseReason(tester, 'unreachable');

      // The task ID is unchanged, but the authoritative attempt snapshot is
      // different; an old confirmation must not be applied to attempt two.
      await tester.pumpWidget(
        _app(
          details: _details(attempt: 2),
          onConfirmed: (_, _) async {
            calls++;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('failure-reason')), findsNothing);
      expect(find.byKey(const ValueKey('failure-description')), findsNothing);
      expect(calls, 0);
    },
  );

  testWidgets('error and retry remain explicit fixture callbacks', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      _app(
        eligible: false,
        errorMessage: 'Chưa xác định kết quả. Thử lại cùng request ID.',
        onRetry: () async {
          retries++;
        },
      ),
    );
    expect(find.byKey(const ValueKey('failure-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('failure-retry')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('failure-retry')));
    await tester.pumpAndSettle();
    expect(retries, 1);
  });

  testWidgets('second failure shows result without COD or stock actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        details: _details(attempt: 2),
        resultLabel: 'Lần giao thứ hai thất bại — chờ cửa hàng xử lý.',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('failure-result')), findsOneWidget);
    expect(
      find.text('Lần giao thứ hai thất bại — chờ cửa hàng xử lý.'),
      findsOneWidget,
    );
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('550.000 đ'), findsNothing);
    expect(find.textContaining('đặt lịch'), findsNothing);
    expect(find.textContaining('hoàn kho'), findsNothing);
    expect(find.byKey(const ValueKey('failure-cod')), findsNothing);
    expect(find.byKey(const ValueKey('failure-payment')), findsNothing);
    expect(find.byKey(const ValueKey('failure-schedule')), findsNothing);
    expect(find.byKey(const ValueKey('failure-stock-return')), findsNothing);
  });

  testWidgets('narrow viewport remains usable at large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        textScale: 1.8,
        resultLabel: 'Lần giao thứ hai thất bại — chờ cửa hàng xử lý.',
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _open(tester);
    expect(find.byKey(const ValueKey('failure-confirm')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
