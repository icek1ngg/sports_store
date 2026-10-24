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

class DeliveryTaskDetails {
  DeliveryTaskDetails({
    required this.task,
    required List<DeliveryTaskItem> items,
    this.notes,
    this.notesSource = DeliveryNotesSource.unavailableSchema,
    this.asOf,
  }) : items = List.unmodifiable(items);

  final DeliveryTaskSnapshot task;
  final List<DeliveryTaskItem> items;
  final String? notes;
  final DeliveryNotesSource notesSource;
  final DateTime? asOf;

  bool get itemsAvailable =>
      task.itemSource == DeliveryItemSource.orderSnapshot ||
      task.itemSource == DeliveryItemSource.returnPlan;
}
