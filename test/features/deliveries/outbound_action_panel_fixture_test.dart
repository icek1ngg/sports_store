// P04.2 TEST-ONLY confirmations; this panel is not the production MH11 page.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/outbound_task_command_repository.dart';

import 'fixtures/delivery_dtos.dart';
import 'fixtures/outbound_action_panel_fixture.dart';
import 'fixtures/outbound_action_fixture.dart';

class _CommandFixture implements OutboundTaskCommandRepository {
  _CommandFixture(this.handler);
  final Future<void> Function(OutboundTaskCommand) handler;
  final calls = <OutboundTaskCommand>[];
  @override
  Future<void> execute(OutboundTaskCommand command) {
    calls.add(command);
    return handler(command);
  }
}

DeliveryTaskDetails _details(String status) => DeliveryTaskDetails(
  task: DeliveryTaskDto.fromJson(
    currentTaskDto(
      status: status,
      acceptedAt: status == 'assigned' ? null : '2026-10-24T09:00:00Z',
      startedAt: status == 'in_transit' ? '2026-10-24T09:10:00Z' : null,
    ),
  ).toDomain(),
  items: const [],
);

Widget _harness(
  FixtureOutboundActionDependencies dependencies,
) => ProviderScope(
  overrides: [
    fixtureOutboundActionDependenciesProvider.overrideWithValue(dependencies),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    home: const Scaffold(body: OutboundActionHarnessFixture(taskId: taskId)),
  ),
);

const _session = FixtureOutboundSession(
  userId: 'shipper-fixture',
  epoch: 1,
  isShipper: true,
);

void main() {
  Widget app({
    String status = 'assigned',
    String kind = 'outbound',
    bool busy = false,
    bool allowed = true,
    String? error,
    Future<void> Function()? retry,
    required Future<void> Function(OutboundTaskAction) submit,
  }) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: OutboundActionPanelFixture(
        task: DeliveryTaskDto.fromJson(
          currentTaskDto(
            status: status,
            kind: kind,
            returnRequest: kind == 'return_pickup' ? returnRequestId : null,
            amount: kind == 'return_pickup' ? 0 : 550000,
            itemSource: kind == 'return_pickup'
                ? 'return_plan'
                : 'order_snapshot',
          ),
        ).toDomain(),
        canAccept: allowed,
        canStart: allowed,
        busy: busy,
        errorMessage: error,
        onRetry: retry,
        onConfirmed: submit,
      ),
    ),
  );

  testWidgets('opening panel and cancelling confirmation never sends accept', (
    tester,
  ) async {
    final calls = <OutboundTaskAction>[];
    await tester.pumpWidget(app(submit: (action) async => calls.add(action)));
    expect(calls, isEmpty);
    expect(find.textContaining('TEST-ONLY'), findsOneWidget);
    expect(find.byKey(const ValueKey('fixture-start')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('fixture-accept')));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.textContaining('thực nhận đủ hàng'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fixture-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(find.byKey(const ValueKey('fixture-accept')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fixture-confirm-submit')));
    await tester.pumpAndSettle();
    expect(calls, [OutboundTaskAction.acceptGoods]);
  });

  testWidgets('accepted only offers start and requires confirmation', (
    tester,
  ) async {
    final calls = <OutboundTaskAction>[];
    await tester.pumpWidget(
      app(status: 'accepted', submit: (action) async => calls.add(action)),
    );
    expect(find.byKey(const ValueKey('fixture-accept')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('fixture-start')));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(find.byKey(const ValueKey('fixture-confirm-submit')));
    await tester.pumpAndSettle();
    expect(calls, [OutboundTaskAction.startDelivery]);
  });

  testWidgets('busy or unavailable dependency keeps action disabled', (
    tester,
  ) async {
    var calls = 0;
    for (final busy in [true, false]) {
      await tester.pumpWidget(
        app(
          busy: busy,
          allowed: false,
          submit: (_) async {
            calls++;
          },
        ),
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('fixture-accept')))
            .onPressed,
        isNull,
      );
    }
    expect(calls, 0);
  });

  testWidgets('return task and transit task expose no outbound actions', (
    tester,
  ) async {
    for (final scenario in [
      ('assigned', 'return_pickup'),
      ('in_transit', 'outbound'),
    ]) {
      await tester.pumpWidget(
        app(
          status: scenario.$1,
          kind: scenario.$2,
          submit: (_) async => fail('No command expected'),
        ),
      );
      expect(find.byType(FilledButton), findsNothing);
    }
  });

  testWidgets(
    'error remains visible and retry only invokes explicit callback',
    (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        app(
          error: 'Chưa xác định kết quả. Thử lại cùng request ID.',
          allowed: false,
          retry: () async {
            retries++;
          },
          submit: (_) async => fail('No new command expected'),
        ),
      );
      expect(find.textContaining('Chưa xác định kết quả'), findsOneWidget);
      expect(retries, 0);
      await tester.tap(find.byKey(const ValueKey('fixture-action-retry')));
      await tester.pumpAndSettle();
      expect(retries, 1);
    },
  );

  testWidgets(
    'Riverpod fixture performs ordered confirmed actions then refetches',
    (tester) async {
      var remoteStatus = 'assigned';
      var reads = 0;
      var listReads = 0;
      var ids = 0;
      final repository = _CommandFixture((command) async {
        remoteStatus = command.action == OutboundTaskAction.acceptGoods
            ? 'accepted'
            : 'in_transit';
      });
      await tester.pumpWidget(
        _harness(
          FixtureOutboundActionDependencies(
            initialSession: _session,
            commandRepository: repository,
            readTask: (_) async {
              reads++;
              return _details(remoteStatus);
            },
            refreshTaskList: () async {
              listReads++;
            },
            createRequestId: () =>
                'aaaaaaaa-aaaa-4aaa-8aaa-${(++ids).toString().padLeft(12, '0')}',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.calls, isEmpty);
      for (final key in ['fixture-accept', 'fixture-start']) {
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        expect(repository.calls.length, key == 'fixture-accept' ? 0 : 1);
        await tester.tap(find.byKey(const ValueKey('fixture-confirm-submit')));
        await tester.pumpAndSettle();
      }
      expect(repository.calls.map((c) => c.action), [
        OutboundTaskAction.acceptGoods,
        OutboundTaskAction.startDelivery,
      ]);
      expect(
        repository.calls[0].requestId,
        isNot(repository.calls[1].requestId),
      );
      expect(reads, 3);
      expect(listReads, 2);
      expect(find.textContaining('in_transit'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    },
  );

  testWidgets(
    'timeout keeps same request and blocks start despite accepted read',
    (tester) async {
      var remoteStatus = 'assigned';
      var ids = 0;
      var listReads = 0;
      var failures = 0;
      final transport = _CommandFixture((_) async {
        remoteStatus =
            'accepted'; // Scripted read fixture, not a backend write.
        if (failures++ == 0) {
          throw TimeoutException('Fixture transport response lost');
        }
      });
      await tester.pumpWidget(
        _harness(
          FixtureOutboundActionDependencies(
            initialSession: _session,
            commandRepository: transport,
            readTask: (_) async => _details(remoteStatus),
            refreshTaskList: () async {
              listReads++;
            },
            createRequestId: () {
              ids++;
              return 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fixture-accept')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fixture-confirm-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Chưa xác định kết quả'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('fixture-start')))
            .onPressed,
        isNull,
      );
      expect(listReads, 0);
      await tester.tap(find.byKey(const ValueKey('fixture-action-retry')));
      await tester.pumpAndSettle();
      expect(transport.calls.length, 2);
      expect(identical(transport.calls[0], transport.calls[1]), isTrue);
      expect(ids, 1);
      expect(listReads, 1);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('fixture-start')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('logout while confirmation is open prevents sending the action', (
    tester,
  ) async {
    final repository = _CommandFixture((_) async {});
    await tester.pumpWidget(
      _harness(
        FixtureOutboundActionDependencies(
          initialSession: _session,
          commandRepository: repository,
          readTask: (_) async => _details('assigned'),
          createRequestId: () => 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OutboundActionHarnessFixture)),
    );
    await tester.tap(find.byKey(const ValueKey('fixture-accept')));
    await tester.pumpAndSettle();
    container
        .read(fixtureOutboundActionViewModelProvider(taskId).notifier)
        .updateSession(
          const FixtureOutboundSession(
            userId: null,
            epoch: 2,
            isShipper: false,
          ),
        );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fixture-confirm-submit')));
    await tester.pumpAndSettle();
    expect(repository.calls, isEmpty);
    expect(find.byKey(const ValueKey('fixture-accept')), findsNothing);
  });

  for (final scenario in [
    (
      OutboundCommandFailureCode.permissionDenied,
      'Bạn không có quyền thực hiện.',
    ),
    (
      OutboundCommandFailureCode.dependencyUnavailable,
      'API nhận/bắt đầu giao chưa sẵn sàng.',
    ),
    (
      OutboundCommandFailureCode.staleState,
      'Trạng thái đã thay đổi. Vui lòng tải lại.',
    ),
  ]) {
    testWidgets(
      'Riverpod fixture surfaces ${scenario.$1} without local success',
      (tester) async {
        var remote = 'assigned';
        final repository = _CommandFixture((_) async {
          if (scenario.$1 == OutboundCommandFailureCode.staleState) {
            remote = 'in_transit';
          }
          throw OutboundCommandFailure(scenario.$1);
        });
        await tester.pumpWidget(
          _harness(
            FixtureOutboundActionDependencies(
              initialSession: _session,
              commandRepository: repository,
              readTask: (_) async => _details(remote),
              createRequestId: () => 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('fixture-accept')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('fixture-confirm-submit')));
        await tester.pumpAndSettle();
        expect(repository.calls.length, 1);
        expect(find.text(scenario.$2), findsOneWidget);
        expect(find.byKey(const ValueKey('fixture-start')), findsNothing);
        if (scenario.$1 != OutboundCommandFailureCode.staleState) {
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const ValueKey('fixture-accept')),
                )
                .onPressed,
            isNull,
          );
          expect(
            find.byKey(const ValueKey('fixture-action-retry')),
            findsNothing,
          );
        }
      },
    );
  }
}
