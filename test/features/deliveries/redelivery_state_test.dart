import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_details_dto.dart';
import 'package:sports_store/features/deliveries/domain/models/redelivery_command.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/redelivery_view_model.dart';

import 'fixtures/delivery_dtos.dart';

void main() {
  for (final status in ['assigned', 'accepted', 'in_transit']) {
    test(
      'authoritative $status gates next stage after previous confirmation',
      () {
        final task = currentTaskDto(
          kind: 'redelivery',
          status: status,
          returnRequest: returnRequestId,
          amount: 0,
          itemSource: 'return_plan',
        );
        task['accepted_at'] = status == 'assigned'
            ? null
            : '2026-10-23T03:01:00Z';
        task['started_at'] = status == 'in_transit'
            ? '2026-10-23T03:02:00Z'
            : null;
        final details = DeliveryTaskDetailsDto.fromJson({
          'task': task,
          'items': [returnItemDto(quantityCollected: 2)],
          'notes': null,
          'notes_source': 'unavailable_schema',
          'as_of': '2026-10-23T04:00:00Z',
        }, requestedTaskId: taskId).toDomain();
        final state = RedeliveryState(
          details: AsyncData(details),
          acknowledged: status != 'assigned',
          confirmed: status != 'assigned',
          confirmedOperation: status == 'accepted'
              ? RedeliveryOperation.accept
              : status == 'in_transit'
              ? RedeliveryOperation.start
              : null,
        );
        expect(state.canAccept, status == 'assigned');
        expect(state.canStart, status == 'accepted');
        expect(state.canComplete, status == 'in_transit');
        expect(state.copyWith(busy: true).canAccept, isFalse);
        expect(state.copyWith(busy: true).canStart, isFalse);
        expect(state.copyWith(busy: true).canComplete, isFalse);
        expect(
          state.copyWith(acknowledged: true, confirmed: false).canFail,
          isFalse,
        );
        expect(state.copyWith(actionsDenied: true).canComplete, isFalse);
      },
    );
  }
}
