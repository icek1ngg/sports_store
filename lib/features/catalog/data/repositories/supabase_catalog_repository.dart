import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../deliveries/data/repositories/operational_read_access.dart';
import '../../../deliveries/domain/models/operational_failure.dart';
import '../../domain/models/catalog_page.dart';
import '../../domain/models/catalog_query.dart';
import '../../domain/models/category.dart';
import '../../domain/models/product.dart';
import '../../domain/models/managed_product.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../models/catalog_dto.dart';

/// Shared Supabase adapter for customer reads and manager catalog operations.
///
/// Role authorization and account-epoch checks are delegated to the shared
/// [OperationalReadAccess]. This adapter never reads role claims from the
/// client-editable auth metadata and never supplies demo rows on failure.
class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository({required this.access});

  static const _categoryProjection = 'id,code,name,is_active';
  static const _productProjection =
      'id,category_id,name,description,image_path,is_active,'
      'categories!inner(id,code,name,is_active)';
  static const _variantProjection =
      'id,product_id,sku,label,attributes,price_vnd,available_quantity,is_active';

  // Read variants in batches with a keyset cursor until the API returns no rows.
  // This avoids both N+1 requests and silent embedded-relation truncation.
  static const _categoryPageSize = 1000;
  static const _variantPageSize = 500;
  static const _signedUrlLifetimeSeconds = 3600;
  static const _maxSafeInteger = 9007199254740991;

  final OperationalReadAccess access;

  SupabaseClient get client => access.client;

  @override
  Future<List<Category>> getCategories() {
    return access.run<List<Category>>(
      roles: const {'customer', 'manager'},
      action: (identity) async {
        final categories = <Category>[];
        final ids = <String>{};
        var offset = 0;

        while (true) {
          identity.ensureCurrent();
          var request = access.client
              .from('categories')
              .select(_categoryProjection);
          if (identity.role == 'customer') {
            request = request.eq('is_active', true);
          }
          final response = await request
              .order('name', ascending: true)
              .order('id', ascending: true)
              .range(offset, offset + _categoryPageSize - 1)
              .retry(enabled: false);
          identity.ensureCurrent();

          final rows = _rows(response, 'categories');
          for (final row in rows) {
            final dto = CategoryDto.fromJson(row);
            if (identity.role == 'customer' && !dto.isActive) continue;
            if (!ids.add(dto.id.toLowerCase())) {
              throw const FormatException('Duplicate category ID');
            }
            categories.add(dto.toDomain());
          }
          if (rows.isEmpty) break;
          offset += rows.length;
        }
        return List<Category>.unmodifiable(categories);
      },
    );
  }

  @override
  Future<CatalogPage> getProducts(CatalogQuery query) {
    _validateQuery(query);
    return access.run<CatalogPage>(
      roles: const {'customer', 'manager'},
      action: (identity) async {
        identity.ensureCurrent();
        var request = access.client.from('products').select(_productProjection);
        // These filters are deliberate for customer reads even though RLS
        // also applies them. Managers need the same repository for catalog
        // maintenance and may inspect inactive rows as unavailable products.
        if (identity.role == 'customer') {
          request = request
              .eq('is_active', true)
              .eq('categories.is_active', true);
        }

        final search = query.search;
        if (search.isNotEmpty) {
          request = request.ilike('name', '%${_escapeIlike(search)}%');
        }
        if (query.categoryId != null) {
          request = request.eq('category_id', query.categoryId!);
        }
        final transformed = request
            .order('name', ascending: true)
            .order('id', ascending: true)
            .range(
              query.page * query.pageSize,
              query.page * query.pageSize + query.pageSize,
            );

        final response = await transformed.retry(enabled: false);
        identity.ensureCurrent();
        final rows = _rows(response, 'products');
        final parsed = <ProductDto>[];
        final ids = <String>{};

        for (final row in rows) {
          final dto = ProductDto.fromJson(row);
          if (identity.role == 'customer' &&
              (!dto.isActive || !dto.categoryIsActive)) {
            continue;
          }
          if (!ids.add(dto.id.toLowerCase())) {
            throw const FormatException('Duplicate product ID');
          }
          parsed.add(dto);
        }

        final hasMore = parsed.length > query.pageSize;
        final visible = parsed.take(query.pageSize).toList();
        final variants = visible.isEmpty
            ? <ProductVariantDto>[]
            : await _readAllVariants(
                visible.map((p) => p.id).toList(),
                identity,
              );
        identity.ensureCurrent();
        final products = visible
            .map(
              (dto) => dto.toDomain(
                variantsOverride: variants
                    .where(
                      (v) => v.productId.toLowerCase() == dto.id.toLowerCase(),
                    )
                    .toList(),
              ),
            )
            .toList();
        return CatalogPage(products: products, hasMore: hasMore);
      },
    );
  }

  @override
  Future<Product?> getProduct(String id) {
    _checkUuid(id, 'id');
    return access.run<Product?>(
      roles: const {'customer', 'manager'},
      action: (identity) async {
        identity.ensureCurrent();
        var request = access.client
            .from('products')
            .select(_productProjection)
            .eq('id', id);
        if (identity.role == 'customer') {
          request = request
              .eq('is_active', true)
              .eq('categories.is_active', true);
        }
        final response = await request
            .limit(1)
            .maybeSingle()
            .retry(enabled: false);
        identity.ensureCurrent();

        if (response == null) return null;
        final row = _row(response, 'product');
        final dto = ProductDto.fromJson(row);
        if (identity.role == 'customer' &&
            (!dto.isActive || !dto.categoryIsActive)) {
          return null;
        }
        if (dto.id.toLowerCase() != id.toLowerCase()) {
          throw const FormatException('Wrong product ID');
        }
        return _toProductWithCompleteVariants(dto, identity);
      },
    );
  }

  @override
  Future<String?> getImageUrl(String path) {
    if (path.trim().isEmpty || path.contains('\u0000')) {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }
    return access.run<String?>(
      roles: const {'customer', 'manager'},
      action: (identity) async {
        identity.ensureCurrent();
        final uri = Uri.tryParse(path);
        if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
          // MH03 accepts an HTTPS image URL as well as a private object path.
          // Customer cards must render the same saved image representation.
          return path;
        }
        final url = await access.client.storage
            .from('product-images')
            .createSignedUrl(path, _signedUrlLifetimeSeconds);
        identity.ensureCurrent();
        return url;
      },
    );
  }

  Future<Product> _toProductWithCompleteVariants(
    ProductDto dto,
    ReadIdentity identity,
  ) async {
    // Always use a separate keyset read for the one-to-many relation. An
    // embedded relation can be silently capped by the API's configured
    // max-rows value, which an explicit referenced-table limit cannot raise.
    final variants = await _readAllVariants([dto.id], identity);
    identity.ensureCurrent();
    return dto.toDomain(variantsOverride: variants);
  }

  Future<List<ProductVariantDto>> _readAllVariants(
    List<String> productIds,
    ReadIdentity identity,
  ) async {
    final variants = <ProductVariantDto>[];
    final ids = <String>{};
    String? afterId;

    while (true) {
      identity.ensureCurrent();
      var request = access.client
          .from('product_variants')
          .select(_variantProjection)
          .inFilter('product_id', productIds)
          .eq('is_active', true);
      if (afterId != null) request = request.gt('id', afterId);
      final transformed = request
          .order('id', ascending: true)
          .limit(_variantPageSize);

      final response = await transformed.retry(enabled: false);
      identity.ensureCurrent();
      final rows = _rows(response, 'product_variants');
      String? pageLastId;
      for (final row in rows) {
        final dto = ProductVariantDto.fromJson(row);
        if (pageLastId != null &&
            dto.id.toLowerCase().compareTo(pageLastId.toLowerCase()) <= 0) {
          throw const FormatException('Variant response is not sorted');
        }
        if (afterId != null &&
            dto.id.toLowerCase().compareTo(afterId.toLowerCase()) <= 0) {
          throw const FormatException('Variant cursor did not advance');
        }
        pageLastId = dto.id;
        if (!productIds.any(
          (id) => id.toLowerCase() == dto.productId.toLowerCase(),
        )) {
          throw const FormatException('Variant belongs to another product');
        }
        if (!dto.isActive) continue;
        if (!ids.add(dto.id.toLowerCase())) {
          throw const FormatException('Duplicate variant ID');
        }
        variants.add(dto);
      }
      if (rows.isEmpty) break;
      if (pageLastId == null) {
        throw const FormatException('Variant response cursor is missing');
      }
      afterId = pageLastId;
    }
    return List<ProductVariantDto>.unmodifiable(variants);
  }

  static List<Map<String, dynamic>> _rows(dynamic response, String source) {
    if (response is! List) throw FormatException('Invalid $source response');
    return response.map((raw) => _row(raw, source)).toList(growable: false);
  }

  static Map<String, dynamic> _row(dynamic raw, String source) {
    if (raw is! Map) throw FormatException('Invalid $source response row');
    final row = <String, dynamic>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) {
        throw FormatException('Invalid $source response keys');
      }
      row[entry.key as String] = entry.value;
    }
    return row;
  }

  static void _validateQuery(CatalogQuery query) {
    if (query.page < 0 || query.pageSize < 1 || query.pageSize > 100) {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }
    if (query.categoryId != null) _checkUuid(query.categoryId!, 'categoryId');
    if (query.page > (_maxSafeInteger - query.pageSize) ~/ query.pageSize) {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }
  }

  static void _checkUuid(String value, String key) {
    try {
      CatalogDtoReaders.checkUuid(value, key);
    } on FormatException {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }
  }

  static String _escapeIlike(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
  }

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
      final categories = await _readAll(
        'categories',
        'id,name,is_active',
        actor: actor,
      );
      final rows = await _readAll(
        'products',
        'id,name,category_id,description,image_path,is_active,updated_at,categories(name)',
        actor: actor,
      );
      final variants = await _readAll(
        'product_variants',
        'id,product_id,sku,label,attributes,price_vnd,on_hand,reserved,is_active',
        actor: actor,
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
    String columns, {
    required ({String userId, String token}) actor,
  }) async {
    final result = <Map<String, dynamic>>[];
    const batchSize = 500;
    var offset = 0;
    while (true) {
      _checkIdentity(actor);
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
