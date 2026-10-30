import '../../domain/models/delivery_task_item.dart';
import 'dto_readers.dart';

/// DTO for one row from `read_my_delivery_task_items`.
class DeliveryTaskItemDto {
  const DeliveryTaskItemDto({
    required this.itemId,
    required this.itemSource,
    required this.productName,
    this.variantLabel,
    this.attributes,
    required this.quantity,
    this.quantityCollected,
    this.unitPriceVnd,
    this.lineTotalVnd,
    this.imageUrl,
    this.allowReturnMetadata = false,
  });

  factory DeliveryTaskItemDto.fromJson(
    Map<String, dynamic> json, {
    bool allowReturnMetadata = false,
  }) {
    return DeliveryTaskItemDto(
      allowReturnMetadata: allowReturnMetadata,
      itemId: DeliveryDtoReaders.readRequiredUuid(json, 'item_id'),
      itemSource: DeliveryItemSource.fromValue(
        DeliveryDtoReaders.readRequiredString(
          json,
          'item_source',
          nonBlank: false,
        ),
      ),
      productName: DeliveryDtoReaders.readRequiredString(json, 'product_name'),
      imageUrl: _httpsImageUrl(json['image_url']),
      variantLabel: DeliveryDtoReaders.readNullableString(
        json,
        'variant_label',
      ),
      attributes: DeliveryDtoReaders.readNullableJsonObject(json, 'attributes'),
      quantity: DeliveryDtoReaders.readRequiredInteger(json, 'quantity'),
      quantityCollected: DeliveryDtoReaders.readNullableInteger(
        json,
        'quantity_collected',
      ),
      unitPriceVnd: DeliveryDtoReaders.readNullableInteger(
        json,
        'unit_price_vnd',
      ),
      lineTotalVnd: DeliveryDtoReaders.readNullableInteger(
        json,
        'line_total_vnd',
      ),
    );
  }

  final String itemId;
  final DeliveryItemSource itemSource;
  final String productName;
  final String? variantLabel;
  final Map<String, dynamic>? attributes;
  final int quantity;
  final int? quantityCollected;
  final int? unitPriceVnd;
  final int? lineTotalVnd;
  final String? imageUrl;
  final bool allowReturnMetadata;

  DeliveryTaskItem toDomain() {
    _validate();
    return DeliveryTaskItem(
      itemId: itemId,
      itemSource: itemSource,
      productName: productName,
      variantLabel: variantLabel,
      attributes: attributes,
      quantity: quantity,
      quantityCollected: quantityCollected,
      unitPriceVnd: unitPriceVnd,
      lineTotalVnd: lineTotalVnd,
      imageUrl: imageUrl,
    );
  }

  static String? _httpsImageUrl(Object? value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    return uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? value
        : null;
  }

  void _validate() {
    DeliveryDtoReaders.checkUuid(itemId, 'item_id');
    if (quantity <= 0 || quantity > 9007199254740991) {
      throw DeliveryDtoReaders.invalid(
        'quantity',
        'a positive integer within the JavaScript safe range',
      );
    }
    if (quantityCollected != null &&
        (quantityCollected! < 0 ||
            quantityCollected! > 9007199254740991 ||
            quantityCollected! > quantity)) {
      throw DeliveryDtoReaders.invalid(
        'quantity_collected',
        'a non-negative integer no greater than quantity',
      );
    }
    _validateMoney(unitPriceVnd, 'unit_price_vnd');
    _validateMoney(lineTotalVnd, 'line_total_vnd');
    if (productName.trim().isEmpty) {
      throw DeliveryDtoReaders.invalid('product_name', 'a non-blank string');
    }
    if (variantLabel != null && variantLabel!.trim().isEmpty) {
      throw DeliveryDtoReaders.invalid(
        'variant_label',
        'null or a non-blank string',
      );
    }

    switch (itemSource) {
      case DeliveryItemSource.orderSnapshot:
        if (quantityCollected != null ||
            unitPriceVnd == null ||
            lineTotalVnd == null) {
          throw DeliveryDtoReaders.invalid(
            'item_source',
            'order snapshot fields (prices required, collection null)',
          );
        }
        _validateLineTotal();
      case DeliveryItemSource.returnPlan:
        if (quantityCollected == null ||
            unitPriceVnd != null ||
            lineTotalVnd != null ||
            (!allowReturnMetadata &&
                (variantLabel != null || attributes != null))) {
          throw DeliveryDtoReaders.invalid(
            'item_source',
            'return plan fields (collection required, prices/metadata absent)',
          );
        }
      case DeliveryItemSource.unavailableRedeliveryPlan:
      case DeliveryItemSource.unavailable:
        throw DeliveryDtoReaders.invalid(
          'item_source',
          'an available item source for an item row',
        );
    }
  }

  static void _validateMoney(int? value, String key) {
    if (value != null && (value < 0 || value > 9007199254740991)) {
      throw DeliveryDtoReaders.invalid(
        key,
        'a non-negative integer within the JavaScript safe range',
      );
    }
  }

  void _validateLineTotal() {
    final expected = BigInt.from(unitPriceVnd!) * BigInt.from(quantity);
    final actual = BigInt.from(lineTotalVnd!);
    if (actual != expected) {
      throw DeliveryDtoReaders.invalid(
        'line_total_vnd',
        'unit_price_vnd multiplied by quantity',
      );
    }
  }
}
