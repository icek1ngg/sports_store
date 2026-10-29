import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_details_dto.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/data/repositories/supabase_delivery_repository.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/domain/repositories/delivery_repository.dart';

import '../support/operational_supabase_fixture.dart';
import 'fixtures/delivery_dtos.dart';

Map<String, dynamic> _detailPayload(Map<String, dynamic> task) => {
  'task': task,
  'items': [outboundItemDto()],
  'notes': null,
  'notes_source': 'unavailable_schema',
  'as_of': '2026-10-23T03:00:00Z',
};

void main() {
  test('destination reports whether both coordinates are usable', () {
    const complete = DeliveryDestination(
      name: 'Nguyễn Văn A',
      phone: '0900000000',
      address: 'Hà Nội',
      latitude: 21.028511,
      longitude: 105.804817,
    );
    const missing = DeliveryDestination(
      name: 'Nguyễn Văn A',
      phone: '0900000000',
      address: 'Hà Nội',
      latitude: null,
      longitude: 105.804817,
    );
    const invalid = DeliveryDestination(
      name: 'Nguyễn Văn A',
      phone: '0900000000',
      address: 'Hà Nội',
      latitude: 91,
      longitude: 105.804817,
    );

    expect(complete.hasValidCoordinates, isTrue);
    expect(missing.hasValidCoordinates, isFalse);
    expect(invalid.hasValidCoordinates, isFalse);
  });

  test(
    'normal task mapper stays strict while map mode accepts missing coords',
    () {
      final task = currentTaskDto()
        ..['destination_latitude'] = null
        ..['destination_longitude'] = null;

      expect(
        () => DeliveryTaskDto.fromJson(task),
        throwsA(isA<FormatException>()),
      );

      final mapped = DeliveryTaskDto.fromJson(
        task,
        allowMissingDestinationCoordinates: true,
      ).toDomain();
      expect(mapped.destination?.name, 'Nguyễn Văn A');
      expect(mapped.destination?.latitude, isNull);
      expect(mapped.destination?.longitude, isNull);
      expect(mapped.destination?.hasValidCoordinates, isFalse);
    },
  );

  test('map mode still rejects malformed or out-of-range coordinates', () {
    for (final entry in {
      'destination_latitude': 91,
      'destination_longitude': double.infinity,
    }.entries) {
      final task = currentTaskDto()..[entry.key] = entry.value;
      expect(
        () => DeliveryTaskDto.fromJson(
          task,
          allowMissingDestinationCoordinates: true,
        ),
        throwsA(isA<FormatException>()),
        reason: entry.key,
      );
    }
  });

  test('detail mapper forwards map-only coordinate allowance', () {
    final task = currentTaskDto()
      ..['destination_latitude'] = null
      ..['destination_longitude'] = null;
    final payload = _detailPayload(task);

    expect(
      () => DeliveryTaskDetailsDto.fromJson(payload, requestedTaskId: taskId),
      throwsA(isA<FormatException>()),
    );
    final mapped = DeliveryTaskDetailsDto.fromJson(
      payload,
      requestedTaskId: taskId,
      allowMissingDestinationCoordinates: true,
    ).toDomain();
    expect(mapped.task.destination?.hasValidCoordinates, isFalse);
  });

  test(
    'map reader uses the authorized detail RPC with map-only allowance',
    () async {
      final task = currentTaskDto()
        ..['destination_latitude'] = null
        ..['destination_longitude'] = null;
      var detailCalls = 0;
      final client = await fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        expect(request.url.path, endsWith('/get_my_delivery_task'));
        detailCalls++;
        return jsonResponse(request, _detailPayload(task));
      });
      final access = OperationalReadAccess(client);
      addTearDown(() async {
        await access.dispose();
        await client.dispose();
      });

      final repository = SupabaseDeliveryRepository(access: access);
      expect(repository, isA<DeliveryMapReader>());
      final details = await repository.getMapTaskDetails(taskId);
      expect(details.task.destination?.latitude, isNull);
      expect(detailCalls, 1);

      await expectLater(
        repository.getTaskDetails(taskId),
        throwsA(
          isA<OperationalFailure>().having(
            (error) => error.code,
            'code',
            OperationalFailureCode.invalidData,
          ),
        ),
      );
      expect(detailCalls, 2);
    },
  );
}
