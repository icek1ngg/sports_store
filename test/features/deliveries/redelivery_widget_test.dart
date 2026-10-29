// Labeled repository/read fixtures exercise the real production action VM.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_details_dto.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/redelivery_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/redelivery_repository.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_task_detail_view_model.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/redelivery_providers.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/redelivery_view_model.dart';
import 'package:sports_store/features/deliveries/presentation/widgets/redelivery_action.dart';
import 'package:sports_store/features/deliveries/presentation/widgets/delivery_task_card.dart';

import 'fixtures/delivery_dtos.dart';

DeliveryTaskDetails _details(String status) {
  final terminal = status == 'delivered' || status == 'manager_action_required';
  final task = terminal
      ? maskedTaskDto(
          kind: 'redelivery',
          status: status,
          scope: status == 'delivered' ? 'history' : 'restricted',
        )
      : currentTaskDto(
          kind: 'redelivery',
          status: status,
          returnRequest: returnRequestId,
          amount: 0,
          itemSource: 'return_plan',
        );
  if (terminal && status == 'manager_action_required') {
    task['completed_at'] = null;
  }
  if (!terminal) {
    task['accepted_at'] = status == 'assigned' ? null : '2026-10-23T03:01:00Z';
    task['started_at'] = status == 'in_transit' ? '2026-10-23T03:02:00Z' : null;
  }
  return DeliveryTaskDetailsDto.fromJson({
    'task': task,
    'items': terminal ? [] : [returnItemDto(quantityCollected: 2)],
    'notes': null,
    'notes_source': 'unavailable_schema',
    'as_of': '2026-10-23T04:00:00Z',
  }, requestedTaskId: taskId).toDomain();
}

class _Details extends DeliveryTaskDetailViewModel {
  _Details(this.initial) : super(taskId);
  final DeliveryTaskDetails initial;
  @override
  AsyncValue<DeliveryTaskDetails> build() => AsyncData(initial);
}

class _FixtureRepo implements RedeliveryRepository {
  final events = <String>[];
  final commands = <RedeliveryCommand>[];
  @override
  Future<RedeliveryAck> execute(RedeliveryCommand c) async {
    commands.add(c);
    events.add('write');
    final now = DateTime.utc(2026, 10, 23, 4);
    return RedeliveryAck(
      taskId: c.taskId,
      returnRequestId: c.returnRequestId,
      orderId: c.orderId,
      operation: c.operation,
      taskStatus: c.isComplete ? 'delivered' : 'manager_action_required',
      returnStatus: c.isComplete
          ? 'rejected_after_inspection'
          : 'manager_action_required',
      eventId: orderId,
      requestId: c.requestId,
      occurredAt: now,
      completedAt: c.isComplete ? now : null,
      closedAt: c.isComplete ? now : null,
      failedAt: c.isFail ? now : null,
      custodyOpen: c.isFail,
      reason: c.reason,
      description: c.trimmedDescription,
    );
  }
}

/// Stateful composition fixture for the complete MH11 redelivery journey.
///
/// Writes only move the server-side state.  The widget/ViewModel receives the
/// new projection only when [completeNextRead] releases the authoritative
/// detail read, which makes optimistic state changes observable in tests.
class _StatefulRedeliveryFixture implements RedeliveryRepository {
  final commands = <RedeliveryCommand>[];
  final readStatuses = <String>[];
  final pendingReads = <Completer<DeliveryTaskDetails>>[];

  String status = 'assigned';

  @override
  Future<RedeliveryAck> execute(RedeliveryCommand command) async {
    final expectedOperation = switch (status) {
      'assigned' => RedeliveryOperation.accept,
      'accepted' => RedeliveryOperation.start,
      'in_transit' =>
        command.isComplete
            ? RedeliveryOperation.complete
            : RedeliveryOperation.fail,
      _ => null,
    };
    if (expectedOperation != command.operation) {
      throw StateError(
        'Expected $expectedOperation from $status, got ${command.operation}',
      );
    }

    if (command.isAccept) {
      final plan = command.items;
      if (plan.length != 1 ||
          plan.single.itemId != itemId ||
          plan.single.quantity != 2) {
        throw StateError('The exact immutable return plan was not submitted');
      }
      status = 'accepted';
    } else if (command.items.isNotEmpty) {
      throw StateError('Only accept may carry the return plan');
    } else if (command.isStart) {
      status = 'in_transit';
    } else if (command.isComplete) {
      status = 'delivered';
    } else {
      status = 'manager_action_required';
    }
    commands.add(command);

    final now = DateTime.utc(2026, 10, 23, 4);
    return RedeliveryAck(
      taskId: command.taskId,
      returnRequestId: command.returnRequestId,
      orderId: command.orderId,
      operation: command.operation,
      taskStatus: status,
      returnStatus: command.isComplete
          ? 'rejected_after_inspection'
          : command.isFail
          ? 'manager_action_required'
          : 'awaiting_redelivery',
      eventId: '88888888-8888-4888-8888-888888888888',
      requestId: command.requestId,
      occurredAt: now,
      acceptedAt: command.isAccept || command.isStart ? now : null,
      startedAt: command.isStart ? now : null,
      completedAt: command.isComplete ? now : null,
      closedAt: command.isComplete ? now : null,
      failedAt: command.isFail ? now : null,
      custodyOpen: command.isFail,
      reason: command.reason,
      description: command.trimmedDescription,
    );
  }

  Future<DeliveryTaskDetails> reload(String requestedTaskId) {
    if (requestedTaskId != taskId) {
      throw StateError('Unexpected task read: $requestedTaskId');
    }
    readStatuses.add(status);
    final read = Completer<DeliveryTaskDetails>();
    pendingReads.add(read);
    return read.future;
  }

  void completeNextRead() {
    if (pendingReads.isEmpty) {
      throw StateError('No authoritative read is waiting');
    }
    pendingReads.removeAt(0).complete(_details(status));
  }
}

void _expectLegalRedeliveryButtons(
  WidgetTester tester,
  List<String> expectedOperations,
) {
  final expectedKeys = expectedOperations
      .map((operation) => 'redelivery-$operation-open')
      .toList(growable: false);
  final actualKeys = tester.allWidgets
      .whereType<ButtonStyleButton>()
      .map((button) => button.key)
      .whereType<ValueKey<String>>()
      .map((key) => key.value)
      .where((key) => key.endsWith('-open'))
      .toList(growable: false);
  expect(actualKeys, expectedKeys);
}

Future<void> _confirmRedeliveryPlan(
  WidgetTester tester,
  String operation,
) async {
  await tester.tap(find.byKey(ValueKey('redelivery-$operation-open')));
  await tester.pumpAndSettle();
  expect(find.byKey(ValueKey('redelivery-plan-$itemId')), findsOneWidget);
  expect(find.textContaining('Số lượng giao lại: 2'), findsOneWidget);
  final confirm = find.byKey(ValueKey('redelivery-$operation-confirm'));
  expect(tester.widget<ButtonStyleButton>(confirm).onPressed, isNull);
  await tester.tap(find.byKey(ValueKey('redelivery-$operation-all')));
  await tester.pump();
  expect(tester.widget<ButtonStyleButton>(confirm).onPressed, isNotNull);
  await tester.ensureVisible(confirm);
  await tester.tap(confirm);
  await tester.pumpAndSettle();
}

void main() {
  for (final status in [
    'assigned',
    'accepted',
    'delivered',
    'manager_action_required',
  ]) {
    testWidgets('$status allows only its legal redelivery actions', (
      tester,
    ) async {
      final sessions = StreamController<OperationalSession>.broadcast();
      final repo = _FixtureRepo();
      final c = ProviderContainer(
        overrides: [
          operationalSessionProvider.overrideWith((ref) => sessions.stream),
          redeliveryRepositoryProvider.overrideWithValue(repo),
          deliveryTaskDetailViewModelProvider(taskId)
              .overrideWith(() => _Details(_details(status))),
        ],
      );
      addTearDown(() async {
        c.dispose();
        await sessions.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: SingleChildScrollView(
                child: RedeliveryAction(taskId: taskId),
              ),
            ),
          ),
        ),
      );
      sessions.add(
        const OperationalSession(userId: 'fixture-shipper', generation: 1),
      );
      await tester.pumpAndSettle();
      final operation = status == 'assigned'
          ? 'accept'
          : status == 'accepted'
          ? 'start'
          : null;
      expect(
        find.byKey(const ValueKey('redelivery-complete-open')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('redelivery-failure-open')),
        findsNothing,
      );
      if (operation != null) {
        expect(
          find.byKey(
            ValueKey(
              'redelivery-${operation == 'accept' ? 'start' : 'accept'}-open',
            ),
          ),
          findsNothing,
        );
        await tester.tap(find.byKey(ValueKey('redelivery-$operation-open')));
        await tester.pumpAndSettle();
        final confirm = find.byKey(ValueKey('redelivery-$operation-confirm'));
        expect(tester.widget<ButtonStyleButton>(confirm).onPressed, isNull);
        await tester.tap(find.byKey(ValueKey('redelivery-$operation-all')));
        await tester.pump();
        expect(tester.widget<ButtonStyleButton>(confirm).onPressed, isNotNull);
        await tester.tap(find.byKey(ValueKey('redelivery-$operation-cancel')));
        await tester.pumpAndSettle();
      } else {
        expect(
          find.byKey(const ValueKey('redelivery-accept-open')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('redelivery-start-open')),
          findsNothing,
        );
      }
      expect(repo.commands, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final fail in [false, true]) {
    testWidgets(
      '${fail ? 'failure' : 'success'} confirmation refetches before showing result',
      (tester) async {
        final session = StreamController<OperationalSession>.broadcast();
        final repo = _FixtureRepo();
        final detailRead = Completer<DeliveryTaskDetails>();
        final listRead = Completer<void>();
        final c = ProviderContainer(
          overrides: [
            operationalSessionProvider.overrideWith((ref) => session.stream),
            redeliveryRepositoryProvider.overrideWithValue(repo),
            redeliveryRequestIdProvider.overrideWithValue(() => orderId),
            deliveryTaskDetailViewModelProvider(taskId)
                .overrideWith(() => _Details(_details('in_transit'))),
            redeliveryDetailsReloadProvider.overrideWithValue((_) {
              repo.events.add('detail');
              return detailRead.future;
            }),
            redeliveryTaskListReloadProvider.overrideWithValue(() {
              repo.events.add('list');
              return listRead.future;
            }),
          ],
        );
        addTearDown(() async {
          c.dispose();
          await session.close();
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(
                body: SingleChildScrollView(
                  child: RedeliveryAction(taskId: taskId),
                ),
              ),
            ),
          ),
        );
        session.add(
          const OperationalSession(userId: 'fixture-shipper', generation: 1),
        );
        await tester.pumpAndSettle();
        expect(repo.commands, isEmpty);
        expect(
          find.byKey(const ValueKey('redelivery-accept-open')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(
            ValueKey(
              fail ? 'redelivery-failure-open' : 'redelivery-complete-open',
            ),
          ),
        );
        await tester.pumpAndSettle();
        final confirm = find.byKey(
          ValueKey(
            fail ? 'redelivery-failure-confirm' : 'redelivery-complete-confirm',
          ),
        );
        expect(tester.widget<ButtonStyleButton>(confirm).onPressed, isNull);
        if (fail) {
          await tester.tap(
            find.byKey(const ValueKey('redelivery-failure-reason')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Khác').last);
          await tester.pumpAndSettle();
          expect(tester.widget<ButtonStyleButton>(confirm).onPressed, isNull);
          await tester.enterText(
            find.byKey(const ValueKey('redelivery-failure-description')),
            'Customer unavailable',
          );
          await tester.pump();
        } else {
          await tester.tap(
            find.byKey(const ValueKey('redelivery-complete-all')),
          );
          await tester.pump();
        }
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(repo.commands.length, 1);
        expect(repo.events, ['write', 'detail']);
        expect(c.read(redeliveryViewModelProvider(taskId)).confirmed, isFalse);
        detailRead.complete(
          _details(fail ? 'manager_action_required' : 'delivered'),
        );
        await tester.pumpAndSettle();
        expect(repo.events, ['write', 'detail', 'list']);
        expect(c.read(redeliveryViewModelProvider(taskId)).confirmed, isFalse);
        listRead.complete();
        await tester.pumpAndSettle();
        expect(c.read(redeliveryViewModelProvider(taskId)).confirmed, isTrue);
        expect(
          find.byKey(
            ValueKey(
              fail
                  ? 'redelivery-fail-confirmed'
                  : 'redelivery-complete-confirmed',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('redelivery-complete-open')),
          findsNothing,
        );
        expect(repo.commands.length, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('MH10 free redelivery has zero COD and no outbound cap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeliveryTaskCard(task: _details('assigned').task, onTap: () {}),
        ),
      ),
    );
    expect(find.text('Không thu COD'), findsOneWidget);
    expect(find.text('GIAO LẠI MIỄN PHÍ'), findsWidgets);
    expect(find.textContaining('/ 2'), findsNothing);
  });

  for (final success in [true, false]) {
    testWidgets(
      'P10.2 stateful fixture ${success ? 'success' : 'failure'} composes '
      'assigned → accept → refetch → accepted → start → refetch → in_transit '
      '→ outcome → terminal refetch',
      (tester) async {
        final session = StreamController<OperationalSession>.broadcast();
        final fixture = _StatefulRedeliveryFixture();
        final requestIds = <String>[
          '55555555-5555-4555-8555-555555555555',
          '66666666-6666-4666-8666-666666666666',
          '77777777-7777-4777-8777-777777777777',
        ];
        var nextRequestId = 0;
        var listReloads = 0;
        final container = ProviderContainer(
          overrides: [
            operationalSessionProvider.overrideWith((ref) => session.stream),
            redeliveryRepositoryProvider.overrideWithValue(fixture),
            redeliveryRequestIdProvider.overrideWithValue(
              () => requestIds[nextRequestId++],
            ),
            deliveryTaskDetailViewModelProvider(taskId)
                .overrideWith(() => _Details(_details('assigned'))),
            redeliveryDetailsReloadProvider.overrideWithValue(fixture.reload),
            redeliveryTaskListReloadProvider.overrideWithValue(() async {
              listReloads++;
            }),
          ],
        );
        addTearDown(() async {
          container.dispose();
          await session.close();
        });

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(
                body: SingleChildScrollView(
                  child: RedeliveryAction(taskId: taskId),
                ),
              ),
            ),
          ),
        );
        session.add(
          const OperationalSession(userId: 'fixture-shipper', generation: 1),
        );
        await tester.pumpAndSettle();

        _expectLegalRedeliveryButtons(tester, ['accept']);
        expect(
          container
              .read(redeliveryViewModelProvider(taskId))
              .details
              .requireValue
              .task
              .amountToCollectVnd,
          0,
        );
        expect(find.textContaining('/ 2'), findsNothing);

        await _confirmRedeliveryPlan(tester, 'accept');
        expect(fixture.commands, hasLength(1));
        expect(fixture.commands.single.operation, RedeliveryOperation.accept);
        expect(fixture.commands.single.items, [
          const RedeliveryItem(itemId: itemId, quantity: 2),
        ]);
        expect(fixture.readStatuses, ['accepted']);
        expect(fixture.pendingReads, hasLength(1));
        expect(
          container
              .read(redeliveryViewModelProvider(taskId))
              .details
              .requireValue
              .task
              .status
              .value,
          'assigned',
        );
        expect(
          find.byKey(const ValueKey('redelivery-accept-confirmed')),
          findsNothing,
        );
        expect(listReloads, 0);

        fixture.completeNextRead();
        await tester.pumpAndSettle();
        expect(listReloads, 1);
        expect(
          container
              .read(redeliveryViewModelProvider(taskId))
              .details
              .requireValue
              .task
              .status
              .value,
          'accepted',
        );
        expect(
          find.byKey(const ValueKey('redelivery-accept-confirmed')),
          findsOneWidget,
        );
        _expectLegalRedeliveryButtons(tester, ['start']);

        await _confirmRedeliveryPlan(tester, 'start');
        expect(fixture.commands, hasLength(2));
        expect(fixture.commands[1].operation, RedeliveryOperation.start);
        expect(fixture.commands[1].items, isEmpty);
        expect(fixture.readStatuses, ['accepted', 'in_transit']);
        expect(fixture.pendingReads, hasLength(1));
        expect(
          container
              .read(redeliveryViewModelProvider(taskId))
              .details
              .requireValue
              .task
              .status
              .value,
          'accepted',
        );
        expect(
          find.byKey(const ValueKey('redelivery-start-confirmed')),
          findsNothing,
        );
        expect(listReloads, 1);

        fixture.completeNextRead();
        await tester.pumpAndSettle();
        expect(listReloads, 2);
        expect(
          container
              .read(redeliveryViewModelProvider(taskId))
              .details
              .requireValue
              .task
              .status
              .value,
          'in_transit',
        );
        expect(
          container
              .read(redeliveryViewModelProvider(taskId))
              .details
              .requireValue
              .task
              .amountToCollectVnd,
          0,
        );
        _expectLegalRedeliveryButtons(tester, ['complete', 'failure']);

        if (success) {
          await _confirmRedeliveryPlan(tester, 'complete');
        } else {
          await tester.tap(
            find.byKey(const ValueKey('redelivery-failure-open')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('redelivery-failure-confirm')),
            findsOneWidget,
          );
          expect(
            tester
                .widget<ButtonStyleButton>(
                  find.byKey(const ValueKey('redelivery-failure-confirm')),
                )
                .onPressed,
            isNull,
          );
          await tester.tap(
            find.byKey(const ValueKey('redelivery-failure-reason')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Khách hẹn lại').last);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<ButtonStyleButton>(
                  find.byKey(const ValueKey('redelivery-failure-confirm')),
                )
                .onPressed,
            isNotNull,
          );
          await tester.tap(
            find.byKey(const ValueKey('redelivery-failure-confirm')),
          );
          await tester.pumpAndSettle();
        }

        expect(fixture.commands, hasLength(3));
        expect(
          fixture.commands[2].operation,
          success ? RedeliveryOperation.complete : RedeliveryOperation.fail,
        );
        expect(fixture.commands[2].items, isEmpty);
        expect(fixture.readStatuses, [
          'accepted',
          'in_transit',
          success ? 'delivered' : 'manager_action_required',
        ]);
        expect(fixture.pendingReads, hasLength(1));
        expect(
          container
              .read(redeliveryViewModelProvider(taskId))
              .details
              .requireValue
              .task
              .status
              .value,
          'in_transit',
        );
        expect(
          find.byKey(
            ValueKey(
              success
                  ? 'redelivery-complete-confirmed'
                  : 'redelivery-fail-confirmed',
            ),
          ),
          findsNothing,
        );
        expect(listReloads, 2);

        fixture.completeNextRead();
        await tester.pumpAndSettle();
        expect(listReloads, 3);
        expect(
          container
              .read(redeliveryViewModelProvider(taskId))
              .details
              .requireValue
              .task
              .status
              .value,
          success ? 'delivered' : 'manager_action_required',
        );
        expect(
          find.byKey(
            ValueKey(
              success
                  ? 'redelivery-complete-confirmed'
                  : 'redelivery-fail-confirmed',
            ),
          ),
          findsOneWidget,
        );
        _expectLegalRedeliveryButtons(tester, const []);

        expect(nextRequestId, 3);
        expect(
          fixture.commands.map((command) => command.requestId).toSet(),
          hasLength(3),
        );
        expect(
          fixture.commands.map((command) => command.requestId),
          requestIds,
        );
        // Financial/attempt preservation is proved by SQL, not by immutable
        // counters in this fixture. This test proves UI/command/read ordering.
        expect(fixture.commands[0].returnRequestId, returnRequestId);
        expect(fixture.commands[0].orderId, orderId);
      },
    );
  }
}
