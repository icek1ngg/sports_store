import '../models/cod_collection.dart';
import '../models/cod_collection_page.dart';
import '../models/cod_collection_query.dart';

/// Read operations for COD collection records.
abstract interface class CodRepository {
  Future<CodCollectionPage> queryCollections(CodCollectionQuery query);

  Future<List<CodCollection>> listCollections({
    String? shipperId,
    String? orderId,
  });
}
