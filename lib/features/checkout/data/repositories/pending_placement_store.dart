import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/models/checkout_failure.dart';
import '../../domain/models/placement_request.dart';
import '../models/pending_placement.dart';

abstract interface class PendingPlacementStore {
  Future<PendingPlacement?> read(String userId);

  Future<void> write(String userId, PlacementRequest request);

  Future<void> clear(String userId);
}

/// Protected-at-rest production store. The key remains user-scoped, while
/// FlutterSecureStorage encrypts the normalized JSON payload on each platform.
class SecurePendingPlacementStore implements PendingPlacementStore {
  SecurePendingPlacementStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<PendingPlacement?> read(String userId) async {
    final value = await _storage.read(key: _key(userId));
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
        throw const FormatException('pending payload is invalid');
      }
      return PendingPlacement(
        request: PlacementRequest.fromJson(Map<String, Object?>.from(decoded)),
      );
    } on FormatException {
      // Do not delete a corrupt value: it may represent a committed request.
      throw const CheckoutFailure(
        CheckoutFailureCode.invalidData,
        message: 'Không thể khôi phục yêu cầu đặt hàng đang chờ.',
      );
    } on TypeError {
      throw const CheckoutFailure(
        CheckoutFailureCode.invalidData,
        message: 'Không thể khôi phục yêu cầu đặt hàng đang chờ.',
      );
    }
  }

  @override
  Future<void> write(String userId, PlacementRequest request) =>
      _storage.write(key: _key(userId), value: jsonEncode(request.toJson()));

  @override
  Future<void> clear(String userId) => _storage.delete(key: _key(userId));

  static String _key(String userId) =>
      'sports_store.checkout.pending.${userId.trim().toLowerCase()}';
}

/// Lightweight fake useful for repository/ViewModel tests and offline UI
/// previews. It follows the same user-scoped semantics as the protected device store.
class InMemoryPendingPlacementStore implements PendingPlacementStore {
  final Map<String, PendingPlacement> _values = {};

  @override
  Future<PendingPlacement?> read(String userId) async =>
      _values[userId.trim().toLowerCase()];

  @override
  Future<void> write(String userId, PlacementRequest request) async {
    _values[userId.trim().toLowerCase()] = PendingPlacement(request: request);
  }

  @override
  Future<void> clear(String userId) async {
    _values.remove(userId.trim().toLowerCase());
  }
}
