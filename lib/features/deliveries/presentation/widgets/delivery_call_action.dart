import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/platform_delivery_phone_dialer.dart';
import '../../data/repositories/operational_providers.dart';
import '../../domain/models/delivery_task.dart';
import '../../domain/repositories/delivery_phone_dialer.dart';
import '../view_models/delivery_task_detail_view_model.dart';

final deliveryPhoneDialerProvider = Provider<DeliveryPhoneDialer>(
  (ref) => const PlatformDeliveryPhoneDialer(),
);

class DeliveryCallAction extends ConsumerStatefulWidget {
  const DeliveryCallAction({required this.task, super.key});
  final DeliveryTaskSnapshot task;
  @override
  ConsumerState<DeliveryCallAction> createState() => _DeliveryCallActionState();
}

class _DeliveryCallActionState extends ConsumerState<DeliveryCallAction> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final phone = widget.task.destination?.phone;
    final normalized = phone?.replaceAll(RegExp(r'[\s().-]'), '');
    final valid =
        widget.task.scope == DeliverySnapshotScope.current &&
        normalized != null &&
        RegExp(r'^\+?[0-9]{8,15}$').hasMatch(normalized);
    return OutlinedButton.icon(
      key: const ValueKey('task-detail-call'),
      onPressed: valid && !_busy ? () => _open(normalized) : null,
      icon: const Icon(Icons.phone_outlined),
      label: const Text('Gọi điện'),
    );
  }

  Future<void> _open(String phone) async {
    final expected = widget.task;
    final session = ref.read(operationalSessionProvider).asData?.value;
    if (session == null || session.userId == null || session.failure != null) {
      return;
    }
    final current = ref.read(
      deliveryTaskDetailViewModelProvider(expected.taskId),
    );
    if (!current.hasValue ||
        current.isLoading ||
        current.requireValue.task != expected) {
      return;
    }
    setState(() => _busy = true);
    final result = await ref
        .read(deliveryPhoneDialerProvider)
        .openDialer(Uri(scheme: 'tel', path: phone));
    if (!mounted) return;
    setState(() => _busy = false);
    if (result != DialerOpenOutcome.opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không mở được trình quay số trên thiết bị này.'),
        ),
      );
    }
  }
}
