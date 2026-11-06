import '../../domain/models/checkout_failure.dart';
import '../../domain/models/placement_result.dart';
import '../../../orders/data/models/order_dto.dart';
import '../../../orders/domain/models/order_item.dart';

/// Strict adapter for the `{ok,data,error}` RPC envelope.
class CheckoutEnvelopeDto {
  const CheckoutEnvelopeDto._();

  static PlacementResult decodePlacement(Object? raw) {
    final data = _decodeSuccessData(raw);
    try {
      return _placementResult(data);
    } on CheckoutFailure {
      rethrow;
    } catch (error) {
      throw CheckoutFailure(
        CheckoutFailureCode.invalidData,
        message: 'Dữ liệu xác nhận đơn hàng không hợp lệ.',
      );
    }
  }

  static PlacementLookupResult decodeLookup(Object? raw) {
    final data = _decodeSuccessData(raw);
    if (!data.keys.toSet().containsAll(const [
      'state',
      'order',
      'items',
      'event_id',
      'replayed',
    ])) {
      throw const CheckoutFailure(CheckoutFailureCode.invalidData);
    }
    final state = data['state'];
    if (state is! String) {
      throw const CheckoutFailure(CheckoutFailureCode.invalidData);
    }
    if (state == 'not_found') {
      if (data['order'] != null ||
          data['items'] is! List ||
          (data['items'] as List).isNotEmpty ||
          data['event_id'] != null ||
          data['replayed'] != false) {
        throw const CheckoutFailure(CheckoutFailureCode.invalidData);
      }
      return const PlacementLookupResult.notFound();
    }
    if (state != 'committed') {
      throw const CheckoutFailure(CheckoutFailureCode.invalidData);
    }
    try {
      final order = data['order'];
      final items = data['items'];
      final eventId = data['event_id'];
      final replayed = data['replayed'];
      if (order is! Map || items is! List || eventId is! String) {
        throw const FormatException('lookup data is incomplete');
      }
      if (replayed is! bool) throw const FormatException('replayed invalid');
      return PlacementLookupResult.committed(
        _placementResult({
          'order': Map<String, Object?>.from(order),
          'items': items,
          'event_id': eventId,
          'replayed': replayed,
        }),
      );
    } catch (error) {
      if (error is CheckoutFailure) rethrow;
      throw const CheckoutFailure(CheckoutFailureCode.invalidData);
    }
  }

  static PlacementResult _placementResult(Map<String, Object?> data) {
    final orderRaw = data['order'];
    final itemsRaw = data['items'];
    final eventId = data['event_id'];
    final replayed = data['replayed'];
    if (orderRaw is! Map || itemsRaw is! List || eventId is! String) {
      throw const FormatException('placement result data is incomplete');
    }
    if (replayed is! bool) throw const FormatException('replayed is invalid');
    final order = OrderDto.fromJson(Map<String, Object?>.from(orderRaw)).domain;
    final items = <OrderItem>[];
    for (final raw in itemsRaw) {
      if (raw is! Map) throw const FormatException('order item is invalid');
      items.add(OrderItemDto.fromJson(Map<String, Object?>.from(raw)).domain);
    }
    return PlacementResult(
      order: order,
      items: items,
      eventId: eventId,
      replayed: replayed,
    );
  }

  static Map<String, Object?> _decodeSuccessData(Object? raw) {
    final envelope = _object(raw, 'rpc_envelope');
    if (!envelope.keys.toSet().containsAll(const ['ok', 'data', 'error'])) {
      throw const CheckoutFailure(CheckoutFailureCode.invalidData);
    }
    final ok = envelope['ok'];
    final data = envelope['data'];
    final error = envelope['error'];
    if (ok is bool && ok && data is Map && error == null) {
      return Map<String, Object?>.from(data);
    }
    if (ok is bool && !ok && data == null && error is Map) {
      final code = error['code'];
      if (code is! String || code.trim().isEmpty) {
        throw const CheckoutFailure(CheckoutFailureCode.invalidData);
      }
      throw checkoutFailureFromServerCode(code);
    }
    throw const CheckoutFailure(CheckoutFailureCode.invalidData);
  }

  static Map<String, Object?> _object(Object? value, String path) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw CheckoutFailure(
        CheckoutFailureCode.invalidData,
        message: 'Dữ liệu $path không hợp lệ.',
      );
    }
    return Map<String, Object?>.from(value);
  }
}
