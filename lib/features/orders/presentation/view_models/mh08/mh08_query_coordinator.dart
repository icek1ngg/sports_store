import 'dart:async';

import '../../../domain/models/order_query.dart';
import '../../../domain/models/order_status.dart';

/// Page-owned editing and debounce lifecycle; repository queries stay canonical.
class Mh08QueryCoordinator {
  OrderQuery query = OrderQuery();
  String value = '';
  String? error;
  Timer? _debounce;

  String get emptyMessage => query.search != null || query.statuses.isNotEmpty
      ? 'Không tìm thấy đơn hàng phù hợp'
      : 'Chưa có đơn hàng cần xử lý';

  void edit(String nextValue, void Function(OrderQuery) onApply) {
    cancelPending();
    value = nextValue;
    if (nextValue.runes.length > 200) {
      error = 'Từ khóa tìm kiếm tối đa 200 ký tự Unicode.';
      return;
    }
    error = null;
    _debounce = Timer(const Duration(milliseconds: 350), () {
      onApply(
        OrderQuery(
          search: nextValue,
          statuses: query.statuses,
          limit: query.limit,
        ),
      );
    });
  }

  OrderQuery clear() {
    cancelPending();
    value = '';
    error = null;
    return OrderQuery(statuses: query.statuses, limit: query.limit);
  }

  OrderQuery select(OrderStatus? status) => OrderQuery(
    search: query.search,
    statuses: status == null ? const [] : [status],
    limit: query.limit,
  );

  bool apply(OrderQuery nextQuery) {
    if (query == nextQuery) return false;
    query = nextQuery.copyWith(cursor: null);
    return true;
  }

  void cancelPending() => _debounce?.cancel();
  void dispose() => cancelPending();
}
