import 'package:flutter/material.dart';

/// Temporary outlet for MH10 until the shared shipper shell is integrated.
class DeliveryTasksRoutePage extends StatelessWidget {
  const DeliveryTasksRoutePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('mh10-outlet'),
      label: 'Danh sách nhiệm vụ giao hàng',
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Giao diện danh sách nhiệm vụ chưa được tích hợp.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// Temporary outlet for MH11 until the shared shipper shell is integrated.
class DeliveryTaskRoutePage extends StatelessWidget {
  const DeliveryTaskRoutePage({required this.taskId, super.key});

  final String taskId;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('mh11-outlet'),
      label: 'Chi tiết nhiệm vụ giao hàng',
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Giao diện chi tiết nhiệm vụ chưa được tích hợp.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// Temporary outlet for MH18 until the shared map shell is integrated.
class DeliveryTaskMapRoutePage extends StatelessWidget {
  const DeliveryTaskMapRoutePage({required this.taskId, super.key});

  final String taskId;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('mh18-outlet'),
      label: 'Bản đồ điểm đến nhiệm vụ giao hàng',
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Giao diện bản đồ điểm đến nhiệm vụ chưa được tích hợp.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
