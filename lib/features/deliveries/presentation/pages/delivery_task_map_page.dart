import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/maps/map_directions.dart';
import '../../../../core/maps/map_providers.dart';
import '../../domain/models/delivery_task.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../domain/models/operational_failure.dart';
import '../../domain/repositories/delivery_phone_dialer.dart';
import '../../data/repositories/operational_providers.dart';
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

class _DeliveryTaskMapPageState extends ConsumerState<DeliveryTaskMapPage>
    with WidgetsBindingObserver {
  int _recenterToken = 0;
  bool _actionBusy = false;
  bool _tileFailed = false;
  bool _foreground = true;
  bool _protected = false;
  int _checksInFlight = 0;
  int _visibilityEpoch = 0;
  Object? _resumeError;
  MapDirectionsOutcome? _navigationFailure;
  Timer? _accessTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _protected = !_foreground;
    // This is a bounded foreground check, not a realtime revocation channel.
    _accessTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_foreground && !_actionBusy && _checksInFlight == 0) {
        unawaited(_verifyAccess());
      }
    });
  }

  @override
  void dispose() {
    _accessTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    _visibilityEpoch++;
    _foreground = lifecycle == AppLifecycleState.resumed;
    setState(() {
      _protected = true;
      _resumeError = null;
      _navigationFailure = null;
    });
    if (_foreground) unawaited(_verifyAccess());
  }

  Future<void> _verifyAccess() async {
    if (!mounted || !_foreground) return;
    final epoch = _visibilityEpoch;
    _checksInFlight++;
    try {
      await ref
          .read(deliveryTaskMapViewModelProvider(widget.taskId).notifier)
          .recheckAuthorizedDetails();
      if (mounted && _foreground && epoch == _visibilityEpoch) {
        setState(() {
          _protected = false;
          _resumeError = null;
        });
      }
    } on Object catch (error) {
      if (mounted && epoch == _visibilityEpoch) {
        setState(() => _resumeError = error);
      }
    } finally {
      if (mounted) _checksInFlight--;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deliveryTaskMapViewModelProvider(widget.taskId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('BẢN ĐỒ GIAO NHẬN'),
        actions: [
          IconButton(
            key: const ValueKey('mh18-refresh'),
            tooltip: 'Tải lại',
            onPressed: state.isLoading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _protected
          ? (_resumeError != null && _foreground
                ? _MapError(error: _resumeError!, onRetry: _verifyAccess)
                : const Center(
                    child: Text(
                      'Đang bảo vệ thông tin điểm đến…',
                      key: ValueKey('mh18-protected'),
                    ),
                  ))
          : state.when(
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

    final savedDestination = destination.hasValidCoordinates
        ? vm.destinationFrom(details)
        : null;
    final session = ref.watch(operationalSessionProvider).asData?.value;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        key: const ValueKey('mh18-content'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _TaskHeading(task: task),
          const SizedBox(height: 12),
          if (savedDestination != null)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ref
                      .watch(mapDisplayAdapterProvider)
                      .buildMap(
                        key: ValueKey('mh18-map-$_recenterToken'),
                        location: savedDestination.location,
                        recenterToken: _recenterToken,
                        onTileError: (_) {
                          if (!mounted || _tileFailed) return;
                          setState(() => _tileFailed = true);
                        },
                      ),
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: FilledButton.tonalIcon(
                    key: const ValueKey('mh18-recenter'),
                    onPressed: () => setState(() => _recenterToken++),
                    icon: const Icon(Icons.center_focus_strong),
                    label: const Text('Về điểm đến'),
                  ),
                ),
              ],
            ),
          if (savedDestination == null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Chưa có tọa độ điểm đến. Bạn có thể sao chép địa chỉ hoặc tải lại; không thể mở chỉ đường.',
                key: ValueKey('mh18-no-coordinates'),
              ),
            ),
          ],
          if (_tileFailed && savedDestination != null) ...[
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('mh18-tile-error'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.softCloud,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Không thể tải dữ liệu bản đồ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Text(
                    'Thông tin điểm đến vẫn khả dụng bên dưới. Bạn có thể thử lại hoặc mở chỉ đường.',
                  ),
                  TextButton.icon(
                    key: const ValueKey('mh18-retry-tiles'),
                    onPressed: () => setState(() {
                      _tileFailed = false;
                      _recenterToken++;
                    }),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại bản đồ'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (savedDestination != null)
            Text(
              '${destination.latitude!.toStringAsFixed(6)}, ${destination.longitude!.toStringAsFixed(6)}',
              key: const ValueKey('mh18-coordinates'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.mute),
            ),
          const SizedBox(height: 14),
          _RecipientCard(
            task: task,
            onCall: (task) => _callRecipient(task, session),
            onCopyAddress: (task) => _copyAddress(task, session),
            onDirections: (task) => _openDirections(task, session),
            busy: _actionBusy,
          ),
          if (_navigationFailure != null)
            Padding(
              key: const ValueKey('mh18-navigation-error'),
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '${_directionsMessage(_navigationFailure!)} Địa chỉ vẫn ở trên; hãy sao chép hoặc bấm chỉ đường để thử lại.',
              ),
            ),
          const SizedBox(height: 12),
          _NotesCard(details: details),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    if (_protected) return _verifyAccess();
    await ref
        .read(deliveryTaskMapViewModelProvider(widget.taskId).notifier)
        .refresh();
  }

  Future<void> _callRecipient(
    DeliveryTaskSnapshot expected,
    Object? session,
  ) async {
    if (_actionBusy) return;
    final epoch = _visibilityEpoch;
    setState(() => _actionBusy = true);
    try {
      final details = await _freshDetails(expected, session, epoch);
      final destination = details.task.destination!;
      final phone = destination.phone.replaceAll(RegExp(r'[\s().-]'), '');
      if (!RegExp(r'^\+?[0-9]{8,15}$').hasMatch(phone)) {
        _showMessage('Số điện thoại người nhận không hợp lệ.');
        return;
      }
      _ensureSession(session, epoch);
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

  Future<void> _copyAddress(
    DeliveryTaskSnapshot expected,
    Object? session,
  ) async {
    if (_actionBusy) return;
    final epoch = _visibilityEpoch;
    setState(() => _actionBusy = true);
    try {
      final details = await _freshDetails(expected, session, epoch);
      _ensureSession(session, epoch);
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

  Future<void> _openDirections(
    DeliveryTaskSnapshot expected,
    Object? session,
  ) async {
    if (_actionBusy) return;
    final epoch = _visibilityEpoch;
    setState(() => _actionBusy = true);
    try {
      _ensureSession(session, epoch);
      final outcome = await ref
          .read(deliveryTaskMapViewModelProvider(widget.taskId).notifier)
          .openDirections(
            expected: expected,
            canLaunch: () =>
                mounted &&
                _foreground &&
                !_protected &&
                epoch == _visibilityEpoch,
          );
      if (!mounted) return;
      setState(
        () => _navigationFailure = outcome == MapDirectionsOutcome.opened
            ? null
            : outcome,
      );
      _showMessage(_directionsMessage(outcome));
    } on Object catch (error) {
      if (mounted) _showMessage(_failureMessage(error));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _ensureSession(Object? session, int epoch) {
    if (!mounted ||
        !_foreground ||
        _protected ||
        epoch != _visibilityEpoch ||
        session == null ||
        !identical(
          ref.read(operationalSessionProvider).asData?.value,
          session,
        )) {
      throw const OperationalFailure(OperationalFailureCode.sessionExpired);
    }
  }

  Future<DeliveryTaskDetails> _freshDetails(
    DeliveryTaskSnapshot expected,
    Object? session,
    int epoch,
  ) async {
    _ensureSession(session, epoch);
    final details = await ref
        .read(deliveryTaskMapViewModelProvider(widget.taskId).notifier)
        .recheckAuthorizedDetails();
    _ensureSession(session, epoch);
    if (expected.destination != details.task.destination) {
      throw const OperationalFailure(OperationalFailureCode.staleAssignment);
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
      MapDirectionsOutcome.opened => 'Đã gửi yêu cầu mở dịch vụ chỉ đường.',
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
                'Trạng thái: ${_statusLabel(task.status)}${task.kind == DeliveryTaskKind.outbound ? ' · Lần ${task.attemptNumber}' : ''}',
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
    required this.busy,
  });

  final DeliveryTaskSnapshot task;
  final ValueChanged<DeliveryTaskSnapshot> onCall;
  final ValueChanged<DeliveryTaskSnapshot> onCopyAddress;
  final ValueChanged<DeliveryTaskSnapshot> onDirections;
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
              'NGƯỜI NHẬN',
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.mute,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              destination.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(destination.phone, key: const ValueKey('mh18-phone')),
            const SizedBox(height: 10),
            Text(
              'ĐỊA CHỈ GIAO NHẬN LƯU TRỮ',
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.mute,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.home_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
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
                  onPressed: busy || !destination.hasValidCoordinates
                      ? null
                      : () => onDirections(task),
                  icon: const Icon(Icons.directions_outlined),
                  label: const Text('Chỉ đường tới điểm này'),
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
