import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/maps/map_providers.dart';
import '../../data/repositories/photon_address_search_repository.dart';
import '../../domain/models/address_suggestion.dart';
import '../../domain/repositories/address_search_repository.dart';

export '../../domain/models/address_suggestion.dart';
export '../../domain/repositories/address_search_repository.dart';

final addressSearchRepositoryProvider =
    Provider.autoDispose<AddressSearchRepository>((ref) {
      final config = ref.watch(mapProviderConfigurationProvider);
      final repository = PhotonAddressSearchRepository(
        endpoint: Uri.parse(
          const String.fromEnvironment(
            'PHOTON_API_URL',
            defaultValue: 'https://photon.komoot.io/api/',
          ),
        ),
        userAgent: config.userAgent,
      );
      ref.onDispose(repository.dispose);
      return repository;
    });

final addressSearchProvider =
    NotifierProvider.autoDispose<AddressSearchViewModel, AddressSearchState>(
      AddressSearchViewModel.new,
    );

class AddressSearchState {
  AddressSearchState({
    this.query = '',
    List<AddressSuggestion> suggestions = const [],
    this.isLoading = false,
    this.hasSearched = false,
    this.failure,
  }) : suggestions = List.unmodifiable(suggestions);

  final String query;
  final List<AddressSuggestion> suggestions;
  final bool isLoading;
  final bool hasSearched;
  final AddressSearchFailure? failure;
}

class AddressSearchViewModel extends Notifier<AddressSearchState> {
  int _generation = 0;

  @override
  AddressSearchState build() {
    // Keep transport lifetime tied to this checkout search session. Rebuilding
    // because configuration changes must also invalidate an older response.
    ref.watch(addressSearchRepositoryProvider);
    _generation++;
    ref.onDispose(() => _generation++);
    return AddressSearchState();
  }

  Future<void> search(String query) async {
    final normalized = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (state.isLoading && state.query == normalized) return;
    final generation = ++_generation;
    state = AddressSearchState(query: normalized, isLoading: true);
    try {
      final results = await ref
          .read(addressSearchRepositoryProvider)
          .search(query);
      if (!ref.mounted || generation != _generation) return;
      state = AddressSearchState(
        query: normalized,
        suggestions: results,
        hasSearched: true,
      );
    } on AddressSearchFailure catch (failure) {
      if (!ref.mounted || generation != _generation) return;
      state = AddressSearchState(
        query: normalized,
        hasSearched: true,
        failure: failure,
      );
    } on Object {
      if (!ref.mounted || generation != _generation) return;
      state = AddressSearchState(
        query: normalized,
        hasSearched: true,
        failure: const AddressSearchFailure(
          AddressSearchFailureCode.unavailable,
        ),
      );
    }
  }

  void clear() {
    _generation++;
    state = AddressSearchState();
  }
}
