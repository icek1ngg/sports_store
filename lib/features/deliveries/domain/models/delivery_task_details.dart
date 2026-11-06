import 'delivery_task.dart';

/// Availability of task notes in the authorized detail projection.
///
/// Notes are not present in the current delivery-task schema. Keeping this
/// explicit prevents an adapter or UI from presenting an invented note as if
/// it came from Supabase.
enum DeliveryNotesSource {
  unavailableSchema('unavailable_schema');

  const DeliveryNotesSource(this.value);

  final String value;

  static DeliveryNotesSource fromValue(String value) {
    for (final source in values) {
      if (source.value == value) return source;
    }
    throw FormatException('Unknown delivery notes source: $value');
  }
}

enum DeliveryCodStatus {
  uncollected('uncollected'),
  collected('collected'),
  received('received');

  const DeliveryCodStatus(this.value);
  final String value;

  static DeliveryCodStatus fromValue(String value) {
    for (final status in values) {
      if (status.value == value) return status;
    }
    throw FormatException('Unknown delivery COD status: $value');
  }
}

class DeliveryCodSnapshot {
  const DeliveryCodSnapshot({
    required this.status,
    required this.expectedAmountVnd,
    required this.collectedAmountVnd,
    required this.receivedAmountVnd,
    this.collectedAt,
    this.handedOverAt,
    this.receivedAt,
  });

  final DeliveryCodStatus status;
  final int expectedAmountVnd;
  final int collectedAmountVnd;
  final int receivedAmountVnd;
  final DateTime? collectedAt;
  final DateTime? handedOverAt;
  final DateTime? receivedAt;
}

class DeliveryTaskDetails {
  DeliveryTaskDetails({
    required this.task,
    required List<DeliveryTaskItem> items,
    this.notes,
    this.notesSource = DeliveryNotesSource.unavailableSchema,
    this.asOf,
    this.cod,
    this.canRetry = false,
  }) : items = List.unmodifiable(items);

  final DeliveryTaskSnapshot task;
  final List<DeliveryTaskItem> items;
  final String? notes;
  final DeliveryNotesSource notesSource;
  final DateTime? asOf;
  final DeliveryCodSnapshot? cod;
  final bool canRetry;

  bool get itemsAvailable =>
      task.itemSource == DeliveryItemSource.orderSnapshot ||
      task.itemSource == DeliveryItemSource.returnPlan;
}
