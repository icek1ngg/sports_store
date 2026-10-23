import '../../../deliveries/data/repositories/operational_read_access.dart';
import '../../../deliveries/domain/models/operational_failure.dart';
import '../../domain/models/cod_collection.dart';
import '../../domain/repositories/cod_repository.dart';
import '../models/cod_collection_dto.dart';

/// Supabase read adapter for COD collection records.
class SupabaseCodRepository implements CodRepository {
  const SupabaseCodRepository({required this.access});

  static const int _pageSize = 200;
  static const String _projection =
      'order_id,shipper_id,status,expected_amount_vnd,'
      'collected_amount_vnd,received_amount_vnd,collected_by,received_by,'
      'collected_at,handed_over_at,received_at,created_at,updated_at';

  final OperationalReadAccess access;

  @override
  Future<List<CodCollection>> listCollections({
    String? shipperId,
    String? orderId,
  }) async {
    try {
      _validateFilter(shipperId, 'shipperId');
      _validateFilter(orderId, 'orderId');
    } on FormatException {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }

    return access.run<List<CodCollection>>(
      roles: const {'shipper', 'manager'},
      action: (identity) async {
        final role = identity.role;
        if (role != 'shipper' && role != 'manager') {
          throw const OperationalFailure(
            OperationalFailureCode.permissionDenied,
          );
        }
        if (role == 'shipper' &&
            shipperId != null &&
            shipperId.toLowerCase() != identity.userId.toLowerCase()) {
          throw const OperationalFailure(
            OperationalFailureCode.permissionDenied,
          );
        }

        if (role == 'shipper') {
          _checkUuid(identity.userId, 'identity.userId');
        }

        final collections = <CodCollection>[];
        final seenOrderIds = <String>{};
        CodCollection? lastCursor;

        while (true) {
          identity.ensureCurrent();
          var query = access.client.from('cod_collections').select(_projection);

          if (role == 'shipper') {
            query = query.eq('shipper_id', identity.userId);
          } else if (shipperId != null) {
            query = query.eq('shipper_id', shipperId);
          }
          if (orderId != null) {
            query = query.eq('order_id', orderId);
          }

          if (lastCursor != null) {
            final cursorTimestamp = lastCursor.createdAt
                .toUtc()
                .toIso8601String();
            final cursorOrderId = lastCursor.orderId;
            query = query.or(
              'created_at.lt.$cursorTimestamp,'
              'and(created_at.eq.$cursorTimestamp,'
              'order_id.lt.$cursorOrderId)',
            );
          }

          final Iterable<dynamic> page = await query
              .order('created_at', ascending: false)
              .order('order_id', ascending: false)
              .limit(_pageSize)
              .retry(enabled: false);
          identity.ensureCurrent();

          CodCollection? pageCursor;
          for (final rawRow in page) {
            if (rawRow is! Map) {
              throw const FormatException('Invalid COD response row');
            }
            final row = <String, dynamic>{};
            for (final entry in rawRow.entries) {
              if (entry.key is! String) {
                throw const FormatException('Invalid COD response row keys');
              }
              row[entry.key as String] = entry.value;
            }
            final collection = CodCollectionDto.fromJson(row).toDomain();
            if (!seenOrderIds.add(collection.orderId.toLowerCase())) {
              throw const FormatException('Duplicate COD order_id in response');
            }
            if (lastCursor != null &&
                !_isBeforeCursor(collection, lastCursor)) {
              throw const FormatException(
                'COD response cursor did not advance',
              );
            }
            if (pageCursor != null &&
                !_isBeforeCursor(collection, pageCursor)) {
              throw const FormatException('COD response order is not sorted');
            }
            collections.add(collection);
            pageCursor = collection;
          }

          if (page.length < _pageSize) {
            return List<CodCollection>.unmodifiable(collections);
          }
          if (pageCursor == null) {
            throw const FormatException('COD response cursor is missing');
          }
          if (lastCursor != null && !_isBeforeCursor(pageCursor, lastCursor)) {
            throw const FormatException('COD response cursor did not advance');
          }
          lastCursor = pageCursor;
        }
      },
    );
  }

  static void _validateFilter(String? value, String key) {
    if (value == null) {
      return;
    }
    _checkUuid(value, key);
  }

  static void _checkUuid(String value, String key) {
    final valid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
    if (!valid) {
      throw FormatException('Invalid $key: expected a UUID');
    }
  }

  static bool _isBeforeCursor(CodCollection candidate, CodCollection cursor) {
    final timestampComparison = candidate.createdAt.compareTo(cursor.createdAt);
    if (timestampComparison != 0) {
      return timestampComparison < 0;
    }
    return candidate.orderId.toLowerCase().compareTo(
          cursor.orderId.toLowerCase(),
        ) <
        0;
  }
}
