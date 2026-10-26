import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/data/repositories/platform_delivery_phone_dialer.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/repositories/delivery_phone_dialer.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_task_detail_view_model.dart';
import 'package:sports_store/features/deliveries/presentation/widgets/delivery_call_action.dart';

import 'fixtures/delivery_dtos.dart';

class _Dialer implements DeliveryPhoneDialer {
  final uris = <Uri>[];
  @override
  Future<DialerOpenOutcome> openDialer(Uri uri) async {
    uris.add(uri);
    return DialerOpenOutcome.opened;
  }
}

class _Detail extends DeliveryTaskDetailViewModel {
  _Detail(this.details) : super(taskId);
  final DeliveryTaskDetails details;
  @override
  AsyncValue<DeliveryTaskDetails> build() => AsyncData(details);
}

void main() {
  for (final signedIn in [true, false]) {
    testWidgets('call opens only tel composer when authorized ($signedIn)', (
      tester,
    ) async {
      final details = DeliveryTaskDetails(
        task: DeliveryTaskDto.fromJson(currentTaskDto()).toDomain(),
        items: const [],
      );
      final dialer = _Dialer();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            operationalSessionProvider.overrideWithValue(
              AsyncData(
                OperationalSession(
                  userId: signedIn ? 'shipper' : null,
                  generation: 1,
                ),
              ),
            ),
            deliveryPhoneDialerProvider.overrideWithValue(dialer),
            deliveryTaskDetailViewModelProvider(taskId)
                .overrideWith(() => _Detail(details)),
          ],
          child: MaterialApp(
            home: Scaffold(body: DeliveryCallAction(task: details.task)),
          ),
        ),
      );
      expect(dialer.uris, isEmpty);
      await tester.tap(find.byKey(const ValueKey('task-detail-call')));
      await tester.pumpAndSettle();
      expect(dialer.uris, signedIn ? [Uri.parse('tel:0900000000')] : isEmpty);
    });
  }
  test('platform dialer rejects arbitrary schemes, query and USSD', () async {
    const dialer = PlatformDeliveryPhoneDialer();
    for (final raw in [
      'https://example.invalid',
      'tel:0900000000?x=1',
      'tel:*123%23',
      'tel://host/0900000000',
    ]) {
      expect(await dialer.openDialer(Uri.parse(raw)), DialerOpenOutcome.failed);
    }
  });
}
