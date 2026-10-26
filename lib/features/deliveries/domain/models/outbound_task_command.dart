import 'delivery_task.dart';

/// Outbound actions backed by the production P04.1 RPCs.
/// Values are domain action names, not RPC or database enum names.
enum OutboundTaskAction {
  acceptGoods('accept_goods'),
  startDelivery('start_delivery');

  const OutboundTaskAction(this.value);

  final String value;
}

/// Idempotent command envelope for the accept/start API.
///
/// The same instance (and therefore the same [requestId]) must be reused for
/// a timeout/network retry.  A successful command is followed by an
/// authoritative task read; this envelope never contains an optimistic state
/// or stock mutation.
class OutboundTaskCommand {
  const OutboundTaskCommand({
    required this.taskId,
    required this.requestId,
    required this.action,
  });

  final String taskId;
  final String requestId;
  final OutboundTaskAction action;

  bool get hasNonEmptyIds =>
      taskId.trim().isNotEmpty && requestId.trim().isNotEmpty;

  bool get isUuidShaped {
    // UUID versions are server-owned and may include newer versions (for
    // example v7), so validate shape without imposing a version nibble.
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuid.hasMatch(taskId) && uuid.hasMatch(requestId);
  }

  @override
  bool operator ==(Object other) {
    return other is OutboundTaskCommand &&
        taskId == other.taskId &&
        requestId == other.requestId &&
        action == other.action;
  }

  @override
  int get hashCode => Object.hash(taskId, requestId, action);

  @override
  String toString() =>
      'OutboundTaskCommand(action: ${action.value}, taskId: $taskId, requestId: $requestId)';
}

/// Typed errors shared by the production action adapter and test seams.
enum OutboundCommandFailureCode {
  timeout,
  network,
  permissionDenied,
  staleState,
  staleAssignment,
  sessionExpired,
  dependencyUnavailable,
  invalidData,
  unexpected,
}

class OutboundCommandFailure implements Exception {
  const OutboundCommandFailure(this.code, {this.cause});

  final OutboundCommandFailureCode code;
  final Object? cause;

  @override
  String toString() => 'OutboundCommandFailure(${code.name})';
}

/// A response arrived after dispatch but cannot be verified: retain its key.
class OutboundAcknowledgementFailure extends OutboundCommandFailure {
  const OutboundAcknowledgementFailure()
    : super(OutboundCommandFailureCode.invalidData);
}

enum OutboundBusinessFailureCode {
  stateConflict,
  idempotencyConflict,
  custodyUnresolved,
  itemsMismatch,
  stockConflict,
  codConflict,
  attemptLimit,
  dispatchConflict,
}

/// Closed server business errors; never display raw PostgREST messages.
class OutboundBusinessFailure extends OutboundCommandFailure {
  const OutboundBusinessFailure(this.businessCode)
    : super(OutboundCommandFailureCode.staleState);

  final OutboundBusinessFailureCode businessCode;

  String get message => switch (businessCode) {
    OutboundBusinessFailureCode.stateConflict =>
      'Trạng thái nhiệm vụ đã thay đổi. Vui lòng đọc lại.',
    OutboundBusinessFailureCode.idempotencyConflict =>
      'Yêu cầu đã được dùng cho thao tác khác. Vui lòng đọc lại nhiệm vụ.',
    OutboundBusinessFailureCode.custodyUnresolved =>
      'Chưa xác minh được việc giữ hàng. Liên hệ quản lý.',
    OutboundBusinessFailureCode.itemsMismatch =>
      'Thông tin hàng không khớp. Liên hệ quản lý để kiểm tra.',
    OutboundBusinessFailureCode.stockConflict =>
      'Chưa đủ tồn hoặc bằng chứng giữ hàng. Liên hệ quản lý.',
    OutboundBusinessFailureCode.codConflict =>
      'Thông tin COD không khớp. Liên hệ quản lý.',
    OutboundBusinessFailureCode.attemptLimit =>
      'Đơn đã đạt giới hạn số lần giao.',
    OutboundBusinessFailureCode.dispatchConflict =>
      'Thông tin xuất kho đã thay đổi. Liên hệ quản lý.',
  };
}

/// Presentation eligibility only; the server validates role/custody/stock.
bool canExecuteOutboundAction(
  DeliveryTaskSnapshot task,
  OutboundTaskAction action,
) {
  if (task.kind != DeliveryTaskKind.outbound ||
      task.scope != DeliverySnapshotScope.current ||
      (task.attemptNumber != 1 && task.attemptNumber != 2)) {
    return false;
  }
  return switch ((action, task.status)) {
    (OutboundTaskAction.acceptGoods, DeliveryTaskStatus.assigned) => true,
    (OutboundTaskAction.startDelivery, DeliveryTaskStatus.accepted) => true,
    _ => false,
  };
}
