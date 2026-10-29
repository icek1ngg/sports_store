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
}
