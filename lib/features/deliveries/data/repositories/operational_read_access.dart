import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/operational_failure.dart';

/// An account epoch, never an access token or a client-authorized role.
class OperationalSession {
  const OperationalSession({
    required this.userId,
    required this.generation,
    this.failure,
  });

  final String? userId;
  final int generation;
  final OperationalFailure? failure;
}

class ReadIdentity {
  ReadIdentity._(this.userId, this.role, this._ensureCurrent);

  final String userId;
  final String role;
  final void Function() _ensureCurrent;

  void ensureCurrent() => _ensureCurrent();
}

/// Owns only its auth listener/timer. The shared Supabase client is never closed.
/// COD reuses this delivery-owned operational access contract, not a ViewModel.
class OperationalReadAccess {
  OperationalReadAccess(
    this.client, {
    this.readTimeout = const Duration(seconds: 20),
  }) {
    _state = _fromSession(client.auth.currentSession);
    _armExpiry(client.auth.currentSession);
    final initialToken = client.auth.currentSession?.accessToken;
    var firstEvent = true;
    _subscription = client.auth.onAuthStateChange.listen(
      (event) {
        // The SDK replays its latest event to new listeners. Initial state
        // already represents that session; do not cancel the first read.
        final isReplay =
            firstEvent &&
            event.session?.accessToken == initialToken &&
            event.session?.user.id == _state.userId;
        firstEvent = false;
        if (!isReplay) _replace(event.session);
      },
      onError: (Object error, StackTrace stack) {
        if (!_disposed) _replace(null, failure: mapOperationalFailure(error));
      },
    );
  }

  final SupabaseClient client;
  final Duration readTimeout;
  late OperationalSession _state;
  late final StreamSubscription<AuthState> _subscription;
  final _changes = StreamController<OperationalSession>.broadcast(sync: true);
  Timer? _expiry;
  int _generation = 0;
  bool _disposed = false;

  /// Read-only epoch used by navigation to reject superseded authorizations.
  OperationalSession get currentSession => _state;

  OperationalSession _fromSession(
    Session? session, {
    OperationalFailure? failure,
  }) {
    final valid =
        session != null && session.expiresAt != null && !session.isExpired;
    return OperationalSession(
      userId: valid ? session.user.id : null,
      generation: _generation,
      failure:
          failure ??
          (valid
              ? null
              : const OperationalFailure(
                  OperationalFailureCode.sessionExpired,
                )),
    );
  }

  Stream<OperationalSession> watchSession() => Stream.multi((controller) {
    controller.addSync(_state);
    final listener = _changes.stream.listen(
      controller.addSync,
      onDone: controller.closeSync,
    );
    controller.onCancel = listener.cancel;
  });

  void _replace(Session? session, {OperationalFailure? failure}) {
    if (_disposed) return;
    _generation++;
    _state = _fromSession(session, failure: failure);
    _armExpiry(session);
    _changes.add(_state);
  }

  void _armExpiry(Session? session) {
    _expiry?.cancel();
    final expiresAt = session?.expiresAt;
    if (expiresAt == null || session!.isExpired) return;
    final remaining =
        DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)
            .difference(DateTime.now()) -
        const Duration(seconds: 10);
    _expiry = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () => _replace(null),
    );
  }

  /// Explicit retry after an auth-stream/network error, without a fake session.
  void refreshSession() => _replace(client.auth.currentSession);

  void _verify(OperationalSession captured, String token) {
    final session = client.auth.currentSession;
    if (_disposed ||
        !identical(captured, _state) ||
        session == null ||
        session.isExpired ||
        session.user.id != captured.userId ||
        session.accessToken != token) {
      throw const OperationalFailure(OperationalFailureCode.sessionExpired);
    }
  }

  Future<T> run<T>({
    required Set<String> roles,
    required Future<T> Function(ReadIdentity identity) action,
  }) async {
    final captured = _state;
    if (_disposed || captured.userId == null || captured.failure != null) {
      throw captured.failure ??
          const OperationalFailure(OperationalFailureCode.sessionExpired);
    }
    final session = client.auth.currentSession;
    if (session == null) {
      throw const OperationalFailure(OperationalFailureCode.sessionExpired);
    }
    final token = session.accessToken;
    _verify(captured, token);
    try {
      // Authorization is never taken from user_metadata or a cached JWT role.
      final profile = await client
          .from('profiles')
          .select('role')
          .eq('id', captured.userId!)
          .maybeSingle()
          .retry(enabled: false)
          .timeout(readTimeout);
      _verify(captured, token);
      final role = profile?['role'];
      if (role != null && role is! String) {
        throw const FormatException('Invalid role');
      }
      if (role == null || !roles.contains(role)) {
        throw const OperationalFailure(OperationalFailureCode.permissionDenied);
      }
      final result = await action(
        ReadIdentity._(
          captured.userId!,
          role as String,
          () => _verify(captured, token),
        ),
      ).timeout(readTimeout);
      _verify(captured, token);
      return result;
    } catch (error) {
      _verify(captured, token);
      throw mapOperationalFailure(error);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _expiry?.cancel();
    await _subscription.cancel();
    await _changes.close();
  }
}

OperationalFailure mapOperationalFailure(Object error) {
  if (error is OperationalFailure) return error;
  if (error is TimeoutException ||
      error is http.ClientException ||
      error is AuthRetryableFetchException) {
    return const OperationalFailure(OperationalFailureCode.network);
  }
  if (error is AuthException) {
    return OperationalFailure(
      error.statusCode == '403'
          ? OperationalFailureCode.permissionDenied
          : OperationalFailureCode.sessionExpired,
    );
  }
  if (error is PostgrestException) {
    return OperationalFailure(switch (error.code) {
      '401' ||
      'PGRST301' ||
      'PGRST302' ||
      'PGRST303' => OperationalFailureCode.sessionExpired,
      '403' || '42501' => OperationalFailureCode.permissionDenied,
      '22P02' || '23514' || '200' => OperationalFailureCode.invalidData,
      '404' ||
      '42883' ||
      '42P01' ||
      'PGRST202' ||
      'PGRST205' ||
      '500' ||
      '502' ||
      '503' ||
      '504' => OperationalFailureCode.backendUnavailable,
      _ => OperationalFailureCode.unexpected,
    });
  }
  if (error is FormatException ||
      error is TypeError ||
      error is ArgumentError) {
    return const OperationalFailure(OperationalFailureCode.invalidData);
  }
  return const OperationalFailure(OperationalFailureCode.unexpected);
}
