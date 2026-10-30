import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_details_dto.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';

import 'fixtures/delivery_dtos.dart';

Map<String, dynamic> detailPayload({
  Map<String, dynamic>? task,
  List<Map<String, dynamic>>? items,
  Object? notes,
  String notesSource = 'unavailable_schema',
  Object asOf = '2026-10-23T03:00:00Z',
}) {
  return {
    'task': task ?? currentTaskDto(),
    'items': items ?? [outboundItemDto()],
    'notes': notes,
    'notes_source': notesSource,
    'as_of': asOf,
  };
}

void main() {
  for (final image in [null, 'https://example.com/product.webp']) {
    test('full detail response accepts approved image_url ($image)', () {
      final item = outboundItemDto()..['image_url'] = image;
      final detail = DeliveryTaskDetailsDto.fromJson(
        detailPayload(items: [item]),
        requestedTaskId: taskId,
      ).toDomain();
      expect(detail.items.single.imageUrl, image);
      expect(detail.items.single.quantity, 2);
      expect(detail.task.amountToCollectVnd, 550000);
      item['refund_bank_account'] = 'must not be accepted';
      expect(
        () => DeliveryTaskDetailsDto.fromJson(
          detailPayload(items: [item]),
          requestedTaskId: taskId,
        ),
        throwsFormatException,
      );
    });
  }
  test('immutable redelivery plan accepts safe variant snapshot only for current redelivery', () {
    final item = {
      ...returnItemDto(quantityCollected: 2),
      'variant_label': 'Size M',
      'attributes': {'size': 'M'},
    };
    final payload = detailPayload(
      task: currentTaskDto(
        kind: 'redelivery',
        returnRequest: returnRequestId,
        amount: 0,
        itemSource: 'return_plan',
      ),
      items: [item],
    );
    final detail = DeliveryTaskDetailsDto.fromJson(
      payload,
      requestedTaskId: taskId,
    ).toDomain();
    expect(detail.items.single.variantLabel, 'Size M');
    expect(detail.items.single.quantityCollected, 2);
    expect(detail.task.amountToCollectVnd, 0);
    expect(
      () => DeliveryTaskDetailsDto.fromJson(
        detailPayload(
          task: currentTaskDto(
            kind: 'return_pickup',
            returnRequest: returnRequestId,
            amount: 0,
            itemSource: 'return_plan',
          ),
          items: [item],
        ),
        requestedTaskId: taskId,
      ).toDomain(),
      throwsFormatException,
    );
  });
  test('maps an outbound snapshot without inventing notes or changing COD', () {
    final details = DeliveryTaskDetailsDto.fromJson(
      detailPayload(),
      requestedTaskId: taskId,
    ).toDomain();

    expect(details.task.taskId, taskId);
    expect(details.task.amountToCollectVnd, 550000);
    expect(details.items.single.itemSource, DeliveryItemSource.orderSnapshot);
    expect(details.items.single.quantity, 2);
    expect(details.notes, isNull);
    expect(details.notesSource, DeliveryNotesSource.unavailableSchema);
    expect(details.asOf, DateTime.utc(2026, 10, 23, 3));
    expect(() => details.items.clear(), throwsUnsupportedError);
  });

  test('maps return-pickup item projection and redelivery as unavailable', () {
    final pickup = DeliveryTaskDetailsDto.fromJson(
      detailPayload(
        task: currentTaskDto(
          kind: 'return_pickup',
          status: 'accepted',
          returnRequest: returnRequestId,
          amount: 0,
          itemSource: 'return_plan',
        ),
        items: [returnItemDto()],
        asOf: '2026-10-23T10:00:00+07:00',
      ),
      requestedTaskId: taskId,
    ).toDomain();
    expect(pickup.task.kind, DeliveryTaskKind.returnPickup);
    expect(pickup.task.assignedAt, DateTime.utc(2026, 10, 23, 3));
    expect(pickup.task.assignedAt!.isUtc, isTrue);
    expect(pickup.task.acceptedAt, isNull);
    expect(pickup.task.startedAt, isNull);
    expect(pickup.items.single.quantityCollected, 1);
    expect(pickup.items.single.variantLabel, isNull);
    expect(pickup.items.single.attributes, isNull);
    expect(pickup.items.single.unitPriceVnd, isNull);
    expect(pickup.items.single.lineTotalVnd, isNull);
    expect(pickup.asOf, DateTime.utc(2026, 10, 23, 3));
    expect(pickup.asOf!.isUtc, isTrue);
    expect(pickup.itemsAvailable, isTrue);

    final redelivery = DeliveryTaskDetailsDto.fromJson(
      detailPayload(
        task: currentTaskDto(
          kind: 'redelivery',
          returnRequest: returnRequestId,
          amount: 0,
          itemSource: 'unavailable_redelivery_plan',
        ),
        items: const [],
      ),
      requestedTaskId: taskId,
    ).toDomain();
    expect(redelivery.items, isEmpty);
    expect(redelivery.itemsAvailable, isFalse);
  });

  test('history and restricted task projections stay masked and item-free', () {
    for (final task in [
      maskedTaskDto(status: 'delivered', scope: 'history'),
      maskedTaskDto(status: 'failed', scope: 'restricted'),
    ]) {
      final details = DeliveryTaskDetailsDto.fromJson(
        detailPayload(task: task, items: const []),
        requestedTaskId: taskId,
      ).toDomain();
      expect(details.task.destination, isNull);
      expect(details.task.orderId, isNull);
      expect(details.task.amountToCollectVnd, isNull);
      expect(details.items, isEmpty);
    }
  });

  test('rejects wrong identity, leaked fields, and malformed envelope', () {
    final wrongId = detailPayload(task: currentTaskDto(task: orderId));
    expect(
      () => DeliveryTaskDetailsDto.fromJson(wrongId, requestedTaskId: taskId),
      throwsA(isA<FormatException>()),
    );

    final leaked = detailPayload()..['bank_account'] = 'do-not-accept';
    expect(
      () => DeliveryTaskDetailsDto.fromJson(leaked, requestedTaskId: taskId),
      throwsA(isA<FormatException>()),
    );

    final taskLeak = detailPayload(
      task: currentTaskDto()..['refund_bank_account'] = 'do-not-accept',
    );
    expect(
      () => DeliveryTaskDetailsDto.fromJson(taskLeak, requestedTaskId: taskId),
      throwsA(isA<FormatException>()),
    );

    final itemLeak = detailPayload(
      items: [outboundItemDto()..['storage_asset_url'] = 'do-not-accept'],
    );
    expect(
      () => DeliveryTaskDetailsDto.fromJson(itemLeak, requestedTaskId: taskId),
      throwsA(isA<FormatException>()),
    );

    final nonNullNotes = detailPayload(notes: 'invented');
    expect(
      () => DeliveryTaskDetailsDto.fromJson(
        nonNullNotes,
        requestedTaskId: taskId,
      ),
      throwsA(isA<FormatException>()),
    );

    final wrongNotesSource = detailPayload(notesSource: 'customer_notes');
    expect(
      () => DeliveryTaskDetailsDto.fromJson(
        wrongNotesSource,
        requestedTaskId: taskId,
      ),
      throwsA(isA<FormatException>()),
    );

    final missingNotes = detailPayload()..remove('notes');
    expect(
      () => DeliveryTaskDetailsDto.fromJson(
        missingNotes,
        requestedTaskId: taskId,
      ),
      throwsA(isA<FormatException>()),
    );

    final missingAsOf = detailPayload()..remove('as_of');
    expect(
      () =>
          DeliveryTaskDetailsDto.fromJson(missingAsOf, requestedTaskId: taskId),
      throwsA(isA<FormatException>()),
    );

    final nonTimezoneAsOf = detailPayload(asOf: '2026-10-23T03:00:00');
    expect(
      () => DeliveryTaskDetailsDto.fromJson(
        nonTimezoneAsOf,
        requestedTaskId: taskId,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects duplicate or cross-source item rows', () {
    final duplicate = detailPayload(
      items: [outboundItemDto(), outboundItemDto()],
    );
    expect(
      () => DeliveryTaskDetailsDto.fromJson(duplicate, requestedTaskId: taskId),
      throwsA(isA<FormatException>()),
    );

    final crossSource = detailPayload(items: [returnItemDto()]);
    expect(
      () =>
          DeliveryTaskDetailsDto.fromJson(crossSource, requestedTaskId: taskId),
      throwsA(isA<FormatException>()),
    );

    final historyWithItems = detailPayload(
      task: maskedTaskDto(status: 'delivered', scope: 'history'),
      items: [outboundItemDto()],
    );
    expect(
      () => DeliveryTaskDetailsDto.fromJson(
        historyWithItems,
        requestedTaskId: taskId,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
