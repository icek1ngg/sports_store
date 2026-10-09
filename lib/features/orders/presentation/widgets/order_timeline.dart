import 'package:flutter/material.dart';

import '../../../../core/utils/display_formatters.dart';
import '../../domain/models/order_status.dart';
import '../../domain/models/order_timeline_entry.dart';

/// Displays the normalized, server supplied timeline in its given order.
///
/// The widget does not create planned stages, infer transitions from the
/// current order status, or turn a missing actor into "Hệ thống".
class OrderTimeline extends StatelessWidget {
  const OrderTimeline({
    required this.entries,
    this.historyComplete = true,
    this.title = 'Lịch sử đơn hàng',
    super.key,
  });

  final List<OrderTimelineEntry> entries;
  final bool historyComplete;
  final String title;

  @override
  Widget build(BuildContext context) {
    final normalizedEntries = _normalizedEntries();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (!historyComplete) ...[
              const SizedBox(height: 8),
              const _IncompleteHistoryNotice(),
            ],
            const SizedBox(height: 12),
            if (normalizedEntries.isEmpty)
              const Text('Chưa có mốc lịch sử được xác nhận')
            else
              ..._timelineChildren(normalizedEntries),
          ],
        ),
      ),
    );
  }

  List<Widget> _timelineChildren(List<OrderTimelineEntry> normalizedEntries) {
    final children = <Widget>[];
    for (var index = 0; index < normalizedEntries.length; index++) {
      children.add(
        _TimelineRow(
          entry: normalizedEntries[index],
          isLast: index == normalizedEntries.length - 1,
        ),
      );
    }
    return children;
  }

  List<OrderTimelineEntry> _normalizedEntries() {
    final byEventId = <String, _IndexedTimelineEntry>{};
    final withoutEventId = <_IndexedTimelineEntry>[];
    for (var index = 0; index < entries.length; index++) {
      final item = _IndexedTimelineEntry(entries[index], index);
      final eventId = item.entry.eventId;
      if (eventId == null) {
        withoutEventId.add(item);
        continue;
      }
      final previous = byEventId[eventId];
      if (previous == null ||
          (_isSnapshot(previous.entry) && !_isSnapshot(item.entry))) {
        byEventId[eventId] = item;
      }
    }

    final actualEvents = byEventId.values
        .where((item) => !_isSnapshot(item.entry))
        .toList(growable: false);
    final seenFallbacks = <String>{};
    final unique = <_IndexedTimelineEntry>[];
    for (final item in [...byEventId.values, ...withoutEventId]) {
      if (!_isSnapshot(item.entry)) {
        unique.add(item);
        continue;
      }
      final fallbackKey = _fallbackKey(item.entry);
      if (!seenFallbacks.add(fallbackKey)) continue;
      if (_hasActualMilestone(item.entry, actualEvents)) continue;
      unique.add(item);
    }

    unique.sort(_compareTimelineEntries);
    return unique.map((item) => item.entry).toList(growable: false);
  }
}

class _IndexedTimelineEntry {
  const _IndexedTimelineEntry(this.entry, this.index);

  final OrderTimelineEntry entry;
  final int index;
}

int _compareTimelineEntries(
  _IndexedTimelineEntry left,
  _IndexedTimelineEntry right,
) {
  final occurred = left.entry.occurredAt.compareTo(right.entry.occurredAt);
  if (occurred != 0) return occurred;

  // An actual event wins a same-instant tie with a fallback milestone. The
  // fallback removal above normally handles recognized milestones, but the
  // ordering remains deterministic for unknown snapshot state values.
  final sourceRank = (_isSnapshot(left.entry) ? 1 : 0).compareTo(
    _isSnapshot(right.entry) ? 1 : 0,
  );
  if (sourceRank != 0) return sourceRank;

  final leftId = left.entry.eventId ?? '';
  final rightId = right.entry.eventId ?? '';
  final eventId = leftId.compareTo(rightId);
  if (eventId != 0) return eventId;
  return left.index.compareTo(right.index);
}

bool _isSnapshot(OrderTimelineEntry entry) =>
    entry.source == TimelineSource.snapshotMilestone;

String _fallbackKey(OrderTimelineEntry entry) => [
  entry.sourceEntityType.wireValue,
  entry.sourceEntityId,
  entry.occurredAt.toIso8601String(),
  entry.toState ?? '',
  entry.fromState ?? '',
].join('|');

bool _hasActualMilestone(
  OrderTimelineEntry fallback,
  List<_IndexedTimelineEntry> actualEvents,
) {
  final fallbackMilestone = _milestoneKind(fallback);
  return actualEvents.any((item) {
    final actual = item.entry;
    final actualMilestone = _milestoneKind(actual);
    if (actualMilestone == null ||
        fallbackMilestone == null ||
        actualMilestone != fallbackMilestone) {
      return false;
    }
    return actual.sourceEntityType == fallback.sourceEntityType &&
        actual.sourceEntityId == fallback.sourceEntityId;
  });
}

String? _milestoneKind(OrderTimelineEntry entry) {
  if (_isSnapshot(entry)) {
    return switch (entry.toState ?? entry.fromState) {
      'pending_confirmation' => 'order_placed',
      'preparing' => 'order_confirmed',
      'delivered' => 'outbound_delivered',
      _ => null,
    };
  }
  return switch (entry.eventKind) {
    'order_placed' => 'order_placed',
    'order_confirmed_manual' ||
    'order_confirmed_automatic' => 'order_confirmed',
    'outbound_delivered' => 'outbound_delivered',
    _ => null,
  };
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.entry, required this.isLast});

  final OrderTimelineEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final title = _eventTitle(entry);
    final actor = _actorText(entry);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Semantics(
                  label: title,
                  child: Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(formatHanoiDateTime(entry.occurredAt)),
                  if (entry.source == TimelineSource.snapshotMilestone) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Mốc từ bản ghi đơn',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (actor != null) ...[
                    const SizedBox(height: 4),
                    Text('Thực hiện bởi: $actor', softWrap: true),
                  ],
                  if (entry.reason != null &&
                      entry.reason!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Lý do: ${entry.reason}', softWrap: true),
                  ],
                  if (entry.fromState != null || entry.toState != null) ...[
                    const SizedBox(height: 4),
                    _StateTransition(entry: entry),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateTransition extends StatelessWidget {
  const _StateTransition({required this.entry});

  final OrderTimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final from = entry.fromState;
    final to = entry.toState;
    final values = <String>[];
    if (from != null && from.trim().isNotEmpty) {
      values.add(_entityStateLabel(entry.sourceEntityType, from));
    }
    if (to != null && to.trim().isNotEmpty) {
      values.add(_entityStateLabel(entry.sourceEntityType, to));
    }
    return Text('Chuyển trạng thái: ${values.join(' → ')}', softWrap: true);
  }
}

class _IncompleteHistoryNotice extends StatelessWidget {
  const _IncompleteHistoryNotice();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Lịch sử có thể chưa đầy đủ',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: Theme.of(context).colorScheme.outline,
            semanticLabel: 'Lịch sử có thể chưa đầy đủ',
          ),
          const SizedBox(width: 6),
          const Expanded(child: Text('Lịch sử có thể chưa đầy đủ')),
        ],
      ),
    );
  }
}

String _eventTitle(OrderTimelineEntry entry) {
  if (entry.source == TimelineSource.snapshotMilestone) {
    return 'Mốc từ bản ghi đơn';
  }
  return const {
        'order_placed': 'Đơn hàng được tạo',
        'task_assigned': 'Đã phân công nhiệm vụ',
        'task_reassigned': 'Đã phân công lại nhiệm vụ',
        'order_confirmed_manual': 'Đơn hàng được xác nhận',
        'order_confirmed_automatic': 'Đơn hàng tự động xác nhận',
        'order_rejected': 'Đơn hàng bị từ chối',
        'order_cancelled': 'Đơn hàng đã hủy',
        'outbound_delivered': 'Đã giao hàng',
        'outbound_failed': 'Giao hàng thất bại',
        'custody_incident': 'Sự cố bàn giao',
        'cod_received': 'Cửa hàng đã nhận COD',
        'return_submitted': 'Đã gửi yêu cầu trả hàng',
        'return_pickup_approved': 'Đã duyệt lấy hàng trả',
        'return_initial_rejected': 'Yêu cầu trả hàng bị từ chối ban đầu',
        'return_pickup_failed': 'Lấy hàng trả thất bại',
        'return_collection_rescheduled': 'Đã hẹn lại lịch lấy hàng trả',
        'return_more_evidence_requested': 'Yêu cầu bổ sung bằng chứng trả hàng',
        'return_inspection_rejected': 'Từ chối sau kiểm tra',
        'refund_recorded': 'Đã ghi nhận hoàn tiền',
        'rejected_goods_redelivery_assigned': 'Đã phân công giao lại hàng trả',
        'rejected_goods_redelivery_completed': 'Đã giao lại hàng trả',
        'rejected_goods_redelivery_failed': 'Giao lại hàng trả thất bại',
        'support_message_received': 'Có tin nhắn hỗ trợ mới',
        'order_pickup': 'Đã nhận hàng để giao',
        'order_store_handover': 'Đã bàn giao về cửa hàng',
        'order_store_received': 'Cửa hàng đã nhận hàng',
        'order_inventory_inspected': 'Đã kiểm tra hàng',
        'task_assignment_audit': 'Đã cập nhật phân công',
      }[entry.eventKind] ??
      'Sự kiện chưa xác định';
}

String? _actorText(OrderTimelineEntry entry) {
  final actorLabel = entry.actorLabel;
  if (actorLabel != null && actorLabel.trim().isNotEmpty) return actorLabel;
  return switch (entry.actorSource) {
    TimelineActorSource.system => 'Hệ thống',
    TimelineActorSource.manager => 'Quản lý',
    TimelineActorSource.shipper => 'Shipper',
    TimelineActorSource.customer => 'Khách hàng',
    TimelineActorSource.unknown => null,
  };
}

String _entityStateLabel(TimelineEntityType type, String state) {
  return switch (type) {
    TimelineEntityType.order => orderStatusLabel(state),
    TimelineEntityType.deliveryTask => deliveryStatusLabel(state),
    TimelineEntityType.cod => codStatusLabel(state),
    TimelineEntityType.returnRequest => returnStatusLabel(state),
  };
}
