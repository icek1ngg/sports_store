import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sports_store/features/checkout/data/repositories/photon_address_search_repository.dart';
import 'package:sports_store/features/checkout/domain/repositories/address_search_repository.dart';

Map<String, dynamic> _feature({
  String name = 'Tràng Tiền',
  double latitude = 21.0247,
  double longitude = 105.8533,
  String country = 'VN',
  int id = 1,
}) => {
  'type': 'Feature',
  'geometry': {
    'type': 'Point',
    'coordinates': [longitude, latitude],
  },
  'properties': {
    'name': name,
    'city': 'Hà Nội',
    'state': 'Hà Nội',
    'countrycode': country,
    'osm_type': 'W',
    'osm_id': id,
  },
};

http.Response _response(List<Object?> features) => http.Response.bytes(
  utf8.encode(jsonEncode({'type': 'FeatureCollection', 'features': features})),
  200,
);

Matcher _failure(AddressSearchFailureCode code) =>
    isA<AddressSearchFailure>().having((failure) => failure.code, 'code', code);

void main() {
  test(
    'search uses Vietnam/Hanoi filters and preserves local UTF-8 names',
    () async {
      final repository = PhotonAddressSearchRepository(
        web: false,
        client: MockClient((request) async {
          expect(request.url.scheme, 'https');
          expect(request.url.queryParameters, {
            'q': 'Tràng Tiền',
            'lat': '21.0285',
            'lon': '105.8542',
            'limit': '5',
            'bbox': '105.2848,20.5645,106.0201,21.3853',
            'countrycode': 'VN',
          });
          expect(request.headers['User-Agent'], startsWith('sports_store/'));
          expect(request.url.queryParameters.containsKey('lang'), isFalse);
          return _response([_feature(), _feature()]);
        }),
      );
      addTearDown(repository.dispose);
      final suggestions = await repository.search('  Tràng   Tiền  ');
      expect(suggestions, hasLength(1));
      expect(suggestions.single.id, 'photon:W:1');
      expect(suggestions.single.label, 'Tràng Tiền, Hà Nội');
      expect(suggestions.single.latitude, 21.0247);
      expect(suggestions.single.longitude, 105.8533);
      expect(() => suggestions.clear(), throwsUnsupportedError);
    },
  );

  test(
    'mixed malformed, foreign and outside-Hanoi points cannot become results',
    () async {
      final invalidGeometry = _feature()
        ..['geometry'] = {
          'type': 'Point',
          'coordinates': ['NaN', 21],
        };
      final noName = _feature()
        ..['properties'] = {'city': 'Hà Nội', 'countrycode': 'VN'};
      final repository = PhotonAddressSearchRepository(
        client: MockClient(
          (_) async => _response([
            null,
            invalidGeometry,
            noName,
            _feature(latitude: 0, longitude: 0),
            _feature(country: 'DE'),
            _feature(latitude: 21.5),
            _feature(name: 'Đường Láng', id: 2),
          ]),
        ),
      );
      addTearDown(repository.dispose);
      final suggestions = await repository.search('Đường Láng');
      expect(suggestions, hasLength(1));
      expect(suggestions.single.label, 'Đường Láng, Hà Nội');
    },
  );

  test('empty response stays empty without a made-up coordinate', () async {
    final repository = PhotonAddressSearchRepository(
      client: MockClient((_) async => _response([])),
    );
    addTearDown(repository.dispose);
    expect(await repository.search('Tên không có'), isEmpty);
  });

  for (final malformed in [
    'not json',
    '{"features":{}}',
    '{"features":[null]}',
  ]) {
    test('malformed provider data is a typed failure: $malformed', () async {
      final repository = PhotonAddressSearchRepository(
        client: MockClient((_) async => http.Response(malformed, 200)),
      );
      addTearDown(repository.dispose);
      await expectLater(
        repository.search('Hà Nội'),
        throwsA(_failure(AddressSearchFailureCode.invalidData)),
      );
    });
  }

  test(
    'query validation never sends short, oversized or control-bearing input',
    () async {
      var calls = 0;
      final repository = PhotonAddressSearchRepository(
        client: MockClient((_) async {
          calls++;
          return _response([]);
        }),
      );
      addTearDown(repository.dispose);
      for (final query in ['ab', 'đ' * 201, 'Hà\nNội', 'Hà\u0000Nội']) {
        await expectLater(
          repository.search(query),
          throwsA(_failure(AddressSearchFailureCode.invalidQuery)),
        );
      }
      expect(calls, 0);
    },
  );

  for (final status in [400, 429, 503]) {
    test('HTTP $status is unavailable without leaking response text', () async {
      final repository = PhotonAddressSearchRepository(
        client: MockClient(
          (_) async => http.Response('private response', status),
        ),
      );
      addTearDown(repository.dispose);
      await expectLater(
        repository.search('Hà Nội'),
        throwsA(_failure(AddressSearchFailureCode.unavailable)),
      );
    });
  }

  test(
    'transport failure is typed and does not include the private query',
    () async {
      final repository = PhotonAddressSearchRepository(
        client: MockClient(
          (_) async => throw http.ClientException('secret request'),
        ),
      );
      addTearDown(repository.dispose);
      try {
        await repository.search('Ngõ riêng tư');
        fail('Expected failure');
      } on AddressSearchFailure catch (failure) {
        expect(failure.code, AddressSearchFailureCode.network);
        expect(failure.toString(), isNot(contains('riêng tư')));
        expect(failure.toString(), isNot(contains('secret')));
      }
    },
  );

  test('duplicate requests share one future, different queries serialize and throttle', () async {
    final firstGate = Completer<http.Response>();
    final delayGate = Completer<void>();
    var calls = 0;
    var now = DateTime.utc(2026, 11, 9);
    Duration? waited;
    final repository = PhotonAddressSearchRepository(
      clock: () => now,
      delay: (duration) {
        waited = duration;
        return delayGate.future;
      },
      client: MockClient((_) async {
        calls++;
        return calls == 1 ? firstGate.future : _response([_feature(id: 2)]);
      }),
    );
    addTearDown(repository.dispose);
    final first = repository.search('Tràng Tiền');
    final duplicate = repository.search('tràng tiền');
    expect(identical(first, duplicate), isTrue);
    final second = repository.search('Đường Láng');
    await expectLater(
      repository.search('Kim Mã'),
      throwsA(_failure(AddressSearchFailureCode.unavailable)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    firstGate.complete(_response([_feature()]));
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(waited, const Duration(seconds: 1));
    now = now.add(const Duration(seconds: 1));
    delayGate.complete();
    expect(await second, hasLength(1));
    expect(calls, 2);
  });

  test('dispose prevents active/queued results from being published and releases no borrowed client', () async {
    final gate = Completer<http.Response>();
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return gate.future;
    });
    final repository = PhotonAddressSearchRepository(client: client);
    final first = repository.search('Tràng Tiền');
    final second = repository.search('Đường Láng');
    final firstError = expectLater(
      first,
      throwsA(_failure(AddressSearchFailureCode.unavailable)),
    );
    final secondError = expectLater(
      second,
      throwsA(_failure(AddressSearchFailureCode.unavailable)),
    );
    await Future<void>.delayed(Duration.zero);
    repository.dispose();
    gate.complete(_response([_feature()]));
    await Future.wait([firstError, secondError]);
    expect(calls, 1);
    await expectLater(
      repository.search('Hà Nội'),
      throwsA(_failure(AddressSearchFailureCode.unavailable)),
    );
    // The borrowed client is still usable by its owner.
    await client.get(Uri.https('example.com'));
    expect(calls, 2);
    client.close();
  });

  test(
    'web uses browser identification and secure configured endpoint',
    () async {
      final repository = PhotonAddressSearchRepository(
        web: true,
        endpoint: Uri.parse('https://geocoding.example.com/photon/api'),
        client: MockClient((request) async {
          expect(request.url.host, 'geocoding.example.com');
          expect(request.headers.containsKey('User-Agent'), isFalse);
          return _response([]);
        }),
      );
      addTearDown(repository.dispose);
      expect(await repository.search('Hà Nội'), isEmpty);
      for (final endpoint in [
        'http://example.com/api',
        'https://u:p@example.com/api',
        'https://example.com/api?q=x',
        'https://example.com/api#x',
      ]) {
        expect(
          () => PhotonAddressSearchRepository(endpoint: Uri.parse(endpoint)),
          throwsArgumentError,
        );
      }
    },
  );
}
