// P07.3 TEST-ONLY integration of scripted provider and dialog; no real RPC.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_failure_command.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';

import 'fixtures/delivery_dtos.dart';
import 'fixtures/failure_harness_fixture.dart';
import 'fixtures/outbound_failure_fixture.dart';

DeliveryTaskDetails _task({int attempt = 1, bool failed = false}) {
  final dto = failed
      ? maskedTaskDto(status: 'failed', scope: 'restricted')
      : currentTaskDto(
          status: 'in_transit',
          acceptedAt: '2026-10-26T01:00:00Z',
          startedAt: '2026-10-26T01:05:00Z',
        );
  dto['attempt_number'] = attempt;
  return DeliveryTaskDetails(
    task: DeliveryTaskDto.fromJson(dto).toDomain(),
    items: const [],
  );
}

OutboundFailureAck _ack(OutboundFailureCommand command) => OutboundFailureAck(
  taskId: command.taskId,
  requestId: command.requestId,
  attemptNumber: command.attemptNumber,
  disposition: OutboundFailureDisposition.forAttempt(command.attemptNumber),
);

Future<void> _mount(
  WidgetTester tester,
  FixtureOutboundFailureDependencies deps,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fixtureOutboundFailureDependenciesProvider.overrideWithValue(deps),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: FailureHarnessFixture(taskId: taskId),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('failure-open')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('failure-reason')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Không liên hệ được').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('failure-confirm')));
}

void main() {
  const session = FixtureOutboundSession(
    userId: 'fixture-shipper',
    epoch: 1,
    isShipper: true,
  );
  const request = '77777777-7777-4777-8777-777777777777';

  testWidgets(
    'timeout retains command; second failure ACK reads only on retry and reloads list',
    (tester) async {
      final repo = ScriptedOutboundFailureRepository();
      var committed = false;
      var readFails = true;
      var generated = 0;
      var listReloads = 0;
      repo.handler = (command) {
        if (repo.commands.length == 1) {
          throw TimeoutException('TEST transport timeout');
        }
        committed = true;
        return _ack(command);
      };
      await _mount(
        tester,
        FixtureOutboundFailureDependencies(
          initialSession: session,
          failureRepository: repo,
          createRequestId: () {
            generated++;
            return request;
          },
          readTask: (_) async {
            if (!committed) return _task(attempt: 2);
            if (readFails) {
              readFails = false;
              throw TimeoutException('TEST read timeout');
            }
            return _task(attempt: 2, failed: true);
          },
          refreshTaskList: () async {
            listReloads++;
          },
        ),
      );
      await _submit(tester);
      await tester.pumpAndSettle();
      expect(repo.commands, hasLength(1));
      expect(find.byKey(const ValueKey('failure-result')), findsNothing);
      expect(find.byKey(const ValueKey('failure-open')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('failure-retry')));
      await tester.pumpAndSettle();
      expect(repo.commands, hasLength(2));
      expect(repo.commands[1], repo.commands[0]);
      expect(generated, 1);
      expect(find.text('Đọc lại dữ liệu'), findsOneWidget);
      expect(find.byKey(const ValueKey('failure-result')), findsNothing);
      expect(listReloads, 0);
      await tester.tap(find.byKey(const ValueKey('failure-retry')));
      await tester.pumpAndSettle();
      expect(repo.commands, hasLength(2));
      expect(find.text('Chờ hoàn về cửa hàng'), findsOneWidget);
      expect(find.text('Chờ quản lý quyết định'), findsNothing);
      expect(listReloads, 1);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.textContaining('550.000'), findsNothing);
    },
  );

  testWidgets(
    'first failed result waits for authoritative read and refreshes list',
    (tester) async {
      final gate = Completer<DeliveryTaskDetails>();
      final repo = ScriptedOutboundFailureRepository()..handler = _ack;
      var reads = 0;
      var reloaded = false;
      await _mount(
        tester,
        FixtureOutboundFailureDependencies(
          initialSession: session,
          failureRepository: repo,
          createRequestId: () => request,
          readTask: (_) async => ++reads == 1 ? _task() : gate.future,
          refreshTaskList: () async {
            reloaded = true;
          },
        ),
      );
      await _submit(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.commands, hasLength(1));
      expect(find.byKey(const ValueKey('failure-result')), findsNothing);
      expect(reloaded, false);
      gate.complete(_task(failed: true));
      await tester.pumpAndSettle();
      expect(find.text('Chờ quản lý quyết định'), findsOneWidget);
      expect(reloaded, true);
    },
  );

  testWidgets('denied RPC surfaces safe error and never shows result', (
    tester,
  ) async {
    final repo = ScriptedOutboundFailureRepository()
      ..handler = (_) => throw const OutboundCommandFailure(
        OutboundCommandFailureCode.permissionDenied,
        cause: 'PRIVATE SERVER TEXT',
      );
    var reloaded = false;
    await _mount(
      tester,
      FixtureOutboundFailureDependencies(
        initialSession: session,
        failureRepository: repo,
        createRequestId: () => request,
        readTask: (_) async => _task(),
        refreshTaskList: () async {
          reloaded = true;
        },
      ),
    );
    await _submit(tester);
    await tester.pumpAndSettle();
    expect(find.text('Bạn không có quyền báo thất bại.'), findsOneWidget);
    expect(find.textContaining('PRIVATE SERVER TEXT'), findsNothing);
    expect(find.byKey(const ValueKey('failure-result')), findsNothing);
    expect(find.byKey(const ValueKey('failure-open')), findsNothing);
    expect(reloaded, false);
  });
}
