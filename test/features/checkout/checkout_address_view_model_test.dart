import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/checkout/presentation/view_models/checkout_address_providers.dart';

const _suggestion = AddressSuggestion(
  id: 'photon:W:1',
  label: 'Tràng Tiền, Hà Nội',
  latitude: 21.0247,
  longitude: 105.8533,
);

class _Repository implements AddressSearchRepository {
  final calls = <String>[];
  final requests = <Completer<List<AddressSuggestion>>>[];

  @override
  Future<List<AddressSuggestion>> search(String query) {
    calls.add(query);
    final request = Completer<List<AddressSuggestion>>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  late _Repository repository;
  late ProviderContainer container;
  late ProviderSubscription<AddressSearchState> subscription;
  setUp(() {
    repository = _Repository();
    container = ProviderContainer(
      overrides: [
        addressSearchRepositoryProvider.overrideWithValue(repository),
      ],
    );
    subscription = container.listen(addressSearchProvider, (_, _) {});
  });
  tearDown(() {
    subscription.close();
    container.dispose();
  });

  test('explicit search renders loading, immutable suggestions, and a normalized query', () async {
    expect(container.read(addressSearchProvider).hasSearched, isFalse);
    final vm = container.read(addressSearchProvider.notifier);
    final search = vm.search('  Tràng   Tiền ');
    expect(container.read(addressSearchProvider).isLoading, isTrue);
    expect(container.read(addressSearchProvider).query, 'Tràng Tiền');
    repository.requests.single.complete([_suggestion]);
    await search;
    final state = container.read(addressSearchProvider);
    expect(state.hasSearched, isTrue);
    expect(state.isLoading, isFalse);
    expect(state.suggestions.single, _suggestion);
    expect(() => state.suggestions.clear(), throwsUnsupportedError);
  });

  test('an older response cannot replace a new query', () async {
    final vm = container.read(addressSearchProvider.notifier);
    final old = vm.search('Tràng Tiền');
    final current = vm.search('Đường Láng');
    repository.requests.first.complete([_suggestion]);
    await old;
    expect(container.read(addressSearchProvider).query, 'Đường Láng');
    expect(container.read(addressSearchProvider).isLoading, isTrue);
    expect(container.read(addressSearchProvider).suggestions, isEmpty);
    repository.requests.last.complete([]);
    await current;
    expect(container.read(addressSearchProvider).hasSearched, isTrue);
    expect(container.read(addressSearchProvider).suggestions, isEmpty);
  });

  test(
    'clear hides old results and invalidates a request still in flight',
    () async {
      final vm = container.read(addressSearchProvider.notifier);
      final search = vm.search('Tràng Tiền');
      vm.clear();
      repository.requests.single.complete([_suggestion]);
      await search;
      final state = container.read(addressSearchProvider);
      expect(state.query, isEmpty);
      expect(state.hasSearched, isFalse);
      expect(state.suggestions, isEmpty);
      expect(state.failure, isNull);
    },
  );

  test(
    'same in-flight submit does not make another repository request',
    () async {
      final vm = container.read(addressSearchProvider.notifier);
      final first = vm.search('Tràng Tiền');
      await vm.search(' Tràng   Tiền ');
      expect(repository.calls, hasLength(1));
      repository.requests.single.complete([]);
      await first;
    },
  );

  test('typed failure differs from an empty successful search', () async {
    final vm = container.read(addressSearchProvider.notifier);
    final search = vm.search('Tràng Tiền');
    repository.requests.single.completeError(
      const AddressSearchFailure(AddressSearchFailureCode.network),
    );
    await search;
    final state = container.read(addressSearchProvider);
    expect(state.hasSearched, isTrue);
    expect(state.isLoading, isFalse);
    expect(state.failure!.code, AddressSearchFailureCode.network);
    expect(state.suggestions, isEmpty);
  });

  test('disposing checkout drops the late response and creates clean state next time', () async {
    final search = container
        .read(addressSearchProvider.notifier)
        .search('Tràng Tiền');
    subscription.close();
    await container.pump();
    repository.requests.single.complete([_suggestion]);
    await search;
    subscription = container.listen(addressSearchProvider, (_, _) {});
    final state = container.read(addressSearchProvider);
    expect(state.query, isEmpty);
    expect(state.suggestions, isEmpty);
    expect(state.hasSearched, isFalse);
  });
}
