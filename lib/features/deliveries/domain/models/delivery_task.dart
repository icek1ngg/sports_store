import 'delivery_task_item.dart';

export 'delivery_task_item.dart';

/// The kind of work represented by a delivery task.
enum DeliveryTaskKind {
  outbound('outbound'),
  returnPickup('return_pickup'),
  redelivery('redelivery');

  const DeliveryTaskKind(this.value);

  final String value;

  static DeliveryTaskKind fromValue(String value) {
    for (final kind in values) {
      if (kind.value == value) {
        return kind;
      }
    }
    throw FormatException('Unknown delivery task kind: $value');
  }
}

/// The database status of a delivery task.
enum DeliveryTaskStatus {
  pendingAssignment('pending_assignment'),
  assigned('assigned'),
  accepted('accepted'),
  inTransit('in_transit'),
  delivered('delivered'),
  failed('failed'),
  returnedToStore('returned_to_store'),
  cancelled('cancelled'),
  managerActionRequired('manager_action_required');

  const DeliveryTaskStatus(this.value);

  final String value;

  static DeliveryTaskStatus fromValue(String value) {
    for (final status in values) {
      if (status.value == value) {
        return status;
      }
    }
    throw FormatException('Unknown delivery task status: $value');
  }
}

/// The privacy scope applied by the read projection.
enum DeliverySnapshotScope {
  current('current'),
  restricted('restricted'),
  history('history');

  const DeliverySnapshotScope(this.value);

  final String value;

  static DeliverySnapshotScope fromValue(String value) {
    for (final scope in values) {
      if (scope.value == value) {
        return scope;
      }
    }
    throw FormatException('Unknown delivery snapshot scope: $value');
  }
}

/// The recipient snapshot needed to perform a delivery task.
class DeliveryDestination {
  const DeliveryDestination({
    required this.name,
    required this.phone,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String phone;
  final String address;
  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) {
    return other is DeliveryDestination &&
        name == other.name &&
        phone == other.phone &&
        address == other.address &&
        latitude == other.latitude &&
        longitude == other.longitude;
  }

  @override
  int get hashCode => Object.hash(name, phone, address, latitude, longitude);
}

/// An immutable delivery task projection returned by the read RPC.
class DeliveryTaskSnapshot {
  const DeliveryTaskSnapshot({
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

  @override
  bool operator ==(Object other) {
    return other is DeliveryTaskSnapshot &&
        taskId == other.taskId &&
        kind == other.kind &&
        status == other.status &&
        attemptNumber == other.attemptNumber &&
        scope == other.scope &&
        orderId == other.orderId &&
        returnRequestId == other.returnRequestId &&
        amountToCollectVnd == other.amountToCollectVnd &&
        destination == other.destination &&
        assignedAt == other.assignedAt &&
        acceptedAt == other.acceptedAt &&
        startedAt == other.startedAt &&
        completedAt == other.completedAt &&
        itemSource == other.itemSource;
  }

  @override
  int get hashCode => Object.hash(
    taskId,
    kind,
    status,
    attemptNumber,
    scope,
    orderId,
    returnRequestId,
    amountToCollectVnd,
    destination,
    assignedAt,
    acceptedAt,
    startedAt,
    completedAt,
    itemSource,
  );
}
