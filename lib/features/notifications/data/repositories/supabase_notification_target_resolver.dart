import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/wire_parsing.dart';
import '../../../../core/state/session_scope.dart';
import '../../../orders/domain/repositories/order_repository.dart';
import '../../domain/models/notification_target.dart';
import '../../domain/repositories/notification_repository.dart';
import '../models/notification_dto.dart';

/// Uses persisted subject_type/subject_id, never notification display text.
/// The Orders aggregate performs the fresh server-side target permission check.
class SupabaseNotificationTargetResolver implements NotificationTargetResolver {
  SupabaseNotificationTargetResolver({
    required this.client,
    required this.orders,
    required this.readSession,
  });

  final SupabaseClient client;
  final OrderRepository orders;
  final SessionScope Function() readSession;

  @override
  Future<NotificationTargetDecision> resolve(String notificationId) async {
    final scope = readSession();
    final sdk = client.auth.currentSession;
    bool current() =>
        scope.canReadPrivateData &&
        readSession() == scope &&
        sdk != null &&
        sdk.expiresAt != null &&
        !sdk.isExpired &&
        identical(client.auth.currentSession, sdk) &&
        sdk.user.id == scope.userId;
    if (!current()) {
      throw const AppFailure(code: AppFailure.unauthenticated);
    }
    if (!{'customer', 'manager'}.contains(scope.role)) {
      return const NotificationTargetDecision.unavailable();
    }
    try {
      requiredUuid({'id': notificationId}, 'id');
      final row = await client
          .from('notifications')
          .select(
            'id,recipient_id,event_id,subject_type,subject_id,title,body,read_at,created_at',
          )
          .eq('id', notificationId)
          .eq('recipient_id', scope.userId!)
          .setHeader('Authorization', 'Bearer ${sdk!.accessToken}')
          .retry(enabled: false, requestTimeout: const Duration(seconds: 10))
          .maybeSingle();
      if (!current()) throw const AppFailure(code: AppFailure.unauthenticated);
      if (row == null) return const NotificationTargetDecision.unavailable();
      final item = NotificationDto.fromJson(row).domain;
      if (item.id != notificationId ||
          item.recipientId != scope.userId ||
          item.rawSubjectType != 'order') {
        return const NotificationTargetDecision.unavailable();
      }
      final detail = await orders.getOrderDetails(item.subjectId);
      if (!current()) throw const AppFailure(code: AppFailure.unauthenticated);
      if (detail.order.id != item.subjectId ||
          (scope.role == 'customer' &&
              detail.order.customerId != scope.userId)) {
        return const NotificationTargetDecision.unavailable();
      }
      return NotificationTargetDecision(
        available: true,
        mode: NotificationTargetMode.order,
        screen: scope.role == 'manager'
            ? NotificationTargetScreen.managerOrder
            : NotificationTargetScreen.customerOrder,
        entityId: detail.order.id,
      );
    } on AppFailure {
      rethrow;
    } catch (_) {
      if (!current()) throw const AppFailure(code: AppFailure.unauthenticated);
      return const NotificationTargetDecision.unavailable();
    }
  }
}
