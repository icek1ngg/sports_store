import 'package:flutter/material.dart';

import 'delivery_task_list_page.dart';
import 'delivery_task_detail_page.dart';
import 'delivery_task_map_page.dart';

/// MH10 entry point inside the shared, authenticated shipper shell.
class DeliveryTasksRoutePage extends StatelessWidget {
  const DeliveryTasksRoutePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('mh10-outlet'),
      label: 'Danh sách nhiệm vụ giao hàng',
      child: const DeliveryTaskListPage(),
    );
  }
}

/// MH11 read-only task detail inside the shared, authenticated shipper shell.
class DeliveryTaskRoutePage extends StatelessWidget {
  const DeliveryTaskRoutePage({required this.taskId, super.key});

  final String taskId;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('mh11-outlet'),
      label: 'Chi tiết nhiệm vụ giao hàng',
      child: DeliveryTaskDetailPage(taskId: taskId),
    );
  }
}

/// MH18 uses the authorized saved destination from the shared task repository.
class DeliveryTaskMapRoutePage extends StatelessWidget {
  const DeliveryTaskMapRoutePage({required this.taskId, super.key});

  final String taskId;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('mh18-outlet'),
      label: 'Bản đồ điểm đến nhiệm vụ giao hàng',
      child: DeliveryTaskMapPage(taskId: taskId),
    );
  }
}
