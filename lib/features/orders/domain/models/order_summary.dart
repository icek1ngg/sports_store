import 'cod_summary.dart';
import 'delivery_summary.dart';
import 'model_validators.dart';
import 'order.dart';
import 'order_capabilities.dart';
import 'order_item.dart';
import 'order_warning.dart';
import 'return_summary.dart';

class OrderSummary {
  OrderSummary({
    required this.order,
    required List<OrderItem> itemPreview,
    required int itemLineCount,
    required int itemQuantityTotal,
    required this.customerDisplayName,
    required this.deliverySummary,
    required this.codSummary,
    required this.returnSummary,
    required List<OrderWarning> warnings,
    required this.capabilities,
  }) : itemPreview = List<OrderItem>.unmodifiable(itemPreview),
       itemLineCount = validateNonNegativeInt(
         itemLineCount,
         field: 'itemLineCount',
       ),
       itemQuantityTotal = validateNonNegativeInt(
         itemQuantityTotal,
         field: 'itemQuantityTotal',
       ),
       warnings = List<OrderWarning>.unmodifiable(warnings) {
    if (this.itemPreview.length > 2) {
      throw InvalidDomainArgumentException(
        'itemPreview must contain at most two items.',
      );
    }
    final itemIds = <String>{};
    var previewQuantity = 0;
    for (final item in this.itemPreview) {
      if (item.orderId != order.id || !itemIds.add(item.id)) {
        throw InvalidDomainArgumentException(
          'Order summary item previews must belong to the order and be unique.',
        );
      }
      previewQuantity += item.quantity;
    }
    if (itemLineCount < this.itemPreview.length ||
        itemQuantityTotal < previewQuantity) {
      throw InvalidDomainArgumentException(
        'Summary counts must include every preview item.',
      );
    }
    if (deliverySummary?.latestAttempt != null &&
        deliverySummary!.latestAttempt!.orderId != order.id) {
      throw InvalidDomainArgumentException(
        'Latest delivery attempt must belong to the order.',
      );
    }
    if (codSummary != null &&
        (codSummary!.orderId != order.id ||
            codSummary!.expectedAmountVnd != order.totalCodVnd)) {
      throw InvalidDomainArgumentException(
        'COD summary must match the order and its full COD obligation.',
      );
    }
    if (returnSummary != null && returnSummary!.orderId != order.id) {
      throw InvalidDomainArgumentException(
        'Return summary must belong to the order.',
      );
    }
  }

  final Order order;
  final String? customerDisplayName;
  final List<OrderItem> itemPreview;
  final int itemLineCount;
  final int itemQuantityTotal;
  final DeliverySummary? deliverySummary;
  final CodSummary? codSummary;
  final ReturnSummary? returnSummary;
  final List<OrderWarning> warnings;
  final OrderCapabilities capabilities;

  Map<String, Object?> toMap() => {
    'order': order.toMap(),
    'customer_display_name': customerDisplayName,
    'item_preview': itemPreview.map((item) => item.toMap()).toList(),
    'item_line_count': itemLineCount,
    'item_quantity_total': itemQuantityTotal,
    'delivery_summary': deliverySummary?.toMap(),
    'cod_summary': codSummary?.toMap(),
    'return_summary': returnSummary?.toMap(),
    'warnings': warnings.map((warning) => warning.toMap()).toList(),
    'capabilities': capabilities.toMap(),
  };
}
