import '../../domain/models/category.dart';
import '../../domain/models/product.dart';
import '../../domain/models/product_variant.dart';

/// Strict readers and transport DTOs for catalogue rows.
///
/// Supabase responses are untrusted input. In particular, bigint values may be
/// decoded as either a Dart int or a lossless decimal string depending on the
/// transport and platform; floating point values are never coerced to money or
/// stock quantities.
class CatalogDtoReaders {
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final RegExp _integerPattern = RegExp(r'^\d+$');
  static final BigInt _maxSafeInteger = BigInt.parse('9007199254740991');

  static String readRequiredString(
    Map<String, dynamic> json,
    String key, {
    bool nonBlank = true,
  }) {
    if (!json.containsKey(key) || json[key] == null) {
      throw _invalid(key, 'a non-null string');
    }
    final raw = json[key];
    if (raw is! String || (nonBlank && raw.trim().isEmpty)) {
      throw _invalid(key, 'a non-blank string');
    }
    return raw;
  }

  static String? readNullableString(
    Map<String, dynamic> json,
    String key, {
    bool nonBlank = true,
  }) {
    if (!json.containsKey(key) || json[key] == null) return null;
    final raw = json[key];
    if (raw is! String || (nonBlank && raw.trim().isEmpty)) {
      throw _invalid(key, 'null or a non-blank string');
    }
    return raw;
  }

  static String readRequiredUuid(Map<String, dynamic> json, String key) {
    final value = readRequiredString(json, key, nonBlank: false);
    checkUuid(value, key);
    return value;
  }

  static int readRequiredInteger(
    Map<String, dynamic> json,
    String key, {
    bool nonNegative = true,
  }) {
    final value = readNullableInteger(json, key, nonNegative: nonNegative);
    if (value == null) throw _invalid(key, 'a safe integer');
    return value;
  }

  static int? readNullableInteger(
    Map<String, dynamic> json,
    String key, {
    bool nonNegative = true,
  }) {
    if (!json.containsKey(key) || json[key] == null) return null;

    final raw = json[key];
    final value = switch (raw) {
      int integer => BigInt.from(integer),
      String text when _integerPattern.hasMatch(text) => BigInt.parse(text),
      _ => throw _invalid(key, 'a safe integer or lossless integer string'),
    };
    if (nonNegative && value.isNegative) {
      throw _invalid(key, 'a non-negative integer');
    }
    if (value > _maxSafeInteger || value < -_maxSafeInteger) {
      throw _invalid(key, 'an integer within the JavaScript safe range');
    }
    return value.toInt();
  }

  static Map<String, dynamic> readRequiredJsonObject(
    Map<String, dynamic> json,
    String key,
  ) {
    if (!json.containsKey(key) || json[key] == null) {
      throw _invalid(key, 'a JSON object');
    }
    final raw = json[key];
    if (raw is! Map) throw _invalid(key, 'a JSON object');
    return _freezeObject(raw, key);
  }

  static bool readRequiredActive(Map<String, dynamic> json, String key) {
    if (!json.containsKey(key)) throw _invalid(key, 'a boolean');
    final raw = json[key];
    if (raw is! bool) throw _invalid(key, 'a boolean');
    return raw;
  }

  static Map<String, dynamic> _freezeObject(Map raw, String key) {
    final result = <String, dynamic>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) {
        throw _invalid(key, 'a JSON object with string keys');
      }
      result[entry.key as String] = _freezeJson(entry.value, key);
    }
    return Map.unmodifiable(result);
  }

  static dynamic _freezeJson(Object? value, String key) {
    if (value == null || value is String || value is bool) return value;
    if (value is num) {
      if (!value.isFinite) throw _invalid(key, 'finite JSON numbers');
      return value;
    }
    if (value is Map) return _freezeObject(value, key);
    if (value is List) {
      return List<dynamic>.unmodifiable(
        value.map((item) => _freezeJson(item, key)),
      );
    }
    throw _invalid(key, 'a JSON value');
  }

  static void checkUuid(String value, String key) {
    if (!_uuidPattern.hasMatch(value)) throw _invalid(key, 'a UUID');
  }

  static FormatException invalid(String key, String expected) =>
      _invalid(key, expected);

  static FormatException _invalid(String key, String expected) {
    return FormatException('Invalid $key: expected $expected');
  }
}

class CategoryDto {
  const CategoryDto({
    required this.id,
    required this.code,
    required this.name,
    this.isActive = true,
  });

  factory CategoryDto.fromJson(Map<String, dynamic> json) {
    return CategoryDto(
      id: CatalogDtoReaders.readRequiredUuid(json, 'id'),
      code: CatalogDtoReaders.readRequiredString(json, 'code'),
      name: CatalogDtoReaders.readRequiredString(json, 'name'),
      isActive: CatalogDtoReaders.readRequiredActive(json, 'is_active'),
    );
  }

  final String id;
  final String code;
  final String name;
  final bool isActive;

  Category toDomain() {
    CatalogDtoReaders.checkUuid(id, 'id');
    return Category(id: id, code: code, name: name);
  }
}

class ProductVariantDto {
  const ProductVariantDto({
    required this.id,
    required this.productId,
    required this.sku,
    required this.label,
    required this.attributes,
    required this.priceVnd,
    required this.availableQuantity,
    this.isActive = true,
  });

  factory ProductVariantDto.fromJson(Map<String, dynamic> json) {
    return ProductVariantDto(
      id: CatalogDtoReaders.readRequiredUuid(json, 'id'),
      productId: CatalogDtoReaders.readRequiredUuid(json, 'product_id'),
      sku: CatalogDtoReaders.readRequiredString(json, 'sku'),
      label: CatalogDtoReaders.readRequiredString(json, 'label'),
      attributes: CatalogDtoReaders.readRequiredJsonObject(json, 'attributes'),
      priceVnd: CatalogDtoReaders.readRequiredInteger(json, 'price_vnd'),
      availableQuantity: CatalogDtoReaders.readRequiredInteger(
        json,
        'available_quantity',
      ),
      isActive: CatalogDtoReaders.readRequiredActive(json, 'is_active'),
    );
  }

  final String id;
  final String productId;
  final String sku;
  final String label;
  final Map<String, dynamic> attributes;
  final int priceVnd;
  final int availableQuantity;
  final bool isActive;

  ProductVariant toDomain() {
    CatalogDtoReaders.checkUuid(id, 'id');
    CatalogDtoReaders.checkUuid(productId, 'product_id');
    if (priceVnd < 0) {
      throw CatalogDtoReaders.invalid('price_vnd', 'a non-negative integer');
    }
    if (availableQuantity < 0) {
      throw CatalogDtoReaders.invalid(
        'available_quantity',
        'a non-negative integer',
      );
    }
    return ProductVariant(
      id: id,
      productId: productId,
      sku: sku,
      label: label,
      attributes: attributes,
      priceVnd: priceVnd,
      availableQuantity: availableQuantity,
    );
  }
}

class ProductDto {
  const ProductDto({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.name,
    required this.description,
    required this.imagePath,
    required this.variants,
    this.isActive = true,
    this.categoryIsActive = true,
    this.hasEmbeddedVariants = true,
  });

  factory ProductDto.fromJson(
    Map<String, dynamic> json, {
    List<ProductVariantDto>? variants,
  }) {
    final categoryId = CatalogDtoReaders.readRequiredUuid(json, 'category_id');
    final category = _readCategory(json, categoryId);
    return ProductDto(
      id: CatalogDtoReaders.readRequiredUuid(json, 'id'),
      categoryId: categoryId,
      categoryName: category.name,
      name: CatalogDtoReaders.readRequiredString(json, 'name'),
      description: CatalogDtoReaders.readNullableString(
        json,
        'description',
        nonBlank: false,
      ),
      imagePath: _readOptionalImagePath(json),
      variants: variants ?? _readEmbeddedVariants(json),
      isActive: CatalogDtoReaders.readRequiredActive(json, 'is_active'),
      categoryIsActive: category.isActive,
      hasEmbeddedVariants: json.containsKey('product_variants'),
    );
  }

  final String id;
  final String categoryId;
  final String categoryName;
  final String name;
  final String? description;
  final String? imagePath;
  final List<ProductVariantDto> variants;
  final bool isActive;
  final bool categoryIsActive;
  final bool hasEmbeddedVariants;

  Product toDomain({List<ProductVariantDto>? variantsOverride}) {
    CatalogDtoReaders.checkUuid(id, 'id');
    CatalogDtoReaders.checkUuid(categoryId, 'category_id');
    final visibleVariants = <ProductVariant>[];
    final ids = <String>{};
    var totalAvailable = BigInt.zero;
    for (final variant in variantsOverride ?? variants) {
      if (variant.productId.toLowerCase() != id.toLowerCase()) {
        throw CatalogDtoReaders.invalid(
          'product_variants.product_id',
          'the parent product UUID',
        );
      }
      if (variant.isActive && ids.add(variant.id.toLowerCase())) {
        visibleVariants.add(variant.toDomain());
        totalAvailable += BigInt.from(variant.availableQuantity);
        if (totalAvailable > BigInt.parse('9007199254740991')) {
          throw CatalogDtoReaders.invalid(
            'available_quantity',
            'a total within the JavaScript safe range',
          );
        }
      } else if (variant.isActive) {
        throw CatalogDtoReaders.invalid('product_variants.id', 'unique UUIDs');
      }
    }
    return Product(
      id: id,
      categoryId: categoryId,
      categoryName: categoryName,
      name: name,
      description: description,
      imagePath: imagePath,
      variants: visibleVariants,
    );
  }

  static _CategoryData _readCategory(
    Map<String, dynamic> json,
    String categoryId,
  ) {
    final raw = json['categories'];
    Map<String, dynamic>? category;
    if (raw is Map) {
      category = <String, dynamic>{};
      for (final entry in raw.entries) {
        if (entry.key is! String) {
          throw CatalogDtoReaders.invalid(
            'categories',
            'a JSON object with string keys',
          );
        }
        category[entry.key as String] = entry.value;
      }
    } else if (raw is List) {
      if (raw.length != 1 || raw.first is! Map) {
        throw CatalogDtoReaders.invalid('categories', 'one category object');
      }
      category = <String, dynamic>{};
      for (final entry in (raw.first as Map).entries) {
        if (entry.key is! String) {
          throw CatalogDtoReaders.invalid(
            'categories',
            'a JSON object with string keys',
          );
        }
        category[entry.key as String] = entry.value;
      }
    }

    if (category != null) {
      final nestedId = CatalogDtoReaders.readRequiredUuid(category, 'id');
      if (nestedId.toLowerCase() != categoryId.toLowerCase()) {
        throw CatalogDtoReaders.invalid(
          'categories.id',
          'the product category UUID',
        );
      }
      CatalogDtoReaders.readRequiredString(category, 'code');
      final active = CatalogDtoReaders.readRequiredActive(
        category,
        'is_active',
      );
      return _CategoryData(
        name: CatalogDtoReaders.readRequiredString(category, 'name'),
        isActive: active,
      );
    }

    throw CatalogDtoReaders.invalid('categories', 'one category object');
  }

  static String? _readOptionalImagePath(Map<String, dynamic> json) {
    final value = CatalogDtoReaders.readNullableString(
      json,
      'image_path',
      nonBlank: false,
    );
    return value == null || value.trim().isEmpty ? null : value;
  }

  static List<ProductVariantDto> _readEmbeddedVariants(
    Map<String, dynamic> json,
  ) {
    if (!json.containsKey('product_variants')) return const [];
    final raw = json['product_variants'];
    if (raw is! List) {
      throw CatalogDtoReaders.invalid('product_variants', 'a list of rows');
    }
    return raw
        .map((item) {
          if (item is! Map) {
            throw CatalogDtoReaders.invalid(
              'product_variants',
              'a list of rows',
            );
          }
          final row = <String, dynamic>{};
          for (final entry in item.entries) {
            if (entry.key is! String) {
              throw CatalogDtoReaders.invalid(
                'product_variants',
                'rows with string keys',
              );
            }
            row[entry.key as String] = entry.value;
          }
          return ProductVariantDto.fromJson(row);
        })
        .toList(growable: false);
  }
}

class _CategoryData {
  const _CategoryData({required this.name, required this.isActive});

  final String name;
  final bool isActive;
}
