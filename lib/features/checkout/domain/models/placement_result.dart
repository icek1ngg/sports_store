import '../../../orders/domain/models/order.dart';
import '../../../orders/domain/models/order_item.dart';
import 'placement_request.dart';

/// Canonical receipt returned by place_order. Checkout never defines another
/// Order/OrderItem model; these are the shared Orders domain types.
class PlacementResult {
  PlacementResult({
    required this.order,
    required List<OrderItem> items,
    required String eventId,
    required this.replayed,
  }) : items = List<OrderItem>.unmodifiable(items),
       eventId = _requireUuid(eventId, 'event_id') {
    if (this.items.isEmpty) {
      throw const FormatException('placement result items must not be empty');
    }
    final variants = <String>{};
    var subtotal = 0;
    for (final item in this.items) {
      if (item.orderId.toLowerCase() != order.id.toLowerCase()) {
        throw const FormatException('order item does not belong to order');
      }
      if (!variants.add(item.variantId.toLowerCase())) {
        throw const FormatException(
          'placement result contains duplicate variant',
        );
      }
      subtotal += item.lineTotalVnd;
    }
    if (subtotal != order.subtotalVnd) {
      throw const FormatException('placement result subtotal does not match');
    }
  }

  final Order order;
  final List<OrderItem> items;
  final String eventId;
  final bool replayed;

  int get totalCodVnd => order.totalCodVnd;
  int get subtotalVnd => order.subtotalVnd;
  int get deliveryFeeVnd => order.deliveryFeeVnd;

  /// Reconciles a receipt against the exact request before it is persisted as
  /// success. This prevents a malformed/replayed response from being shown to
  /// another account or from silently changing the requested variant set.
  void validateAgainst(PlacementRequest request, {required String customerId}) {
    if (order.customerId.toLowerCase() != customerId.toLowerCase() ||
        order.requestId.toLowerCase() != request.requestId.toLowerCase()) {
      throw const FormatException('placement result owner/request mismatch');
    }
    if (order.recipientName != request.recipientName ||
        order.recipientPhone != request.recipientPhone ||
        order.addressDetail != request.addressDetail ||
        (order.latitude - request.latitude).abs() > 0.00000051 ||
        (order.longitude - request.longitude).abs() > 0.00000051) {
      throw const FormatException('placement result recipient mismatch');
    }
    final expected = <String, int>{
      for (final item in request.items)
        item.variantId.toLowerCase(): item.quantity,
    };
    final actual = <String, int>{
      for (final item in items) item.variantId.toLowerCase(): item.quantity,
    };
    if (expected.length != actual.length ||
        expected.entries.any((entry) => actual[entry.key] != entry.value)) {
      throw const FormatException('placement result items mismatch');
    }
  }
}

enum PlacementLookupState { committed, notFound }

/// Lookup deliberately distinguishes not_found from a proven rollback.
class PlacementLookupResult {
  const PlacementLookupResult._({required this.state, this.result});

  factory PlacementLookupResult.committed(PlacementResult result) =>
      PlacementLookupResult._(
        state: PlacementLookupState.committed,
        result: result,
      );

  const PlacementLookupResult.notFound()
    : state = PlacementLookupState.notFound,
      result = null;

  final PlacementLookupState state;
  final PlacementResult? result;

  bool get isCommitted => state == PlacementLookupState.committed;
  bool get isNotFound => state == PlacementLookupState.notFound;
  Order? get order => result?.order;
  List<OrderItem> get items => result?.items ?? const [];
  String? get eventId => result?.eventId;
  bool get replayed => result?.replayed ?? false;
}

String _requireUuid(String value, String field) {
  final normalized = value.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
      .hasMatch(normalized)) {
    throw FormatException('$field must be a UUID');
  }
  return normalized;
}
