/// Shared failure contract for delivery and COD reads. Contains no server PII.
enum OperationalFailureCode {
  sessionExpired,
  permissionDenied,
  staleAssignment,
  invalidData,
  network,
  backendUnavailable,
  unexpected,
}

class OperationalFailure implements Exception {
  const OperationalFailure(this.code);

  final OperationalFailureCode code;

  String get message => switch (code) {
    OperationalFailureCode.sessionExpired => 'Phiên đăng nhập đã hết hạn.',
    OperationalFailureCode.permissionDenied => 'Bạn không có quyền truy cập.',
    OperationalFailureCode.staleAssignment =>
      'Nhiệm vụ không còn khả dụng hoặc bạn không có quyền truy cập.',
    OperationalFailureCode.invalidData => 'Dữ liệu không hợp lệ.',
    OperationalFailureCode.network => 'Không thể kết nối. Vui lòng thử lại.',
    OperationalFailureCode.backendUnavailable =>
      'Dịch vụ chưa sẵn sàng. Vui lòng thử lại sau.',
    OperationalFailureCode.unexpected => 'Không thể tải dữ liệu.',
  };

  @override
  String toString() => 'OperationalFailure(${code.name})';
}
