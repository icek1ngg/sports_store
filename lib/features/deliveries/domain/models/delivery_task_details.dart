import 'delivery_task.dart';

class DeliveryTaskDetails {
  DeliveryTaskDetails({
    required this.task,
    required List<DeliveryTaskItem> items,
  }) : items = List.unmodifiable(items);

  final DeliveryTaskSnapshot task;
  final List<DeliveryTaskItem> items;

  bool get itemsAvailable =>
      task.itemSource == DeliveryItemSource.orderSnapshot ||
      task.itemSource == DeliveryItemSource.returnPlan;
}
