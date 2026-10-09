import 'package:flutter_test/flutter_test.dart';

import 'package:sports_store/core/utils/display_formatters.dart';

void main() {
  test('formats VND as an exact integer with Vietnamese separators', () {
    expect(formatVnd(3480000), '3.480.000 ₫');
    expect(formatVnd(0), '0 ₫');
    expect(formatVnd(-1200), '-1.200 ₫');
    expect(formatOptionalVnd(null), 'Chưa có dữ liệu');
    expect(formatVnd(-9223372036854775808), '-9.223.372.036.854.775.808 ₫');
  });

  test('renders UTC instants in fixed Hanoi UTC+07:00', () {
    final utc = DateTime.utc(2026, 10, 8, 3, 32);
    expect(formatHanoiDateTime(utc), '08/10/2026 10:32');
    expect(formatHanoiDate(utc), '08/10/2026');
    expect(toHanoi(utc), DateTime.utc(2026, 10, 8, 10, 32));
    expect(
      formatHanoiDateTime(DateTime.utc(2026, 12, 31, 19, 15)),
      '01/01/2027 02:15',
    );
  });

  test('keeps UUIDs full and maps four lifecycles independently', () {
    const id = '10000000-0000-4000-8000-000000000001';
    expect(formatFullUuid(id), id);
    expect(orderStatusLabel('delivering'), 'Đang giao');
    expect(deliveryStatusLabel('failed'), 'Thất bại');
    expect(codStatusLabel('received'), 'Cửa hàng đã nhận');
    expect(returnStatusLabel('under_inspection'), 'Đang kiểm tra');
    expect(orderStatusLabel('made_up_status'), 'Trạng thái chưa hỗ trợ');
    expect(orderStatusPresentation('delivered').isKnown, isTrue);
    expect(deliveryStatusPresentation('delivered').label, 'Hoàn tất nhiệm vụ');
    expect(codStatusPresentation('delivered').isKnown, isFalse);
  });
}
