import '../models/delivery_task.dart';
import '../models/delivery_task_details.dart';

abstract interface class DeliveryRepository {
  Future<List<DeliveryTaskSnapshot>> listTasks();
  Future<DeliveryTaskSnapshot> getTask(String taskId);
  Future<DeliveryTaskDetails> getTaskDetails(String taskId);
}
