import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/state/epoch_cache.dart';
import '../../../../core/state/foundation_providers.dart';
import '../../../../core/state/session_scope.dart';
import '../../domain/models/notification_item.dart';
import '../../domain/models/notification_target.dart';
import '../../domain/repositories/notification_repository.dart';
import 'notification_providers.dart';
import 'notification_read_invalidation.dart';

/// The target resolver is supplied by the owner of the destination feature.
///
/// The inbox deliberately has no route fallback.  A missing resolver is an
/// explicit unavailable state, which keeps a notification from becoming an
/// arbitrary deep-link or a cached permission decision.
final notificationTargetResolverProvider =
    Provider<NotificationTargetResolver?>((ref) => null);

/// Local interaction state for MH17.
///
/// This state contains only transient affordances.  Accepted notifications,
/// unread counts and read timestamps remain in the foundation read providers
/// and their epoch cache.
class NotificationInteractionState {
  const NotificationInteractionState({
    this.pendingReadIds = const <String>{},
    this.failures = const <String, AppFailure>{},
    this.lastUnavailableMessageKey,
  });

  final Set<String> pendingReadIds;
  final Map<String, AppFailure> failures;
  final String? lastUnavailableMessageKey;

  bool isReadPending(String notificationId) =>
      pendingReadIds.contains(notificationId);

  AppFailure? failureFor(String notificationId) => failures[notificationId];

  NotificationInteractionState copyWith({
    Set<String>? pendingReadIds,
    Map<String, AppFailure>? failures,
    Object? lastUnavailableMessageKey = _unset,
  }) {
    return NotificationInteractionState(
      pendingReadIds: pendingReadIds ?? this.pendingReadIds,
      failures: failures ?? this.failures,
      lastUnavailableMessageKey: identical(lastUnavailableMessageKey, _unset)
          ? this.lastUnavailableMessageKey
          : lastUnavailableMessageKey as String?,
    );
  }
}

const _unset = Object();

/// Coordinates explicit read acknowledgements and guarded target opening.
///
/// A read acknowledgement is accepted only after the repository returns the
/// complete canonical row and [NotificationReadInvalidation] validates its
/// identity, recipient and server read timestamp.  The VM never changes a
/// tile to read optimistically and never decrements the badge locally.
class NotificationInteractionViewModel
    extends Notifier<NotificationInteractionState> {
  final Map<String, Future<bool>> _readRequests = <String, Future<bool>>{};
  int _lifecycle = 0;

  @override
  NotificationInteractionState build() {
    ref.watch(featureSessionScopeProvider);
    // Riverpod may rebuild this notifier in the same session after an inbox
    // permission denial. Old interactions must not publish into that rebuild.
    _lifecycle++;
    // Old futures may complete after an account change or invalidation, but
    // publication requires both their original scope and notifier lifecycle.
    _readRequests.clear();
    ref.onDispose(_readRequests.clear);
    return const NotificationInteractionState();
  }

  /// Returns true only when the server acknowledgement was canonical and was
  /// accepted by the current session's invalidation hook.
  ///
  /// Repeated taps for one row share the same in-flight future.  Other rows
  /// remain interactive while this request is pending.
  Future<bool> markRead(NotificationItem notification) {
    if (!ref.mounted) return Future<bool>.value(false);
    final existing = _readRequests[notification.id];
    if (existing != null) return existing;

    final submittedScope = ref.read(featureSessionScopeProvider);
    final cache = ref.read(epochCacheProvider);
    if (!ref.mounted || !submittedScope.canReadPrivateData || !cache.canRead) {
      final failure = const AppFailure(code: AppFailure.unauthenticated);
      _recordFailure(notification.id, failure, submittedScope);
      return Future<bool>.value(false);
    }
    if (notification.recipientId != submittedScope.userId) {
      const failure = AppFailure(code: AppFailure.forbiddenOrUnavailable);
      _recordFailure(notification.id, failure, submittedScope);
      return Future<bool>.value(false);
    }
    // A read row needs no PATCH.  Perform this after the session/recipient
    // namespace guard so an old or mis-scoped row cannot be acknowledged by
    // merely presenting a non-null read_at.
    if (notification.isRead) return Future<bool>.value(true);

    final repository = ref.read(notificationRepositoryProvider);

    final request = _markRead(
      notification,
      submittedScope: submittedScope,
      cache: cache,
      repository: repository,
      lifecycle: _lifecycle,
    );
    _readRequests[notification.id] = request;
    // Remove only this exact request.  A newer request for this ID must not be
    // removed by an obsolete completion callback.
    unawaited(
      request.whenComplete(() {
        if (identical(_readRequests[notification.id], request)) {
          _readRequests.remove(notification.id);
        }
      }),
    );
    return request;
  }

  Future<bool> _markRead(
    NotificationItem notification, {
    required SessionScope submittedScope,
    required EpochCache cache,
    required NotificationRepository? repository,
    required int lifecycle,
  }) async {
    try {
      _setPending(notification.id, true, submittedScope);
      if (repository == null) {
        throw const AppFailure(code: AppFailure.externalDependencyUnavailable);
      }

      final canonical = await repository
          .markRead(notification.id)
          .timeout(const Duration(seconds: 15));
      if (!_canPublish(submittedScope, cache, lifecycle)) return false;

      // NotificationItem guarantees UTC timestamps at construction time.  The
      // explicit check documents the acknowledgement boundary and protects a
      // future adapter that might bypass the DTO.
      if (canonical.readAt == null || !canonical.readAt!.isUtc) {
        throw const AppFailure(code: AppFailure.unsupportedData);
      }

      final acknowledged = ref
          .read(notificationReadInvalidationProvider)
          .acknowledge(
            canonical,
            expectedNotificationId: notification.id,
            submittedScope: submittedScope,
          );
      if (!acknowledged) {
        throw const AppFailure(code: AppFailure.unsupportedData);
      }
      _clearFailure(notification.id, submittedScope);
      return true;
    } catch (error) {
      if (!_isCurrentLifecycle(lifecycle)) return false;
      final failure = error is TimeoutException
          ? const AppFailure(
              code: AppFailure.outcomeUnknownCode,
              messageKey: 'MSG-10',
              outcomeUnknown: true,
            )
          : _normalizeFailure(error);
      if (failure.code == AppFailure.unauthenticated &&
          _canPublish(submittedScope, cache, lifecycle)) {
        // This invalidates every private resource in this session.  No later
        // callback may reveal the old account while Auth catches up.
        cache.blockSession();
      }
      _recordFailure(notification.id, failure, submittedScope);
      return false;
    } finally {
      if (_isCurrentLifecycle(lifecycle)) {
        _setPending(notification.id, false, submittedScope);
      }
    }
  }

  /// Opens a notification after rechecking current target permission.
  ///
  /// Read acknowledgement and navigation are intentionally independent.  A
  /// network or adapter failure while marking a row read therefore does not
  /// prevent a valid resolver decision from reaching [onNavigate].
  Future<bool> openNotification(
    NotificationItem notification, {
    Future<bool> Function(NotificationTargetDecision)? onNavigate,
  }) async {
    if (!ref.mounted) return false;
    final lifecycle = _lifecycle;
    final submittedScope = ref.read(featureSessionScopeProvider);
    final cache = ref.read(epochCacheProvider);
    if (!ref.mounted || !submittedScope.canReadPrivateData || !cache.canRead) {
      _recordFailure(
        notification.id,
        const AppFailure(code: AppFailure.unauthenticated),
        submittedScope,
      );
      return false;
    }
    // Resolver navigation is recipient-scoped too.  A cached/read row from a
    // different recipient must never reach a target resolver, even when the
    // row itself is already read and therefore needs no mutation.
    if (notification.recipientId != submittedScope.userId) {
      const failure = AppFailure(code: AppFailure.forbiddenOrUnavailable);
      _recordFailure(notification.id, failure, submittedScope);
      return false;
    }

    // A tap on an unread row starts OP-N03, but does not await it before the
    // target lookup.  The read request is deduplicated by row ID.
    if (!notification.isRead) {
      unawaited(markRead(notification));
    }

    final rawType = notification.subjectType.rawValue;
    if (rawType == NotificationSubjectType.notificationOnly.rawValue) {
      // This is an inbox context item.  It has no external subject read and
      // must never invoke a resolver or a deep-link callback.
      return false;
    }
    if (!notification.subjectType.isSupported) {
      _recordFailure(
        notification.id,
        const AppFailure(code: AppFailure.unsupportedData),
        submittedScope,
      );
      return false;
    }

    final resolver = ref.read(notificationTargetResolverProvider);
    if (resolver == null) {
      _setUnavailable('MSG-63', submittedScope);
      return false;
    }

    try {
      // The resolver owns current role/ownership/target permission.  This is
      // intentionally called for already-read rows as well.
      final decision = await resolver
          .resolve(notification.id)
          .timeout(const Duration(seconds: 10));
      if (!_canPublish(submittedScope, cache, lifecycle)) return false;
      if (!_isValidDecision(notification, decision, submittedScope) ||
          onNavigate == null) {
        _setUnavailable(decision.messageKey ?? 'MSG-63', submittedScope);
        return false;
      }
      final navigated = await onNavigate(decision);
      if (!_canPublish(submittedScope, cache, lifecycle)) return false;
      if (!navigated) {
        _setUnavailable(decision.messageKey ?? 'MSG-63', submittedScope);
      } else {
        _clearUnavailable(submittedScope);
      }
      return navigated;
    } catch (error) {
      if (!_isCurrentLifecycle(lifecycle)) return false;
      final failure = _normalizeFailure(error);
      if (failure.code == AppFailure.unauthenticated &&
          _canPublish(submittedScope, cache, lifecycle)) {
        cache.blockSession();
      }
      _recordFailure(notification.id, failure, submittedScope);
      return false;
    }
  }

  bool _isCurrentLifecycle(int lifecycle) =>
      ref.mounted && _lifecycle == lifecycle;

  bool _canPublish(
    SessionScope submittedScope,
    EpochCache cache,
    int lifecycle,
  ) {
    return _isCurrentLifecycle(lifecycle) &&
        ref.read(featureSessionScopeProvider) == submittedScope &&
        identical(ref.read(epochCacheProvider), cache) &&
        cache.canRead;
  }

  void _setPending(String id, bool pending, SessionScope submittedScope) {
    if (!ref.mounted ||
        ref.read(featureSessionScopeProvider) != submittedScope) {
      return;
    }
    final cache = ref.read(epochCacheProvider);
    // Clearing a local token after expiry is safe and prevents an obsolete
    // spinner from surviving in the old namespace.  Starting/publishing a
    // token still requires a readable cache.
    if (!cache.canRead && pending) return;
    final ids = {...state.pendingReadIds};
    if (pending) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    state = state.copyWith(pendingReadIds: ids);
  }

  void _recordFailure(String id, AppFailure failure, SessionScope scope) {
    if (!ref.mounted || ref.read(featureSessionScopeProvider) != scope) return;
    state = state.copyWith(failures: {...state.failures, id: failure});
  }

  void _clearFailure(String id, SessionScope scope) {
    if (!ref.mounted || ref.read(featureSessionScopeProvider) != scope) return;
    if (!state.failures.containsKey(id)) return;
    final failures = {...state.failures}..remove(id);
    state = state.copyWith(failures: failures);
  }

  void _setUnavailable(String messageKey, SessionScope scope) {
    if (!ref.mounted || ref.read(featureSessionScopeProvider) != scope) return;
    state = state.copyWith(lastUnavailableMessageKey: messageKey);
  }

  void _clearUnavailable(SessionScope scope) {
    if (!ref.mounted || ref.read(featureSessionScopeProvider) != scope) return;
    if (state.lastUnavailableMessageKey == null) return;
    state = state.copyWith(lastUnavailableMessageKey: null);
  }

  static AppFailure _normalizeFailure(Object error) {
    if (error is AppFailure) return error;
    if (error is TimeoutException) {
      return const AppFailure(
        code: AppFailure.network,
        messageKey: 'MSG-09',
        retryable: true,
      );
    }
    return const AppFailure(code: AppFailure.unsupportedData);
  }

  /// A resolver is the authority for current object permission, while this
  /// consumer still validates the typed result before allowing the callback.
  /// This prevents a malformed or misrouted resolver response from turning a
  /// notification into an arbitrary screen or entity lookup.
  static bool _isValidDecision(
    NotificationItem notification,
    NotificationTargetDecision decision,
    SessionScope scope,
  ) {
    if (!decision.available ||
        decision.entityId == null ||
        decision.mode == null ||
        decision.screen == null) {
      return false;
    }

    final expectedMode = switch (notification.subjectType.rawValue) {
      'order' => NotificationTargetMode.order,
      'delivery_task' => NotificationTargetMode.deliveryTask,
      'cod' => NotificationTargetMode.cod,
      'return_request' => NotificationTargetMode.returnRequest,
      'conversation' => NotificationTargetMode.conversation,
      _ => null,
    };
    if (expectedMode == null || decision.mode != expectedMode) return false;
    try {
      NotificationTarget(mode: expectedMode, entityId: decision.entityId);
    } on Object {
      return false;
    }

    // A manager opens a delivery incident through MH09's order detail.  The
    // resolver's typed result therefore carries the authorized order UUID,
    // while a shipper opens the task itself.  All other targets remain tied to
    // the persisted subject UUID.
    if (!(expectedMode == NotificationTargetMode.deliveryTask &&
            scope.role == 'manager') &&
        decision.entityId != notification.subjectId) {
      return false;
    }

    return switch ((scope.role, expectedMode, decision.screen)) {
      (
        'customer',
        NotificationTargetMode.order,
        NotificationTargetScreen.customerOrder,
      ) =>
        true,
      (
        'manager',
        NotificationTargetMode.order,
        NotificationTargetScreen.managerOrder,
      ) =>
        true,
      (
        'manager',
        NotificationTargetMode.deliveryTask,
        NotificationTargetScreen.managerOrder,
      ) =>
        true,
      (
        'shipper',
        NotificationTargetMode.deliveryTask,
        NotificationTargetScreen.shipperTask,
      ) =>
        true,
      ('manager', NotificationTargetMode.cod, NotificationTargetScreen.cod) =>
        true,
      ('shipper', NotificationTargetMode.cod, NotificationTargetScreen.cod) =>
        true,
      (
        'customer',
        NotificationTargetMode.returnRequest,
        NotificationTargetScreen.customerReturn,
      ) =>
        true,
      (
        'manager',
        NotificationTargetMode.returnRequest,
        NotificationTargetScreen.managerReturn,
      ) =>
        true,
      (
        'customer',
        NotificationTargetMode.conversation,
        NotificationTargetScreen.conversation,
      ) =>
        true,
      (
        'manager',
        NotificationTargetMode.conversation,
        NotificationTargetScreen.conversation,
      ) =>
        true,
      _ => false,
    };
  }
}

final notificationInteractionViewModelProvider =
    NotifierProvider.autoDispose<
      NotificationInteractionViewModel,
      NotificationInteractionState
    >(NotificationInteractionViewModel.new);
