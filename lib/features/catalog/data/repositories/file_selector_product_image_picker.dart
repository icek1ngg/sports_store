import 'package:file_selector/file_selector.dart';

import '../../domain/models/managed_product.dart';
import '../../domain/models/product_image.dart';
import '../../domain/repositories/product_image_repository.dart';

class FileSelectorProductImagePicker implements ProductImagePicker {
  @override
  Future<SelectedProductImage?> pickImage() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Ảnh sản phẩm',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
            mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
            uniformTypeIdentifiers: [
              'public.png',
              'public.jpeg',
              'org.webmproject.webp',
            ],
          ),
        ],
      );
      if (file == null) return null;
      final size = await file.length();
      if (size == 0 || size > SelectedProductImage.maxBytes) {
        throw const CatalogFailure(
          'Chọn ảnh có dung lượng từ 1 byte đến 5 MB.',
        );
      }
      return SelectedProductImage.fromBytes(await file.readAsBytes());
    } on CatalogFailure {
      rethrow;
    } catch (_) {
      throw const CatalogFailure('Không thể mở ảnh đã chọn. Vui lòng thử lại.');
    }
  }
}
