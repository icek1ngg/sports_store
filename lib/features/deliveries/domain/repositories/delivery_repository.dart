import '../models/delivery_task.dart';
import '../models/delivery_task_details.dart';
import '../models/delivery_task_query.dart';

abstract interface class DeliveryRepository {
  Future<List<DeliveryTaskSnapshot>> listTasks();
  Future<DeliveryTaskPage> queryTasks(DeliveryTaskQuery query);
  Future<DeliveryTaskSnapshot> getTask(String taskId);
  Future<DeliveryTaskDetails> getTaskDetails(String taskId);
}

/// The separately scoped read contract used by MH18's map projection.
///
/// This remains outside [DeliveryRepository] so existing delivery fakes and
/// non-map consumers keep the strict detail-read contract unchanged.
abstract interface class DeliveryMapReader {
  Future<DeliveryTaskDetails> getMapTaskDetails(String taskId);
}
