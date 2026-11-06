import 'package:sports_store/features/notifications/data/models/notification_dto.dart';
import 'package:sports_store/features/notifications/domain/models/notification_item.dart';
import 'package:sports_store/features/notifications/domain/models/notification_page.dart';
import 'package:sports_store/features/notifications/domain/models/notification_query.dart';
import 'package:sports_store/features/notifications/domain/models/notification_target.dart';
import 'package:sports_store/features/notifications/domain/repositories/notification_repository.dart';

import '../../../../../fixtures/order_notification_fixtures.dart';

export 'dart:async' show Completer;

export 'package:flutter_riverpod/flutter_riverpod.dart';
export 'package:flutter_test/flutter_test.dart';
export 'package:sports_store/core/errors/app_failure.dart';
export 'package:sports_store/core/state/epoch_cache.dart';
export 'package:sports_store/core/state/foundation_providers.dart';
export 'package:sports_store/core/state/read_snapshot.dart';
export 'package:sports_store/core/state/session_scope.dart';
export 'package:sports_store/features/notifications/domain/models/notification_item.dart';
export 'package:sports_store/features/notifications/domain/models/notification_page.dart';
export 'package:sports_store/features/notifications/domain/models/notification_query.dart';
export 'package:sports_store/features/notifications/domain/models/notification_target.dart';
export 'package:sports_store/features/notifications/presentation/view_models/notification_interaction_view_model.dart';
export 'package:sports_store/features/notifications/presentation/view_models/notification_providers.dart';
export 'package:sports_store/features/notifications/presentation/view_models/mh17/notification_page_actions.dart';
export 'package:sports_store/features/notifications/presentation/view_models/mh17/notification_page_read_coordinator.dart';
export 'package:sports_store/features/notifications/presentation/view_models/mh17/notification_page_session_bridge.dart';
export 'package:sports_store/features/notifications/presentation/view_models/mh17/notification_snapshot_projection.dart';

export '../../../../../fixtures/order_notification_fixtures.dart';

NotificationItem actionItem({
  String type = 'order',
  bool read = false,
  String? recipient,
}) {
  final json = fixtureNotificationJson(
    subjectType: type,
    readAt: read ? '2026-10-08T04:00:00Z' : null,
  );
  if (type == 'notification_only') json['subject_id'] = json['event_id'];
  if (recipient != null) json['recipient_id'] = recipient;
  return NotificationDto.fromJson(json).domain;
}

const availableActionOrder = NotificationTargetDecision(
  available: true,
  screen: NotificationTargetScreen.customerOrder,
  entityId: fixtureOrderId,
  mode: NotificationTargetMode.order,
);

class ActionRepositoryFake implements NotificationRepository {
  final calls = <String>[];
  Future<NotificationItem> Function(String)? handler;
  var listCalls = 0, countCalls = 0;
  @override
  Future<NotificationItem> markRead(String id) {
    calls.add(id);
    return handler?.call(id) ?? Future.value(actionItem(read: true));
  }

  @override
  Future<NotificationPage> getPage(NotificationQuery query) async {
    listCalls++;
    return NotificationPage(
      items: const [],
      nextCursor: null,
      unreadCount: null,
      asOf: null,
    );
  }

  @override
  Future<int> getUnreadCount() async {
    countCalls++;
    return 41;
  }
}

class ActionResolverFake implements NotificationTargetResolver {
  final calls = <String>[];
  Future<NotificationTargetDecision> Function(String)? handler;
  NotificationTargetDecision decision = availableActionOrder;
  @override
  Future<NotificationTargetDecision> resolve(String id) {
    calls.add(id);
    return handler?.call(id) ?? Future.value(decision);
  }
}
