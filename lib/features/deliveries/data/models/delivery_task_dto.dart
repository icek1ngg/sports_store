import '../../domain/models/delivery_task.dart';
import 'dto_readers.dart';

/// DTO for one row from `read_my_delivery_tasks`.
class DeliveryTaskDto {
  const DeliveryTaskDto({
    required this.taskId,
    required this.kind,
    required this.status,
    required this.attemptNumber,
    required this.scope,
    this.orderId,
    this.returnRequestId,
    this.amountToCollectVnd,
    this.destination,
    this.assignedAt,
    this.acceptedAt,
    this.startedAt,
    this.completedAt,
    required this.itemSource,
  });

  factory DeliveryTaskDto.fromJson(Map<String, dynamic> json) {
    final taskId = DeliveryDtoReaders.readRequiredUuid(json, 'task_id');
    final kind = DeliveryTaskKind.fromValue(
      DeliveryDtoReaders.readRequiredString(json, 'kind', nonBlank: false),
    );
    final status = DeliveryTaskStatus.fromValue(
      DeliveryDtoReaders.readRequiredString(json, 'status', nonBlank: false),
    );
    final scope = DeliverySnapshotScope.fromValue(
      DeliveryDtoReaders.readRequiredString(
        json,
        'snapshot_scope',
        nonBlank: false,
      ),
    );
    final destination = _readDestination(json);

    return DeliveryTaskDto(
      taskId: taskId,
      kind: kind,
      status: status,
      attemptNumber: DeliveryDtoReaders.readRequiredInteger(
        json,
        'attempt_number',
      ),
      scope: scope,
      orderId: DeliveryDtoReaders.readNullableUuid(json, 'order_id'),
      returnRequestId: DeliveryDtoReaders.readNullableUuid(
        json,
        'return_request_id',
      ),
      amountToCollectVnd: DeliveryDtoReaders.readNullableInteger(
        json,
        'amount_to_collect_vnd',
      ),
      destination: destination,
      assignedAt: DeliveryDtoReaders.readNullableTimestamp(json, 'assigned_at'),
      acceptedAt: DeliveryDtoReaders.readNullableTimestamp(json, 'accepted_at'),
      startedAt: DeliveryDtoReaders.readNullableTimestamp(json, 'started_at'),
      completedAt: DeliveryDtoReaders.readNullableTimestamp(
        json,
        'completed_at',
      ),
      itemSource: DeliveryItemSource.fromValue(
        DeliveryDtoReaders.readRequiredString(
          json,
          'item_source',
          nonBlank: false,
        ),
      ),
    );
  }

  final String taskId;
  final DeliveryTaskKind kind;
  final DeliveryTaskStatus status;
  final int attemptNumber;
  final DeliverySnapshotScope scope;
  final String? orderId;
  final String? returnRequestId;
  final int? amountToCollectVnd;
  final DeliveryDestination? destination;
  final DateTime? assignedAt;
  final DateTime? acceptedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DeliveryItemSource itemSource;

  DeliveryTaskSnapshot toDomain() {
    _validate();
    return DeliveryTaskSnapshot(
      taskId: taskId,
      kind: kind,
      status: status,
      attemptNumber: attemptNumber,
      scope: scope,
      orderId: orderId,
      returnRequestId: returnRequestId,
      amountToCollectVnd: amountToCollectVnd,
      destination: destination,
      assignedAt: assignedAt?.toUtc(),
      acceptedAt: acceptedAt?.toUtc(),
      startedAt: startedAt?.toUtc(),
      completedAt: completedAt?.toUtc(),
      itemSource: itemSource,
    );
  }

  void _validate() {
    DeliveryDtoReaders.checkUuid(taskId, 'task_id');
    if (orderId != null) {
      DeliveryDtoReaders.checkUuid(orderId!, 'order_id');
    }
    if (returnRequestId != null) {
      DeliveryDtoReaders.checkUuid(returnRequestId!, 'return_request_id');
    }

    if (attemptNumber < 1 || attemptNumber > 2) {
      throw DeliveryDtoReaders.invalid(
        'attempt_number',
        'an integer between 1 and 2',
      );
    }
    if (kind != DeliveryTaskKind.outbound && attemptNumber != 1) {
      throw DeliveryDtoReaders.invalid(
        'attempt_number',
        '1 for a non-outbound task',
      );
    }
    if (amountToCollectVnd != null &&
        (amountToCollectVnd! < 0 || amountToCollectVnd! > 9007199254740991)) {
      throw DeliveryDtoReaders.invalid(
        'amount_to_collect_vnd',
        'a non-negative integer within the JavaScript safe range',
      );
    }

    final expectedScope = _scopeForStatus(status);
    if (scope != expectedScope) {
      throw DeliveryDtoReaders.invalid(
        'snapshot_scope',
        'the scope corresponding to status ${status.value}',
      );
    }

    final expectedItemSource = _itemSourceFor(kind, scope);
    if (itemSource != expectedItemSource) {
      throw DeliveryDtoReaders.invalid(
        'item_source',
        'the source corresponding to kind ${kind.value} and scope ${scope.value}',
      );
    }

    _validateTimestamps();
    if (scope == DeliverySnapshotScope.current) {
      _validateCurrentFields();
    } else {
      _validateMaskedFields();
    }
  }

  void _validateCurrentFields() {
    if (orderId == null) {
      throw DeliveryDtoReaders.invalid('order_id', 'a UUID for a current task');
    }
    if (kind == DeliveryTaskKind.outbound) {
      if (returnRequestId != null) {
        throw DeliveryDtoReaders.invalid(
          'return_request_id',
          'null for an outbound task',
        );
      }
    } else if (returnRequestId == null) {
      throw DeliveryDtoReaders.invalid(
        'return_request_id',
        'a UUID for a return task',
      );
    }
    if (amountToCollectVnd == null) {
      throw DeliveryDtoReaders.invalid(
        'amount_to_collect_vnd',
        'a value for a current task',
      );
    }
    if (kind != DeliveryTaskKind.outbound && amountToCollectVnd != 0) {
      throw DeliveryDtoReaders.invalid(
        'amount_to_collect_vnd',
        '0 for a non-outbound task',
      );
    }
    if (destination == null) {
      throw DeliveryDtoReaders.invalid(
        'destination',
        'all destination fields for a current task',
      );
    }
    _validateDestination(destination!);
  }

  void _validateMaskedFields() {
    if (orderId != null ||
        returnRequestId != null ||
        amountToCollectVnd != null ||
        destination != null ||
        assignedAt != null ||
        acceptedAt != null ||
        startedAt != null) {
      throw DeliveryDtoReaders.invalid(
        'snapshot_scope',
        'masked order, destination and lifecycle fields for a non-current task',
      );
    }
  }

  void _validateTimestamps() {
    for (final timestamp in [assignedAt, acceptedAt, startedAt, completedAt]) {
      if (timestamp != null && !timestamp.isUtc) {
        throw DeliveryDtoReaders.invalid(
          'timestamp',
          'a UTC timestamp normalized from an offset',
        );
      }
    }
  }

  static DeliverySnapshotScope _scopeForStatus(DeliveryTaskStatus status) {
    return switch (status) {
      DeliveryTaskStatus.assigned ||
      DeliveryTaskStatus.accepted ||
      DeliveryTaskStatus.inTransit => DeliverySnapshotScope.current,
      DeliveryTaskStatus.delivered ||
      DeliveryTaskStatus.cancelled ||
      DeliveryTaskStatus.returnedToStore => DeliverySnapshotScope.history,
      DeliveryTaskStatus.pendingAssignment ||
      DeliveryTaskStatus.failed ||
      DeliveryTaskStatus.managerActionRequired =>
        DeliverySnapshotScope.restricted,
    };
  }

  static DeliveryItemSource _itemSourceFor(
    DeliveryTaskKind kind,
    DeliverySnapshotScope scope,
  ) {
    if (scope != DeliverySnapshotScope.current) {
      return DeliveryItemSource.unavailable;
    }
    return switch (kind) {
      DeliveryTaskKind.outbound => DeliveryItemSource.orderSnapshot,
      DeliveryTaskKind.returnPickup => DeliveryItemSource.returnPlan,
      DeliveryTaskKind.redelivery =>
        DeliveryItemSource.unavailableRedeliveryPlan,
    };
  }

  static void _validateDestination(DeliveryDestination destination) {
    if (destination.name.trim().isEmpty ||
        destination.phone.trim().isEmpty ||
        destination.address.trim().isEmpty) {
      throw DeliveryDtoReaders.invalid(
        'destination',
        'non-blank name, phone and address',
      );
    }
    if (!destination.latitude.isFinite ||
        destination.latitude < -90 ||
        destination.latitude > 90) {
      throw DeliveryDtoReaders.invalid(
        'destination_latitude',
        'a finite coordinate in [-90, 90]',
      );
    }
    if (!destination.longitude.isFinite ||
        destination.longitude < -180 ||
        destination.longitude > 180) {
      throw DeliveryDtoReaders.invalid(
        'destination_longitude',
        'a finite coordinate in [-180, 180]',
      );
    }
  }

  static DeliveryDestination? _readDestination(Map<String, dynamic> json) {
    final name = DeliveryDtoReaders.readNullableString(
      json,
      'destination_name',
    );
    final phone = DeliveryDtoReaders.readNullableString(
      json,
      'destination_phone',
    );
    final address = DeliveryDtoReaders.readNullableString(
      json,
      'destination_address',
    );
    final latitude = DeliveryDtoReaders.readNullableCoordinate(
      json,
      'destination_latitude',
      minimum: -90,
      maximum: 90,
    );
    final longitude = DeliveryDtoReaders.readNullableCoordinate(
      json,
      'destination_longitude',
      minimum: -180,
      maximum: 180,
    );

    final fields = [name, phone, address, latitude, longitude];
    if (fields.every((field) => field == null)) {
      return null;
    }
    if (fields.any((field) => field == null)) {
      throw DeliveryDtoReaders.invalid(
        'destination',
        'all destination fields or all null',
      );
    }
    return DeliveryDestination(
      name: name!,
      phone: phone!,
      address: address!,
      latitude: latitude!,
      longitude: longitude!,
    );
  }
}
