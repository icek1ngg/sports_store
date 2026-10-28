import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/notifications/domain/models/notification_item.dart';
import 'package:sports_store/features/notifications/domain/models/notification_page.dart';
import 'package:sports_store/features/notifications/domain/models/notification_query.dart';
import 'package:sports_store/features/notifications/domain/repositories/notification_repository.dart';

export 'dart:async' show Completer;

export 'package:flutter/material.dart';
export 'package:flutter_riverpod/flutter_riverpod.dart';
export 'package:flutter_test/flutter_test.dart';
export 'package:sports_store/core/errors/app_failure.dart';
export 'package:sports_store/core/state/epoch_cache.dart';
export 'package:sports_store/core/state/foundation_providers.dart';
export 'package:sports_store/core/state/session_scope.dart';
export 'package:sports_store/features/notifications/domain/models/notification_page.dart';
export 'package:sports_store/features/notifications/domain/models/notification_query.dart';
export 'package:sports_store/features/notifications/presentation/view_models/notification_providers.dart';
export 'package:sports_store/features/notifications/presentation/widgets/mh17/notification_context_handle.dart';
export 'package:sports_store/features/notifications/presentation/widgets/mh17/notification_context_modal.dart';
export 'package:sports_store/features/notifications/presentation/widgets/mh17/notification_context_sheet.dart';

const contextOwner = '10000000-0000-4000-8000-000000000001';
const otherContextOwner = '10000000-0000-4000-8000-000000000002';
const contextScope = SessionScope(
  userId: contextOwner,
  role: 'customer',
  generation: 1,
);
final contextScopeProvider = NotifierProvider<ContextScope, SessionScope>(
  ContextScope.new,
);

class ContextScope extends Notifier<SessionScope> {
  @override
  SessionScope build() => contextScope;
  void change(SessionScope value) => state = value;
}

NotificationPage emptyContextPage() => NotificationPage(
  items: const [],
  nextCursor: null,
  unreadCount: 0,
  asOf: DateTime.utc(2026, 10, 22),
);

class ContextRepository implements NotificationRepository {
  bool denyList = false, denyCount = false;
  int pageCalls = 0, countCalls = 0, markCalls = 0;
  Completer<NotificationPage>? pendingPage;
  @override
  Future<NotificationPage> getPage(NotificationQuery query) async {
    pageCalls++;
    if (denyList) {
      throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
    }
    return pendingPage?.future ?? emptyContextPage();
  }

  @override
  Future<int> getUnreadCount() async {
    countCalls++;
    if (denyCount) {
      throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
    }
    return 41;
  }

  @override
  Future<NotificationItem> markRead(String id) async {
    markCalls++;
    throw StateError('Modal must never request acknowledgement');
  }
}
