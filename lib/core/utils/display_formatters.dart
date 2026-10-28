/// Presentation formatters shared by the Orders and Notifications features.
///
/// These helpers deliberately keep business values in their original units.
/// VND amounts are integers and server timestamps are rendered in the fixed
/// Hanoi offset (UTC+07:00), independent of the device timezone.
library;

const Duration _hanoiOffset = Duration(hours: 7);

/// Formats an integer VND amount using Vietnamese thousands separators.
///
/// For example, `3480000` becomes `3.480.000 ₫`. No floating point conversion
/// is used, so large values remain exact. A null amount is left to the caller
/// to describe because a missing financial value must not be shown as zero.
String formatVnd(int amount) {
  final negative = amount < 0;
  final raw = amount.toString();
  final digits = negative ? raw.substring(1) : raw;
  final grouped = StringBuffer();

  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      grouped.write('.');
    }
    grouped.write(digits[index]);
  }

  return '${negative ? '-' : ''}${grouped.toString()} ₫';
}

/// Formats a nullable amount without inventing a financial value.
String formatOptionalVnd(
  int? amount, {
  String placeholder = 'Chưa có dữ liệu',
}) {
  return amount == null ? placeholder : formatVnd(amount);
}

/// Converts a server timestamp to the fixed Hanoi presentation timezone.
///
/// Domain timestamps are required to represent an instant. `toUtc` first
/// removes the device's local timezone interpretation, then the fixed +7
/// offset is applied without relying on local timezone or daylight-saving
/// rules.
DateTime toHanoi(DateTime value) => value.toUtc().add(_hanoiOffset);

/// Renders a server timestamp as `dd/MM/yyyy HH:mm` in Hanoi time.
String formatHanoiDateTime(DateTime value) {
  final hanoi = toHanoi(value);
  final day = _twoDigits(hanoi.day);
  final month = _twoDigits(hanoi.month);
  final hour = _twoDigits(hanoi.hour);
  final minute = _twoDigits(hanoi.minute);
  return '$day/$month/${hanoi.year} $hour:$minute';
}

/// Renders only the Hanoi calendar date as `dd/MM/yyyy`.
String formatHanoiDate(DateTime value) {
  final hanoi = toHanoi(value);
  return '${_twoDigits(hanoi.day)}/${_twoDigits(hanoi.month)}/${hanoi.year}';
}

/// Formats a timestamp when it is present; no device-local fallback is used.
String formatOptionalHanoiDateTime(
  DateTime? value, {
  String placeholder = 'Chưa có dữ liệu',
}) {
  return value == null ? placeholder : formatHanoiDateTime(value);
}

/// Keeps identifiers intact. The contract uses full UUIDs as business keys;
/// callers may add a semantic label around this value, but must not shorten
/// it for display.
String formatFullUuid(String value) => value;

/// Converts either a wire string or a Dart enum into its wire-style value.
/// This keeps presentation code compatible with the immutable domain enums
/// while allowing safe use in small view adapters.
String? statusValue(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  final text = value.toString();
  final separator = text.lastIndexOf('.');
  return separator < 0 ? text : text.substring(separator + 1);
}

/// Maps the order lifecycle to the approved Vietnamese presentation label.
String orderStatusLabel(Object? status) {
  return _statusLabel(statusValue(status), const {
    'pending_confirmation': 'Chờ xác nhận',
    'preparing': 'Đang chuẩn bị',
    'awaiting_pickup': 'Chờ shipper nhận hàng',
    'delivering': 'Đang giao',
    'awaiting_redelivery': 'Chờ xử lý giao lại',
    'awaiting_store_return': 'Chờ hàng về cửa hàng',
    'delivered': 'Đã giao hàng',
    'cancelled': 'Đã hủy',
    'rejected': 'Đã từ chối',
    'undeliverable_returned': 'Không giao được — đã nhận hàng về',
  });
}

/// Maps the delivery-task lifecycle independently from [orderStatusLabel].
String deliveryStatusLabel(Object? status) {
  return _statusLabel(statusValue(status), const {
    'pending_assignment': 'Chờ phân công',
    'assigned': 'Đã phân công',
    'accepted': 'Đã tiếp nhận nhiệm vụ',
    'in_transit': 'Đang thực hiện',
    'delivered': 'Hoàn tất nhiệm vụ',
    'failed': 'Thất bại',
    'returned_to_store': 'Đã bàn giao về cửa hàng',
    'cancelled': 'Đã hủy nhiệm vụ',
    'manager_action_required': 'Cần quản lý xử lý',
  });
}

/// Maps COD collection status independently from order and delivery status.
String codStatusLabel(Object? status) {
  return _statusLabel(statusValue(status), const {
    'uncollected': 'Chưa thu',
    'collected': 'Shipper đã thu',
    'received': 'Cửa hàng đã nhận',
  });
}

/// Maps the return-request lifecycle independently from the order lifecycle.
String returnStatusLabel(Object? status) {
  return _statusLabel(statusValue(status), const {
    'pending_review': 'Chờ duyệt',
    'awaiting_return_pickup': 'Chờ lấy hàng trả',
    'returning_to_store': 'Đang về cửa hàng',
    'under_inspection': 'Đang kiểm tra',
    'awaiting_refund': 'Chờ hoàn tiền',
    'refunded': 'Đã hoàn tiền',
    'initially_rejected': 'Từ chối ban đầu',
    'awaiting_redelivery': 'Chờ giao lại hàng trả',
    'redelivery_failed': 'Giao lại hàng trả thất bại',
    'manager_action_required': 'Cần quản lý xử lý',
    'rejected_after_inspection': 'Từ chối sau kiểm tra — đã giao lại',
  });
}

/// Text-only presentation data for one of the independent lifecycle enums.
/// Keeping this object free of Flutter colours lets domain and widget tests
/// verify that a delivery state is never treated as an order state.
class StatusPresentation {
  const StatusPresentation({required this.label, required this.isKnown});

  final String label;
  final bool isKnown;
}

StatusPresentation orderStatusPresentation(Object? status) =>
    _presentation(status, orderStatusLabel, const {
      'pending_confirmation',
      'preparing',
      'awaiting_pickup',
      'delivering',
      'awaiting_redelivery',
      'awaiting_store_return',
      'delivered',
      'cancelled',
      'rejected',
      'undeliverable_returned',
    });

StatusPresentation deliveryStatusPresentation(Object? status) =>
    _presentation(status, deliveryStatusLabel, const {
      'pending_assignment',
      'assigned',
      'accepted',
      'in_transit',
      'delivered',
      'failed',
      'returned_to_store',
      'cancelled',
      'manager_action_required',
    });

StatusPresentation codStatusPresentation(Object? status) => _presentation(
  status,
  codStatusLabel,
  const {'uncollected', 'collected', 'received'},
);

StatusPresentation returnStatusPresentation(Object? status) =>
    _presentation(status, returnStatusLabel, const {
      'pending_review',
      'awaiting_return_pickup',
      'returning_to_store',
      'under_inspection',
      'awaiting_refund',
      'refunded',
      'initially_rejected',
      'awaiting_redelivery',
      'redelivery_failed',
      'manager_action_required',
      'rejected_after_inspection',
    });

StatusPresentation _presentation(
  Object? value,
  String Function(Object?) labelFor,
  Set<String> knownValues,
) {
  final raw = statusValue(value);
  return StatusPresentation(
    label: labelFor(value),
    isKnown: raw != null && knownValues.contains(raw),
  );
}

/// Presentation for an unknown value is intentionally generic. It never
/// turns an unknown server value into a known business state.
String _statusLabel(String? value, Map<String, String> labels) {
  if (value == null || value.trim().isEmpty) return 'Chưa có dữ liệu';
  return labels[value] ?? 'Trạng thái chưa hỗ trợ';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
