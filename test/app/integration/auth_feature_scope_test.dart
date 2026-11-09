import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/state/epoch_cache.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/auth/domain/repositories/auth_repository.dart';
import 'package:sports_store/features/auth/presentation/view_models/auth_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _userA = '10000000-0000-4000-8000-000000000001';
const _userB = '10000000-0000-4000-8000-000000000002';

void main() {
  late _ScopeFixture fixture;

  setUp(() async {
    fixture = await _ScopeFixture.create();
  });

  tearDown(() async => fixture.dispose());

  test(
    'projects server profile role and never exposes token in SessionScope',
    () {
      final scope = fixture.scope;

      expect(scope.userId, _userA);
      expect(scope.role, 'customer');
      expect(scope.roleResolved, isTrue);
      expect(scope.canReadPrivateData, isTrue);
      expect(scope.generation, greaterThanOrEqualTo(1));
      expect(
        scope.toString(),
        isNot(contains(fixture.auth.currentSession.accessToken)),
      );
    },
  );

  test('loading, profile errors and mismatches fail closed', () async {
    final previous = fixture.scope;
    final pending = Completer<AppProfile?>();
    fixture.auth.profileResolver = (_) => pending.future;
    fixture.container.invalidate(currentProfileProvider);
    await _settle();
    expect(fixture.scope.canReadPrivateData, isFalse);

    fixture.auth.profileResolver = (_) async =>
        throw StateError('profile unavailable');
    fixture.container.invalidate(currentProfileProvider);
    await _settle();
    expect(fixture.scope.canReadPrivateData, isFalse);

    fixture.auth.profileResolver = (_) async =>
        const AppProfile(id: _userB, role: AppRole.manager);
    fixture.container.invalidate(currentProfileProvider);
    await _settle();
    expect(fixture.scope.canReadPrivateData, isFalse);
    expect(fixture.scope.userId, isNull);
    expect(fixture.scope.generation, greaterThan(previous.generation));

    pending.complete(const AppProfile(id: _userA, role: AppRole.customer));
    await _settle();
    expect(fixture.scope.canReadPrivateData, isFalse);
  });

  test(
    'account switch and token refresh create new cache namespaces',
    () async {
      final oldScope = fixture.scope;
      final oldCache = fixture.container.read(epochCacheProvider);
      final oldToken = oldCache.begin('private');
      expect(oldCache.accept(oldToken, 'A-only'), isTrue);

      await fixture.switchAccount(_userB, role: AppRole.shipper, nonce: 2);
      final switched = fixture.scope;
      expect(switched.userId, _userB);
      expect(switched.role, 'shipper');
      expect(switched.generation, greaterThan(oldScope.generation));
      expect(
        fixture.container.read(epochCacheProvider).read<String>('private'),
        isNull,
      );

      final beforeRefresh = fixture.scope;
      await fixture.refreshToken(nonce: 3);
      final refreshed = fixture.scope;
      expect(refreshed.userId, _userB);
      expect(refreshed.role, 'shipper');
      expect(refreshed.generation, greaterThan(beforeRefresh.generation));
      // The old cache is disposed when the canonical scope changes; no stale
      // aggregate survives the account/token namespace transition.
      expect(oldCache.read<String>('private'), isNull);
    },
  );

  test('a mismatched SDK token fails closed until Auth catches up', () async {
    final previous = fixture.scope;
    await fixture.replaceSdkSession(_userA, nonce: 99);
    // Production Auth forwards SDK token events.  The explicit invalidation
    // models that event while keeping the SDK client a check-only input.
    fixture.container.invalidate(trustedFeatureSessionProvider);
    await _settle();

    expect(fixture.scope.canReadPrivateData, isFalse);
    expect(fixture.scope.userId, isNull);
    expect(fixture.scope.generation, greaterThan(previous.generation));
  });

  test('a server role change creates a new authorization generation', () async {
    final previous = fixture.scope;
    fixture.auth.profileResolver = (_) async =>
        const AppProfile(id: _userA, role: AppRole.manager);
    fixture.container.invalidate(currentProfileProvider);
    await _settle();

    expect(fixture.scope.userId, _userA);
    expect(fixture.scope.role, 'manager');
    expect(fixture.scope.canReadPrivateData, isTrue);
    expect(fixture.scope.generation, greaterThan(previous.generation));
  });

  test(
    'expiry timer reaches a fail-closed state without rescheduling forever',
    () async {
      await fixture.dispose();
      fixture = await _ScopeFixture.create(expiryInSeconds: 32);
      expect(fixture.scope.canReadPrivateData, isTrue);
      await Future<void>.delayed(const Duration(seconds: 4));
      expect(fixture.scope.canReadPrivateData, isFalse);
      expect(fixture.scope.roleResolved, isTrue);
    },
  );

  test(
    'provider recreation cannot reuse a previous request namespace',
    () async {
      final previous = fixture.scope;
      fixture.container.invalidate(trustedFeatureSessionProvider);
      await _settle();
      expect(fixture.scope.canReadPrivateData, isTrue);
      expect(fixture.scope.generation, greaterThan(previous.generation));
    },
  );

  test(
    'logout denies the old namespace and clears the canonical cache',
    () async {
      final oldCache = fixture.container.read(epochCacheProvider);
      final token = oldCache.begin('private');
      oldCache.accept(token, 'private A');

      fixture.auth.emit(const AuthSession());
      await _settle();

      expect(fixture.scope.canReadPrivateData, isFalse);
      expect(fixture.scope.roleResolved, isTrue);
      expect(fixture.scope.userId, isNull);
      expect(
        fixture.container.read(epochCacheProvider).read<String>('private'),
        isNull,
      );
    },
  );

  test(
    'late profile from a previous account cannot repopulate the new scope',
    () async {
      await fixture.dispose();
      final first = Completer<AppProfile?>();
      final second = Completer<AppProfile?>();
      var calls = 0;
      fixture = await _ScopeFixture.create(
        profileResolver: (_) {
          calls++;
          return calls == 1 ? first.future : second.future;
        },
        settleAfterCreate: false,
      );

      await fixture.switchAccount(_userB, role: AppRole.manager, nonce: 2);
      second.complete(const AppProfile(id: _userB, role: AppRole.manager));
      await _settle();
      expect(fixture.scope.userId, _userB);
      expect(fixture.scope.role, 'manager');
      expect(fixture.scope.canReadPrivateData, isTrue);

      first.complete(const AppProfile(id: _userA, role: AppRole.customer));
      await _settle();
      expect(fixture.scope.userId, _userB);
      expect(fixture.scope.role, 'manager');
    },
  );
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _ScopeFixture {
  _ScopeFixture._(this.client, this.auth, this.container);

  final SupabaseClient client;
  final _FakeAuthRepository auth;
  final ProviderContainer container;

  SessionScope get scope => container.read(trustedFeatureSessionProvider);

  static Future<_ScopeFixture> create({
    Future<AppProfile?> Function(AuthSession session)? profileResolver,
    bool settleAfterCreate = true,
    int expiryInSeconds = 3600,
  }) async {
    final client = await _clientWithSession(
      _userA,
      nonce: 1,
      expiryInSeconds: expiryInSeconds,
    );
    final token = client.auth.currentSession!.accessToken;
    final auth = _FakeAuthRepository(
      AuthSession(userId: _userA, accessToken: token),
      profileResolver ??
          (_) async => const AppProfile(id: _userA, role: AppRole.customer),
    );
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        supabaseClientProvider.overrideWithValue(client),
        featureSessionScopeProvider.overrideWith(
          (ref) => ref.watch(trustedFeatureSessionProvider),
        ),
      ],
    );
    // Keep the bridge, canonical scope and EpochCache alive while events are
    // delivered; this mirrors the eager production composition.
    container.listen<SessionScope>(trustedFeatureSessionProvider, (_, _) {});
    container.listen<SessionScope>(featureSessionScopeProvider, (_, _) {});
    container.listen<EpochCache>(epochCacheProvider, (_, _) {});
    final fixture = _ScopeFixture._(client, auth, container);
    if (settleAfterCreate) await _settle();
    return fixture;
  }

  Future<void> switchAccount(
    String userId, {
    required AppRole role,
    required int nonce,
  }) async {
    await replaceSdkSession(userId, nonce: nonce);
    auth.profileResolver = (_) async => AppProfile(id: userId, role: role);
    auth.emit(
      AuthSession(
        userId: userId,
        accessToken: client.auth.currentSession!.accessToken,
      ),
    );
    await _settle();
  }

  Future<void> refreshToken({required int nonce}) async {
    final userId = client.auth.currentSession!.user.id;
    await replaceSdkSession(userId, nonce: nonce);
    auth.emit(
      AuthSession(
        userId: userId,
        accessToken: client.auth.currentSession!.accessToken,
      ),
    );
    await _settle();
  }

  Future<void> replaceSdkSession(String userId, {required int nonce}) async {
    await client.auth.recoverSession(
      jsonEncode(_sessionJson(userId, nonce: nonce)),
    );
  }

  Future<void> dispose() async {
    container.dispose();
    await client.dispose();
    await auth.dispose();
  }
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._current, this.profileResolver);

  AuthSession _current;
  Future<AppProfile?> Function(AuthSession session) profileResolver;
  final _events = StreamController<AuthSession>.broadcast(sync: true);

  @override
  AuthSession get currentSession => _current;

  @override
  Stream<AuthSession> watchSession() => Stream.multi((controller) {
    controller.addSync(_current);
    final subscription = _events.stream.listen(
      controller.addSync,
      onError: controller.addErrorSync,
    );
    controller.onCancel = subscription.cancel;
  });

  @override
  Future<AppProfile?> getCurrentProfile() => profileResolver(_current);

  void emit(AuthSession value) {
    _current = value;
    _events.add(value);
  }

  @override
  Future<void> login({required String email, required String password}) async {}

  @override
  Future<RegistrationResult> register({
    required String fullName,
    required String phone,
    required String email,
    required String password,
  }) async => const RegistrationResult(needsEmailConfirmation: false);

  @override
  Future<void> logout() async => emit(const AuthSession());

  Future<void> dispose() => _events.close();
}

Future<SupabaseClient> _clientWithSession(
  String userId, {
  required int nonce,
  int expiryInSeconds = 3600,
}) async {
  final client = SupabaseClient(
    'https://scope-test.invalid',
    'sb_publishable_scope_test',
    authOptions: AuthClientOptions(
      autoRefreshToken: false,
      pkceAsyncStorage: _MemoryPkceStorage(),
    ),
    httpClient: MockClient((_) async => http.Response('{}', 200)),
  );
  await client.auth.recoverSession(
    jsonEncode(
      _sessionJson(userId, nonce: nonce, expiryInSeconds: expiryInSeconds),
    ),
  );
  return client;
}

Map<String, Object?> _sessionJson(
  String userId, {
  required int nonce,
  int expiryInSeconds = 3600,
}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final expiresAt =
      DateTime.now()
          .add(Duration(seconds: expiryInSeconds))
          .millisecondsSinceEpoch ~/
      1000;
  final accessToken = [
    part({'alg': 'HS256', 'typ': 'JWT'}),
    part({'sub': userId, 'role': 'authenticated', 'exp': expiresAt}),
    'scope-test-signature-$nonce',
  ].join('.');
  return {
    'access_token': accessToken,
    'refresh_token': 'scope-test-refresh-$nonce',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': userId,
      'aud': 'authenticated',
      'email': 'scope@example.com',
      'app_metadata': <String, Object?>{},
      'user_metadata': {'role': 'manager'},
      'created_at': '2026-10-01T00:00:00Z',
    },
  };
}

class _MemoryPkceStorage extends GotrueAsyncStorage {
  final _values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _values[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}
