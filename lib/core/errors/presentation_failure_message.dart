import 'app_failure.dart';

/// Localized, safe feedback; never exposes adapter/SQL exception text.
String failureMessage(AppFailure? failure) => switch (failure?.code) {
  AppFailure.unauthenticated =>
    'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
  AppFailure.forbiddenOrUnavailable =>
    'Mục này không khả dụng hoặc bạn không còn quyền truy cập.',
  AppFailure.network => 'Không thể kết nối. Kiểm tra mạng và thử lại.',
  AppFailure.stateChanged || AppFailure.cancellationNotAllowed =>
    'Dữ liệu đã thay đổi. Làm mới trước khi tiếp tục.',
  AppFailure.invalidArgument => 'Thông tin chưa hợp lệ. Vui lòng kiểm tra lại.',
  AppFailure.invalidCursor => 'Danh sách đã thay đổi. Làm mới để tải lại.',
  AppFailure.outcomeUnknownCode =>
    'Chưa xác định được kết quả. Làm mới trạng thái trước khi tiếp tục.',
  AppFailure.externalDependencyUnavailable =>
    'Thao tác hiện chưa khả dụng. Vui lòng thử lại sau.',
  AppFailure.unsupportedData ||
  AppFailure.dataIntegrity => 'Dữ liệu chưa thể hiển thị. Vui lòng làm mới.',
  _ => 'Không thể hoàn tất thao tác. Vui lòng thử lại.',
};
