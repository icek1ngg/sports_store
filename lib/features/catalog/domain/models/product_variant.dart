/// A sellable product variant and its currently available stock.
class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.productId,
    required this.sku,
    required this.label,
    required this.attributes,
    required this.priceVnd,
    required this.availableQuantity,
  });

  final String id;
  final String productId;
  final String sku;
  final String label;
  final Map<String, dynamic> attributes;
  final int priceVnd;
  final int availableQuantity;

  bool get isInStock => availableQuantity > 0;

  /// Optional catalog attributes; older variants can still use only [label].
  String? get color => _textAttribute('color');
  String? get size => _textAttribute('size');

  /// Six-digit RGB swatch, independent of the product photograph.
  String? get colorHex {
    final value = _textAttribute('color_hex');
    return value != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)
        ? value
        : null;
  }

  /// Image of this exact colorway, not a recolored product-level photograph.
  String? get imagePath => _imagePath(attributes['image_path']);

  /// Ordered, unique gallery paths, with the primary image first if present.
  List<String> get imagePaths {
    final paths = <String>{};
    final primary = imagePath;
    if (primary != null) paths.add(primary);
    final gallery = attributes['image_paths'];
    if (gallery is List) {
      for (final raw in gallery) {
        final path = _imagePath(raw);
        if (path != null) paths.add(path);
      }
    }
    return List.unmodifiable(paths);
  }

  String? _textAttribute(String key) {
    final value = attributes[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  static String? _imagePath(Object? raw) {
    if (raw is! String) return null;
    final path = raw.trim();
    if (path.isEmpty || path.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      return null;
    }
    final uri = Uri.tryParse(path);
    if (uri == null) return null;
    if (uri.hasScheme) {
      if (uri.scheme == 'asset') {
        return catalogAssetPath(path) == null ? null : path;
      }
      return uri.scheme == 'https' &&
              uri.host.isNotEmpty &&
              uri.userInfo.isEmpty
          ? path
          : null;
    }
    // Storage object path, resolved by the shared signed-URL provider.
    String decoded;
    try {
      decoded = Uri.decodeComponent(path);
    } on FormatException {
      return null;
    }
    if (uri.hasAuthority ||
        uri.hasQuery ||
        uri.hasFragment ||
        path.startsWith('/') ||
        path.contains('\\') ||
        decoded
            .split('/')
            .any((segment) => segment == '.' || segment == '..')) {
      return null;
    }
    return path;
  }

  @override
  bool operator ==(Object other) {
    return other is ProductVariant &&
        id == other.id &&
        productId == other.productId &&
        sku == other.sku &&
        label == other.label &&
        _jsonEquals(attributes, other.attributes) &&
        priceVnd == other.priceVnd &&
        availableQuantity == other.availableQuantity;
  }

  @override
  int get hashCode => Object.hash(
    id,
    productId,
    sku,
    label,
    _jsonHash(attributes),
    priceVnd,
    availableQuantity,
  );
}

/// Resolves only explicitly bundled catalog images, without URI decoding.
///
/// Keeping this grammar shared by mapping, adapters and rendering prevents an
/// encoded traversal or a remote authority from reaching an asset loader.
String? catalogAssetPath(String value) {
  final match = RegExp(
    r'^asset:assets/images/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*\.(?:png|jpg|jpeg|webp)$',
  ).firstMatch(value);
  if (match == null || match.end != value.length) {
    return null;
  }
  return value.substring('asset:'.length);
}

bool _jsonEquals(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_jsonEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_jsonEquals(left[index], right[index])) return false;
    }
    return true;
  }
  return left == right;
}

int _jsonHash(Object? value) {
  if (value is Map) {
    final entries =
        value.entries
            .map(
              (entry) => MapEntry(entry.key.toString(), _jsonHash(entry.value)),
            )
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return Object.hashAll(
      entries.map((entry) => Object.hash(entry.key, entry.value)),
    );
  }
  if (value is List) return Object.hashAll(value.map(_jsonHash));
  return value.hashCode;
}
