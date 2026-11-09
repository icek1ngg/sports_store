import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/state/session_scope.dart';
import '../../domain/models/order_command.dart';
import '../../domain/models/order_status.dart';
import '../../domain/repositories/order_repository.dart';

/// Protected per-account ledger. Unknown commands survive logout and restart.
/// Corrupt storage is retained and fails closed rather than losing an outcome.
class SecurePendingOrderCommandStore implements PendingOrderCommandStore {
  SecurePendingOrderCommandStore({
    required this.scope,
    required this.readSession,
    FlutterSecureStorage? storage,
  }) : storage = storage ?? const FlutterSecureStorage();

  final SessionScope scope;
  final SessionScope Function() readSession;
  final FlutterSecureStorage storage;
  // Provider recreation/account-generation changes may overlap an old plugin
  // write. Serialize by protected namespace across instances, without caching
  // any command contents in static memory.
  static final Map<String, Future<void>> _tails = {};
  String get _key => 'sports_store.orders.pending.v1.${scope.userId}';

  void _guard() {
    if (!scope.canReadPrivateData || readSession() != scope) {
      throw const AppFailure(code: AppFailure.unauthenticated);
    }
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = (_tails[_key] ?? Future<void>.value()).then((_) {
      _guard();
      return action();
    });
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[_key] = tail;
    return result.whenComplete(() {
      if (identical(_tails[_key], tail)) _tails.remove(_key);
    });
  }

  Future<Map<String, Object?>> _read() async {
    final raw = await storage.read(key: _key);
    _guard();
    if (raw == null) return {};
    try {
      final entries = Map<String, Object?>.from(jsonDecode(raw) as Map);
      for (final entry in entries.entries) {
        final row = Map<String, Object?>.from(entry.value as Map);
        final command = _decode(row);
        if (entry.key != command.requestId ||
            row['user_id'] != scope.userId ||
            DateTime.tryParse(row['created_at_client'] as String? ?? '') ==
                null) {
          throw const FormatException();
        }
      }
      return entries;
    } catch (_) {
      throw const AppFailure(code: AppFailure.dataIntegrity);
    }
  }

  StableOrderCommand _decode(Map<String, Object?> row) => StableOrderCommand(
    orderId: row['order_id'] as String,
    requestId: row['request_id'] as String,
    operation: OrderOperation.parse(row['operation']),
    reason: row['reason'] as String?,
  );

  @override
  Future<List<StableOrderCommand>> list() => _serial(
    () async => (await _read()).values
        .map((value) => _decode(Map<String, Object?>.from(value as Map)))
        .toList(growable: false),
  );

  @override
  Future<void> save(StableOrderCommand command) => _serial(() async {
    final entries = await _read();
    final old = entries[command.requestId];
    if (old != null) {
      final previous = _decode(Map<String, Object?>.from(old as Map));
      if (previous.orderId != command.orderId ||
          previous.operation != command.operation ||
          previous.reason != command.reason) {
        throw const AppFailure(code: AppFailure.idempotencyConflict);
      }
      return;
    }
    entries[command.requestId] = {
      'user_id': scope.userId,
      'order_id': command.orderId,
      'request_id': command.requestId,
      'operation': command.operation.wireValue,
      'reason': command.reason,
      'created_at_client': DateTime.now().toUtc().toIso8601String(),
    };
    _guard();
    await storage.write(key: _key, value: jsonEncode(entries));
    _guard();
  });

  @override
  Future<void> remove(String requestId) => _serial(() async {
    final entries = await _read();
    entries.remove(requestId);
    _guard();
    await storage.write(key: _key, value: jsonEncode(entries));
    _guard();
  });
}
