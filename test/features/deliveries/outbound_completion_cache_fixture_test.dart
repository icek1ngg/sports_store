// P05.2 TEST-ONLY cache integration. These providers are fixtures, not MH10/COD live wiring.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_completion_command.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/outbound_completion_repository.dart';

import 'fixtures/delivery_dtos.dart';
import 'fixtures/outbound_completion_fixture.dart';

final _countsFixture = FutureProvider<Map<String, int>>(
  (ref) => throw UnimplementedError(),
);
final _codFixture = FutureProvider<int>((ref) => throw UnimplementedError());

class _RepositoryFixture implements OutboundCompletionRepository {
  _RepositoryFixture(this.handler);
  final Future<void> Function() handler;
  var calls = 0;
  @override
  Future<void> execute(OutboundCompletionCommand command) {
    calls++;
    return handler();
  }
}

DeliveryTaskDetails _readFixture(bool delivered) => DeliveryTaskDetails(
  task: DeliveryTaskDto.fromJson(
    delivered
        ? maskedTaskDto(status: 'delivered', scope: 'history')
        : currentTaskDto(
            status: 'in_transit',
            acceptedAt: '2026-10-25T01:00:00Z',
            startedAt: '2026-10-25T01:05:00Z',
          ),
  ).toDomain(),
  items: const [],
);

void main() {
  for (final failCodReload in [false, true]) {
    test(
      'invalidates both fixture caches after ACK; COD retry=$failCodReload never resubmits',
      () async {
        final ack = Completer<void>();
        var delivered = false, countReads = 0, codReads = 0;
        final repository = _RepositoryFixture(() async {
          delivered = true;
          await ack.future;
        });
        late ProviderContainer container;
        final dependencies = FixtureOutboundCompletionDependencies(
          initialSession: const FixtureOutboundSession(
            userId: 'fixture-shipper',
            epoch: 1,
            isShipper: true,
          ),
          commandRepository: repository,
          readTask: (_) async => _readFixture(delivered),
          createRequestId: () => 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          refreshTaskList: () async {
            container.invalidate(_countsFixture);
            await container.read(_countsFixture.future);
          },
          refreshCod: () async {
            container.invalidate(_codFixture);
            await container.read(_codFixture.future);
          },
        );
        container = ProviderContainer(
          retry: (_, _) => null,
          overrides: [
            fixtureOutboundCompletionDependenciesProvider.overrideWithValue(
              dependencies,
            ),
            _countsFixture.overrideWith((ref) async {
              countReads++;
              return {
                'inTransit': delivered ? 0 : 1,
                'completed': delivered ? 1 : 0,
              };
            }),
            _codFixture.overrideWith((ref) async {
              if (++codReads == 2 && failCodReload) {
                throw const OutboundCommandFailure(
                  OutboundCommandFailureCode.network,
                );
              }
              return delivered ? 550000 : 0;
            }),
          ],
        );
        addTearDown(container.dispose);
        container.listen(_countsFixture, (_, _) {});
        container.listen(_codFixture, (_, _) {});
        final provider = fixtureOutboundCompletionViewModelProvider(taskId);
        container.listen(provider, (_, _) {});
        await container.read(_countsFixture.future);
        await container.read(_codFixture.future);
        for (var i = 0; i < 20 && !container.read(provider).canComplete; i++) {
          await container.pump();
        }
        expect(container.read(provider).canComplete, true);
        final vm = container.read(provider.notifier);
        final submission = vm.submit(
          receivedAllItems: true,
          receivedFullCod: true,
          displayedAmountVnd: 550000,
        );
        await Future<void>.delayed(Duration.zero);
        expect((await container.read(_countsFixture.future))['completed'], 0);
        expect(await container.read(_codFixture.future), 0);
        expect(countReads, 1);
        expect(codReads, 1);
        ack.complete();
        await submission;
        expect(repository.calls, 1);
        expect((await container.read(_countsFixture.future))['completed'], 1);
        if (failCodReload) {
          expect(container.read(provider).requiresReadRetry, true);
          await vm.retry();
          expect(repository.calls, 1);
        }
        expect(await container.read(_codFixture.future), 550000);
        expect(countReads, 2);
        expect(codReads, failCodReload ? 3 : 2);
        expect(container.read(provider).completionConfirmed, true);
      },
    );
  }
}
