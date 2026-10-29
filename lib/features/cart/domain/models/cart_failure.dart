enum CartFailureCode {
  sessionExpired,
  permissionDenied,
  invalidData,
  unavailable,
  insufficientStock,
  network,
  backendUnavailable,
  unexpected,
}

class CartFailure implements Exception {
  const CartFailure(this.code);

  final CartFailureCode code;

  String get message => switch (code) {
    CartFailureCode.sessionExpired => 'Phiên đăng nhập đã hết hạn.',
    CartFailureCode.permissionDenied => 'Bạn không có quyền truy cập giỏ hàng.',
    CartFailureCode.invalidData => 'Dữ liệu giỏ hàng không hợp lệ.',
    CartFailureCode.unavailable => 'Sản phẩm hoặc biến thể không còn được bán.',
    CartFailureCode.insufficientStock =>
      'Số lượng vượt tồn hiện tại. Vui lòng kiểm tra lại giỏ hàng.',
    CartFailureCode.network =>
      'Chưa xác nhận được kết quả. Vui lòng thử lại thao tác đang chờ.',
    CartFailureCode.backendUnavailable =>
      'Dịch vụ giỏ hàng chưa sẵn sàng. Vui lòng thử lại.',
    CartFailureCode.unexpected =>
      'Không thể cập nhật giỏ hàng. Vui lòng thử lại.',
  };

  @override
  String toString() => 'CartFailure(${code.name})';
}
