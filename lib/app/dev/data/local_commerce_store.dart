import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../demo/data/local_demo_store.dart';
import '../../../../features/cart/domain/models/cart_failure.dart';
import '../../../../features/cart/domain/models/cart_item.dart';
import '../../../../features/cart/domain/repositories/cart_repository.dart';
import '../../../../features/catalog/domain/models/catalog_page.dart';
import '../../../../features/catalog/domain/models/catalog_query.dart';
import '../../../../features/catalog/domain/models/category.dart';
import '../../../../features/catalog/domain/models/managed_product.dart';
import '../../../../features/catalog/domain/models/product.dart';
import '../../../../features/catalog/domain/models/product_variant.dart';
import '../../../../features/catalog/domain/repositories/catalog_repository.dart';
import '../../../../features/catalog/domain/repositories/product_image_repository.dart';
import '../../../../features/catalog/domain/models/product_image.dart';
import '../../../../features/checkout/data/repositories/pending_placement_store.dart';
import '../../../../features/checkout/domain/models/checkout_failure.dart';
import '../../../../features/checkout/domain/models/placement_request.dart';
import '../../../../features/checkout/domain/models/placement_result.dart';
import '../../../../features/checkout/domain/repositories/checkout_repository.dart';
import '../../../../features/orders/domain/models/order.dart';
import '../../../../features/orders/domain/models/order_item.dart';
import '../../../../features/orders/domain/models/order_status.dart';

/// RAM-only catalogue, stock and carts. Checkout joins the existing local Orders
/// aggregate, so manager/customer lists never read a disconnected fixture.
class LocalCommerceStore implements ProductImageRepository {
  LocalCommerceStore(this.store) {
    store.onInventoryRelease = _release;
    reset();
  }
  final LocalDemoStore store;
  late final CatalogRepository catalog = _Catalog(this);
  late final CartRepository cart = _Cart(this);
  late final CheckoutRepository checkout = _Checkout(this);
  var pendingPlacements = InMemoryPendingPlacementStore();
  final _products = <String, ManagedProduct>{};
  final _carts = <String, Map<String, int>>{};
  final _placements =
      <String, ({String fingerprint, PlacementResult result})>{};
  final _reservations = <String, List<PlacementItem>>{};
  final _saves = <String, ({String fingerprint, String id})>{};
  final _imageUrls = <String, String>{};
  final _uploads = <String, ({String body, UploadedProductImage ack})>{};
  static const _uuid = Uuid();
  static const categoryId = '30000000-0000-4000-8000-000000000001';
  static String productId(int n) =>
      '30000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
  static String variantId(int n) =>
      '40000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
  static const categories = [
    Category(id: categoryId, code: 'sports', name: 'Đồ thể thao'),
  ];

  void reset() {
    pendingPlacements = InMemoryPendingPlacementStore();
    _products.clear();
    _carts.clear();
    _placements.clear();
    _reservations.clear();
    _saves.clear();
    _imageUrls.clear();
    _uploads.clear();
    for (var n = 1; n <= 6; n++) {
      _products[productId(n)] = ManagedProduct(
        id: productId(n),
        name: [
          'Giày chạy bộ STRIDE',
          'Áo thể thao ACTIVE',
          'Vợt cầu lông SPEED',
          'Bóng đá MATCH',
          'Quần thể thao FLEX',
          'Túi thể thao CLUB',
        ][n - 1],
        categoryId: categoryId,
        categoryName: 'Đồ thể thao',
        imagePath: 'assets/images/stride-products.png',
        imageUrl: 'assets/images/stride-products.png',
        description:
            'Thiết kế thoải mái, phù hợp tập luyện và vận động hàng ngày.',
        variants: [
          ManagedVariant(
            id: variantId(n),
            sku: 'SPORT-$n',
            label: n == 1 ? 'Xanh navy · 42' : 'Đen · M',
            attributes: {
              'color': n == 1 ? 'Xanh navy' : 'Đen',
              'size': n == 1 ? '42' : 'M',
            },
            priceVnd: [450000, 250000, 650000, 300000, 220000, 350000][n - 1],
            onHand: 20,
          ),
        ],
      );
    }
  }

  String _customer() {
    if (store.session.role != 'customer') {
      throw const CartFailure(CartFailureCode.permissionDenied);
    }
    return store.session.userId!;
  }

  void _manager() {
    if (store.session.role != 'manager') {
      throw const CatalogFailure('Chỉ quản lý được thay đổi sản phẩm.');
    }
  }

  @override
  Future<UploadedProductImage> uploadImage(
    SelectedProductImage image, {
    required String requestId,
  }) async {
    _manager();
    final body = base64Encode(image.bytes);
    final previous = _uploads[requestId];
    if (previous != null) {
      if (previous.body != body) {
        throw const CatalogFailure(
          'Yêu cầu ảnh đã được dùng với nội dung khác.',
        );
      }
      return previous.ack;
    }
    final path = 'local-images/$requestId.${image.extension}';
    final url = 'data:${image.contentType};base64,$body';
    final ack = UploadedProductImage(path: path, previewUrl: url);
    _imageUrls[path] = url;
    _uploads[requestId] = (body: body, ack: ack);
    return ack;
  }

  Product _product(ManagedProduct p) => Product(
    id: p.id!,
    categoryId: p.categoryId,
    categoryName: p.categoryName,
    name: p.name,
    description: p.description,
    imagePath: p.imagePath.isEmpty ? null : p.imagePath,
    variants: p.variants
        .where((v) => v.active)
        .map(
          (v) => ProductVariant(
            id: v.id!,
            productId: p.id!,
            sku: v.sku,
            label: v.label,
            attributes: v.attributes,
            priceVnd: v.priceVnd,
            availableQuantity: v.available,
          ),
        )
        .toList(),
  );
  ({ManagedProduct product, ManagedVariant variant})? _variant(String id) {
    for (final p in _products.values) {
      if (!p.active) continue;
      for (final v in p.variants) {
        if (v.id == id && v.active) return (product: p, variant: v);
      }
    }
    return null;
  }

  void _adjust(String id, int delta) {
    for (final p in _products.values.toList()) {
      if (!p.variants.any((v) => v.id == id)) continue;
      _products[p.id!] = ManagedProduct(
        id: p.id,
        name: p.name,
        categoryId: p.categoryId,
        categoryName: p.categoryName,
        description: p.description,
        imagePath: p.imagePath,
        imageUrl: p.imageUrl,
        active: p.active,
        variants: p.variants
            .map(
              (v) => v.id != id
                  ? v
                  : ManagedVariant(
                      id: v.id,
                      sku: v.sku,
                      label: v.label,
                      priceVnd: v.priceVnd,
                      onHand: v.onHand,
                      reserved: v.reserved + delta,
                      active: v.active,
                      attributes: v.attributes,
                    ),
            )
            .toList(),
      );
      return;
    }
  }

  void _release(String orderId) {
    final items = _reservations.remove(orderId);
    if (items != null) {
      for (final item in items) {
        _adjust(item.variantId, -item.quantity);
      }
    }
  }
}

class _Catalog implements CatalogRepository {
  _Catalog(this.s);
  final LocalCommerceStore s;
  @override
  Future<List<Category>> getCategories() async => LocalCommerceStore.categories;
  @override
  Future<String?> getImageUrl(String path) async =>
      path.startsWith('assets/') ? path : s._imageUrls[path];
  @override
  Future<Product?> getProduct(String id) async {
    final p = s._products[id];
    return p == null || !p.active ? null : s._product(p);
  }

  @override
  Future<CatalogPage> getProducts(CatalogQuery q) async {
    final rows = s._products.values
        .where(
          (p) =>
              p.active &&
              (q.categoryId == null || p.categoryId == q.categoryId) &&
              p.name.toLowerCase().contains(q.search.trim().toLowerCase()),
        )
        .toList();
    final offset = q.page * q.pageSize;
    return CatalogPage(
      products: rows.skip(offset).take(q.pageSize).map(s._product).toList(),
      hasMore: offset + q.pageSize < rows.length,
    );
  }

  @override
  Future<CatalogSnapshot> loadManagement() async {
    s._manager();
    return CatalogSnapshot(
      categories: LocalCommerceStore.categories
          .map((c) => CatalogCategory(id: c.id, name: c.name, active: true))
          .toList(),
      products: s._products.values.toList(),
    );
  }

  @override
  Future<String> saveProduct(
    ManagedProduct p, {
    required String requestId,
  }) async {
    s._manager();
    if (p.name.trim().isEmpty ||
        p.categoryId != LocalCommerceStore.categoryId ||
        p.variants.isEmpty ||
        p.variants.any(
          (v) =>
              v.priceVnd < 0 ||
              v.onHand < v.reserved ||
              v.sku.trim().isEmpty ||
              v.label.trim().isEmpty,
        )) {
      throw const CatalogFailure('Thông tin sản phẩm chưa hợp lệ.');
    }
    final fingerprint = jsonEncode([
      p.id,
      p.name,
      p.categoryId,
      p.description,
      p.imagePath,
      p.active,
      p.variants.map((v) => v.toCommand()).toList(),
    ]);
    final old = s._saves[requestId];
    if (old != null) {
      if (old.fingerprint != fingerprint) {
        throw const CatalogFailure('Mã yêu cầu đã được sử dụng.');
      }
      return old.id;
    }
    final id = p.id ?? LocalCommerceStore._uuid.v4();
    final previous = s._products[id];
    final variants = p.variants.map((v) {
      final oldVariants = previous?.variants
          .where((old) => old.id == v.id)
          .toList();
      final current = oldVariants?.isNotEmpty == true
          ? oldVariants!.single
          : null;
      final reserved = current?.reserved ?? 0;
      if ((v.expectedOnHand != null && v.expectedOnHand != current?.onHand) ||
          v.onHand < reserved) {
        throw const CatalogFailure('Tồn kho đã thay đổi. Vui lòng tải lại.');
      }
      return ManagedVariant(
        id: v.id ?? LocalCommerceStore._uuid.v4(),
        sku: v.sku,
        label: v.label,
        priceVnd: v.priceVnd,
        onHand: v.onHand,
        reserved: reserved,
        active: v.active,
        attributes: v.attributes,
      );
    }).toList();
    if (previous != null &&
        previous.variants.any(
          (old) => old.reserved > 0 && !variants.any((v) => v.id == old.id),
        )) {
      throw const CatalogFailure(
        'Không thể xóa biến thể đang giữ hàng cho đơn.',
      );
    }
    s._products[id] = ManagedProduct(
      id: id,
      name: p.name,
      categoryId: p.categoryId,
      categoryName: 'Đồ thể thao',
      description: p.description,
      imagePath: p.imagePath,
      imageUrl: p.imagePath.startsWith('assets/')
          ? p.imagePath
          : s._imageUrls[p.imagePath],
      active: p.active,
      variants: variants,
    );
    s._saves[requestId] = (fingerprint: fingerprint, id: id);
    return id;
  }
}

class _Cart implements CartRepository {
  _Cart(this.s);
  final LocalCommerceStore s;
  @override
  Future<List<CartItem>> getItems() async {
    final owner = s._customer();
    return (s._carts[owner] ?? {}).entries.map((e) {
      final found = s._variant(e.key);
      final product = found == null ? null : s._product(found.product);
      return CartItem(
        variantId: e.key,
        quantity: e.value,
        product: product,
        variant: product?.variants.where((v) => v.id == e.key).firstOrNull,
      );
    }).toList();
  }

  @override
  Future<void> setQuantity({
    required String variantId,
    required int quantity,
  }) async {
    final owner = s._customer();
    final v = s._variant(variantId);
    if (quantity < 1) throw const CartFailure(CartFailureCode.invalidData);
    if (v == null) throw const CartFailure(CartFailureCode.unavailable);
    if (quantity > v.variant.available) {
      throw const CartFailure(CartFailureCode.insufficientStock);
    }
    (s._carts[owner] ??= {})[variantId] = quantity;
  }

  @override
  Future<void> removeItem(String variantId) async {
    s._carts[s._customer()]?.remove(variantId);
  }
}

class _Checkout implements CheckoutRepository {
  _Checkout(this.s);
  final LocalCommerceStore s;
  @override
  Future<PlacementLookupResult> lookupPlacementResult(String requestId) async {
    final owner = s._customer();
    final saved = s._placements['$owner:$requestId'];
    return saved == null
        ? const PlacementLookupResult.notFound()
        : PlacementLookupResult.committed(_replay(saved.result));
  }

  @override
  Future<PlacementResult> placeOrder(PlacementRequest r) async {
    final scope = s.store.session;
    if (scope.role != 'customer') {
      throw const CheckoutFailure(
        CheckoutFailureCode.permissionDenied,
        definitiveNoCommit: true,
      );
    }
    final key = '${scope.userId}:${r.requestId}';
    final saved = s._placements[key];
    if (saved != null) {
      if (saved.fingerprint != r.fingerprint) {
        throw const CheckoutFailure(
          CheckoutFailureCode.idempotencyConflict,
          definitiveNoCommit: true,
        );
      }
      return _replay(saved.result);
    }
    if (!await _insideHanoi(r.latitude, r.longitude)) {
      throw const CheckoutFailure(
        CheckoutFailureCode.outsideServiceArea,
        definitiveNoCommit: true,
      );
    }
    if (scope != s.store.session) {
      throw const CheckoutFailure(CheckoutFailureCode.sessionExpired);
    }
    // Recheck after async geography read: a competing request may have committed.
    final raced = s._placements[key];
    if (raced != null) {
      if (raced.fingerprint != r.fingerprint) {
        throw const CheckoutFailure(
          CheckoutFailureCode.idempotencyConflict,
          definitiveNoCommit: true,
        );
      }
      return _replay(raced.result);
    }
    final id = LocalCommerceStore._uuid.v4();
    final event = LocalCommerceStore._uuid.v4();
    final now = DateTime.now().toUtc();
    final items = <OrderItem>[];
    for (final i in r.items) {
      final v = s._variant(i.variantId);
      if (v == null || v.variant.available < i.quantity) {
        throw const CheckoutFailure(
          CheckoutFailureCode.insufficientStock,
          definitiveNoCommit: true,
        );
      }
      items.add(
        OrderItem(
          id: LocalCommerceStore._uuid.v4(),
          orderId: id,
          productId: v.product.id!,
          variantId: i.variantId,
          productName: v.product.name,
          variantLabel: v.variant.label,
          attributes: Map<String, Object?>.from(v.variant.attributes),
          unitPriceVnd: v.variant.priceVnd,
          quantity: i.quantity,
          lineTotalVnd: v.variant.priceVnd * i.quantity,
          createdAt: now,
        ),
      );
    }
    final subtotal = items.fold<int>(0, (sum, i) => sum + i.lineTotalVnd);
    final order = Order(
      id: id,
      customerId: scope.userId!,
      requestId: r.requestId,
      status: OrderStatus.pendingConfirmation,
      recipientName: r.recipientName,
      recipientPhone: r.recipientPhone,
      addressDetail: r.addressDetail,
      latitude: r.latitude,
      longitude: r.longitude,
      subtotalVnd: subtotal,
      deliveryFeeVnd: 30000,
      totalCodVnd: subtotal + 30000,
      deliveryAttemptCount: 0,
      placedAt: now,
      confirmedAt: null,
      source: null,
      confirmedBy: null,
      deliveredAt: null,
      cancelReason: null,
      createdAt: now,
      updatedAt: now,
    );
    final result = PlacementResult(
      order: order,
      items: items,
      eventId: event,
      replayed: false,
    );
    s.store.addCheckoutOrder(order, items, event);
    for (final i in r.items) {
      s._adjust(i.variantId, i.quantity);
    }
    s._reservations[id] = r.items;
    s._carts[scope.userId]?.clear();
    s._placements[key] = (fingerprint: r.fingerprint, result: result);
    return result;
  }

  PlacementResult _replay(PlacementResult result) => PlacementResult(
    order: result.order,
    items: result.items,
    eventId: result.eventId,
    replayed: true,
  );
}

Future<bool> _insideHanoi(double latitude, double longitude) async {
  final root = jsonDecode(
    await rootBundle.loadString('assets/data/hanoi_boundary_source.geojson'),
  ) as Map;
  bool ring(List points) {
    var inside = false;
    for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
      final a = points[i] as List;
      final b = points[j] as List;
      final ax = (a[0] as num).toDouble(), ay = (a[1] as num).toDouble();
      final bx = (b[0] as num).toDouble(), by = (b[1] as num).toDouble();
      if ((ay > latitude) != (by > latitude) &&
          longitude < (bx - ax) * (latitude - ay) / (by - ay) + ax) {
        inside = !inside;
      }
    }
    return inside;
  }

  bool polygon(List rings) =>
      rings.isNotEmpty &&
      ring(rings.first as List) &&
      !rings.skip(1).any((r) => ring(r as List));
  bool geometry(Map g) {
    final coordinates = g['coordinates'] as List;
    return g['type'] == 'Polygon'
        ? polygon(coordinates)
        : g['type'] == 'MultiPolygon' &&
              coordinates.any((p) => polygon(p as List));
  }

  if (root['type'] == 'FeatureCollection') {
    return (root['features'] as List).any(
      (f) => geometry((f as Map)['geometry'] as Map),
    );
  }
  return geometry(root['type'] == 'Feature' ? root['geometry'] as Map : root);
}
