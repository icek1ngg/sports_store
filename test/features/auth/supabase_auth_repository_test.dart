import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sports_store/features/auth/data/repositories/supabase_auth_repository.dart';
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
    handle = (_) async => _json(_user(_userId));
    final result = await repository.register(
      fullName: ' Nguyễn An ',
      phone: ' 0912345678 ',
      email: ' customer@example.com ',
      password: 'strong-password',
    );
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(requests.single.url.path, '/auth/v1/signup');
    expect(body['data'], {'full_name': 'Nguyễn An', 'phone': '0912345678'});
    expect((body['data'] as Map).containsKey('role'), isFalse);
    expect(result.needsEmailConfirmation, isTrue);
    expect(repository.currentSession.signedIn, isFalse);
  });

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
