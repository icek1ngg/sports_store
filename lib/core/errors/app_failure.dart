import 'unsupported_data_exception.dart';
import 'wire_parsing.dart';

/// Safe error categories exposed to presentation code.  This class deliberately
/// carries no SDK/PostgREST exception and no PII.
class AppFailure implements Exception {
  const AppFailure({
    required this.code,
    this.messageKey,
    this.retryable = false,
    this.currentOrderRef,
    this.outcomeUnknown = false,
  });

  final String code;
  final String? messageKey;
  final bool retryable;
  final OrderStateReference? currentOrderRef;
  final bool outcomeUnknown;

  static const unauthenticated = 'unauthenticated';
  static const forbiddenOrUnavailable = 'forbidden_or_unavailable';
  static const invalidArgument = 'invalid_argument';
  static const stateChanged = 'state_changed';
  static const cancellationNotAllowed = 'cancellation_not_allowed';
  static const idempotencyConflict = 'idempotency_conflict';
  static const dataIntegrity = 'data_integrity';
  static const invalidCursor = 'invalid_cursor';
  static const network = 'network';
  static const outcomeUnknownCode = 'outcome_unknown';
  static const unsupportedData = 'unsupported_data';
  static const externalDependencyUnavailable =
      'external_dependency_unavailable';
  static const custodyUnverified = 'custody_unverified';
  static const goodsDiscrepancy = 'goods_discrepancy';
  static const storeLocationUnavailable = 'store_location_unavailable';

  @override
  String toString() {
    final suffix = messageKey == null ? '' : ' ($messageKey)';
    return 'AppFailure($code$suffix)';
  }

  factory AppFailure.fromDto(AppErrorDto dto, {bool outcomeUnknown = false}) {
    return AppFailure(
      code: dto.code,
      messageKey: dto.messageKey,
      retryable: dto.retryable,
      currentOrderRef: dto.currentOrder,
      outcomeUnknown:
          outcomeUnknown || dto.code == AppFailure.outcomeUnknownCode,
    );
  }
}

/// The JSON error object inside an Orders RPC envelope.  It is kept separate
/// from [AppFailure] so data adapters can validate the wire shape first.
class AppErrorDto {
  AppErrorDto({
    required this.code,
    required this.messageKey,
    required this.retryable,
    required this.currentOrder,
  });

  factory AppErrorDto.fromJson(Map<String, Object?> json) {
    final code = requiredString(json, 'code');
    if (!_knownCodes.contains(code)) {
      throw UnsupportedDataException.unknownEnum(
        path: 'code',
        enumName: 'AppErrorCode',
        rawValue: code,
      );
    }
    final current = requiredField(json, 'current_order');
    if (current != null &&
        code != AppFailure.stateChanged &&
        code != AppFailure.cancellationNotAllowed) {
      throw UnsupportedDataException.invalid(
        path: 'current_order',
        rawValue: current,
        expected:
            'null unless code is state_changed or cancellation_not_allowed',
      );
    }
    OrderStateReference? order;
    if (current != null) {
      final object = _objectFromValue(current, 'current_order');
      final status = requiredString(object, 'status', nonBlank: true);
      if (!_orderStatuses.contains(status)) {
        throw UnsupportedDataException.unknownEnum(
          path: 'current_order.status',
          enumName: 'OrderStatus',
          rawValue: status,
        );
      }
      order = OrderStateReference(
        id: requiredUuid(object, 'id'),
        status: status,
      );
    }
    return AppErrorDto(
      code: code,
      messageKey: nullableString(json, 'message_key'),
      retryable: requiredBool(json, 'retryable'),
      currentOrder: order,
    );
  }

  final String code;
  final String? messageKey;
  final bool retryable;
  final OrderStateReference? currentOrder;

  Map<String, Object?> toJson() => {
    'code': code,
    'message_key': messageKey,
    'retryable': retryable,
    'current_order': currentOrder == null
        ? null
        : {'id': currentOrder!.id, 'status': currentOrder!.status},
  };

  static final _knownCodes = <String>{
    AppFailure.unauthenticated,
    AppFailure.forbiddenOrUnavailable,
    AppFailure.invalidArgument,
    AppFailure.stateChanged,
    AppFailure.cancellationNotAllowed,
    AppFailure.idempotencyConflict,
    AppFailure.dataIntegrity,
    AppFailure.invalidCursor,
    AppFailure.network,
    AppFailure.outcomeUnknownCode,
    AppFailure.unsupportedData,
    AppFailure.externalDependencyUnavailable,
    AppFailure.custodyUnverified,
    AppFailure.goodsDiscrepancy,
    AppFailure.storeLocationUnavailable,
  };

  static const _orderStatuses = <String>{
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
  };

  static Map<String, Object?> _objectFromValue(Object? value, String path) {
    if (value is! Map) {
      throw UnsupportedDataException.invalid(
        path: path,
        rawValue: value,
        expected: 'object',
      );
    }
    try {
      return Map<String, Object?>.from(value);
    } on TypeError {
      throw UnsupportedDataException.invalid(
        path: path,
        rawValue: value,
        expected: 'object with string keys',
      );
    }
  }
}

/// The deliberately small order reference allowed in state/precondition
/// failures.  It does not contain a full order snapshot.
class OrderStateReference {
  OrderStateReference({required String id, required String status})
    : id = _validateUuid(id),
      status = _validateStatus(status);

  final String id;
  final String status;

  static String _validateUuid(String value) {
    final map = <String, Object?>{'id': value};
    return requiredUuid(map, 'id');
  }

  static String _validateStatus(String value) {
    if (value.trim().isEmpty) {
      throw InvalidDomainArgumentException('Order status must not be blank.');
    }
    return value;
  }
}
