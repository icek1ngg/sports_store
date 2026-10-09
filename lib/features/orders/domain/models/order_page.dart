import 'model_validators.dart';
import 'order_status.dart';
import 'order_summary.dart';

class OrderPage {
  OrderPage({
    required List<OrderSummary> items,
    required this.nextCursor,
    required int totalCount,
    required Map<OrderStatus, int> statusCounts,
    required DateTime asOf,
  }) : items = List<OrderSummary>.unmodifiable(items),
       totalCount = validateNonNegativeInt(totalCount, field: 'totalCount'),
       statusCounts = _validateCounts(statusCounts),
       asOf = validateUtc(asOf, field: 'asOf') {
    final ids = <String>{};
    for (final item in this.items) {
      if (!ids.add(item.order.id)) {
        throw InvalidDomainArgumentException(
          'Order page items must not contain duplicate order IDs.',
        );
      }
    }
    if (totalCount < this.items.length) {
      throw InvalidDomainArgumentException(
        'totalCount cannot be smaller than the page item count.',
      );
    }
  }

  final List<OrderSummary> items;
  final String? nextCursor;
  final int totalCount;
  final Map<OrderStatus, int> statusCounts;
  final DateTime asOf;

  static Map<OrderStatus, int> _validateCounts(Map<OrderStatus, int> value) {
    if (value.length != OrderStatus.values.length ||
        !OrderStatus.values.every(value.containsKey)) {
      throw InvalidDomainArgumentException(
        'statusCounts must contain every OrderStatus exactly once.',
      );
    }
    for (final count in value.values) {
      validateNonNegativeInt(count, field: 'statusCounts');
    }
    return Map<OrderStatus, int>.unmodifiable(value);
  }
}
