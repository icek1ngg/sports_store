import 'buyer.dart';
import 'cod_summary.dart';
import 'delivery_summary.dart';
import 'model_validators.dart';
import 'order.dart';
import 'order_capabilities.dart';
import 'order_item.dart';
import 'order_status.dart';
import 'order_timeline_entry.dart';
import 'return_summary.dart';

class OrderDetails {
  OrderDetails({
    required this.order,
    required List<OrderItem> items,
    required this.buyer,
    required this.deliverySummary,
    required this.codSummary,
    required List<ReturnSummary> returnSummaries,
    required List<OrderTimelineEntry> timeline,
    required this.historyComplete,
    required this.capabilities,
    required DateTime asOf,
  }) : items = List<OrderItem>.unmodifiable(items),
       returnSummaries = List<ReturnSummary>.unmodifiable(returnSummaries),
       timeline = List<OrderTimelineEntry>.unmodifiable(
         _deduplicateTimeline(timeline),
       ),
       asOf = validateUtc(asOf, field: 'asOf') {
    final itemIds = <String>{};
    for (final item in this.items) {
      if (item.orderId != order.id || !itemIds.add(item.id)) {
        throw InvalidDomainArgumentException(
          'Order detail items must belong to the order and be unique.',
        );
      }
    }
    final itemSubtotal = this.items.fold<int>(
      0,
      (sum, item) => sum + item.lineTotalVnd,
    );
    if (itemSubtotal != order.subtotalVnd) {
      throw InvalidDomainArgumentException(
        'Full detail item totals must match order.subtotalVnd.',
      );
    }
    final returnIds = <String>{};
    for (final summary in this.returnSummaries) {
      if (summary.orderId != order.id || !returnIds.add(summary.returnId)) {
        throw InvalidDomainArgumentException(
          'Return summaries must belong to the order and be unique.',
        );
      }
    }
    if (buyer != null && buyer!.id != order.customerId) {
      throw InvalidDomainArgumentException(
        'Buyer projection must reference order.customerId.',
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
    for (final entry in this.timeline) {
      if ((entry.sourceEntityType == TimelineEntityType.order ||
              entry.sourceEntityType == TimelineEntityType.cod) &&
          entry.sourceEntityId != order.id) {
        throw InvalidDomainArgumentException(
          'Order/COD timeline entries must reference the order.',
        );
      }
      if (entry.sourceEntityType == TimelineEntityType.returnRequest &&
          !returnIds.contains(entry.sourceEntityId)) {
        throw InvalidDomainArgumentException(
          'Return timeline entries must reference a returned order summary.',
        );
      }
      if (entry.source == TimelineSource.actualEvent && entry.eventId == null) {
        throw InvalidDomainArgumentException(
          'Actual timeline events require eventId.',
        );
      }
      if (entry.source == TimelineSource.snapshotMilestone &&
          entry.eventId != null) {
        throw InvalidDomainArgumentException(
          'Snapshot milestones must not invent eventId.',
        );
      }
    }
    // The aggregate contract asks the producer to deduplicate event IDs. A
    // legacy adapter can still return a repeated row. Identical rows are
    // coalesced; conflicting rows with one event ID are malformed data.
  }

  static List<OrderTimelineEntry> _deduplicateTimeline(
    Iterable<OrderTimelineEntry> values,
  ) {
    final result = <OrderTimelineEntry>[];
    final byEventId = <String, OrderTimelineEntry>{};
    final fallbackKeys = <String>{};
    for (final entry in values) {
      final eventId = entry.eventId;
      if (eventId != null) {
        final previous = byEventId[eventId];
        if (previous == null) {
          byEventId[eventId] = entry;
          result.add(entry);
        } else if (!_sameTimelineEntry(previous, entry)) {
          throw InvalidDomainArgumentException(
            'Timeline entries with one event ID must agree.',
          );
        }
        continue;
      }
      final key = _timelineKey(entry);
      if (fallbackKeys.add(key)) result.add(entry);
    }
    return result;
  }

  static bool _sameTimelineEntry(
    OrderTimelineEntry left,
    OrderTimelineEntry right,
  ) {
    return left.eventId == right.eventId &&
        left.sourceEntityType == right.sourceEntityType &&
        left.sourceEntityId == right.sourceEntityId &&
        left.eventKind == right.eventKind &&
        left.fromState == right.fromState &&
        left.toState == right.toState &&
        left.actorId == right.actorId &&
        left.actorLabel == right.actorLabel &&
        left.actorSource == right.actorSource &&
        left.occurredAt == right.occurredAt &&
        left.reason == right.reason &&
        left.source == right.source;
  }

  static String _timelineKey(OrderTimelineEntry entry) {
    return [
      entry.sourceEntityType.wireValue,
      entry.sourceEntityId,
      entry.eventKind,
      entry.fromState,
      entry.toState,
      entry.actorId,
      entry.actorLabel,
      entry.actorSource.wireValue,
      entry.occurredAt.toIso8601String(),
      entry.reason,
      entry.source.wireValue,
    ].join('\u0000');
  }

  final Order order;
  final List<OrderItem> items;
  final Buyer? buyer;
  final DeliverySummary? deliverySummary;
  final CodSummary? codSummary;
  final List<ReturnSummary> returnSummaries;
  final List<OrderTimelineEntry> timeline;
  final bool historyComplete;
  final OrderCapabilities capabilities;
  final DateTime asOf;

  DateTime get authoritativeAsOf => asOf;

  Map<String, Object?> toMap() => {
    'order': order.toMap(),
    'items': items.map((item) => item.toMap()).toList(),
    'buyer': buyer?.toMap(),
    'delivery_summary': deliverySummary?.toMap(),
    'cod_summary': codSummary?.toMap(),
    'return_summaries': returnSummaries
        .map((summary) => summary.toMap())
        .toList(),
    'timeline': timeline.map((entry) => entry.toMap()).toList(),
    'history_complete': historyComplete,
    'capabilities': capabilities.toMap(),
    'as_of': asOf.toIso8601String(),
  };
}
