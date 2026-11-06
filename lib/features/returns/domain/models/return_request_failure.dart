enum ReturnRequestFailureCode {
  sessionExpired,
  permissionDenied,
  orderNotFound,
  returnNotFound,
  orderNotDelivered,
  returnWindowExpired,
  activeReturnExists,
  videoRequired,
  videoAlreadyUsed,
  invalidInput,
  idempotencyConflict,
  stateConflict,
  itemsMismatch,
  invalidShipper,
  amountMismatch,
  evidenceRequired,
  invalidTransferTime,
  network,
  backendUnavailable,
  unexpected,
}

class ReturnRequestFailure implements Exception {
  const ReturnRequestFailure(this.code);

  final ReturnRequestFailureCode code;

  /// Network/unknown outcomes may have reached the server: the caller must
  /// retry with the same request id instead of starting a new request.
  bool get isAmbiguous =>
      code == ReturnRequestFailureCode.network ||
      code == ReturnRequestFailureCode.unexpected;

  /// The caller may no longer see this data (other account, lost access):
  /// previously shown private data must be cleared, not kept as "stale".
  bool get revokesAccess =>
      code == ReturnRequestFailureCode.sessionExpired ||
      code == ReturnRequestFailureCode.permissionDenied ||
      code == ReturnRequestFailureCode.returnNotFound;

  String get message => switch (code) {
    ReturnRequestFailureCode.sessionExpired =>
      'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
    ReturnRequestFailureCode.permissionDenied =>
      'Bạn không có quyền tạo yêu cầu trả hàng cho đơn này.',
    ReturnRequestFailureCode.orderNotFound =>
      'Không tìm thấy đơn hàng của bạn.',
    ReturnRequestFailureCode.returnNotFound =>
      'Không tìm thấy yêu cầu trả hàng của bạn.',
    ReturnRequestFailureCode.orderNotDelivered =>
      'Đơn chưa giao thành công nên chưa thể trả hàng.',
    ReturnRequestFailureCode.returnWindowExpired =>
      'Đơn đã quá 7 ngày kể từ khi nhận hàng.',
    ReturnRequestFailureCode.activeReturnExists =>
      'Đơn này đã có yêu cầu trả hàng đang được xử lý.',
    ReturnRequestFailureCode.videoRequired =>
      'Không xác nhận được video mở kiện. Vui lòng chọn lại video.',
    ReturnRequestFailureCode.videoAlreadyUsed =>
      'Video này đã được dùng cho một yêu cầu khác.',
    ReturnRequestFailureCode.invalidInput =>
      'Thông tin chưa hợp lệ. Vui lòng kiểm tra lại.',
    ReturnRequestFailureCode.idempotencyConflict =>
      'Yêu cầu trước đó đã được ghi nhận với nội dung khác.',
    ReturnRequestFailureCode.stateConflict =>
      'Yêu cầu đã được xử lý ở nơi khác. Tải lại để xem trạng thái mới.',
    ReturnRequestFailureCode.itemsMismatch =>
      'Sản phẩm hoặc số lượng thu hồi không khớp với đơn hàng.',
    ReturnRequestFailureCode.invalidShipper =>
      'Shipper đã chọn không còn khả dụng. Chọn shipper khác.',
    ReturnRequestFailureCode.amountMismatch =>
      'Số tiền hoàn phải bằng đúng tiền hàng cộng phí giao ban đầu.',
    ReturnRequestFailureCode.evidenceRequired =>
      'Chưa có chứng từ hợp lệ. Tải lên ảnh hoặc tệp chứng từ rồi thử lại.',
    ReturnRequestFailureCode.invalidTransferTime =>
      'Thời điểm chuyển khoản phải sau lúc kiểm tra và không ở tương lai.',
    ReturnRequestFailureCode.network =>
      'Không thể kết nối. Vui lòng kiểm tra mạng và gửi lại.',
    ReturnRequestFailureCode.backendUnavailable =>
      'Dịch vụ trả hàng chưa sẵn sàng. Vui lòng thử lại sau.',
    ReturnRequestFailureCode.unexpected =>
      'Chưa rõ yêu cầu đã được ghi nhận hay chưa. Vui lòng gửi lại.',
  };

  @override
  String toString() => 'ReturnRequestFailure($code)';
}
