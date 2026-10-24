import '../models/delivery_task.dart';
import '../models/delivery_task_details.dart';
import '../models/delivery_task_query.dart';

abstract interface class DeliveryRepository {
  Future<List<DeliveryTaskSnapshot>> listTasks();
  Future<DeliveryTaskPage> queryTasks(DeliveryTaskQuery query);
  Future<DeliveryTaskSnapshot> getTask(String taskId);
  Future<DeliveryTaskDetails> getTaskDetails(String taskId);
}
