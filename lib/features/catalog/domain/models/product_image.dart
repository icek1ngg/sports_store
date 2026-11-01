import 'dart:typed_data';

import 'managed_product.dart';

/// Technical upload limit; product images never accept executable SVG content.
class SelectedProductImage {
  SelectedProductImage._(this.bytes, this.extension, this.contentType);

  static const maxBytes = 5 * 1024 * 1024;
  final Uint8List bytes;
  final String extension;
  final String contentType;

  factory SelectedProductImage.fromBytes(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const CatalogFailure('Chọn ảnh có dung lượng từ 1 byte đến 5 MB.');
    }
    bool startsWith(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[i] == signature[i],
        ).every((matches) => matches);
    final (extension, contentType) = switch (bytes) {
      _ when startsWith([137, 80, 78, 71, 13, 10, 26, 10]) => (
        'png',
        'image/png',
      ),
      _ when startsWith([255, 216, 255]) => ('jpg', 'image/jpeg'),
      _
          when startsWith([82, 73, 70, 70]) &&
              bytes.length >= 12 &&
              bytes[8] == 87 &&
              bytes[9] == 69 &&
              bytes[10] == 66 &&
              bytes[11] == 80 =>
        ('webp', 'image/webp'),
      _ => throw const CatalogFailure('Chỉ hỗ trợ ảnh PNG, JPEG hoặc WebP.'),
    };
    return SelectedProductImage._(
      Uint8List.fromList(bytes),
      extension,
      contentType,
    );
  }
}

class UploadedProductImage {
  const UploadedProductImage({required this.path, required this.previewUrl});
  final String path;
  final String previewUrl;
}
