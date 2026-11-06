import '../models/product_image.dart';

abstract interface class ProductImagePicker {
  /// Null means that the user closed the native picker without selecting a file.
  Future<SelectedProductImage?> pickImage();
}

abstract interface class ProductImageRepository {
  Future<UploadedProductImage> uploadImage(
    SelectedProductImage image, {
    required String requestId,
  });
}
