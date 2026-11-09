import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/state/session_scope.dart';
import '../../../../core/supabase/supabase_providers.dart';
import 'auth_providers.dart';

// Survives provider recreation so an old request namespace cannot be reused.
int _lastScopeGeneration = 0;

/// Projects the trusted Auth session and server-owned profile into the
/// namespace consumed by feature read caches.
///
/// The provider is intentionally not auto-disposed.  A scope generation is a
/// process-local namespace for [EpochCache], so the counter must survive the
/// normal `build` reruns caused by Auth/profile provider changes.
/// Auth -> feature-scope composition boundary.
///
/// AuthSession supplies identity and the access-token change signal, while the
/// profile supplied by [currentProfileProvider] supplies authorization.  The
/// Supabase SDK session is consulted only for expiry scheduling/checks; its
/// user metadata is never projected into [SessionScope].
class TrustedFeatureSession extends Notifier<SessionScope> {
  int _generation = 0;
  _ScopeFingerprint? _lastFingerprint;
  Timer? _expiryTimer;
  String? _expiryKey;

  @override
  SessionScope build() {
    _registerDisposeHook();

    final client = ref.watch(supabaseClientProvider);
    final sessionState = ref.watch(authSessionProvider);
    final profileState = ref.watch(currentProfileProvider);
    final sdkSession = client.auth.currentSession;

    _armExpiry(client, sdkSession);

    final projection = _project(
      sessionState: sessionState,
      profileState: profileState,
      sdkSession: sdkSession,
    );
    _advanceGeneration(projection.fingerprint, projection.isValid);

    if (!projection.isValid) {
      // Keep the current generation on the denied namespace.  EpochCache sees
      // canReadPrivateData == false and rejects/clears private data while the
      // next Auth/profile generation is loading.
      final signedOut =
          !sessionState.isLoading &&
          !sessionState.hasError &&
          sessionState.asData?.value.signedIn == false;
      return SessionScope(
        userId: null,
        role: null,
        generation: _generation,
        // Known logout/expiry renders the expired UI, while an unresolved
        // identity/profile continues to show the loading boundary.
        roleResolved: signedOut || sdkSession?.isExpired == true,
      );
    }

    return SessionScope(
      userId: projection.userId,
      role: projection.role,
      generation: _generation,
      roleResolved: true,
    );
  }

  void _registerDisposeHook() {
    ref.onDispose(() {
      _expiryTimer?.cancel();
      _expiryTimer = null;
    });
  }

  _ScopeProjection _project({
    required AsyncValue<AuthSession> sessionState,
    required AsyncValue<AppProfile?> profileState,
    required Session? sdkSession,
  }) {
    final authSession = sessionState.asData?.value;
    final signedIn =
        !sessionState.isLoading &&
        !sessionState.hasError &&
        authSession != null &&
        authSession.signedIn &&
        authSession.userId != null &&
        authSession.userId!.isNotEmpty &&
        authSession.accessToken != null &&
        authSession.accessToken!.isNotEmpty;

    if (!signedIn) {
      return _ScopeProjection.invalid(
        _ScopeFingerprint(
          authPhase: _authPhaseFrom(sessionState, signedIn: false),
          userId: null,
          accessToken: null,
          profilePhase: _ProfilePhase.ignored,
          profileId: null,
          role: null,
          sdkPhase: _SdkPhase.ignored,
        ),
      );
    }

    final userId = authSession.userId!;
    final accessToken = authSession.accessToken!;
    final sdkPhase = _sdkPhaseFrom(sdkSession, userId, accessToken);
    final profile = profileState.asData?.value;
    final profilePhase = _profilePhaseFrom(profileState, profile, userId);
    final role = profile == null ? null : _roleName(profile.role);
    final fingerprint = _ScopeFingerprint(
      authPhase: _AuthPhase.signedIn,
      userId: userId,
      accessToken: accessToken,
      profilePhase: profilePhase,
      profileId: profile?.id,
      role: role,
      sdkPhase: sdkPhase,
    );

    if (sessionState.isLoading || sessionState.hasError) {
      return _ScopeProjection.invalid(fingerprint);
    }
    if (profileState.isLoading || profileState.hasError) {
      return _ScopeProjection.invalid(fingerprint);
    }
    if (profile == null ||
        profile.id != userId ||
        sdkPhase != _SdkPhase.valid) {
      return _ScopeProjection.invalid(fingerprint);
    }
    return _ScopeProjection.valid(fingerprint, userId: userId, role: role!);
  }

  void _advanceGeneration(_ScopeFingerprint fingerprint, bool isValid) {
    final previous = _lastFingerprint;
    if (previous == null) {
      // Preserve the conventional generation 0 for the initial unresolved
      // namespace, while making an already-hydrated valid session generation
      // 1 instead of exposing a never-versioned private namespace.
      if (isValid) _generation = ++_lastScopeGeneration;
    } else if (previous != fingerprint || isValid) {
      // Riverpod invalidation can rebuild the same Notifier instance with an
      // unchanged fingerprint. A new verified build still needs a fresh lease.
      _generation = ++_lastScopeGeneration;
    }
    _lastFingerprint = fingerprint;
  }

  void _armExpiry(SupabaseClient client, Session? sdkSession) {
    final nextKey = _sessionExpiryKey(sdkSession);
    if (nextKey == _expiryKey && _expiryTimer != null) return;

    _expiryTimer?.cancel();
    _expiryTimer = null;
    _expiryKey = nextKey;
    final expiresAt = sdkSession?.expiresAt;
    if (sdkSession == null || expiresAt == null || nextKey == null) return;
    if (sdkSession.isExpired) return;

    // Match the SDK 2.27.x thirty-second expiry margin.  The callback rechecks the
    // current SDK session so a refresh cannot be invalidated by an old timer.
    final due = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)
        .subtract(const Duration(seconds: 30));
    var delay = due.difference(DateTime.now());
    if (delay.isNegative && !sdkSession.isExpired) {
      // The SDK margin uses a moving wall clock.  Keep a tiny retry window
      // instead of spinning zero-duration timers at the margin boundary.
      delay = const Duration(milliseconds: 100);
    }
    _expiryTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => _onExpiryTimer(client, nextKey),
    );
  }

  void _onExpiryTimer(SupabaseClient client, String key) {
    if (!ref.mounted || key != _expiryKey) return;
    _expiryTimer = null;
    final current = client.auth.currentSession;
    final currentKey = _sessionExpiryKey(current);
    if (current == null || currentKey != key) {
      // Do not publish the old scope while logout/refresh is between the SDK
      // and Auth streams.  The next Auth/profile event can establish a new
      // matching namespace.
      ref.invalidateSelf();
      return;
    }
    if (!current.isExpired) {
      _armExpiry(client, current);
      return;
    }
    // Rebuild causes the projection to fail closed from the SDK expiry check.
    ref.invalidateSelf();
  }

  static String? _sessionExpiryKey(Session? session) {
    if (session == null) return null;
    return '${session.user.id}:${session.accessToken}:${session.expiresAt}';
  }

  static String _roleName(AppRole role) => switch (role) {
    AppRole.customer => 'customer',
    AppRole.manager => 'manager',
    AppRole.shipper => 'shipper',
  };
}

enum _AuthPhase { loading, error, signedOut, signedIn }

_AuthPhase _authPhaseFrom(
  AsyncValue<AuthSession> state, {
  required bool signedIn,
}) {
  if (state.hasError) return _AuthPhase.error;
  if (state.isLoading) return _AuthPhase.loading;
  return signedIn ? _AuthPhase.signedIn : _AuthPhase.signedOut;
}

enum _ProfilePhase { ignored, loading, error, missing, valid, mismatch }

_ProfilePhase _profilePhaseFrom(
  AsyncValue<AppProfile?> state,
  AppProfile? profile,
  String userId,
) {
  if (state.hasError) return _ProfilePhase.error;
  if (state.isLoading) return _ProfilePhase.loading;
  if (profile == null) return _ProfilePhase.missing;
  return profile.id == userId ? _ProfilePhase.valid : _ProfilePhase.mismatch;
}

enum _SdkPhase { ignored, missing, mismatched, expired, valid }

_SdkPhase _sdkPhaseFrom(
  Session? sdkSession,
  String userId,
  String accessToken,
) {
  if (sdkSession == null || sdkSession.expiresAt == null) {
    return _SdkPhase.missing;
  }
  if (sdkSession.user.id != userId || sdkSession.accessToken != accessToken) {
    return _SdkPhase.mismatched;
  }
  return sdkSession.isExpired ? _SdkPhase.expired : _SdkPhase.valid;
}

class _ScopeFingerprint {
  const _ScopeFingerprint({
    required this.authPhase,
    required this.userId,
    required this.accessToken,
    required this.profilePhase,
    required this.profileId,
    required this.role,
    required this.sdkPhase,
  });

  final _AuthPhase authPhase;
  final String? userId;
  final String? accessToken;
  final _ProfilePhase profilePhase;
  final String? profileId;
  final String? role;
  final _SdkPhase sdkPhase;

  @override
  bool operator ==(Object other) =>
      other is _ScopeFingerprint &&
      authPhase == other.authPhase &&
      userId == other.userId &&
      accessToken == other.accessToken &&
      profilePhase == other.profilePhase &&
      profileId == other.profileId &&
      role == other.role &&
      sdkPhase == other.sdkPhase;

  @override
  int get hashCode => Object.hash(
    authPhase,
    userId,
    accessToken,
    profilePhase,
    profileId,
    role,
    sdkPhase,
  );
}

class _ScopeProjection {
  const _ScopeProjection.invalid(this.fingerprint)
    : isValid = false,
      userId = null,
      role = null;

  const _ScopeProjection.valid(
    this.fingerprint, {
    required this.userId,
    required this.role,
  }) : isValid = true;

  final _ScopeFingerprint fingerprint;
  final bool isValid;
  final String? userId;
  final String? role;
}
