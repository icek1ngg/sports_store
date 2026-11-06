String formatCodVnd(int value) =>
    '${value.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match[1]}.')} đ';

/// Explicit UTC, consistent with the existing shipper MH12 presentation.
String formatCodTimestamp(DateTime? value) {
  if (value == null) return 'Chưa có dữ liệu thời gian';
  final time = value.toUtc();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(time.day)}/${two(time.month)}/${time.year} ${two(time.hour)}:${two(time.minute)} UTC';
}
