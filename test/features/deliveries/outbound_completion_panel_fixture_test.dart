// P05.2 TEST-ONLY UI with explicit scripted reads, never a backend adapter.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_completion_command.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/outbound_completion_repository.dart';
import 'package:sports_store/features/deliveries/domain/repositories/delivery_phone_dialer.dart';

import 'fixtures/completion_harness_fixture.dart';
import 'fixtures/delivery_dtos.dart';
import 'fixtures/outbound_completion_fixture.dart';

class _RepositoryFixture implements OutboundCompletionRepository {
  final calls = <OutboundCompletionCommand>[];
  Future<void> Function(OutboundCompletionCommand)? handler;
  @override
  Future<void> execute(OutboundCompletionCommand command) {
    calls.add(command);
    return handler?.call(command) ?? Future.value();
  }
}

class _DialerFixture implements DeliveryPhoneDialer {
  final uris = <Uri>[];
  DialerOpenOutcome outcome = DialerOpenOutcome.opened;
  @override
  Future<DialerOpenOutcome> openDialer(Uri uri) async {
    uris.add(uri);
    return outcome;
  }
}

DeliveryTaskDetails _details({
  int amount = 550000,
  String status = 'in_transit',
  String phone = '0900000000',
}) {
  final json = currentTaskDto(
    amount: amount,
    status: status,
    acceptedAt: status == 'assigned' ? null : '2026-10-25T01:00:00Z',
    startedAt: status == 'in_transit' ? '2026-10-25T01:05:00Z' : null,
  );
  json['destination_phone'] = phone;
  return DeliveryTaskDetails(
    task: DeliveryTaskDto.fromJson(json).toDomain(),
    items: const [],
  );
}

DeliveryTaskDetails _delivered() => DeliveryTaskDetails(
  task: DeliveryTaskDto.fromJson(
    maskedTaskDto(status: 'delivered', scope: 'history'),
  ).toDomain(),
  items: const [],
);

const _session = FixtureOutboundSession(
  userId: 'fixture-shipper',
  epoch: 1,
  isShipper: true,
);
const _request = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

Widget _app(
  FixtureOutboundCompletionDependencies deps, {
  DeliveryPhoneDialer? dialer,
}) => ProviderScope(
  overrides: [
    fixtureOutboundCompletionDependenciesProvider.overrideWithValue(deps),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: CompletionHarnessFixture(taskId: taskId, dialer: dialer),
        ),
      ),
    ),
  ),
);

FixtureOutboundCompletionDependencies _deps(
  _RepositoryFixture repo,
  Future<DeliveryTaskDetails> Function(String) read, {
  Future<void> Function()? tasks,
  Future<void> Function()? cod,
  String Function()? id,
}) => FixtureOutboundCompletionDependencies(
  initialSession: _session,
  readTask: read,
  commandRepository: repo,
  createRequestId: id ?? () => _request,
  refreshTaskList: tasks,
  refreshCod: cod,
);

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(CompletionHarnessFixture)),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('completion-open')));
  await tester.pumpAndSettle();
}

Future<void> _checkBoth(WidgetTester tester) async {
  for (final key in ['completion-goods', 'completion-money']) {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'unavailable amounts and states expose no usable success button',
    (tester) async {
      // Deliberately malformed direct-domain amount: real P03.1 DTO mapping rejects it.
      final missing = DeliveryTaskDetails(
        task: const DeliveryTaskSnapshot(
          taskId: taskId,
          kind: DeliveryTaskKind.outbound,
          status: DeliveryTaskStatus.inTransit,
          attemptNumber: 1,
          scope: DeliverySnapshotScope.current,
          itemSource: DeliveryItemSource.orderSnapshot,
        ),
        items: const [],
      );
      for (final value in [
        missing,
        _details(status: 'assigned'),
        _details(status: 'accepted'),
        _delivered(),
      ]) {
        final repo = _RepositoryFixture();
        await tester.pumpWidget(
          const SizedBox.shrink(),
        ); // Dispose the previous provider scope.
        await tester.pumpWidget(_app(_deps(repo, (_) async => value)));
        await tester.pumpAndSettle();
        final button = find.byKey(const ValueKey('completion-open'));
        if (button.evaluate().isNotEmpty) {
          expect(tester.widget<FilledButton>(button).onPressed, isNull);
        }
        expect(repo.calls, isEmpty);
        expect(find.byType(TextField), findsNothing);
      }
    },
  );
  testWidgets(
    'shows full backend COD; both checks required; no auto completion or editable amount',
    (tester) async {
      final repo = _RepositoryFixture();
      var remote = _details();
      repo.handler = (_) async {
        remote = _delivered();
      };
      var tasks = 0, cod = 0;
      await tester.pumpWidget(
        _app(
          _deps(
            repo,
            (_) async => remote,
            tasks: () async {
              tasks++;
            },
            cod: () async {
              cod++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);
      expect(find.text('550.000 đ'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await _open(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('completion-confirm')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('completion-goods')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('completion-confirm')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('completion-money')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('completion-confirm')));
      await tester.pumpAndSettle();
      expect(
        repo.calls.single.reportedCollectedAmountVnd,
        550000,
      ); // No second fee.
      expect(repo.calls.single.receivedAllItems, true);
      expect(repo.calls.single.requestId, _request);
      expect(tasks, 1);
      expect(cod, 1);
      expect(
        find.text('Đã giao thành công (theo dữ liệu đọc)'),
        findsOneWidget,
      );
      expect(
        find.text('COD không khả dụng trong snapshot này.'),
        findsOneWidget,
      );
      expect(
        find.text('550.000 đ'),
        findsNothing,
      ); // Masked history, no cached PII/COD.
    },
  );

  testWidgets('cancelling confirmation sends no command', (tester) async {
    final repo = _RepositoryFixture();
    await tester.pumpWidget(_app(_deps(repo, (_) async => _details())));
    await tester.pumpAndSettle();
    await _open(tester);
    await _checkBoth(tester);
    await tester.tap(find.byKey(const ValueKey('completion-cancel')));
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
  });

  testWidgets(
    'timeout retry freezes ID/amount; ACK waits for authoritative read',
    (tester) async {
      var ids = 0, attempts = 0, tasks = 0, cod = 0;
      var remote = _details();
      final ack = Completer<void>();
      final repo = _RepositoryFixture()
        ..handler = (_) async {
          if (attempts++ == 0) throw TimeoutException('Fixture lost response');
          await ack.future;
          remote = _delivered();
        };
      await tester.pumpWidget(
        _app(
          _deps(
            repo,
            (_) async => remote,
            id: () {
              ids++;
              return _request;
            },
            tasks: () async {
              tasks++;
            },
            cod: () async {
              cod++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _open(tester);
      await _checkBoth(tester);
      await tester.tap(find.byKey(const ValueKey('completion-confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Chưa xác định kết quả'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('completion-open')))
            .onPressed,
        isNull,
      );
      expect(tasks + cod, 0);
      await tester.tap(find.byKey(const ValueKey('completion-retry')));
      await tester.pump();
      expect(repo.calls.length, 2);
      expect(repo.calls.first, same(repo.calls.last));
      expect(ids, 1);
      expect(find.text('Đã giao thành công (theo dữ liệu đọc)'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('completion-retry')),
            )
            .onPressed,
        isNull,
      );
      ack.complete();
      await tester.pumpAndSettle();
      expect(tasks, 1);
      expect(cod, 1);
      expect(
        find.text('Đã giao thành công (theo dữ liệu đọc)'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'changed amount while dialog is open cannot be silently submitted',
    (tester) async {
      final repo = _RepositoryFixture();
      var remote = _details();
      await tester.pumpWidget(_app(_deps(repo, (_) async => remote)));
      await tester.pumpAndSettle();
      await _open(tester);
      remote = _details(amount: 580000);
      await _container(tester)
          .read(fixtureOutboundCompletionViewModelProvider(taskId).notifier)
          .refresh();
      await tester.pumpAndSettle();
      await _checkBoth(tester);
      await tester.tap(find.byKey(const ValueKey('completion-confirm')));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);
      expect(find.textContaining('số tiền đã thay đổi'), findsOneWidget);
    },
  );

  testWidgets('logout while dialog is open prevents command', (tester) async {
    final repo = _RepositoryFixture();
    await tester.pumpWidget(_app(_deps(repo, (_) async => _details())));
    await tester.pumpAndSettle();
    await _open(tester);
    await _checkBoth(tester);
    _container(tester)
        .read(fixtureOutboundCompletionViewModelProvider(taskId).notifier)
        .updateSession(
          const FixtureOutboundSession(
            userId: null,
            epoch: 2,
            isShipper: false,
          ),
        );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('completion-confirm')));
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
  });

  testWidgets(
    'dialer callback receives tel URI only and never completes delivery',
    (tester) async {
      final repo = _RepositoryFixture();
      final dialer = _DialerFixture();
      await tester.pumpWidget(
        _app(_deps(repo, (_) async => _details()), dialer: dialer),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('completion-dialer')));
      await tester.pumpAndSettle();
      expect(dialer.uris.single, Uri(scheme: 'tel', path: '0900000000'));
      expect(find.text('Đã mở trình quay số (fixture).'), findsOneWidget);
      expect(repo.calls, isEmpty);
    },
  );

  for (final outcome in [
    DialerOpenOutcome.failed,
    DialerOpenOutcome.unavailable,
  ]) {
    testWidgets('dialer $outcome is surfaced without reporting a call', (
      tester,
    ) async {
      final repo = _RepositoryFixture();
      final dialer = _DialerFixture()..outcome = outcome;
      await tester.pumpWidget(
        _app(_deps(repo, (_) async => _details()), dialer: dialer),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('completion-dialer')));
      await tester.pumpAndSettle();
      expect(find.text('Đã mở trình quay số (fixture).'), findsNothing);
      expect(
        find.text(
          outcome == DialerOpenOutcome.failed
              ? 'Không thể mở trình quay số.'
              : 'Không có trình quay số khả dụng.',
        ),
        findsOneWidget,
      );
      expect(repo.calls, isEmpty);
    });
  }

  testWidgets('invalid numbers and historical snapshots cannot open dialer', (
    tester,
  ) async {
    final dialer = _DialerFixture();
    for (final details in [
      _details(phone: '*123#'),
      _details(phone: 'tel:0900000000'),
      _delivered(),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _app(_deps(_RepositoryFixture(), (_) async => details), dialer: dialer),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('completion-dialer'));
      if (button.evaluate().isNotEmpty) {
        expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      }
    }
    expect(dialer.uris, isEmpty);
  });

  for (final entry in {
    OutboundCommandFailureCode.permissionDenied:
        'Bạn không có quyền giao thành công.',
    OutboundCommandFailureCode.staleAssignment: 'Phân công đã thay đổi.',
    OutboundCommandFailureCode.dependencyUnavailable:
        'Completion API live chưa sẵn sàng.',
    OutboundCommandFailureCode.staleState:
        'Trạng thái đã thay đổi. Cần đọc lại dữ liệu.',
  }.entries) {
    testWidgets('business error ${entry.key} is shown without success', (
      tester,
    ) async {
      final repo = _RepositoryFixture()
        ..handler = (_) async => throw OutboundCommandFailure(entry.key);
      await tester.pumpWidget(_app(_deps(repo, (_) async => _details())));
      await tester.pumpAndSettle();
      await _open(tester);
      await _checkBoth(tester);
      await tester.tap(find.byKey(const ValueKey('completion-confirm')));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('Đã giao thành công (theo dữ liệu đọc)'), findsNothing);
      expect(repo.calls, hasLength(1));
    });
  }
}
