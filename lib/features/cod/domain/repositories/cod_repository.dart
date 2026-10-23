import '../models/cod_collection.dart';

/// Read operations for COD collection records.
abstract interface class CodRepository {
  Future<List<CodCollection>> listCollections({
    String? shipperId,
    String? orderId,
  });
}
