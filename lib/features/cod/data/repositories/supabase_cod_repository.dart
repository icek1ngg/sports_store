import '../../../deliveries/data/repositories/operational_read_access.dart';
import '../../../deliveries/domain/models/operational_failure.dart';
import '../../domain/models/cod_collection.dart';
import '../../domain/models/cod_collection_page.dart';
import '../../domain/models/cod_collection_query.dart';
import '../../domain/repositories/cod_repository.dart';
import '../models/cod_collection_page_dto.dart';

/// Supabase read adapter for COD collection records.
class SupabaseCodRepository implements CodRepository {
  const SupabaseCodRepository({required this.access});

  final OperationalReadAccess access;

  @override
  Future<CodCollectionPage> queryCollections(CodCollectionQuery query) async {
    return access.run<CodCollectionPage>(
      roles: const {'shipper', 'manager'},
      action: (identity) async {
        if (identity.role == 'shipper' &&
            query.shipperId != null &&
            query.shipperId!.toLowerCase() != identity.userId.toLowerCase()) {
          throw const OperationalFailure(
            OperationalFailureCode.permissionDenied,
          );
        }
        identity.ensureCurrent();
        final raw = await access.client
            .rpc('list_cod_collections', params: query.toRpcParams())
            .retry(enabled: false);
        identity.ensureCurrent();
        if (raw is! Map) {
          throw const FormatException('Invalid COD page response');
        }
        final page = CodCollectionPageDto.fromJson(
          Map<String, dynamic>.from(raw),
          query: query,
        ).toDomain();
        if (identity.role == 'shipper' &&
            page.items.any(
              (item) =>
                  item.shipperId?.toLowerCase() !=
                  identity.userId.toLowerCase(),
            )) {
          throw const OperationalFailure(
            OperationalFailureCode.permissionDenied,
          );
        }
        return page;
      },
    );
  }

  @override
  Future<List<CodCollection>> listCollections({
    String? shipperId,
    String? orderId,
  }) async {
    final collections = <CodCollection>[];
    final seenOrders = <String>{};
    final seenCursors = <String>{};
    final capturedSession = access.currentSession;
    if (capturedSession.userId == null || capturedSession.failure != null) {
      throw capturedSession.failure ??
          const OperationalFailure(OperationalFailureCode.sessionExpired);
    }
    CodCollectionPage? firstPage;
    CodCollection? previousLast;
    late CodCollectionQuery query;
    try {
      query = CodCollectionQuery(
        shipperId: shipperId,
        orderId: orderId,
        limit: CodCollectionQuery.maxPageSize,
      );
    } on ArgumentError {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }
    while (true) {
      if (!identical(access.currentSession, capturedSession)) {
        throw const OperationalFailure(OperationalFailureCode.sessionExpired);
      }
      final page = await queryCollections(query);
      if (!identical(access.currentSession, capturedSession)) {
        throw const OperationalFailure(OperationalFailureCode.sessionExpired);
      }
      if (firstPage == null) {
        firstPage = page;
      } else if (page.filteredTotal != firstPage.filteredTotal ||
          page.outstandingVnd != firstPage.outstandingVnd ||
          page.counts.all != firstPage.counts.all ||
          page.counts.uncollected != firstPage.counts.uncollected ||
          page.counts.collected != firstPage.counts.collected ||
          page.counts.received != firstPage.counts.received) {
        throw const OperationalFailure(OperationalFailureCode.invalidData);
      }
      if (previousLast != null &&
          page.items.isNotEmpty &&
          !_isBefore(page.items.first, previousLast)) {
        throw const OperationalFailure(OperationalFailureCode.invalidData);
      }
      for (final item in page.items) {
        if (!seenOrders.add(item.orderId.toLowerCase())) {
          throw const OperationalFailure(OperationalFailureCode.invalidData);
        }
        collections.add(item);
      }
      if (page.items.isNotEmpty) previousLast = page.items.last;
      if (collections.length > firstPage.filteredTotal) {
        throw const OperationalFailure(OperationalFailureCode.invalidData);
      }
      final cursor = page.nextCursor;
      if (cursor == null) break;
      if (!seenCursors.add(cursor)) {
        throw const OperationalFailure(OperationalFailureCode.invalidData);
      }
      try {
        query = CodCollectionQuery(
          shipperId: shipperId,
          orderId: orderId,
          limit: CodCollectionQuery.maxPageSize,
          cursor: cursor,
        );
      } on ArgumentError {
        throw const OperationalFailure(OperationalFailureCode.invalidData);
      }
    }
    if (collections.length != firstPage.filteredTotal) {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }
    return List<CodCollection>.unmodifiable(collections);
  }

  static bool _isBefore(CodCollection candidate, CodCollection cursor) {
    final timestamp = candidate.createdAt.compareTo(cursor.createdAt);
    if (timestamp != 0) return timestamp < 0;
    return candidate.orderId.toLowerCase().compareTo(
          cursor.orderId.toLowerCase(),
        ) <
        0;
  }
}
