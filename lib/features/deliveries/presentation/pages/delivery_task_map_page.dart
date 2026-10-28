import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/maps/map_directions.dart';
import '../../../../core/maps/map_providers.dart';
import '../../../../core/maps/saved_destination_map.dart';
import '../../domain/models/delivery_task.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../domain/models/operational_failure.dart';
import '../../domain/repositories/delivery_phone_dialer.dart';
import '../view_models/delivery_task_map_view_model.dart';
import '../widgets/delivery_call_action.dart';

/// MH18 — the saved destination map for the currently assigned task.
///
/// The route carries only a task UUID.  The task projection supplies the
/// recipient snapshot again and the server-backed read gate decides whether
/// it is still safe to display.
class DeliveryTaskMapPage extends ConsumerStatefulWidget {
  const DeliveryTaskMapPage({required this.taskId, super.key});

  final String taskId;

  @override
  ConsumerState<DeliveryTaskMapPage> createState() =>
      _DeliveryTaskMapPageState();
}

class _DeliveryTaskMapPageState extends ConsumerState<DeliveryTaskMapPage> {
  int _recenterToken = 0;
  bool _actionBusy = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deliveryTaskMapViewModelProvider(widget.taskId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Điểm đến nhiệm vụ'),
        actions: [
          IconButton(
            key: const ValueKey('mh18-refresh'),
            tooltip: 'Tải lại',
            onPressed: state.isLoading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            _MapError(error: error, onRetry: _refresh),
        data: (details) => _buildData(context, details),
      ),
    );
  }

  Widget _buildData(BuildContext context, DeliveryTaskDetails details) {
    final vm = ref.read(
      deliveryTaskMapViewModelProvider(widget.taskId).notifier,
    );
    final task = details.task;
    final destination = task.destination;
    if (task.scope != DeliverySnapshotScope.current || destination == null) {
      return const _RestrictedMap();
    }

    final savedDestination = vm.destinationFrom(details);
    final tileSource = ref.watch(mapTileSourceProvider);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        key: const ValueKey('mh18-content'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _TaskHeading(task: task),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SavedDestinationMap(
              key: ValueKey('mh18-map-$_recenterToken'),
              destination: savedDestination,
              tileSource: tileSource,
              recenterToken: _recenterToken,
              onTileError: (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Nền bản đồ đang lỗi. Bạn vẫn có thể dùng địa chỉ và mở chỉ đường.',
                      ),
                    ),
                  );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Bản đồ © OpenStreetMap contributors',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.mute),
          ),
          const SizedBox(height: 14),
          _RecipientCard(
            task: task,
            onCall: _callRecipient,
            onCopyAddress: _copyAddress,
            onDirections: _openDirections,
            onRecenter: () => setState(() => _recenterToken++),
            busy: _actionBusy,
          ),
          const SizedBox(height: 12),
          _NotesCard(details: details),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    await ref
        .read(deliveryTaskMapViewModelProvider(widget.taskId).notifier)
        .refresh();
  }

  Future<void> _callRecipient(DeliveryTaskSnapshot expected) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final details = await _freshDetails();
      final destination = details.task.destination!;
      final phone = destination.phone.replaceAll(RegExp(r'[\s().-]'), '');
      if (!RegExp(r'^\+?[0-9]{8,15}$').hasMatch(phone)) {
        _showMessage('Số điện thoại người nhận không hợp lệ.');
        return;
      }
      final outcome = await ref
          .read(deliveryPhoneDialerProvider)
          .openDialer(Uri(scheme: 'tel', path: phone));
      if (!mounted) return;
      if (outcome != DialerOpenOutcome.opened) {
        _showMessage('Không mở được trình quay số trên thiết bị này.');
      }
    } on Object catch (error) {
      if (mounted) _showMessage(_failureMessage(error));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _copyAddress(DeliveryTaskSnapshot expected) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final details = await _freshDetails();
      await Clipboard.setData(
        ClipboardData(text: details.task.destination!.address),
      );
      if (mounted) _showMessage('Đã sao chép địa chỉ điểm đến.');
    } on Object catch (error) {
      if (mounted) _showMessage(_failureMessage(error));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _openDirections(DeliveryTaskSnapshot expected) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final outcome = await ref
          .read(deliveryTaskMapViewModelProvider(widget.taskId).notifier)
          .openDirections();
      if (!mounted) return;
      _showMessage(_directionsMessage(outcome));
    } on Object catch (error) {
      if (mounted) _showMessage(_failureMessage(error));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<DeliveryTaskDetails> _freshDetails() async {
    final details = await ref
        .read(deliveryTaskMapViewModelProvider(widget.taskId).notifier)
        .recheckAuthorizedDetails();
    if (!mounted) {
      throw const OperationalFailure(OperationalFailureCode.sessionExpired);
    }
    return details;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _failureMessage(Object error) {
    if (error is OperationalFailure) return error.message;
    return 'Không thể thực hiện thao tác. Vui lòng thử lại.';
  }

  String _directionsMessage(MapDirectionsOutcome outcome) {
    return switch (outcome) {
      MapDirectionsOutcome.opened => 'Đã mở Google Maps để chỉ đường.',
      MapDirectionsOutcome.unavailable =>
        'Thiết bị không có ứng dụng/dịch vụ chỉ đường khả dụng.',
      MapDirectionsOutcome.failed =>
        'Không mở được dịch vụ chỉ đường. Bạn có thể thử lại.',
      MapDirectionsOutcome.invalidDestination =>
        'Tọa độ điểm đến không hợp lệ; địa chỉ vẫn được giữ để bạn sao chép.',
    };
  }
}

class _TaskHeading extends StatelessWidget {
  const _TaskHeading({required this.task});

  final DeliveryTaskSnapshot task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.location_on_outlined, color: AppColors.sale),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _kindLabel(task.kind),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Trạng thái: ${_statusLabel(task.status)} · Lần ${task.attemptNumber}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.mute,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecipientCard extends StatelessWidget {
  const _RecipientCard({
    required this.task,
    required this.onCall,
    required this.onCopyAddress,
    required this.onDirections,
    required this.onRecenter,
    required this.busy,
  });

  final DeliveryTaskSnapshot task;
  final ValueChanged<DeliveryTaskSnapshot> onCall;
  final ValueChanged<DeliveryTaskSnapshot> onCopyAddress;
  final ValueChanged<DeliveryTaskSnapshot> onDirections;
  final VoidCallback onRecenter;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final destination = task.destination!;
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              destination.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              destination.phone,
              key: const ValueKey('mh18-phone'),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.home_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    destination.address,
                    key: const ValueKey('mh18-address'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('mh18-call'),
                  onPressed: busy ? null : () => onCall(task),
                  icon: const Icon(Icons.phone_outlined),
                  label: const Text('Gọi điện'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('mh18-copy'),
                  onPressed: busy ? null : () => onCopyAddress(task),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Sao chép địa chỉ'),
                ),
                FilledButton.icon(
                  key: const ValueKey('mh18-directions'),
                  onPressed: busy ? null : () => onDirections(task),
                  icon: const Icon(Icons.directions_outlined),
                  label: const Text('Mở chỉ đường'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('mh18-recenter'),
                  onPressed: busy ? null : onRecenter,
                  icon: const Icon(Icons.my_location_outlined),
                  label: const Text('Đưa về điểm đến'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.details});

  final DeliveryTaskDetails details;

  @override
  Widget build(BuildContext context) {
    final notes = details.notes;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.notes_outlined),
        title: const Text('Ghi chú giao nhận'),
        subtitle: Text(
          notes?.trim().isNotEmpty == true
              ? notes!
              : 'Ghi chú chưa có trong dữ liệu nhiệm vụ được cấp quyền.',
        ),
      ),
    );
  }
}

class _MapError extends StatelessWidget {
  const _MapError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error is OperationalFailure
        ? (error as OperationalFailure).message
        : 'Không thể tải điểm đến nhiệm vụ.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_outlined, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('mh18-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestrictedMap extends StatelessWidget {
  const _RestrictedMap();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Điểm đến không còn được cấp quyền. Hãy quay lại và tải lại nhiệm vụ.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

String _kindLabel(DeliveryTaskKind kind) => switch (kind) {
  DeliveryTaskKind.outbound => 'Điểm giao hàng',
  DeliveryTaskKind.returnPickup => 'Điểm nhận hàng trả',
  DeliveryTaskKind.redelivery => 'Điểm giao lại',
};

String _statusLabel(DeliveryTaskStatus status) => switch (status) {
  DeliveryTaskStatus.pendingAssignment => 'Chờ phân công',
  DeliveryTaskStatus.assigned => 'Đã phân công',
  DeliveryTaskStatus.accepted => 'Đã nhận hàng',
  DeliveryTaskStatus.inTransit => 'Đang vận chuyển',
  DeliveryTaskStatus.delivered => 'Đã giao',
  DeliveryTaskStatus.failed => 'Giao thất bại',
  DeliveryTaskStatus.returnedToStore => 'Đã về cửa hàng',
  DeliveryTaskStatus.cancelled => 'Đã hủy',
  DeliveryTaskStatus.managerActionRequired => 'Chờ cửa hàng xử lý',
};
