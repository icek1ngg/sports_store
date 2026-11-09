import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              // Never silently erase an uncertain order after a KeyStore error.
              resetOnError: false,
              // Resume an interrupted cipher upgrade with an encrypted backup.
              migrateWithBackup: true,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<PendingPlacement?> read(String userId) async {
    final String? value;
    try {
      value = await _storage.read(key: _key(userId));
    } catch (error) {
      throw _storageFailure(error, writing: false);
    }
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
  Future<void> write(String userId, PlacementRequest request) async {
    final key = _key(userId);
    final value = jsonEncode(request.toJson());
    try {
      await _storage.write(key: key, value: value);
      // A successful method-channel reply alone is insufficient for retry
      // safety. Verify the exact durable payload before calling place_order.
      if (await _storage.read(key: key) != value) {
        throw const FormatException('pending write did not round-trip');
      }
    } catch (error) {
      throw _storageFailure(error, writing: true);
    }
  }

  @override
  Future<void> clear(String userId) => _storage.delete(key: _key(userId));

  static String _key(String userId) =>
      'sports_store.checkout.pending.${userId.trim().toLowerCase()}';

  static CheckoutFailure _storageFailure(
    Object error, {
    required bool writing,
  }) {
    final missingPlugin = error is MissingPluginException;
    final kind = missingPlugin
        ? 'plugin_missing'
        : error is PlatformException
        ? 'platform_error'
        : error is FormatException
        ? 'verification_failed'
        : 'unavailable';
    // Do not print native exception details, storage keys, addresses or payloads.
    debugPrint('Checkout storage: ${writing ? 'write' : 'read'} / $kind');
    return CheckoutFailure(
      CheckoutFailureCode.localStorageUnavailable,
      definitiveNoCommit: writing,
      message: missingPlugin
          ? 'Ứng dụng chưa nạp được bộ lưu trữ bảo mật. Hãy dừng hẳn và chạy lại bản cài mới, không chỉ tải lại giao diện.'
          : writing
          ? 'Không lưu được yêu cầu trên thiết bị. Chưa gửi đơn hàng; hãy mở lại ứng dụng và thử lại.'
          : 'Không đọc được yêu cầu đang chờ trên thiết bị. Hãy mở lại ứng dụng để kiểm tra đơn trước khi đặt lại.',
    );
  }
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
