import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_completion_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/outbound_completion_repository.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/outbound_completion_providers.dart';
import 'package:sports_store/features/deliveries/presentation/widgets/outbound_completion_action.dart';

import 'fixtures/delivery_dtos.dart';

const _taskId = taskId;
const _requestId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

class _Repository implements OutboundCompletionRepository {
  final commands = <OutboundCompletionCommand>[];
  Future<void> Function(OutboundCompletionCommand)? handler;

  @override
  Future<void> execute(OutboundCompletionCommand command) {
    commands.add(command);
    return handler?.call(command) ?? Future<void>.value();
  }
}

DeliveryTaskDetails _current() => DeliveryTaskDetails(
  task: DeliveryTaskDto.fromJson(
    currentTaskDto(
      status: 'in_transit',
      acceptedAt: '2026-10-25T09:00:00Z',
      startedAt: '2026-10-25T09:10:00Z',
    ),
  ).toDomain(),
  items: const [],
);

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('widget did not settle: $finder');
}

({
  StreamController<OperationalSession> sessions,
  _Repository repository,
  ProviderContainer container,
})
_harness() {
  final sessions = StreamController<OperationalSession>.broadcast();
  final repository = _Repository();
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      operationalSessionProvider.overrideWith((ref) => sessions.stream),
      outboundCompletionRepositoryProvider.overrideWithValue(repository),
      outboundCompletionRequestIdProvider.overrideWithValue(() => _requestId),
      outboundCompletionDetailsReloadProvider.overrideWithValue(
        (_) async => _current(),
      ),
      outboundCompletionTaskListReloadProvider.overrideWithValue(() async {}),
      outboundCompletionCodReloadProvider.overrideWithValue(() async {}),
    ],
  );
  return (sessions: sessions, repository: repository, container: container);
}

Widget _app(ProviderContainer container, {bool routed = false}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: routed
            ? Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    key: const ValueKey('open-detail-route'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(
                          key: ValueKey('completion-detail-route'),
                          body: OutboundCompletionAction(taskId: _taskId),
                        ),
                      ),
                    ),
                    child: const Text('Open detail'),
                  ),
                ),
              )
            : const Scaffold(body: OutboundCompletionAction(taskId: _taskId)),
      ),
    );

void main() {
  testWidgets('shows server amount and requires both confirmations', (
    tester,
  ) async {
    final h = _harness();
    addTearDown(() async {
      h.container.dispose();
      await h.sessions.close();
    });
    await tester.pumpWidget(_app(h.container));
    h.sessions.add(
      const OperationalSession(userId: 'shipper-a', generation: 1),
    );
    await _pumpUntil(tester, find.byKey(const ValueKey('completion-open')));
    expect(find.text('550.000 đ'), findsOneWidget);
    expect(h.repository.commands, isEmpty);
    await tester.tap(find.byKey(const ValueKey('completion-open')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('completion-dialog-amount')),
      findsOneWidget,
    );
    final confirm = find.byKey(const ValueKey('completion-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('completion-goods')));
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('completion-money')));
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(h.repository.commands, hasLength(1));
    expect(h.repository.commands.single.reportedCollectedAmountVnd, 550000);
  });

  testWidgets('double confirmation taps send one command', (tester) async {
    final h = _harness();
    final gate = Completer<void>();
    h.repository.handler = (_) => gate.future;
    addTearDown(() async {
      h.container.dispose();
      await h.sessions.close();
    });
    await tester.pumpWidget(_app(h.container, routed: true));
    await tester.tap(find.byKey(const ValueKey('open-detail-route')));
    await tester.pumpAndSettle();
    h.sessions.add(
      const OperationalSession(userId: 'shipper-a', generation: 1),
    );
    await _pumpUntil(tester, find.byKey(const ValueKey('completion-open')));
    await tester.tap(find.byKey(const ValueKey('completion-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('completion-goods')));
    await tester.tap(find.byKey(const ValueKey('completion-money')));
    await tester.pump();
    final confirm = find.byKey(const ValueKey('completion-confirm'));
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(h.repository.commands, hasLength(1));
    // The dialog is already closed; a second tap cannot dispatch another key.
    expect(find.byKey(const ValueKey('completion-confirm')), findsNothing);
    expect(
      find.byKey(const ValueKey('completion-detail-route')),
      findsOneWidget,
    );
    gate.complete();
  });

  testWidgets('session switch closes and redacts an open confirmation', (
    tester,
  ) async {
    final h = _harness();
    addTearDown(() async {
      h.container.dispose();
      await h.sessions.close();
    });
    await tester.pumpWidget(_app(h.container));
    h.sessions.add(
      const OperationalSession(userId: 'shipper-a', generation: 1),
    );
    await _pumpUntil(tester, find.byKey(const ValueKey('completion-open')));
    await tester.tap(find.byKey(const ValueKey('completion-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('completion-goods')), findsOneWidget);
    h.sessions.add(
      const OperationalSession(userId: 'shipper-b', generation: 2),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('completion-goods')), findsNothing);
    expect(h.repository.commands, isEmpty);
  });
}
