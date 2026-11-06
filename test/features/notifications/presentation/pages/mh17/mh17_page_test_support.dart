import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/read_retry_policy.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/notifications/data/models/notification_dto.dart';
import 'package:sports_store/features/notifications/domain/models/notification_item.dart';
import 'package:sports_store/features/notifications/domain/models/notification_page.dart';
import 'package:sports_store/features/notifications/domain/models/notification_target.dart';
import 'package:sports_store/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sports_store/features/notifications/presentation/pages/notifications_page.dart';
import 'package:sports_store/features/notifications/presentation/view_models/notification_interaction_view_model.dart';
import 'package:sports_store/features/notifications/presentation/view_models/notification_providers.dart';

import '../../../../../fixtures/order_notification_fixtures.dart';

import 'mh17_page_test_fakes.dart';

export 'dart:async' show Completer;

export 'package:flutter/material.dart';
export 'package:flutter_riverpod/flutter_riverpod.dart';
export 'package:flutter_test/flutter_test.dart';
export 'package:sports_store/core/errors/app_failure.dart';
export 'package:sports_store/core/state/foundation_providers.dart';
export 'package:sports_store/core/state/read_retry_policy.dart';
export 'package:sports_store/core/state/session_scope.dart';
export 'package:sports_store/features/notifications/data/models/notification_dto.dart';
export 'package:sports_store/features/notifications/domain/models/notification_item.dart';
export 'package:sports_store/features/notifications/domain/models/notification_page.dart';
export 'package:sports_store/features/notifications/domain/models/notification_query.dart';
export 'package:sports_store/features/notifications/domain/models/notification_target.dart';
export 'package:sports_store/features/notifications/domain/repositories/notification_repository.dart';
export 'package:sports_store/features/notifications/presentation/pages/notifications_page.dart';
export 'package:sports_store/features/notifications/presentation/widgets/notification_tile.dart';
export 'package:sports_store/features/notifications/presentation/view_models/notification_interaction_view_model.dart';
export 'package:sports_store/features/notifications/presentation/view_models/notification_providers.dart';
export 'package:sports_store/shared/widgets/async_content.dart';

export '../../../../../fixtures/order_notification_fixtures.dart';

export 'mh17_page_test_fakes.dart';

const pageScope = SessionScope(
  userId: fixtureCustomerId,
  role: 'customer',
  generation: 1,
);

final row1 = NotificationDto.fromJson({
  ...fixtureNotificationJson(),
  'id': '50000000-0000-4000-8000-000000000011',
  'title': 'Thông báo trang một',
}).domain;

final row2 = NotificationDto.fromJson({
  ...fixtureNotificationJson(),
  'id': '50000000-0000-4000-8000-000000000012',
  'read_at': '2026-10-08T04:00:00Z',
  'title': 'Thông báo trang hai',
}).domain;

final row1Read = NotificationDto.fromJson({
  ...row1.toMap(),
  'read_at': '2026-10-08T04:00:00Z',
}).domain;

final newRow = NotificationDto.fromJson({
  ...fixtureNotificationJson(),
  'id': '50000000-0000-4000-8000-000000000014',
  'title': 'Thông báo mới từ polling',
  'created_at': '2026-10-08T05:00:00Z',
}).domain;

final longRow = NotificationDto.fromJson({
  ...fixtureNotificationJson(),
  'id': '50000000-0000-4000-8000-000000000013',
  'title': 'Thông báo có tiêu đề rất dài để kiểm tra khả năng xuống dòng trên màn hình nhỏ 320 dp',
  'body': List.filled(
    4,
    'Nội dung thông báo dài được giữ nguyên từ máy chủ và phải tự xuống dòng an toàn trên màn hình hẹp mà không gây tràn bố cục hoặc cắt mất ngữ cảnh của người nhận. ',
  ).join(),
}).domain;

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

Widget host(
  PageNotifications repository, {
  NotificationTargetResolver? resolver,
  Future<bool> Function(NotificationTargetDecision)? onNavigate,
  double? textScale,
  bool enablePolling = false,
}) {
  return ProviderScope(
    overrides: [
      featureSessionScopeProvider.overrideWithValue(pageScope),
      notificationRepositoryProvider.overrideWithValue(repository),
      notificationTargetResolverProvider.overrideWithValue(resolver),
      readRetryPolicyProvider.overrideWithValue(
        const ReadRetryPolicy(backoffs: []),
      ),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) {
          final page = NotificationsPage(
            enablePolling: enablePolling,
            onNavigate: onNavigate,
          );
          if (textScale == null) return page;
          return MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: page,
          );
        },
      ),
    ),
  );
}

NotificationPage page(
  List<NotificationItem> items, {
  String? nextCursor,
  int? unreadCount,
}) {
  return NotificationPage(
    items: items,
    nextCursor: nextCursor,
    unreadCount: unreadCount,
    asOf: DateTime.utc(2026, 10, 8, 4),
  );
}
