/// Presentation-only helpers used by the catalog screens.
///
/// Amounts are stored as whole VND values. Keeping formatting here avoids
/// introducing a second currency abstraction into the catalog domain model.
String formatVnd(int? amount) {
  if (amount == null) return 'Liên hệ';

  final absolute = amount.abs().toString();
  final formatted = absolute.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  final sign = amount < 0 ? '-' : '';
  return '$sign$formatted đ';
}

String formatAvailableQuantity(int quantity) {
  if (quantity <= 0) return 'Hết hàng';
  return 'Còn $quantity sản phẩm';
}

String formatVariantAttributeLabel(String key) =>
    switch (key.trim().toLowerCase()) {
      'size' => 'Kích cỡ',
      'color' || 'colour' => 'Màu sắc',
      'material' => 'Chất liệu',
      _ => key,
    };

/// Multiplies a VND unit price only while it remains within the safe integer
/// range also supported by web clients. A null result is rendered as a safe
/// unavailable estimate rather than a rounded amount.
int? safeVndTotal(int unitPriceVnd, int quantity) {
  if (unitPriceVnd < 0 || quantity < 0) return null;
  const maxSafeInteger = 9007199254740991;
  if (quantity == 0) return 0;
  if (unitPriceVnd > maxSafeInteger ~/ quantity) return null;
  return unitPriceVnd * quantity;
}
