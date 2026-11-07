import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sports_store/features/auth/data/repositories/supabase_auth_repository.dart';
import 'package:sports_store/features/auth/data/email_confirmation_callback.dart';
import 'package:sports_store/features/auth/domain/models/email_confirmation_result.dart';
import 'package:sports_store/features/auth/domain/models/app_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _userId = '10000000-0000-4000-8000-000000000001';
const _otherId = '10000000-0000-4000-8000-000000000002';

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

Map<String, Object?> _user(String id) => {
  'id': id,
  'aud': 'authenticated',
  'email': 'customer@example.com',
  'app_metadata': <String, Object?>{},
  // Deliberately malicious user-editable role. It must never authorize access.
  'user_metadata': {'role': 'manager'},
  'created_at': '2026-10-01T00:00:00Z',
};

Map<String, Object?> _session({String id = _userId, bool expired = false}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final expiresAt =
      DateTime.now()
          .add(expired ? const Duration(hours: -1) : const Duration(hours: 1))
          .millisecondsSinceEpoch ~/
      1000;
  return {
    'access_token': [
      part({'alg': 'HS256', 'typ': 'JWT'}),
      part({'sub': id, 'role': 'authenticated', 'exp': expiresAt}),
      part('test-only-signature'),
    ].join('.'),
    'refresh_token': 'test-only-refresh',
    'token_type': 'bearer',
    'expires_in': expired ? -3600 : 3600,
    'user': _user(id),
  };
}

http.Response _json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  late SupabaseClient client;
  late SupabaseAuthRepository repository;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) handle;

  setUp(() {
    requests = [];
    handle = (_) async => _json({});
    client = SupabaseClient(
      'https://auth-test.invalid',
      'sb_publishable_test-only',
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: _MemoryPkceStorage(),
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        final response = await handle(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    repository = SupabaseAuthRepository(client);
  });

  tearDown(() => client.dispose());

  Future<void> supplySession({String id = _userId}) =>
      client.auth.recoverSession(jsonEncode(_session(id: id)));

  test(
    'login sends normalized email, preserves password and creates session',
    () async {
      handle = (request) async => _json(_session());
      await repository.login(
        email: ' customer@example.com ',
        password: ' pass 123 ',
      );
      expect(requests.single.url.path, '/auth/v1/token');
      expect(requests.single.url.queryParameters['grant_type'], 'password');
      expect(
        jsonDecode(requests.single.body),
        allOf(
          containsPair('email', 'customer@example.com'),
          containsPair('password', ' pass 123 '),
        ),
      );
      expect(repository.currentSession.userId, _userId);
      expect(repository.currentSession.signedIn, isTrue);
    },
  );

  test('signup submits personal fields only and requires confirmation without session', () async {
    repository = SupabaseAuthRepository(
      client,
      emailRedirectTo: 'http://localhost:57604/auth/confirm-email',
    );
    handle = (_) async => _json(_user(_userId));
    final result = await repository.register(
      fullName: ' Nguyễn An ',
      phone: ' 0912345678 ',
      email: ' customer@example.com ',
      password: 'strong-password',
    );
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(requests.single.url.path, '/auth/v1/signup');
    expect(
      requests.single.url.queryParameters['redirect_to'],
      'http://localhost:57604/auth/confirm-email',
    );
    expect(body['data'], {'full_name': 'Nguyễn An', 'phone': '0912345678'});
    expect((body['data'] as Map).containsKey('role'), isFalse);
    expect(result.needsEmailConfirmation, isTrue);
    expect(repository.currentSession.signedIn, isFalse);
  });

  test(
    'signup callback reports success after SDK exchanges the code',
    () async {
      handle = (request) async {
        if (request.url.path.endsWith('/signup')) return _json(_user(_userId));
        expect(request.url.queryParameters['grant_type'], 'pkce');
        final session = _session();
        (session['user']! as Map<String, Object?>)['email_confirmed_at'] =
            '2026-11-07T00:00:00Z';
        return _json(session);
      };
      await repository.register(
        fullName: 'Nguyễn An',
        phone: '0912345678',
        email: 'customer@example.com',
        password: 'strong-password',
      );
      final callback = Uri.parse('http://localhost:57604/?code=test-code');
      await client.auth.getSessionFromUrl(callback);
      expect(
        EmailConfirmationCallback.resolveAfterSdkInitialization(
          callback,
          client.auth.currentSession,
        ),
        EmailConfirmationResult.success,
      );
      expect(
        requests.where((r) => r.url.path.endsWith('/token')),
        hasLength(1),
      );
    },
  );

  test('failed SDK code exchange never reports confirmation success', () async {
    handle = (_) async =>
        _json({'error_code': 'bad_code_verifier', 'msg': 'Invalid code'}, 400);
    final callback = Uri.parse('http://localhost:57604/?code=invalid');
    await expectLater(
      client.auth.getSessionFromUrl(callback),
      throwsA(isA<AuthException>()),
    );
    expect(
      EmailConfirmationCallback.resolveAfterSdkInitialization(
        callback,
        client.auth.currentSession,
      ),
      EmailConfirmationResult.failed,
    );
  });

  test(
    'legacy implicit callback succeeds only after the SDK verifies its user',
    () async {
      handle = (request) async {
        expect(request.url.path, '/auth/v1/user');
        return _json({
          ..._user(_userId),
          'email_confirmed_at': '2026-11-07T00:00:00Z',
        });
      };
      final session = _session();
      final callback = Uri.parse('http://localhost:57604/').replace(
        fragment: Uri(
          queryParameters: {
            'access_token': session['access_token']! as String,
            'refresh_token': session['refresh_token']! as String,
            'expires_in': '3600',
            'token_type': 'bearer',
            'type': 'signup',
          },
        ).query,
      );
      await client.auth.getSessionFromUrl(callback);
      expect(
        EmailConfirmationCallback.resolveAfterSdkInitialization(
          callback,
          client.auth.currentSession,
        ),
        EmailConfirmationResult.success,
      );
      // An auth error takes precedence even when a verified session exists.
      expect(
        EmailConfirmationCallback.resolveAfterSdkInitialization(
          Uri.parse('http://localhost:57604/#error_code=otp_expired'),
          client.auth.currentSession,
        ),
        EmailConfirmationResult.expired,
      );
    },
  );

  test(
    'profile uses server role rather than user metadata and scopes read by id',
    () async {
      await supplySession();
      handle = (_) async => _json([
        {
          'id': _userId,
          'role': 'customer',
          'full_name': 'An',
          'phone': '0912345678',
        },
      ]);
      final profile = await repository.getCurrentProfile();
      expect(profile!.role, AppRole.customer);
      expect(profile.fullName, 'An');
      expect(requests.single.url.queryParameters['id'], 'eq.$_userId');
      expect(
        requests.single.url.queryParameters['select'],
        'id,role,full_name,phone',
      );
    },
  );

  test('missing profile never falls back to role in metadata', () async {
    await supplySession();
    handle = (_) async => _json(<Object>[]);
    await expectLater(
      repository.getCurrentProfile(),
      throwsA(isA<AuthenticationFailure>()),
    );
  });

  test('unknown server role is rejected', () async {
    await supplySession();
    handle = (_) async => _json({'id': _userId, 'role': 'admin'});
    await expectLater(
      repository.getCurrentProfile(),
      throwsA(isA<AuthenticationFailure>()),
    );
  });

  test('profile completion after an account switch is rejected', () async {
    await supplySession();
    final pending = Completer<http.Response>();
    handle = (_) => pending.future;
    final read = repository.getCurrentProfile();
    final assertion = expectLater(read, throwsA(isA<AuthenticationFailure>()));
    await Future<void>.delayed(Duration.zero);
    await supplySession(id: _otherId);
    pending.complete(_json({'id': _userId, 'role': 'manager'}));
    await assertion;
  });

  test('a failed profile request has no automatic SDK retry', () async {
    await supplySession();
    handle = (_) async => _json({'message': 'unavailable'}, 503);
    await expectLater(
      repository.getCurrentProfile(),
      throwsA(isA<AuthenticationFailure>()),
    );
    expect(requests.length, 1);
  });

  test(
    'watchSession receives SDK initial session without a login action',
    () async {
      final first = await repository.watchSession().first;
      expect(first.signedIn, isFalse);
    },
  );

  test('logout clears session after backend acknowledgement', () async {
    await supplySession();
    handle = (_) async => http.Response('', 204);
    await repository.logout();
    expect(requests.single.url.path, '/auth/v1/logout');
    expect(repository.currentSession.signedIn, isFalse);
  });

  test(
    'auth errors are mapped without backend details or credentials',
    () async {
      handle = (_) async => _json({
        'error_code': 'invalid_credentials',
        'msg': 'private backend diagnostic',
      }, 400);
      await expectLater(
        repository.login(email: 'customer@example.com', password: 'wrong'),
        throwsA(
          isA<AuthenticationFailure>().having(
            (failure) => failure.message,
            'message',
            'Email hoặc mật khẩu không đúng.',
          ),
        ),
      );
    },
  );
}
