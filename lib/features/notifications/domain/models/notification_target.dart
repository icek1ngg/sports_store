import '../../../../core/errors/unsupported_data_exception.dart';
import '../../../../core/errors/wire_parsing.dart';
import 'notification_item.dart';

enum NotificationTargetMode {
  order('order'),
  deliveryTask('delivery_task'),
  cod('cod'),
  returnRequest('return_request'),
  conversation('conversation'),
  notificationOnly('notification_only');

  const NotificationTargetMode(this.wireValue);

  final String wireValue;
}

enum NotificationTargetScreen {
  customerOrder('customer_order'),
  managerOrder('manager_order'),
  shipperTask('shipper_task'),
  cod('cod'),
  customerReturn('customer_return'),
  managerReturn('manager_return'),
  conversation('conversation'),
  notifications('notifications');

  const NotificationTargetScreen(this.wireValue);

  final String wireValue;
}

/// Typed target data used by the resolver.  It contains no arbitrary URL or
/// route string; the central router chooses the actual destination.
class NotificationTarget {
  NotificationTarget({required this.mode, required String? entityId})
    : entityId = entityId == null
          ? null
          : requiredUuid({'entity_id': entityId}, 'entity_id') {
    if (mode == NotificationTargetMode.notificationOnly && entityId == null) {
      // notification_only normally uses the source event ID, but the
      // resolver may intentionally withhold it from navigation.
      return;
    }
    if (mode != NotificationTargetMode.notificationOnly && entityId == null) {
      throw UnsupportedDataException.invalid(
        path: 'entity_id',
        rawValue: null,
        expected: 'UUID for target mode',
      );
    }
  }

  final NotificationTargetMode mode;
  final String? entityId;
}

class NotificationTargetDecision {
  const NotificationTargetDecision({
    required this.available,
    required this.screen,
    required this.entityId,
    required this.mode,
    this.messageKey,
  });

  const NotificationTargetDecision.unavailable({String? messageKey})
    : this(
        available: false,
        screen: null,
        entityId: null,
        mode: null,
        messageKey: messageKey,
      );

  final bool available;
  final NotificationTargetScreen? screen;
  final String? entityId;
  final NotificationTargetMode? mode;
  final String? messageKey;
}

NotificationTarget targetFromNotification(NotificationItem item) {
  final type = item.subjectType.rawValue;
  final mode = switch (type) {
    'order' => NotificationTargetMode.order,
    'delivery_task' => NotificationTargetMode.deliveryTask,
    'cod' => NotificationTargetMode.cod,
    'return_request' => NotificationTargetMode.returnRequest,
    'conversation' => NotificationTargetMode.conversation,
    'notification_only' => NotificationTargetMode.notificationOnly,
    _ => throw UnsupportedDataException.unknownEnum(
      path: 'subject_type',
      enumName: 'NotificationSubjectType',
      rawValue: type,
    ),
  };
  return NotificationTarget(mode: mode, entityId: item.subjectId);
}
