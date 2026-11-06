import 'outbound_task_command.dart';

/// Server business failures specific to successful outbound completion.
/// Raw PostgREST messages are never exposed to the UI.
enum OutboundCompletionBusinessFailureCode {
  itemsMismatch,
  amountMismatch,
  stateConflict,
  idempotencyConflict,
  custodyUnresolved,
  dependencyNotReady,
}

class OutboundCompletionBusinessFailure extends OutboundCommandFailure {
  const OutboundCompletionBusinessFailure(this.businessCode)
    : super(OutboundCommandFailureCode.staleState);

  final OutboundCompletionBusinessFailureCode businessCode;

  String get message => switch (businessCode) {
    OutboundCompletionBusinessFailureCode.itemsMismatch =>
      'Chưa xác nhận đủ hàng. Vui lòng kiểm tra lại.',
    OutboundCompletionBusinessFailureCode.amountMismatch =>
      'Số tiền thu không khớp với COD do hệ thống tính.',
    OutboundCompletionBusinessFailureCode.stateConflict =>
      'Trạng thái nhiệm vụ đã thay đổi. Vui lòng đọc lại.',
    OutboundCompletionBusinessFailureCode.idempotencyConflict =>
      'Yêu cầu đã được dùng cho thao tác khác. Vui lòng đọc lại nhiệm vụ.',
    OutboundCompletionBusinessFailureCode.custodyUnresolved =>
      'Chưa xác minh được việc giữ hàng. Liên hệ quản lý.',
    OutboundCompletionBusinessFailureCode.dependencyNotReady =>
      'Dữ liệu giao hàng chưa sẵn sàng để hoàn tất.',
  };
}
