import 'package:sports_store/features/orders/domain/models/order.dart';
import 'package:sports_store/features/orders/domain/models/order_capabilities.dart';
import 'package:sports_store/features/orders/domain/models/order_details.dart';
import 'package:sports_store/features/orders/domain/models/order_item.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/domain/models/order_summary.dart';
import 'package:sports_store/features/orders/domain/models/order_timeline_entry.dart';
import 'package:sports_store/features/orders/domain/models/return_summary.dart';

import 'mh09_preview_scenario.dart';

/// Pure, deterministic MH09 fixtures layered on top of an existing MH08
/// aggregate.  The selected [Order] remains the source of identity and money
/// values for every scenario.
final class Mh09PreviewFixtures {
  const Mh09PreviewFixtures._();

  static OrderDetails detail(OrderDetails base, Mh09PreviewScenario scene) {
    if (scene == Mh09PreviewScenario.canonical) return base;
    if (scene == Mh09PreviewScenario.normal &&
        base.order.status != OrderStatus.delivered) {
      return base;
    }

    final isDeliveredNormal =
        scene == Mh09PreviewScenario.normal &&
        base.order.status == OrderStatus.delivered;
    final returns = isDeliveredNormal
        ? [_pendingReturn(base.order)]
        : scene == Mh09PreviewScenario.emptyReturns
        ? const <ReturnSummary>[]
        : base.returnSummaries;
    final timeline = isDeliveredNormal
        ? _timelineWithReturn(base, returns.single)
        : scene == Mh09PreviewScenario.emptyReturns
        ? base.timeline
              .where(
                (entry) =>
                    entry.sourceEntityType != TimelineEntityType.returnRequest,
              )
              .toList(growable: false)
        : base.timeline;

    return OrderDetails(
      order: base.order,
      items: scene == Mh09PreviewScenario.large
          ? _largeItems(base.order)
          : base.items,
      buyer: scene == Mh09PreviewScenario.missingBuyer ? null : base.buyer,
      deliverySummary: scene == Mh09PreviewScenario.missingDelivery
          ? null
          : base.deliverySummary,
      codSummary: scene == Mh09PreviewScenario.missingCod
          ? null
          : base.codSummary,
      returnSummaries: returns,
      timeline: timeline,
      historyComplete: base.historyComplete,
      capabilities: _capabilities(base.order.status, base.capabilities, scene),
      asOf: isDeliveredNormal ? returns.single.submittedAt : base.asOf,
    );
  }

  static OrderSummary summary(OrderSummary base, OrderDetails world) {
    if (_isCanonicalSummary(base, world)) return base;

    return OrderSummary(
      order: world.order,
      itemPreview: world.items.take(2).toList(growable: false),
      itemLineCount: world.items.length,
      itemQuantityTotal: world.items.fold<int>(
        0,
        (sum, item) => sum + item.quantity,
      ),
      customerDisplayName: world.buyer?.fullName,
      deliverySummary: world.deliverySummary,
      codSummary: world.codSummary,
      returnSummary: _latestReturn(world.returnSummaries),
      warnings: base.warnings,
      capabilities: world.capabilities,
    );
  }

  static ReturnSummary? _latestReturn(List<ReturnSummary> values) {
    if (values.isEmpty) return null;
    var latest = values.first;
    for (final value in values.skip(1)) {
      if (value.submittedAt.isAfter(latest.submittedAt)) latest = value;
    }
    return latest;
  }

  static bool _isCanonicalSummary(OrderSummary base, OrderDetails world) {
    if (world.order != base.order ||
        world.items.length != base.itemLineCount ||
        world.items.fold<int>(0, (sum, item) => sum + item.quantity) !=
            base.itemQuantityTotal ||
        world.buyer?.fullName != base.customerDisplayName ||
        world.deliverySummary != base.deliverySummary ||
        world.codSummary != base.codSummary ||
        world.capabilities.toMap().toString() !=
            base.capabilities.toMap().toString() ||
        _latestReturn(world.returnSummaries) != base.returnSummary ||
        world.items.length < base.itemPreview.length) {
      return false;
    }
    for (var index = 0; index < base.itemPreview.length; index++) {
      if (world.items[index] != base.itemPreview[index]) return false;
    }
    return true;
  }

  static const _largeItemCount = 40;

  static List<OrderItem> _largeItems(Order order) {
    final unit = order.subtotalVnd ~/ _largeItemCount;
    final remainder = order.subtotalVnd % _largeItemCount;
    final createdAt = order.placedAt;
    return [
      for (var index = 0; index < _largeItemCount; index++)
        OrderItem(
          id: _uuid('item', order.id, index),
          orderId: order.id,
          productId: _uuid('product', order.id, index),
          variantId: _uuid('variant', order.id, index),
          productName:
              'Bộ dụng cụ thể thao chuyên nghiệp phiên bản minh họa MH09 ${index + 1}',
          variantLabel:
              'Màu xanh navy / phiên bản kiểm thử dài / kích thước tiêu chuẩn ${index + 1}',
          attributes: {
            'source': 'MH09-03B large fixture',
            'snapshot_index': index,
          },
          unitPriceVnd: unit + (index < remainder ? 1 : 0),
          quantity: 1,
          lineTotalVnd: unit + (index < remainder ? 1 : 0),
          createdAt: createdAt,
        ),
    ];
  }

  static ReturnSummary _pendingReturn(Order order) {
    final deliveredAt = order.deliveredAt ?? order.updatedAt;
    final submittedAt = deliveredAt.add(const Duration(hours: 2));
    return ReturnSummary(
      returnId: _uuid('return', order.id, 0),
      orderId: order.id,
      status: ReturnRequestStatus.pendingReview,
      submittedAt: submittedAt,
      closedAt: null,
      decisionReason: null,
      isActive: true,
      canSubmitReturn: false,
      eligibilityReason: EligibilityReason.activeReturn,
      returnDeadline: deliveredAt.add(const Duration(days: 7)),
    );
  }

  static List<OrderTimelineEntry> _timelineWithReturn(
    OrderDetails base,
    ReturnSummary summary,
  ) {
    final event = OrderTimelineEntry(
      eventId: _uuid('return-event', base.order.id, 0),
      sourceEntityType: TimelineEntityType.returnRequest,
      sourceEntityId: summary.returnId,
      eventKind: 'return_submitted',
      fromState: null,
      toState: ReturnRequestStatus.pendingReview.wireValue,
      actorId: base.order.customerId,
      actorLabel: 'Khách hàng',
      actorSource: TimelineActorSource.customer,
      occurredAt: summary.submittedAt,
      reason: null,
      source: TimelineSource.actualEvent,
    );
    final result = [...base.timeline, event];
    result.sort((left, right) => left.occurredAt.compareTo(right.occurredAt));
    return result;
  }

  static OrderCapabilities _capabilities(
    OrderStatus status,
    OrderCapabilities base,
    Mh09PreviewScenario scene,
  ) {
    if (scene == Mh09PreviewScenario.commandsDenied) {
      return const OrderCapabilities.none();
    }
    if (scene == Mh09PreviewScenario.confirmOnly) {
      return status == OrderStatus.pendingConfirmation
          ? _only(confirm: true)
          : base;
    }
    if (scene == Mh09PreviewScenario.rejectOnly) {
      return status == OrderStatus.pendingConfirmation
          ? _only(reject: true)
          : base;
    }
    if (scene == Mh09PreviewScenario.exceptionalCancel) {
      return status == OrderStatus.preparing
          ? _only(exceptionalCancel: true)
          : base;
    }
    if (scene == Mh09PreviewScenario.operations) {
      if (status == OrderStatus.preparing) {
        return _only(assign: true, reassign: true);
      }
      if (status == OrderStatus.awaitingRedelivery) {
        return _only(retry: true, earlyReturn: true);
      }
    }
    return base;
  }

  static OrderCapabilities _only({
    bool confirm = false,
    bool reject = false,
    bool exceptionalCancel = false,
    bool assign = false,
    bool reassign = false,
    bool retry = false,
    bool earlyReturn = false,
  }) => OrderCapabilities(
    canCancelCustomer: false,
    canConfirm: confirm,
    canReject: reject,
    canCancelExceptional: exceptionalCancel,
    canAssign: assign,
    canReassign: reassign,
    canArrangeSecondAttempt: retry,
    canRequestEarlyReturn: earlyReturn,
    canReceiveUndelivered: false,
    canOpenReturnCreation: false,
  );

  static String _uuid(String purpose, String orderId, int index) {
    var hash = 0xcbf29ce484222325;
    for (final rune in '$purpose:$orderId:$index'.runes) {
      hash ^= rune;
      hash = (hash * 0x100000001b3) & 0xffffffffffff;
    }
    return 'd09e0000-0000-4000-8000-${hash.toRadixString(16).padLeft(12, '0')}';
  }
}
