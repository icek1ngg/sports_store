import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/maps/map_provider_configuration.dart';
import '../../domain/models/address_suggestion.dart';
import '../../domain/repositories/address_search_repository.dart';

/// Explicit, small address searches against Photon. This client does not keep
/// a query cache or send recipient/contact/apartment fields to the provider.
class PhotonAddressSearchRepository implements AddressSearchRepository {
  PhotonAddressSearchRepository({
    http.Client? client,
    Uri? endpoint,
    String? userAgent,
    bool? web,
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
    this.minimumRequestInterval = const Duration(seconds: 1),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _endpoint = endpoint ?? Uri.parse('https://photon.komoot.io/api/'),
       _userAgent = userAgent ?? const MapProviderConfiguration().userAgent,
       _web = web ?? kIsWeb,
       _clock = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed {
    if (_endpoint.scheme != 'https' ||
        _endpoint.host.isEmpty ||
        _endpoint.userInfo.isNotEmpty ||
        _endpoint.hasPort ||
        _endpoint.hasQuery ||
        _endpoint.hasFragment ||
        _endpoint.path.isEmpty ||
        _userAgent.trim().isEmpty ||
        _userAgent.contains('\r') ||
        _userAgent.contains('\n') ||
        minimumRequestInterval < Duration.zero) {
      if (_ownsClient) _client.close();
      throw ArgumentError('Invalid address provider configuration');
    }
  }

  final http.Client _client;
  final bool _ownsClient;
  final Uri _endpoint;
  final String _userAgent;
  final bool _web;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;
  final Duration minimumRequestInterval;
  final _pending = <String, Future<List<AddressSuggestion>>>{};
  Future<void> _tail = Future<void>.value();
  DateTime? _lastStartedAt;
  bool _disposed = false;

  // Outward-rounded extent of the existing Hanoi boundary source. This is a
  // search filter only, never a replacement for the server's service polygon.
  static const _minLongitude = 105.2848;
  static const _minLatitude = 20.5645;
  static const _maxLongitude = 106.0201;
  static const _maxLatitude = 21.3853;
  static const _bbox = '105.2848,20.5645,106.0201,21.3853';

  @override
  Future<List<AddressSuggestion>> search(String query) {
    final normalized = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (_disposed) {
      return Future.error(
        const AddressSearchFailure(AddressSearchFailureCode.unavailable),
      );
    }
    if (normalized.runes.length < 3 ||
        normalized.runes.length > 200 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(query)) {
      return Future.error(
        const AddressSearchFailure(AddressSearchFailureCode.invalidQuery),
      );
    }
    final key = normalized.toLowerCase();
    final existing = _pending[key];
    if (existing != null) return existing;
    // At most one active and one queued query. The submit button normally
    // prevents queuing; this guard also bounds callers outside the widget.
    if (_pending.length >= 2) {
      return Future.error(
        const AddressSearchFailure(AddressSearchFailureCode.unavailable),
      );
    }
    final request = _tail.then((_) => _search(normalized));
    final tracked = request.whenComplete(() {
      _pending.remove(key);
    });
    _pending[key] = tracked;
    _tail = tracked.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return tracked;
  }

  Future<List<AddressSuggestion>> _search(String query) async {
    if (_disposed) {
      throw const AddressSearchFailure(AddressSearchFailureCode.unavailable);
    }
    final lastStart = _lastStartedAt;
    if (lastStart != null) {
      final remaining = minimumRequestInterval - _clock().difference(lastStart);
      if (remaining > Duration.zero) {
        await _delay(
          remaining > minimumRequestInterval
              ? minimumRequestInterval
              : remaining,
        );
      }
    }
    if (_disposed) {
      throw const AddressSearchFailure(AddressSearchFailureCode.unavailable);
    }
    _lastStartedAt = _clock();
    final uri = _endpoint.replace(
      queryParameters: {
        'q': query,
        'lat': '21.0285',
        'lon': '105.8542',
        'limit': '5',
        'bbox': _bbox,
        'countrycode': 'VN',
      },
    );
    http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              if (!_web) 'User-Agent': _userAgent,
            },
          )
          .timeout(const Duration(seconds: 15));
    } on Object {
      throw const AddressSearchFailure(AddressSearchFailureCode.network);
    }
    if (_disposed || response.statusCode != 200) {
      throw const AddressSearchFailure(AddressSearchFailureCode.unavailable);
    }
    if (response.bodyBytes.length > 1024 * 1024) {
      throw const AddressSearchFailure(AddressSearchFailureCode.invalidData);
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic> || decoded['features'] is! List) {
        throw const FormatException();
      }
      final suggestions = <AddressSuggestion>[];
      final seen = <String>{};
      final features = decoded['features'] as List;
      if (features.length > 100) throw const FormatException();
      for (final feature in features) {
        final suggestion = _parseFeature(feature);
        if (suggestion == null) continue;
        final signature =
            '${suggestion.label.toLowerCase()}|'
            '${suggestion.latitude.toStringAsFixed(6)}|'
            '${suggestion.longitude.toStringAsFixed(6)}';
        if (!seen.add(signature)) continue;
        suggestions.add(suggestion);
        if (suggestions.length == 5) break;
      }
      // A legitimate empty result differs from a nonempty malformed response.
      if (features.isNotEmpty && suggestions.isEmpty) {
        throw const FormatException();
      }
      return List.unmodifiable(suggestions);
    } on FormatException {
      throw const AddressSearchFailure(AddressSearchFailureCode.invalidData);
    }
  }

  AddressSuggestion? _parseFeature(dynamic feature) {
    if (feature is! Map<String, dynamic> || feature['type'] != 'Feature') {
      return null;
    }
    final geometry = feature['geometry'];
    final properties = feature['properties'];
    if (geometry is! Map<String, dynamic> ||
        geometry['type'] != 'Point' ||
        properties is! Map<String, dynamic> ||
        properties['countrycode'] is! String ||
        (properties['countrycode'] as String).toUpperCase() != 'VN') {
      return null;
    }
    final coordinates = geometry['coordinates'];
    if (coordinates is! List ||
        coordinates.length < 2 ||
        coordinates[0] is! num ||
        coordinates[1] is! num) {
      return null;
    }
    final longitude = (coordinates[0] as num).toDouble();
    final latitude = (coordinates[1] as num).toDouble();
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < _minLatitude ||
        latitude > _maxLatitude ||
        longitude < _minLongitude ||
        longitude > _maxLongitude) {
      return null;
    }
    String? text(String key) {
      final value = properties[key];
      if (value is! String || value.runes.length > 300) return null;
      final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (clean.isEmpty || RegExp(r'[\x00-\x1f\x7f]').hasMatch(clean)) {
        return null;
      }
      return clean;
    }

    final name = text('name');
    final street = text('street');
    if (name == null && street == null) return null;
    final house = text('housenumber');
    final parts = <String>[
      ?name,
      if (street != null) [?house, street].join(' '),
      for (final key in ['district', 'locality', 'city', 'county', 'state'])
        ?text(key),
    ];
    final distinctParts = <String>[];
    final seen = <String>{};
    for (final part in parts) {
      if (seen.add(part.toLowerCase())) distinctParts.add(part);
    }
    final label = distinctParts.join(', ');
    if (label.isEmpty || label.runes.length > 600) return null;
    final osmType = properties['osm_type'];
    final osmId = properties['osm_id'];
    final id =
        osmType is String &&
            RegExp(r'^[NWR]$').hasMatch(osmType) &&
            osmId is int &&
            osmId > 0
        ? 'photon:$osmType:$osmId'
        : 'photon:$latitude:$longitude:$label';
    return AddressSuggestion(
      id: id,
      label: label,
      latitude: latitude,
      longitude: longitude,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pending.clear();
    if (_ownsClient) _client.close();
  }
}
