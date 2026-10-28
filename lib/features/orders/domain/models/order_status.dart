import '../../../../core/errors/unsupported_data_exception.dart';

/// The exact order_status values from the database contract.
enum OrderStatus {
  pendingConfirmation('pending_confirmation'),
  preparing('preparing'),
  awaitingPickup('awaiting_pickup'),
  delivering('delivering'),
  awaitingRedelivery('awaiting_redelivery'),
  awaitingStoreReturn('awaiting_store_return'),
  delivered('delivered'),
  cancelled('cancelled'),
  rejected('rejected'),
  undeliverableReturned('undeliverable_returned');

  const OrderStatus(this.wireValue);

  final String wireValue;

  String get value => wireValue;

  static OrderStatus parse(Object? raw, {String path = 'status'}) {
    if (raw is! String) {
      throw UnsupportedDataException.invalid(
        path: path,
        rawValue: raw,
        expected: 'OrderStatus string',
      );
    }
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    throw UnsupportedDataException.unknownEnum(
      path: path,
      enumName: 'OrderStatus',
      rawValue: raw,
    );
  }

  static OrderStatus fromWire(Object? raw) => parse(raw);

  static OrderStatus? tryParse(Object? raw) {
    if (raw is! String) return null;
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    return null;
  }

  @override
  String toString() => wireValue;
}

enum OrderConfirmationSource {
  manager('manager'),
  automatic('automatic');

  const OrderConfirmationSource(this.wireValue);

  final String wireValue;

  static OrderConfirmationSource parse(Object? raw, {String path = 'source'}) {
    if (raw is! String) {
      throw UnsupportedDataException.invalid(
        path: path,
        rawValue: raw,
        expected: 'OrderConfirmationSource string',
      );
    }
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    throw UnsupportedDataException.unknownEnum(
      path: path,
      enumName: 'OrderConfirmationSource',
      rawValue: raw,
    );
  }

  static OrderConfirmationSource fromWire(Object? raw) => parse(raw);

  @override
  String toString() => wireValue;
}

enum DeliveryTaskKind {
  outbound('outbound'),
  returnPickup('return_pickup'),
  redelivery('redelivery');

  const DeliveryTaskKind(this.wireValue);

  final String wireValue;

  static DeliveryTaskKind parse(Object? raw, {String path = 'kind'}) {
    if (raw is! String) {
      throw UnsupportedDataException.invalid(
        path: path,
        rawValue: raw,
        expected: 'DeliveryTaskKind string',
      );
    }
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    throw UnsupportedDataException.unknownEnum(
      path: path,
      enumName: 'DeliveryTaskKind',
      rawValue: raw,
    );
  }

  static DeliveryTaskKind fromWire(Object? raw) => parse(raw);

  @override
  String toString() => wireValue;
}

enum DeliveryTaskStatus {
  pendingAssignment('pending_assignment'),
  assigned('assigned'),
  accepted('accepted'),
  inTransit('in_transit'),
  delivered('delivered'),
  failed('failed'),
  returnedToStore('returned_to_store'),
  cancelled('cancelled'),
  managerActionRequired('manager_action_required');

  const DeliveryTaskStatus(this.wireValue);

  final String wireValue;

  static DeliveryTaskStatus parse(Object? raw, {String path = 'task_status'}) {
    if (raw is! String) {
      throw UnsupportedDataException.invalid(
        path: path,
        rawValue: raw,
        expected: 'DeliveryTaskStatus string',
      );
    }
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    throw UnsupportedDataException.unknownEnum(
      path: path,
      enumName: 'DeliveryTaskStatus',
      rawValue: raw,
    );
  }

  static DeliveryTaskStatus fromWire(Object? raw) => parse(raw);

  @override
  String toString() => wireValue;
}

enum DeliveryAttemptResult {
  success('success'),
  failed('failed');

  const DeliveryAttemptResult(this.wireValue);

  final String wireValue;

  static DeliveryAttemptResult parse(Object? raw, {String path = 'result'}) {
    if (raw is! String) {
      throw UnsupportedDataException.invalid(
        path: path,
        rawValue: raw,
        expected: 'DeliveryAttemptResult string',
      );
    }
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    throw UnsupportedDataException.unknownEnum(
      path: path,
      enumName: 'DeliveryAttemptResult',
      rawValue: raw,
    );
  }

  static DeliveryAttemptResult fromWire(Object? raw) => parse(raw);

  @override
  String toString() => wireValue;
}

enum CodStatus {
  uncollected('uncollected'),
  collected('collected'),
  received('received');

  const CodStatus(this.wireValue);

  final String wireValue;

  static CodStatus parse(Object? raw, {String path = 'status'}) {
    if (raw is! String) {
      throw UnsupportedDataException.invalid(
        path: path,
        rawValue: raw,
        expected: 'CodStatus string',
      );
    }
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    throw UnsupportedDataException.unknownEnum(
      path: path,
      enumName: 'CodStatus',
      rawValue: raw,
    );
  }

  static CodStatus fromWire(Object? raw) => parse(raw);

  @override
  String toString() => wireValue;
}

enum ReturnRequestStatus {
  pendingReview('pending_review'),
  initiallyRejected('initially_rejected'),
  awaitingReturnPickup('awaiting_return_pickup'),
  returningToStore('returning_to_store'),
  underInspection('under_inspection'),
  awaitingRefund('awaiting_refund'),
  refunded('refunded'),
  rejectedAfterInspection('rejected_after_inspection'),
  awaitingRedelivery('awaiting_redelivery'),
  redeliveryFailed('redelivery_failed'),
  managerActionRequired('manager_action_required');

  const ReturnRequestStatus(this.wireValue);

  final String wireValue;

  static ReturnRequestStatus parse(Object? raw, {String path = 'status'}) {
    if (raw is! String) {
      throw UnsupportedDataException.invalid(
        path: path,
        rawValue: raw,
        expected: 'ReturnRequestStatus string',
      );
    }
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    throw UnsupportedDataException.unknownEnum(
      path: path,
      enumName: 'ReturnRequestStatus',
      rawValue: raw,
    );
  }

  static ReturnRequestStatus fromWire(Object? raw) => parse(raw);

  @override
  String toString() => wireValue;
}

enum OrderOperation {
  confirm('confirm'),
  reject('reject'),
  customerCancel('customer_cancel'),
  managerCancel('manager_cancel'),
  autoConfirm('auto_confirm');

  const OrderOperation(this.wireValue);

  final String wireValue;

  bool get isClientOperation => this != autoConfirm;

  static OrderOperation parse(Object? raw, {String path = 'operation'}) {
    if (raw is! String) {
      throw UnsupportedDataException.invalid(
        path: path,
        rawValue: raw,
        expected: 'OrderOperation string',
      );
    }
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    throw UnsupportedDataException.unknownEnum(
      path: path,
      enumName: 'OrderOperation',
      rawValue: raw,
    );
  }

  static OrderOperation fromWire(Object? raw) => parse(raw);

  @override
  String toString() => wireValue;
}

enum TimelineEntityType {
  order('order'),
  deliveryTask('delivery_task'),
  cod('cod'),
  returnRequest('return_request');

  const TimelineEntityType(this.wireValue);

  final String wireValue;

  static TimelineEntityType parse(
    Object? raw, {
    String path = 'source_entity_type',
  }) {
    if (raw is! String) {
      throw UnsupportedDataException.invalid(
        path: path,
        rawValue: raw,
        expected: 'TimelineEntityType string',
      );
    }
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    throw UnsupportedDataException.unknownEnum(
      path: path,
      enumName: 'TimelineEntityType',
      rawValue: raw,
    );
  }

  static TimelineEntityType fromWire(Object? raw) => parse(raw);

  @override
  String toString() => wireValue;
}

enum TimelineActorSource {
  manager('manager'),
  system('system'),
  shipper('shipper'),
  customer('customer'),
  unknown('unknown');

  const TimelineActorSource(this.wireValue);

  final String wireValue;

  static TimelineActorSource parse(
    Object? raw, {
    String path = 'actor_source',
  }) {
    if (raw is! String) {
      throw UnsupportedDataException.invalid(
        path: path,
        rawValue: raw,
        expected: 'TimelineActorSource string',
      );
    }
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    throw UnsupportedDataException.unknownEnum(
      path: path,
      enumName: 'TimelineActorSource',
      rawValue: raw,
    );
  }

  static TimelineActorSource fromWire(Object? raw) => parse(raw);

  @override
  String toString() => wireValue;
}

enum TimelineSource {
  actualEvent('actual_event'),
  snapshotMilestone('snapshot_milestone');

  const TimelineSource(this.wireValue);

  final String wireValue;

  static TimelineSource parse(Object? raw, {String path = 'source'}) {
    if (raw is! String) {
      throw UnsupportedDataException.invalid(
        path: path,
        rawValue: raw,
        expected: 'TimelineSource string',
      );
    }
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    throw UnsupportedDataException.unknownEnum(
      path: path,
      enumName: 'TimelineSource',
      rawValue: raw,
    );
  }

  static TimelineSource fromWire(Object? raw) => parse(raw);

  @override
  String toString() => wireValue;
}

enum WarningCode {
  outboundFailure('outbound_failure'),
  custodyIncident('custody_incident'),
  returnActive('return_active'),
  externalDependencyUnavailable('external_dependency_unavailable'),
  historyIncomplete('history_incomplete'),
  goodsDiscrepancy('goods_discrepancy'),
  unknown('unknown');

  const WarningCode(this.wireValue);

  final String wireValue;

  static WarningCode parse(Object? raw, {String path = 'code'}) {
    if (raw is! String) {
      throw UnsupportedDataException.invalid(
        path: path,
        rawValue: raw,
        expected: 'WarningCode string',
      );
    }
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    // Warnings are advisory.  A newer warning code must remain renderable as
    // a generic, no-action warning instead of invalidating the whole order
    // aggregate.  Preserve its raw code on OrderWarning.
    return WarningCode.unknown;
  }

  static WarningCode fromWire(Object? raw) => parse(raw);

  @override
  String toString() => wireValue;
}

enum EligibilityReason {
  outsideWindow('outside_window'),
  notDelivered('not_delivered'),
  activeReturn('active_return'),
  unauthorizedOrUnavailable('unauthorized_or_unavailable'),
  missingContract('missing_contract');

  const EligibilityReason(this.wireValue);

  final String wireValue;

  static EligibilityReason parse(
    Object? raw, {
    String path = 'eligibility_reason',
  }) {
    if (raw is! String) {
      throw UnsupportedDataException.invalid(
        path: path,
        rawValue: raw,
        expected: 'EligibilityReason string',
      );
    }
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    throw UnsupportedDataException.unknownEnum(
      path: path,
      enumName: 'EligibilityReason',
      rawValue: raw,
    );
  }

  static EligibilityReason fromWire(Object? raw) => parse(raw);

  @override
  String toString() => wireValue;
}
