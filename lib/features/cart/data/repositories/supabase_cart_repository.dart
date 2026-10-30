import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../catalog/data/models/catalog_dto.dart';
import '../../../deliveries/data/repositories/operational_read_access.dart';
import '../../../deliveries/domain/models/operational_failure.dart';
import '../../domain/models/cart_failure.dart';
import '../../domain/models/cart_item.dart';
import '../../domain/repositories/cart_repository.dart';
import '../models/cart_item_dto.dart';

/// Uses existing column grants and RLS; never writes price or stock.
class SupabaseCartRepository implements CartRepository {
  SupabaseCartRepository({required this.access});

  final OperationalReadAccess access;

  static const _pageSize = 200;
  static const _rowProjection = 'customer_id,variant_id,quantity';
  static const _variantProjection =
      'id,product_id,sku,label,attributes,price_vnd,available_quantity,is_active,'
      'products(id,category_id,name,description,image_path,is_active,'
      'categories(id,code,name,is_active))';
  static const _projection =
      '$_rowProjection,product_variants($_variantProjection)';
  static final _maxSafe = BigInt.parse('9007199254740991');

  @override
  Future<List<CartItem>> getItems() => _run((identity) async {
    final items = <CartItem>[];
    String? cursor;
    var total = BigInt.zero;
    var quantityTotal = BigInt.zero;
    while (true) {
      identity.ensureCurrent();
      var query = access.client
          .from('cart_items')
          .select(_projection)
          .eq('customer_id', identity.userId);
      if (cursor != null) query = query.gt('variant_id', cursor);
      final rows = await query
          .order('variant_id')
          .limit(_pageSize)
          .retry(enabled: false);
      identity.ensureCurrent();
      if (rows.isEmpty) break;
      for (final row in rows) {
        final item = CartItemDto.fromJson(row, customerId: identity.userId);
        final id = item.variantId.toLowerCase();
        if (cursor != null && id.compareTo(cursor) <= 0) {
          throw const FormatException('Cart cursor did not advance');
        }
        cursor = id;
        total +=
            BigInt.from(item.variant?.priceVnd ?? 0) *
            BigInt.from(item.quantity);
        quantityTotal += BigInt.from(item.quantity);
        if (total > _maxSafe || quantityTotal > _maxSafe) {
          throw const FormatException('Cart total exceeds safe integer range');
        }
        items.add(item);
      }
    }
    return List<CartItem>.unmodifiable(items);
  });

  @override
  Future<void> setQuantity({required String variantId, required int quantity}) {
    _validate(variantId, quantity);
    return _run((identity) async {
      identity.ensureCurrent();
      final raw = await access.client
          .from('product_variants')
          .select(_variantProjection)
          .eq('id', variantId)
          .maybeSingle()
          .retry(enabled: false);
      identity.ensureCurrent();
      if (raw == null) throw const CartFailure(CartFailureCode.unavailable);
      final current = CartItemDto.fromJson({
        'customer_id': identity.userId,
        'variant_id': variantId,
        'quantity': quantity,
        'product_variants': raw,
      }, customerId: identity.userId);
      if (!current.isAvailable) {
        throw const CartFailure(CartFailureCode.unavailable);
      }
      if (!current.hasEnoughStock) {
        throw const CartFailure(CartFailureCode.insufficientStock);
      }
      if (BigInt.from(current.variant!.priceVnd) * BigInt.from(quantity) >
          _maxSafe) {
        throw const CartFailure(CartFailureCode.invalidData);
      }

      // UPDATE only quantity. Supabase upsert would also update the key
      // columns, which this project's column grants deliberately forbid.
      if (await _update(identity, variantId, quantity)) return;
      identity.ensureCurrent();
      try {
        final rows = await access.client
            .from('cart_items')
            .insert({
              'customer_id': identity.userId,
              'variant_id': variantId,
              'quantity': quantity,
            })
            .select(_rowProjection)
            .retry(enabled: false);
        identity.ensureCurrent();
        _verifyReceipt(rows, identity.userId, variantId, quantity);
      } on PostgrestException catch (error) {
        identity.ensureCurrent();
        if (error.code != '23505') rethrow;
        // Another device may have inserted the row. Repeat the SAME absolute
        // target, never reinterpret this as another increment.
        if (!await _update(identity, variantId, quantity)) {
          throw const CartFailure(CartFailureCode.unavailable);
        }
      }
    });
  }

  Future<bool> _update(
    ReadIdentity identity,
    String variantId,
    int quantity,
  ) async {
    identity.ensureCurrent();
    final rows = await access.client
        .from('cart_items')
        .update({'quantity': quantity})
        .eq('customer_id', identity.userId)
        .eq('variant_id', variantId)
        .select(_rowProjection)
        .retry(enabled: false);
    identity.ensureCurrent();
    if (rows.isEmpty) return false;
    _verifyReceipt(rows, identity.userId, variantId, quantity);
    return true;
  }

  @override
  Future<void> removeItem(String variantId) {
    _validate(variantId, 1);
    return _run((identity) async {
      identity.ensureCurrent();
      await access.client
          .from('cart_items')
          .delete()
          .eq('customer_id', identity.userId)
          .eq('variant_id', variantId)
          .retry(enabled: false);
      identity.ensureCurrent();
      // A missing row is a successful retry of an already deleted item.
    });
  }

  Future<T> _run<T>(Future<T> Function(ReadIdentity) action) async {
    try {
      final result = await access.run<_CartResult<T>>(
        roles: const {'customer'},
        action: (identity) async {
          try {
            return _CartResult(value: await action(identity));
          } on CartFailure catch (failure) {
            return _CartResult(failure: failure);
          }
        },
      );
      if (result.failure != null) throw result.failure!;
      return result.value as T;
    } catch (error) {
      throw mapCartFailure(error);
    }
  }

  static void _validate(String id, int quantity) {
    try {
      CatalogDtoReaders.checkUuid(id, 'variant_id');
      if (quantity < 1 || BigInt.from(quantity) > _maxSafe) {
        throw const FormatException('Invalid cart quantity');
      }
    } on FormatException {
      throw const CartFailure(CartFailureCode.invalidData);
    }
  }

  static void _verifyReceipt(
    List<Map<String, dynamic>> rows,
    String owner,
    String id,
    int quantity,
  ) {
    if (rows.length != 1 ||
        CatalogDtoReaders.readRequiredUuid(
              rows.single,
              'customer_id',
            ).toLowerCase() !=
            owner.toLowerCase() ||
        CatalogDtoReaders.readRequiredUuid(
              rows.single,
              'variant_id',
            ).toLowerCase() !=
            id.toLowerCase() ||
        CatalogDtoReaders.readRequiredInteger(rows.single, 'quantity') !=
            quantity) {
      throw const FormatException('Cart write was not acknowledged');
    }
  }
}

class _CartResult<T> {
  const _CartResult({this.value, this.failure});
  final T? value;
  final CartFailure? failure;
}

CartFailure mapCartFailure(Object error) {
  if (error is CartFailure) return error;
  final failure = mapOperationalFailure(error);
  return CartFailure(switch (failure.code) {
    OperationalFailureCode.sessionExpired => CartFailureCode.sessionExpired,
    OperationalFailureCode.permissionDenied => CartFailureCode.permissionDenied,
    OperationalFailureCode.staleAssignment => CartFailureCode.unavailable,
    OperationalFailureCode.invalidData => CartFailureCode.invalidData,
    OperationalFailureCode.network => CartFailureCode.network,
    OperationalFailureCode.backendUnavailable =>
      CartFailureCode.backendUnavailable,
    OperationalFailureCode.unexpected => CartFailureCode.unexpected,
  });
}
