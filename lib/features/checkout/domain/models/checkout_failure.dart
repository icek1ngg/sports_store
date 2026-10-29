/// Errors that can be shown by MH16 without exposing transport details.
enum CheckoutFailureCode {
  invalidArgument,
  insufficientStock,
  outsideServiceArea,
  idempotencyConflict,
  forbiddenOrUnavailable,
  externalDependencyUnavailable,
  network,
  sessionExpired,
  permissionDenied,
  backendUnavailable,
  invalidData,
  unexpected,
}

/// A typed checkout failure. The optional [serverCode] is retained for
/// diagnostics/tests, but is never rendered directly as UI text.
class CheckoutFailure implements Exception {
  const CheckoutFailure(
    this.code, {
    this.message,
    this.serverCode,
    this.definitiveNoCommit = false,
  });

  final CheckoutFailureCode code;
  final String? message;
  final String? serverCode;

  /// True only when the server explicitly returned a rejection envelope that
  /// proves this request did not commit. Transport/session failures remain
  /// pending because their result may be unknown.
  final bool definitiveNoCommit;

  String get userMessage =>
      message ??
      _defaultCheckoutFailureMessages[code] ??
      'Không thể hoàn tất đặt hàng. Vui lòng thử lại.';

  bool get canClearPending => definitiveNoCommit;

  @override
  String toString() =>
      'CheckoutFailure(${code.name}${serverCode == null ? '' : ':$serverCode'}): $userMessage';
}

const Map<CheckoutFailureCode, String> _defaultCheckoutFailureMessages = {
  CheckoutFailureCode.invalidArgument: 'Thông tin đặt hàng chưa hợp lệ.',
  CheckoutFailureCode.insufficientStock:
      'Một hoặc nhiều sản phẩm không còn đủ tồn kho.',
  CheckoutFailureCode.outsideServiceArea:
      'Địa chỉ nằm ngoài khu vực giao hàng tại Hà Nội.',
  CheckoutFailureCode.idempotencyConflict:
      'Yêu cầu đặt hàng đã được dùng cho dữ liệu khác.',
  CheckoutFailureCode.forbiddenOrUnavailable:
      'Tài khoản hiện không thể đặt hàng.',
  CheckoutFailureCode.externalDependencyUnavailable:
      'Dịch vụ đặt hàng tạm thời chưa sẵn sàng. Vui lòng thử lại.',
  CheckoutFailureCode.network: 'Không kết nối được dịch vụ đặt hàng. Kết quả có thể vẫn đang được xác minh.',
  CheckoutFailureCode.sessionExpired:
      'Phiên đăng nhập đã hết. Vui lòng đăng nhập lại.',
  CheckoutFailureCode.permissionDenied: 'Bạn không có quyền đặt hàng.',
  CheckoutFailureCode.backendUnavailable:
      'Dịch vụ đặt hàng tạm thời không khả dụng.',
  CheckoutFailureCode.invalidData: 'Dữ liệu trả về từ máy chủ không hợp lệ.',
  CheckoutFailureCode.unexpected:
      'Không thể hoàn tất đặt hàng. Vui lòng thử lại.',
};

/// Maps the lowercase server error contract to a typed failure.
CheckoutFailure checkoutFailureFromServerCode(String? code) {
  final normalized = code?.trim().toLowerCase();
  final mapped = switch (normalized) {
    'invalid_argument' => CheckoutFailureCode.invalidArgument,
    'insufficient_stock' => CheckoutFailureCode.insufficientStock,
    'outside_service_area' => CheckoutFailureCode.outsideServiceArea,
    'idempotency_conflict' => CheckoutFailureCode.idempotencyConflict,
    'forbidden_or_unavailable' => CheckoutFailureCode.forbiddenOrUnavailable,
    'external_dependency_unavailable' =>
      CheckoutFailureCode.externalDependencyUnavailable,
    _ => CheckoutFailureCode.unexpected,
  };

  // Only an explicit business rejection proves that this RPC did not commit.
  // External dependency failures can happen after an internal write and must
  // therefore keep the durable pending payload.
  final definitive = switch (mapped) {
    CheckoutFailureCode.invalidArgument ||
    CheckoutFailureCode.insufficientStock ||
    CheckoutFailureCode.outsideServiceArea => true,
    // A conflict may mean a different payload already committed under this
    // request ID, and a forbidden response can race a role/session change
    // after commit. Keep the exact pending payload for lookup in both cases.
    CheckoutFailureCode.idempotencyConflict ||
    CheckoutFailureCode.forbiddenOrUnavailable => false,
    _ => false,
  };
  return CheckoutFailure(
    mapped,
    serverCode: normalized,
    definitiveNoCommit: definitive,
  );
}
