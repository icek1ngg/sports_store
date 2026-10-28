import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/wire_parsing.dart';
import '../../../../core/state/session_scope.dart';
import '../../domain/models/notification_item.dart';
import '../../domain/models/notification_page.dart';
import '../../domain/models/notification_query.dart';
import '../../domain/repositories/notification_repository.dart';
import '../models/notification_dto.dart';

typedef _RequestScope = ({SessionScope scope, Session sdk});

/// OP-N01..03 raw Data API adapter. Authentication is supplied externally.
/// No auth lifecycle, cache, target permission or routing authority lives here.
class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository({
    required this.client,
    required this.readSession,
  });

  final SupabaseClient client;
  final SessionScope Function() readSession;
  static const _columns =
      'id,recipient_id,event_id,subject_type,subject_id,title,body,read_at,created_at';

  _RequestScope _capture() {
    final SessionScope scope;
    final Session? sdk;
    try {
      scope = readSession();
      sdk = client.auth.currentSession;
    } catch (_) {
      throw const AppFailure(code: AppFailure.unauthenticated);
    }
    if (!scope.canReadPrivateData ||
        sdk == null ||
        sdk.expiresAt == null ||
        sdk.isExpired ||
        sdk.user.id != scope.userId) {
      throw const AppFailure(code: AppFailure.unauthenticated);
    }
    try {
      requiredUuid({'id': scope.userId}, 'id');
    } catch (_) {
      throw const AppFailure(code: AppFailure.unauthenticated);
    }
    return (scope: scope, sdk: sdk);
  }

  void _assertCurrent(_RequestScope request) {
    final live = _capture();
    if (live.scope != request.scope || !identical(live.sdk, request.sdk)) {
      throw const AppFailure(code: AppFailure.unauthenticated);
    }
  }

  PostgrestQueryBuilder<dynamic> _table(_RequestScope request) => client
      .from('notifications')
      .setHeader('Authorization', 'Bearer ${request.sdk.accessToken}')
      // Foundation VM owns read retry. A write failure is recovered by another
      // canonical GET on a later markRead call, never by optimistic local ACK.
      .retry(enabled: false, requestTimeout: const Duration(seconds: 10));

  Future<T> _run<T>(Future<T> Function(_RequestScope) operation) async {
    final request = _capture();
    try {
      final result = await operation(request);
      _assertCurrent(request);
      return result;
    } catch (error) {
      // A stale account response cannot be published, even if it was an error.
      _assertCurrent(request);
      throw _failure(error);
    }
  }

  @override
  Future<NotificationPage> getPage(NotificationQuery query) => _run((
    request,
  ) async {
    final cursor = _NotificationCursor.decode(query, request.scope.userId!);
    var select = _table(request)
        .select(_columns)
        .eq('recipient_id', request.scope.userId!);
    if (query.filter == NotificationFilter.unread) {
      select = select.isFilter('read_at', null);
    }
    if (cursor != null) {
      final timestamp = cursor.createdAt.toIso8601String();
      select = select.or(
        'created_at.lt.$timestamp,and(created_at.eq.$timestamp,id.lt.${cursor.id})',
      );
    }
    final response = await select
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(query.limit + 1);
    _assertCurrent(request);
    if (response.length > query.limit + 1) {
      throw const AppFailure(code: AppFailure.unsupportedData);
    }
    final rows = response
        .map((row) => NotificationDto.fromJson(row).domain)
        .toList(growable: false);
    final ids = <String>{};
    NotificationItem? previous;
    for (final row in rows) {
      if (row.recipientId != request.scope.userId ||
          !ids.add(row.id) ||
          (query.filter == NotificationFilter.unread && row.isRead) ||
          (cursor != null && !cursor.precedes(row)) ||
          (previous != null &&
              !_NotificationCursor(
                previous.createdAt,
                previous.id,
              ).precedes(row))) {
        throw const AppFailure(code: AppFailure.unsupportedData);
      }
      previous = row;
    }
    final visible = rows.take(query.limit).toList(growable: false);
    return NotificationPage(
      items: visible,
      nextCursor: rows.length > query.limit
          ? _NotificationCursor(
              visible.last.createdAt,
              visible.last.id,
            ).encode(query, request.scope.userId!)
          : null,
      unreadCount: null,
      asOf: null,
    );
  });

  @override
  Future<int> getUnreadCount() => _run((request) async {
    final count = await _table(request)
        .count(CountOption.exact)
        .eq('recipient_id', request.scope.userId!)
        .isFilter('read_at', null);
    if (count < 0) throw const AppFailure(code: AppFailure.unsupportedData);
    return count;
  });

  NotificationItem _one(
    List<Map<String, dynamic>> rows,
    String id,
    _RequestScope request,
  ) {
    if (rows.isEmpty) {
      throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
    }
    if (rows.length != 1) {
      throw const AppFailure(code: AppFailure.unsupportedData);
    }
    final row = NotificationDto.fromJson(rows.single).domain;
    if (row.id != id || row.recipientId != request.scope.userId) {
      throw const AppFailure(code: AppFailure.unsupportedData);
    }
    return row;
  }

  @override
  Future<NotificationItem> markRead(String notificationId) => _run((
    request,
  ) async {
    String id;
    try {
      id = requiredUuid({'id': notificationId}, 'id');
    } catch (_) {
      throw const AppFailure(code: AppFailure.invalidArgument);
    }
    final existing = await _table(request)
        .select(_columns)
        .eq('id', id)
        .eq('recipient_id', request.scope.userId!);
    _assertCurrent(request);
    final before = _one(existing, id, request);
    if (before.isRead) {
      return before; // canonical first-read ACK, no extra PATCH
    }

    final updated = await _table(request)
        .update({
          // OP-N03 requires a non-null UTC signal. Reuse a timestamp already
          // obtained from this server row instead of a client clock/fake time.
          // stamp_read_time MUST replace it with the first server read time.
          'read_at': before.createdAt.toIso8601String(),
        })
        .eq('id', id)
        .eq('recipient_id', request.scope.userId!)
        .select(_columns);
    _assertCurrent(request);
    final ack = _one(updated, id, request);
    if (!ack.isRead ||
        ack.eventId != before.eventId ||
        ack.subjectType != before.subjectType ||
        ack.subjectId != before.subjectId ||
        ack.title != before.title ||
        ack.body != before.body ||
        ack.createdAt != before.createdAt) {
      throw const AppFailure(code: AppFailure.unsupportedData);
    }
    // Only the database-selected acknowledgement may enter feature state.
    return ack;
  });

  static AppFailure _failure(Object error) {
    if (error is AppFailure) return error;
    if (error is TimeoutException) {
      return const AppFailure(code: AppFailure.network, retryable: true);
    }
    if (error is PostgrestException) {
      final code = error.code;
      if (const {'401', 'PGRST301', 'PGRST302', 'PGRST303'}.contains(code)) {
        return const AppFailure(code: AppFailure.unauthenticated);
      }
      if (const {'403', '42501'}.contains(code)) {
        return const AppFailure(code: AppFailure.forbiddenOrUnavailable);
      }
      if (const {
        'PGRST202',
        'PGRST204',
        'PGRST205',
        '42P01',
        '42703',
      }.contains(code)) {
        return const AppFailure(code: AppFailure.externalDependencyUnavailable);
      }
      if (const {'23503', '23505', '23514'}.contains(code)) {
        return const AppFailure(code: AppFailure.dataIntegrity);
      }
      final status = int.tryParse(code ?? '') ?? 0;
      if ((status >= 500 && status <= 599) ||
          const {
            'PGRST000',
            'PGRST001',
            'PGRST002',
            'PGRST003',
            '40001',
            '40P01',
            '57014',
          }.contains(code)) {
        return const AppFailure(code: AppFailure.network, retryable: true);
      }
      return const AppFailure(code: AppFailure.unsupportedData);
    }
    if (error is AuthException) {
      return error is AuthRetryableFetchException
          ? const AppFailure(code: AppFailure.network, retryable: true)
          : const AppFailure(code: AppFailure.unauthenticated);
    }
    if (error is FormatException || error is Error) {
      return const AppFailure(code: AppFailure.unsupportedData);
    }
    return const AppFailure(code: AppFailure.network, retryable: true);
  }
}

class _NotificationCursor {
  const _NotificationCursor(this.createdAt, this.id);
  final DateTime createdAt;
  final String id;

  bool precedes(NotificationItem item) =>
      item.createdAt.isBefore(createdAt) ||
      (item.createdAt == createdAt && item.id.compareTo(id) < 0);

  String encode(NotificationQuery query, String userId) => base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'user_id': userId,
            'filter': query.filter.wireValue,
            'limit': query.limit,
            'last_created_at': createdAt.toIso8601String(),
            'last_id': id,
          }),
        ),
      )
      .replaceAll('=', '');

  static _NotificationCursor? decode(NotificationQuery query, String userId) {
    final cursor = query.cursor;
    if (cursor == null) return null;
    try {
      if (cursor.length > 2048 ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(cursor)) {
        throw const FormatException();
      }
      final json = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(cursor))),
      );
      if (json is! Map<String, dynamic> ||
          json.length != 6 ||
          json['v'] is! int ||
          json['v'] != 1 ||
          json['user_id'] != userId ||
          json['filter'] != query.filter.wireValue ||
          json['limit'] is! int ||
          json['limit'] != query.limit) {
        throw const FormatException();
      }
      return _NotificationCursor(
        requiredUtcTimestamp(json, 'last_created_at'),
        requiredUuid(json, 'last_id'),
      );
    } catch (_) {
      throw const AppFailure(code: AppFailure.invalidCursor);
    }
  }
}
