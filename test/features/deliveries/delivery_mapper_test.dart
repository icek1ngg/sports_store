import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_item_dto.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';

import 'fixtures/delivery_dtos.dart';

void main() {
  group('delivery enum wire values', () {
    test('round trip every wire value', () {
      for (final kind in DeliveryTaskKind.values) {
        expect(DeliveryTaskKind.fromValue(kind.value), kind);
      }
      for (final status in DeliveryTaskStatus.values) {
        expect(DeliveryTaskStatus.fromValue(status.value), status);
      }
      for (final scope in DeliverySnapshotScope.values) {
        expect(DeliverySnapshotScope.fromValue(scope.value), scope);
      }
      for (final source in DeliveryItemSource.values) {
        expect(DeliveryItemSource.fromValue(source.value), source);
      }
    });

    test('rejects unknown wire values', () {
      expect(
        () => DeliveryTaskKind.fromValue('pickup'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => DeliveryTaskStatus.fromValue('done'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => DeliverySnapshotScope.fromValue('public'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => DeliveryItemSource.fromValue('catalog'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('DeliveryTaskDto', () {
    test('maps current outbound and normalizes an offset timestamp', () {
      final snapshot = DeliveryTaskDto.fromJson(
        currentTaskDto(
          acceptedAt: '2026-10-23T03:01:02.123456Z',
          startedAt: '2026-10-23T10:02:00+07:00',
        ),
      ).toDomain();

      expect(snapshot.kind, DeliveryTaskKind.outbound);
      expect(snapshot.status, DeliveryTaskStatus.assigned);
      expect(snapshot.scope, DeliverySnapshotScope.current);
      expect(snapshot.orderId, orderId);
      expect(snapshot.returnRequestId, isNull);
      expect(snapshot.amountToCollectVnd, 550000);
      expect(snapshot.destination?.latitude, 21.028511);
      expect(snapshot.destination?.longitude, 105.804817);
      expect(
        snapshot.acceptedAt,
        DateTime.utc(2026, 10, 23, 3, 1, 2, 123, 456),
      );
      expect(snapshot.startedAt, DateTime.utc(2026, 10, 23, 3, 2));
      expect(snapshot.acceptedAt?.isUtc, isTrue);
    });

    test('maps current pickup and redelivery with zero COD', () {
      final pickup = DeliveryTaskDto.fromJson(
        currentTaskDto(
          kind: 'return_pickup',
          returnRequest: returnRequestId,
          amount: '0',
          itemSource: 'return_plan',
        ),
      ).toDomain();
      final redelivery = DeliveryTaskDto.fromJson(
        currentTaskDto(
          kind: 'redelivery',
          returnRequest: returnRequestId,
          amount: 0,
          itemSource: 'unavailable_redelivery_plan',
        ),
      ).toDomain();

      expect(pickup.kind, DeliveryTaskKind.returnPickup);
      expect(pickup.returnRequestId, returnRequestId);
      expect(pickup.itemSource, DeliveryItemSource.returnPlan);
      expect(redelivery.kind, DeliveryTaskKind.redelivery);
      expect(
        redelivery.itemSource,
        DeliveryItemSource.unavailableRedeliveryPlan,
      );
    });

    test('maps every status to its contract scope and source', () {
      for (final status in DeliveryTaskStatus.values) {
        final isCurrent = {
          DeliveryTaskStatus.assigned,
          DeliveryTaskStatus.accepted,
          DeliveryTaskStatus.inTransit,
        }.contains(status);
        final isHistory = {
          DeliveryTaskStatus.delivered,
          DeliveryTaskStatus.cancelled,
          DeliveryTaskStatus.returnedToStore,
        }.contains(status);
        final map = isCurrent
            ? currentTaskDto(status: status.value, itemSource: 'order_snapshot')
            : maskedTaskDto(
                status: status.value,
                scope: isHistory ? 'history' : 'restricted',
              );

        final snapshot = DeliveryTaskDto.fromJson(map).toDomain();
        expect(
          snapshot.scope,
          isCurrent
              ? DeliverySnapshotScope.current
              : isHistory
              ? DeliverySnapshotScope.history
              : DeliverySnapshotScope.restricted,
        );
        expect(
          snapshot.itemSource,
          isCurrent
              ? DeliveryItemSource.orderSnapshot
              : DeliveryItemSource.unavailable,
        );
      }
    });

    test('allows null optional current lifecycle values', () {
      final snapshot = DeliveryTaskDto.fromJson(currentTaskDto()).toDomain();

      expect(snapshot.acceptedAt, isNull);
      expect(snapshot.startedAt, isNull);
      expect(snapshot.completedAt, isNull);
    });

    test('allows omitted nullable lifecycle fields from the projection', () {
      final map = currentTaskDto();
      map
        ..remove('assigned_at')
        ..remove('accepted_at')
        ..remove('started_at')
        ..remove('completed_at');

      final snapshot = DeliveryTaskDto.fromJson(map).toDomain();

      expect(snapshot.assignedAt, isNull);
      expect(snapshot.acceptedAt, isNull);
      expect(snapshot.startedAt, isNull);
      expect(snapshot.completedAt, isNull);
    });

    test('rejects non-null masked fields instead of dropping them', () {
      final map = maskedTaskDto();
      map['destination_name'] = 'should not be visible';
      expect(
        () => DeliveryTaskDto.fromJson(map).toDomain(),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'rejects inconsistent scope, source, kind references and attempts',
      () {
        final wrongScope = maskedTaskDto(scope: 'history');
        expect(
          () => DeliveryTaskDto.fromJson(wrongScope).toDomain(),
          throwsA(isA<FormatException>()),
        );

        final wrongSource = currentTaskDto(itemSource: 'return_plan');
        expect(
          () => DeliveryTaskDto.fromJson(wrongSource).toDomain(),
          throwsA(isA<FormatException>()),
        );

        final wrongKindReference = currentTaskDto(
          kind: 'return_pickup',
          returnRequest: null,
          amount: 0,
          itemSource: 'return_plan',
        );
        expect(
          () => DeliveryTaskDto.fromJson(wrongKindReference).toDomain(),
          throwsA(isA<FormatException>()),
        );

        final wrongAttempt = currentTaskDto();
        wrongAttempt['attempt_number'] = 2;
        wrongAttempt['kind'] = 'return_pickup';
        wrongAttempt['return_request_id'] = returnRequestId;
        wrongAttempt['amount_to_collect_vnd'] = 0;
        wrongAttempt['item_source'] = 'return_plan';
        expect(
          () => DeliveryTaskDto.fromJson(wrongAttempt).toDomain(),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('rejects malformed UUIDs, money, coordinates and timestamps', () {
      final malformedUuid = currentTaskDto();
      malformedUuid['task_id'] = 'not-a-uuid';
      expect(
        () => DeliveryTaskDto.fromJson(malformedUuid),
        throwsA(isA<FormatException>()),
      );

      for (final amount in [1.0, '1.5', '-1', 9007199254740992]) {
        final map = currentTaskDto(amount: amount);
        expect(
          () => DeliveryTaskDto.fromJson(map),
          throwsA(isA<FormatException>()),
          reason: 'amount $amount',
        );
      }

      final badLatitude = currentTaskDto();
      badLatitude['destination_latitude'] = '91.0';
      expect(
        () => DeliveryTaskDto.fromJson(badLatitude),
        throwsA(isA<FormatException>()),
      );

      final badLongitude = currentTaskDto();
      badLongitude['destination_longitude'] = double.infinity;
      expect(
        () => DeliveryTaskDto.fromJson(badLongitude),
        throwsA(isA<FormatException>()),
      );

      for (final timestamp in [
        '2026-02-30T00:00:00Z',
        '2026-10-23T00:00:00',
        '2026-10-23T24:00:00Z',
      ]) {
        final map = currentTaskDto(acceptedAt: timestamp);
        expect(
          () => DeliveryTaskDto.fromJson(map),
          throwsA(isA<FormatException>()),
          reason: 'timestamp $timestamp',
        );
      }
    });
  });

  group('DeliveryTaskItemDto', () {
    test('maps order snapshot and deep-copies nested attributes', () {
      final rawAttributes = <String, dynamic>{
        'color': 'white',
        'nested': <String, dynamic>{'size': '5'},
      };
      final map = outboundItemDto(attributes: rawAttributes);
      final dto = DeliveryTaskItemDto.fromJson(map);
      rawAttributes['color'] = 'black';
      final item = dto.toDomain();

      expect(item.itemSource, DeliveryItemSource.orderSnapshot);
      expect(item.quantity, 2);
      expect(item.unitPriceVnd, 260000);
      expect(item.attributes?['color'], 'white');
      expect(
        () => (item.attributes!['nested'] as Map)['size'] = '10',
        throwsA(anything),
      );
    });

    test('maps return plan without prices and requires collected quantity', () {
      final item = DeliveryTaskItemDto.fromJson(returnItemDto()).toDomain();

      expect(item.itemSource, DeliveryItemSource.returnPlan);
      expect(item.quantityCollected, 1);
      expect(item.unitPriceVnd, isNull);
      expect(item.lineTotalVnd, isNull);
    });

    test('rejects item source field mismatches and unavailable rows', () {
      final priceOnReturn = returnItemDto();
      priceOnReturn['unit_price_vnd'] = 1;
      expect(
        () => DeliveryTaskItemDto.fromJson(priceOnReturn).toDomain(),
        throwsA(isA<FormatException>()),
      );

      final collectedOutbound = outboundItemDto(quantityCollected: 1);
      expect(
        () => DeliveryTaskItemDto.fromJson(collectedOutbound).toDomain(),
        throwsA(isA<FormatException>()),
      );

      final unavailable = outboundItemDto();
      unavailable['item_source'] = 'unavailable';
      unavailable['quantity_collected'] = null;
      expect(
        () => DeliveryTaskItemDto.fromJson(unavailable).toDomain(),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a mismatched outbound line total', () {
      final map = outboundItemDto(lineTotal: 519999);

      expect(
        () => DeliveryTaskItemDto.fromJson(map).toDomain(),
        throwsA(isA<FormatException>()),
      );
    });

    test('checks an overflowing multiplication with BigInt', () {
      final map = outboundItemDto(
        quantity: 9007199254740991,
        unitPrice: 9007199254740991,
        lineTotal: 0,
      );

      expect(
        () => DeliveryTaskItemDto.fromJson(map).toDomain(),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed quantities and money', () {
      for (final quantity in [1.0, '1.5', '-1', 9007199254740992]) {
        final map = outboundItemDto(quantity: quantity);
        expect(
          () => DeliveryTaskItemDto.fromJson(map),
          throwsA(isA<FormatException>()),
          reason: 'quantity $quantity',
        );
      }

      for (final price in [1.5, '-1', 9007199254740992]) {
        final map = outboundItemDto(unitPrice: price);
        expect(
          () => DeliveryTaskItemDto.fromJson(map),
          throwsA(isA<FormatException>()),
          reason: 'price $price',
        );
      }
    });
  });
}
