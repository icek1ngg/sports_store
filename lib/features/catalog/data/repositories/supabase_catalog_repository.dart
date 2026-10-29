import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/managed_product.dart';
import '../../domain/repositories/catalog_repository.dart';

class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository(this.client);
  final SupabaseClient client;

  ({String userId, String token}) _identity() {
    final id = client.auth.currentUser?.id;
    final session = client.auth.currentSession;
    if (id == null || session == null || session.isExpired) {
      throw const CatalogFailure('Vui lòng đăng nhập lại.');
    }
    return (userId: id, token: session.accessToken);
  }

  void _checkIdentity(({String userId, String token}) identity) {
    if (client.auth.currentUser?.id != identity.userId ||
        client.auth.currentSession?.accessToken != identity.token) {
      throw const CatalogFailure(
        'Phiên đăng nhập đã thay đổi. Vui lòng tải lại.',
        outcomeUnknown: true,
      );
    }
  }

  @override
  Future<CatalogSnapshot> loadManagement() async {
    final actor = _identity();
    try {
      final profile = await client
          .from('profiles')
          .select('role')
          .eq('id', actor.userId)
          .single()
          .setHeader('Authorization', 'Bearer ${actor.token}')
          .retry(enabled: false, requestTimeout: const Duration(seconds: 15));
      _checkIdentity(actor);
      if (profile['role'] != 'manager') {
        throw const CatalogFailure(
          'Chỉ quản lý được truy cập quản lý sản phẩm.',
        );
      }
      // Explicit batches avoid silently truncating the catalog at the Data API
      // row cap. Flat variant reads also avoid nested-relation row limits.
      final categories = await _readAll('categories', 'id,name,is_active');
      final rows = await _readAll(
        'products',
        'id,name,category_id,description,image_path,is_active,updated_at,categories(name)',
      );
      final variants = await _readAll(
        'product_variants',
        'id,product_id,sku,label,attributes,price_vnd,on_hand,reserved,is_active',
      );
      final products = <ManagedProduct>[];
      for (final row in rows) {
        final path = row['image_path'] as String? ?? '';
        String? url;
        if (path.isNotEmpty) {
          if (Uri.tryParse(path)?.scheme == 'https') {
            url = path;
          } else {
            url = await client.storage
                .from('product-images')
                .createSignedUrl(path, 3600);
          }
        }
        products.add(
          ManagedProduct(
            id: row['id'] as String,
            name: row['name'] as String,
            categoryId: row['category_id'] as String,
            categoryName: (row['categories'] as Map?)?['name'] as String? ?? '',
            description: row['description'] as String? ?? '',
            imagePath: path,
            imageUrl: url,
            active: row['is_active'] as bool,
            updatedAt: row['updated_at'] as String,
            variants: variants
                .where((v) => v['product_id'] == row['id'])
                .map((value) {
                  final v = value as Map;
                  return ManagedVariant(
                    id: v['id'] as String,
                    sku: v['sku'] as String,
                    label: v['label'] as String,
                    priceVnd: (v['price_vnd'] as num).toInt(),
                    onHand: (v['on_hand'] as num).toInt(),
                    reserved: (v['reserved'] as num).toInt(),
                    expectedOnHand: (v['on_hand'] as num).toInt(),
                    active: v['is_active'] as bool,
                    attributes: Map<String, dynamic>.from(
                      v['attributes'] as Map,
                    ),
                  );
                })
                .toList(growable: false),
          ),
        );
      }
      _checkIdentity(actor);
      return CatalogSnapshot(
        categories: categories
            .map(
              (r) => CatalogCategory(
                id: r['id'] as String,
                name: r['name'] as String,
                active: r['is_active'] as bool,
              ),
            )
            .toList(growable: false),
        products: products,
      );
    } on CatalogFailure {
      rethrow;
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<String> saveProduct(
    ManagedProduct product, {
    required String requestId,
  }) async {
    final actor = _identity();
    try {
      final result = await client
          .rpc(
            'save_managed_product',
            params: {
              'p_request_id': requestId,
              'p_product_id': product.id,
              'p_expected_updated_at': product.updatedAt,
              'p_name': product.name.trim(),
              'p_category_id': product.categoryId,
              'p_description': product.description.trim(),
              'p_image_path': product.imagePath.trim().isEmpty
                  ? null
                  : product.imagePath.trim(),
              'p_is_active': product.active,
              'p_variants': product.variants.map((v) => v.toCommand()).toList(),
            },
          )
          .setHeader('Authorization', 'Bearer ${actor.token}')
          .retry(enabled: false, requestTimeout: const Duration(seconds: 15));
      _checkIdentity(actor);
      if (result is! String ||
          !RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
          ).hasMatch(result)) {
        throw const CatalogFailure(
          'Máy chủ chưa xác nhận lưu sản phẩm.',
          outcomeUnknown: true,
        );
      }
      return result;
    } on CatalogFailure {
      rethrow;
    } catch (error) {
      throw _failure(error, writing: true);
    }
  }

  Future<List<Map<String, dynamic>>> _readAll(
    String table,
    String columns,
  ) async {
    final actor = _identity();
    final result = <Map<String, dynamic>>[];
    const batchSize = 500;
    var offset = 0;
    while (true) {
      final batch = await client
          .from(table)
          .select(columns)
          .order('id')
          .range(offset, offset + batchSize - 1)
          .setHeader('Authorization', 'Bearer ${actor.token}')
          .retry(enabled: false, requestTimeout: const Duration(seconds: 15));
      _checkIdentity(actor);
      result.addAll(batch);
      if (batch.length < batchSize) return result;
      offset += batchSize;
    }
  }

  CatalogFailure _failure(Object error, {bool writing = false}) {
    if (error is PostgrestException) {
      if (error.code == '42501') {
        return const CatalogFailure('Bạn không có quyền quản lý sản phẩm.');
      }
      if (error.code == '23505') {
        return const CatalogFailure('SKU đã tồn tại. Vui lòng chọn SKU khác.');
      }
      if (error.code == '40001') {
        return const CatalogFailure(
          'Sản phẩm hoặc tồn kho đã thay đổi. Đóng biểu mẫu và tải lại trước khi sửa.',
        );
      }
      if (error.code == '22023' || error.code == '23514') {
        return const CatalogFailure(
          'Kiểm tra thông tin, SKU, giá và tồn kho (không được thấp hơn số đã giữ).',
        );
      }
      if (error.code == 'PGRST202') {
        return const CatalogFailure(
          'Chức năng lưu sản phẩm chưa sẵn sàng. Vui lòng liên hệ quản trị viên.',
        );
      }
      if (RegExp(r'^[0-9A-Z]{5}$').hasMatch(error.code ?? '')) {
        return const CatalogFailure(
          'Máy chủ từ chối lưu. Kiểm tra dữ liệu và thử lại.',
        );
      }
    }
    return CatalogFailure(
      'Không thể kết nối dữ liệu sản phẩm. Vui lòng thử lại.',
      outcomeUnknown: writing,
    );
  }
}
