import '../../domain/models/return_pickup_command.dart';
import 'dto_readers.dart';

/// Strict decoder for `get_my_return_pickup_handover`.
///
/// This is intentionally a narrow marker projection. It must not be replaced
/// with the task details read or with a return-request/table query, because
/// the marker is what prevents a second handover report after reopening MH11.
final class ReturnPickupHandoverStatusDto {
  const ReturnPickupHandoverStatusDto({
    required this.taskId,
    required this.reported,
    this.reportedAt,
  });

  static const responseKeys = <String>{'task_id', 'reported', 'reported_at'};

  factory ReturnPickupHandoverStatusDto.fromJson(
    Map<String, dynamic> json, {
    required String taskId,
  }) {
    if (json.length != responseKeys.length ||
        json.keys.any((key) => !responseKeys.contains(key))) {
      throw DeliveryDtoReaders.invalid(
        'handover status',
        'exactly task_id, reported and reported_at',
      );
    }
    final returnedTaskId = DeliveryDtoReaders.readRequiredUuid(json, 'task_id');
    if (returnedTaskId.toLowerCase() != taskId.toLowerCase()) {
      throw DeliveryDtoReaders.invalid('task_id', 'the requested task UUID');
    }
    final reported = json['reported'];
    if (reported is! bool) {
      throw DeliveryDtoReaders.invalid('reported', 'a boolean');
    }
    final reportedAt = DeliveryDtoReaders.readNullableTimestamp(
      json,
      'reported_at',
    );
    if (reported && (reportedAt == null || !reportedAt.isUtc)) {
      throw DeliveryDtoReaders.invalid(
        'reported_at',
        'a required UTC timestamp when reported is true',
      );
    }
    if (!reported && reportedAt != null) {
      throw DeliveryDtoReaders.invalid(
        'reported_at',
        'null when reported is false',
      );
    }
    return ReturnPickupHandoverStatusDto(
      taskId: returnedTaskId,
      reported: reported,
      reportedAt: reportedAt,
    );
  }

  final String taskId;
  final bool reported;
  final DateTime? reportedAt;

  ReturnPickupHandoverStatus toDomain() => ReturnPickupHandoverStatus(
    taskId: taskId,
    reported: reported,
    reportedAt: reportedAt,
  );
}

typedef ReturnPickupHandoverDto = ReturnPickupHandoverStatusDto;
