import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/unsupported_data_exception.dart';
import '../../../../core/errors/wire_parsing.dart';
import '../../domain/models/buyer.dart';
import '../../domain/models/cod_summary.dart';
import '../../domain/models/delivery_summary.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_capabilities.dart';
import '../../domain/models/order_details.dart';
import '../../domain/models/order_item.dart';
import '../../domain/models/order_mutation_receipt.dart';
import '../../domain/models/order_page.dart';
import '../../domain/models/order_status.dart';
import '../../domain/models/order_summary.dart';
import '../../domain/models/order_timeline_entry.dart';
import '../../domain/models/order_warning.dart';
import '../../domain/models/operation_result.dart';
import '../../domain/models/return_summary.dart';

/// Decodes the revision 1.2 envelope before exposing any business data.
/// An HTTP 200 response with ok=false remains a typed application failure.
T decodeOrderRpcEnvelope<T>(
  Map<String, Object?> json,
  T Function(Map<String, Object?>) decodeData,
) {
  final ok = requiredBool(json, 'ok');
  final data = nullableObject(json, 'data');
  final error = nullableObject(json, 'error');
  if (ok && data != null && error == null) return decodeData(data);
  if (!ok && data == null && error != null) {
    throw AppFailure.fromDto(AppErrorDto.fromJson(error));
  }
  throw UnsupportedDataException.invalid(
    path: 'rpc_envelope',
    rawValue: null,
    expected: 'ok/data/error discriminated response',
  );
}

/// Data-layer mapper for the canonical 21-key `OrderDto` wire object.
class OrderDto {
  OrderDto(this.value);

  factory OrderDto.fromJson(Map<String, Object?> json) {
    return _mapDomainError(
      'order',
      () => OrderDto(
        Order(
          id: requiredUuid(json, 'id'),
          customerId: requiredUuid(json, 'customer_id'),
          requestId: requiredUuid(json, 'request_id'),
          status: OrderStatus.parse(requiredField(json, 'status')),
          recipientName: requiredString(json, 'recipient_name', nonBlank: true),
          recipientPhone: requiredString(
            json,
            'recipient_phone',
            nonBlank: true,
          ),
          addressDetail: requiredString(json, 'address_detail', nonBlank: true),
          latitude: requiredFiniteDouble(json, 'latitude', min: -90, max: 90),
          longitude: requiredFiniteDouble(
            json,
            'longitude',
            min: -180,
            max: 180,
          ),
          subtotalVnd: requiredInt(json, 'subtotal_vnd', min: 0),
          deliveryFeeVnd: requiredInt(json, 'delivery_fee_vnd', min: 0),
          totalCodVnd: requiredInt(json, 'total_cod_vnd', min: 0),
          deliveryAttemptCount: requiredInt(
            json,
            'delivery_attempt_count',
            min: 0,
            max: 2,
          ),
          placedAt: requiredUtcTimestamp(json, 'placed_at'),
          confirmedAt: nullableUtcTimestamp(json, 'confirmed_at'),
          source: _nullableConfirmationSource(json),
          confirmedBy: nullableUuid(json, 'confirmed_by'),
          deliveredAt: nullableUtcTimestamp(json, 'delivered_at'),
          cancelReason: nullableString(json, 'cancel_reason'),
          createdAt: requiredUtcTimestamp(json, 'created_at'),
          updatedAt: requiredUtcTimestamp(json, 'updated_at'),
        ),
      ),
    );
  }

  final Order value;

  Order get domain => value;
  String get id => value.id;
  OrderStatus get status => value.status;

  Map<String, Object?> toJson() => value.toMap();
}

class OrderItemDto {
  OrderItemDto(this.value);

  factory OrderItemDto.fromJson(Map<String, Object?> json) {
    return _mapDomainError(
      'order_item',
      () => OrderItemDto(
        OrderItem(
          id: requiredUuid(json, 'id'),
          orderId: requiredUuid(json, 'order_id'),
          productId: requiredUuid(json, 'product_id'),
          variantId: requiredUuid(json, 'variant_id'),
          productName: requiredString(json, 'product_name', nonBlank: true),
          variantLabel: requiredString(json, 'variant_label', nonBlank: true),
          attributes: requiredObject(json, 'attributes'),
          unitPriceVnd: requiredInt(json, 'unit_price_vnd', min: 0),
          quantity: requiredInt(json, 'quantity', min: 1),
          lineTotalVnd: requiredInt(json, 'line_total_vnd', min: 0),
          createdAt: requiredUtcTimestamp(json, 'created_at'),
        ),
      ),
    );
  }

  final OrderItem value;

  OrderItem get domain => value;

  Map<String, Object?> toJson() => value.toMap();
}

class BuyerDto {
  BuyerDto(this.value);

  factory BuyerDto.fromJson(Map<String, Object?> json) {
    return _mapDomainError(
      'buyer',
      () => BuyerDto(
        Buyer(
          id: requiredUuid(json, 'id'),
          fullName: nullableString(json, 'full_name'),
        ),
      ),
    );
  }

  final Buyer value;
  Buyer get domain => value;

  Map<String, Object?> toJson() => value.toMap();
}

class OrderCapabilitiesDto {
  OrderCapabilitiesDto(this.value);

  factory OrderCapabilitiesDto.fromJson(Map<String, Object?> json) {
    return _mapDomainError(
      'capabilities',
      () => OrderCapabilitiesDto(
        OrderCapabilities(
          canCancelCustomer: requiredBool(json, 'can_cancel_customer'),
          canConfirm: requiredBool(json, 'can_confirm'),
          canReject: requiredBool(json, 'can_reject'),
          canCancelExceptional: requiredBool(json, 'can_cancel_exceptional'),
          canAssign: requiredBool(json, 'can_assign'),
          canReassign: requiredBool(json, 'can_reassign'),
          canArrangeSecondAttempt: requiredBool(
            json,
            'can_arrange_second_attempt',
          ),
          canRequestEarlyReturn: requiredBool(json, 'can_request_early_return'),
          canReceiveUndelivered: requiredBool(json, 'can_receive_undelivered'),
          canOpenReturnCreation: requiredBool(json, 'can_open_return_creation'),
        ),
      ),
    );
  }

  final OrderCapabilities value;
  OrderCapabilities get domain => value;

  Map<String, bool> toJson() => value.toMap();
}

class AttemptSummaryDto {
  AttemptSummaryDto(this.value);

  factory AttemptSummaryDto.fromJson(Map<String, Object?> json) {
    final taskKind = DeliveryTaskKind.parse(requiredField(json, 'task_kind'));
    if (taskKind != DeliveryTaskKind.outbound) {
      throw UnsupportedDataException.invalid(
        path: 'task_kind',
        rawValue: taskKind.wireValue,
        expected: 'outbound',
      );
    }
    return _mapDomainError(
      'attempt_summary',
      () => AttemptSummaryDto(
        AttemptSummary(
          id: requiredUuid(json, 'id'),
          taskId: requiredUuid(json, 'task_id'),
          orderId: requiredUuid(json, 'order_id'),
          attemptNumber: requiredInt(json, 'attempt_number', min: 1, max: 2),
          result: DeliveryAttemptResult.parse(requiredField(json, 'result')),
          reason: nullableString(json, 'reason'),
          occurredAt: requiredUtcTimestamp(json, 'occurred_at'),
          shipperId: nullableUuid(json, 'shipper_id'),
        ),
      ),
    );
  }

  final AttemptSummary value;
  AttemptSummary get domain => value;

  Map<String, Object?> toJson() => value.toMap();
}

class DeliverySummaryDto {
  DeliverySummaryDto(this.value);

  factory DeliverySummaryDto.fromJson(Map<String, Object?> json) {
    final latest = nullableObject(json, 'latest_attempt');
    return _mapDomainError(
      'delivery_summary',
      () => DeliverySummaryDto(
        DeliverySummary(
          taskId: nullableUuid(json, 'task_id'),
          kind: _nullableDeliveryKind(json),
          taskStatus: _nullableDeliveryStatus(json),
          assignedShipperId: nullableUuid(json, 'assigned_shipper_id'),
          assignedShipperName: nullableString(json, 'assigned_shipper_name'),
          assignedAt: nullableUtcTimestamp(json, 'assigned_at'),
          acceptedAt: nullableUtcTimestamp(json, 'accepted_at'),
          startedAt: nullableUtcTimestamp(json, 'started_at'),
          completedAt: nullableUtcTimestamp(json, 'completed_at'),
          amountToCollectVnd: nullableInt(
            json,
            'amount_to_collect_vnd',
            min: 0,
          ),
          attemptCount: requiredInt(json, 'attempt_count', min: 0, max: 2),
          latestAttempt: latest == null
              ? null
              : AttemptSummaryDto.fromJson(latest).domain,
          failureReason: nullableString(json, 'failure_reason'),
        ),
      ),
    );
  }

  final DeliverySummary value;
  DeliverySummary get domain => value;

  Map<String, Object?> toJson() => value.toMap();
}

class CodSummaryDto {
  CodSummaryDto(this.value);

  factory CodSummaryDto.fromJson(Map<String, Object?> json) {
    return _mapDomainError(
      'cod_summary',
      () => CodSummaryDto(
        CodSummary(
          orderId: requiredUuid(json, 'order_id'),
          shipperId: nullableUuid(json, 'shipper_id'),
          status: CodStatus.parse(requiredField(json, 'status')),
          expectedAmountVnd: requiredInt(json, 'expected_amount_vnd', min: 1),
          collectedAmountVnd: requiredInt(json, 'collected_amount_vnd', min: 0),
          receivedAmountVnd: requiredInt(json, 'received_amount_vnd', min: 0),
          collectedAt: nullableUtcTimestamp(json, 'collected_at'),
          collectedBy: nullableUuid(json, 'collected_by'),
          handedOverAt: nullableUtcTimestamp(json, 'handed_over_at'),
          receivedAt: nullableUtcTimestamp(json, 'received_at'),
          receivedBy: nullableUuid(json, 'received_by'),
        ),
      ),
    );
  }

  final CodSummary value;
  CodSummary get domain => value;

  Map<String, Object?> toJson() => value.toMap();
}

class ReturnSummaryDto {
  ReturnSummaryDto(this.value);

  factory ReturnSummaryDto.fromJson(Map<String, Object?> json) {
    return _mapDomainError(
      'return_summary',
      () => ReturnSummaryDto(
        ReturnSummary(
          returnId: requiredUuid(json, 'return_id'),
          orderId: requiredUuid(json, 'order_id'),
          status: ReturnRequestStatus.parse(requiredField(json, 'status')),
          submittedAt: requiredUtcTimestamp(json, 'submitted_at'),
          closedAt: nullableUtcTimestamp(json, 'closed_at'),
          decisionReason: nullableString(json, 'decision_reason'),
          isActive: requiredBool(json, 'is_active'),
          canSubmitReturn: requiredBool(json, 'can_submit_return'),
          eligibilityReason: _nullableEligibilityReason(json),
          returnDeadline: nullableUtcTimestamp(json, 'return_deadline'),
        ),
      ),
    );
  }

  final ReturnSummary value;
  ReturnSummary get domain => value;

  Map<String, Object?> toJson() => value.toMap();
}

class OrderWarningDto {
  OrderWarningDto(this.value);

  factory OrderWarningDto.fromJson(Map<String, Object?> json) {
    final rawCode = requiredString(json, 'code', nonBlank: true);
    return _mapDomainError(
      'warning',
      () => OrderWarningDto(
        OrderWarning(
          code: WarningCode.parse(rawCode),
          sourceId: requiredUuid(json, 'source_id'),
          message: requiredString(json, 'message', nonBlank: true),
          rawCode: rawCode,
        ),
      ),
    );
  }

  final OrderWarning value;
  OrderWarning get domain => value;

  Map<String, Object?> toJson() => value.toMap();
}

class OrderTimelineEntryDto {
  OrderTimelineEntryDto(this.value);

  factory OrderTimelineEntryDto.fromJson(Map<String, Object?> json) {
    return _mapDomainError(
      'timeline',
      () => OrderTimelineEntryDto(
        OrderTimelineEntry(
          eventId: nullableUuid(json, 'event_id'),
          sourceEntityType: TimelineEntityType.parse(
            requiredField(json, 'source_entity_type'),
          ),
          sourceEntityId: requiredUuid(json, 'source_entity_id'),
          eventKind: requiredString(json, 'event_kind', nonBlank: true),
          fromState: nullableString(json, 'from_state', nonBlank: true),
          toState: nullableString(json, 'to_state', nonBlank: true),
          actorId: nullableUuid(json, 'actor_id'),
          actorLabel: nullableString(json, 'actor_label'),
          actorSource: TimelineActorSource.parse(
            requiredField(json, 'actor_source'),
          ),
          occurredAt: requiredUtcTimestamp(json, 'occurred_at'),
          reason: nullableString(json, 'reason'),
          source: TimelineSource.parse(requiredField(json, 'source')),
        ),
      ),
    );
  }

  final OrderTimelineEntry value;
  OrderTimelineEntry get domain => value;

  Map<String, Object?> toJson() => value.toMap();
}

class OrderSummaryDto {
  OrderSummaryDto(this.value);

  factory OrderSummaryDto.fromJson(Map<String, Object?> json) {
    final order = OrderDto.fromJson(requiredObject(json, 'order')).domain;
    final itemMaps = requiredList(json, 'item_preview');
    return _mapDomainError(
      'order_summary',
      () => OrderSummaryDto(
        OrderSummary(
          order: order,
          customerDisplayName: nullableString(json, 'customer_display_name'),
          itemPreview: itemMaps
              .asMap()
              .entries
              .map(
                (entry) => OrderItemDto.fromJson(
                  _mapAt(entry.value, 'item_preview[${entry.key}]'),
                ).domain,
              )
              .toList(),
          itemLineCount: requiredInt(json, 'item_line_count', min: 0),
          itemQuantityTotal: requiredInt(json, 'item_quantity_total', min: 0),
          deliverySummary: _nullableDeliverySummary(json),
          codSummary: _nullableCodSummary(json),
          returnSummary: _nullableReturnSummary(json, 'return_summary'),
          warnings: requiredList(json, 'warnings')
              .asMap()
              .entries
              .map(
                (entry) => OrderWarningDto.fromJson(
                  _mapAt(entry.value, 'warnings[${entry.key}]'),
                ).domain,
              )
              .toList(),
          capabilities: OrderCapabilitiesDto.fromJson(
            requiredObject(json, 'capabilities'),
          ).domain,
        ),
      ),
    );
  }

  final OrderSummary value;
  OrderSummary get domain => value;

  Map<String, Object?> toJson() => value.toMap();
}

class OrderDetailsDto {
  OrderDetailsDto(this.value);

  factory OrderDetailsDto.fromJson(Map<String, Object?> json) {
    final itemMaps = requiredList(json, 'items');
    final returnMaps = requiredList(json, 'return_summaries');
    final timelineMaps = requiredList(json, 'timeline');
    return _mapDomainError(
      'order_details',
      () => OrderDetailsDto(
        OrderDetails(
          order: OrderDto.fromJson(requiredObject(json, 'order')).domain,
          items: itemMaps
              .asMap()
              .entries
              .map(
                (entry) => OrderItemDto.fromJson(
                  _mapAt(entry.value, 'items[${entry.key}]'),
                ).domain,
              )
              .toList(),
          buyer: _nullableBuyer(json),
          deliverySummary: _nullableDeliverySummary(json),
          codSummary: _nullableCodSummary(json),
          returnSummaries: returnMaps
              .asMap()
              .entries
              .map(
                (entry) => ReturnSummaryDto.fromJson(
                  _mapAt(entry.value, 'return_summaries[${entry.key}]'),
                ).domain,
              )
              .toList(),
          timeline: timelineMaps
              .asMap()
              .entries
              .map(
                (entry) => OrderTimelineEntryDto.fromJson(
                  _mapAt(entry.value, 'timeline[${entry.key}]'),
                ).domain,
              )
              .toList(),
          historyComplete: requiredBool(json, 'history_complete'),
          capabilities: OrderCapabilitiesDto.fromJson(
            requiredObject(json, 'capabilities'),
          ).domain,
          asOf: requiredUtcTimestamp(json, 'as_of'),
        ),
      ),
    );
  }

  final OrderDetails value;
  OrderDetails get domain => value;

  Map<String, Object?> toJson() => value.toMap();
}

class OrderListResponseDto {
  OrderListResponseDto(this.value);

  factory OrderListResponseDto.fromJson(Map<String, Object?> json) {
    final itemMaps = requiredList(json, 'items');
    final countMap = requiredObject(json, 'status_counts');
    final counts = <OrderStatus, int>{};
    for (final status in OrderStatus.values) {
      if (!countMap.containsKey(status.wireValue)) {
        throw UnsupportedDataException.missing(
          'status_counts.${status.wireValue}',
        );
      }
      final count = countMap[status.wireValue];
      if (count is! int || count < 0) {
        throw UnsupportedDataException.invalid(
          path: 'status_counts.${status.wireValue}',
          rawValue: count,
          expected: 'non-negative integer',
        );
      }
      counts[status] = count;
    }
    for (final key in countMap.keys) {
      if (OrderStatus.tryParse(key) == null) {
        throw UnsupportedDataException.unknownEnum(
          path: 'status_counts.$key',
          enumName: 'OrderStatus',
          rawValue: key,
        );
      }
    }
    return _mapDomainError(
      'order_page',
      () => OrderListResponseDto(
        OrderPage(
          items: itemMaps
              .asMap()
              .entries
              .map(
                (entry) => OrderSummaryDto.fromJson(
                  _mapAt(entry.value, 'items[${entry.key}]'),
                ).domain,
              )
              .toList(),
          nextCursor: nullableString(json, 'next_cursor', nonBlank: true),
          totalCount: requiredInt(json, 'total_count', min: 0),
          statusCounts: counts,
          asOf: requiredUtcTimestamp(json, 'as_of'),
        ),
      ),
    );
  }

  final OrderPage value;
  OrderPage get domain => value;

  Map<String, Object?> toJson() => {
    'items': value.items.map((item) => item.toMap()).toList(),
    'next_cursor': value.nextCursor,
    'total_count': value.totalCount,
    'status_counts': {
      for (final entry in value.statusCounts.entries)
        entry.key.wireValue: entry.value,
    },
    'as_of': value.asOf.toIso8601String(),
  };
}

/// Alias used by the repository contract when naming the page rather than the
/// wire response.  It retains the same strict parser.
typedef OrderPageDto = OrderListResponseDto;

class OrderMutationReceiptDto {
  OrderMutationReceiptDto(this.value);

  factory OrderMutationReceiptDto.fromJson(Map<String, Object?> json) {
    final current = requiredField(json, 'current_order');
    if (current != null) {
      throw UnsupportedDataException.invalid(
        path: 'current_order',
        rawValue: current,
        expected: 'null in wire revision 1.2',
      );
    }
    return _mapDomainError(
      'mutation_receipt',
      () => OrderMutationReceiptDto(
        OrderMutationReceipt(
          operation: OrderOperation.parse(requiredField(json, 'operation')),
          requestId: requiredUuid(json, 'request_id'),
          eventId: requiredUuid(json, 'event_id'),
          order: OrderDto.fromJson(requiredObject(json, 'order')).domain,
          committedAt: requiredUtcTimestamp(json, 'committed_at'),
          replayed: requiredBool(json, 'replayed'),
          currentOrder: null,
        ),
      ),
    );
  }

  final OrderMutationReceipt value;
  OrderMutationReceipt get domain => value;

  Map<String, Object?> toJson() => value.toMap();
}

class OperationResultDto {
  OperationResultDto(this.value);

  factory OperationResultDto.fromJson(Map<String, Object?> json) {
    final state = requiredString(json, 'state', nonBlank: true);
    final receipt = requiredField(json, 'receipt');
    final failure = requiredField(json, 'failure');
    switch (state) {
      case 'committed':
        if (receipt is! Map || failure != null) {
          throw UnsupportedDataException.invalid(
            path: 'data',
            rawValue: json,
            expected: 'committed with receipt and null failure',
          );
        }
        return OperationResultDto.committed(
          OrderMutationReceiptDto.fromJson(_mapAt(receipt, 'receipt')).domain,
        );
      case 'failed':
        if (receipt != null || failure is! Map) {
          throw UnsupportedDataException.invalid(
            path: 'data',
            rawValue: json,
            expected: 'failed with null receipt and failure',
          );
        }
        return OperationResultDto.failed(
          AppFailure.fromDto(AppErrorDto.fromJson(_mapAt(failure, 'failure'))),
        );
      case 'not_found':
        if (receipt != null || failure != null) {
          throw UnsupportedDataException.invalid(
            path: 'data',
            rawValue: json,
            expected: 'not_found with null receipt and failure',
          );
        }
        return OperationResultDto.notFound();
      default:
        throw UnsupportedDataException.unknownEnum(
          path: 'state',
          enumName: 'OperationResultState',
          rawValue: state,
        );
    }
  }

  OperationResultDto.committed(OrderMutationReceipt receipt)
    : value = OperationResult.committed(receipt);

  OperationResultDto.failed(AppFailure failure)
    : value = OperationResult.failed(failure);

  OperationResultDto.notFound() : value = const OperationResult.notFound();

  final OperationResult value;
  OperationResult get domain => value;
}

OrderConfirmationSource? _nullableConfirmationSource(
  Map<String, Object?> json,
) {
  final value = requiredField(json, 'source');
  return value == null ? null : OrderConfirmationSource.parse(value);
}

DeliveryTaskKind? _nullableDeliveryKind(Map<String, Object?> json) {
  final value = requiredField(json, 'kind');
  return value == null ? null : DeliveryTaskKind.parse(value);
}

DeliveryTaskStatus? _nullableDeliveryStatus(Map<String, Object?> json) {
  final value = requiredField(json, 'task_status');
  return value == null ? null : DeliveryTaskStatus.parse(value);
}

EligibilityReason? _nullableEligibilityReason(Map<String, Object?> json) {
  final value = requiredField(json, 'eligibility_reason');
  return value == null ? null : EligibilityReason.parse(value);
}

DeliverySummary? _nullableDeliverySummary(Map<String, Object?> json) {
  final object = nullableObject(json, 'delivery_summary');
  return object == null ? null : DeliverySummaryDto.fromJson(object).domain;
}

CodSummary? _nullableCodSummary(Map<String, Object?> json) {
  final object = nullableObject(json, 'cod_summary');
  return object == null ? null : CodSummaryDto.fromJson(object).domain;
}

ReturnSummary? _nullableReturnSummary(Map<String, Object?> json, String key) {
  final object = nullableObject(json, key);
  return object == null ? null : ReturnSummaryDto.fromJson(object).domain;
}

Buyer? _nullableBuyer(Map<String, Object?> json) {
  final object = nullableObject(json, 'buyer');
  return object == null ? null : BuyerDto.fromJson(object).domain;
}

Map<String, Object?> _mapAt(Object? value, String path) {
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

T _mapDomainError<T>(String path, T Function() parser) {
  try {
    return parser();
  } on InvalidDomainArgumentException {
    // Domain constructors intentionally avoid wire/parser dependencies. Once
    // a constructor is reached from a DTO, its semantic violation is still a
    // malformed server projection and must be normalized as unsupported data.
    throw UnsupportedDataException.invalid(
      path: path,
      rawValue: null,
      expected: 'valid domain projection',
    );
  }
}
