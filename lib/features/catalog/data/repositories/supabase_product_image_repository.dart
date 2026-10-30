import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/managed_product.dart';
import '../../domain/models/product_image.dart';
import '../../domain/repositories/product_image_repository.dart';

class SupabaseProductImageRepository implements ProductImageRepository {
  SupabaseProductImageRepository(this.client);
  final SupabaseClient client;

  @override
  Future<UploadedProductImage> uploadImage(
    SelectedProductImage image, {
    required String requestId,
  }) async {
    final session = client.auth.currentSession;
    if (session == null || session.isExpired) {
      throw const CatalogFailure('Vui lòng đăng nhập lại để tải ảnh.');
    }
    void checkSession() {
      if (client.auth.currentSession?.accessToken != session.accessToken ||
          client.auth.currentUser?.id != session.user.id) {
        throw const CatalogFailure(
          'Tài khoản đã thay đổi. Vui lòng mở lại biểu mẫu.',
        );
      }
    }

    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(requestId)) {
      throw const CatalogFailure('Mã tải ảnh không hợp lệ. Vui lòng thử lại.');
    }
    // Validate again at the repository boundary; ignore the original file name.
    final validated = SelectedProductImage.fromBytes(image.bytes);
    try {
      final profile = await client
          .from('profiles')
          .select('role')
          .eq('id', session.user.id)
          .single()
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .retry(enabled: false, requestTimeout: const Duration(seconds: 15));
      checkSession();
      if (profile['role'] != 'manager') {
        throw const CatalogFailure('Chỉ quản lý được tải ảnh sản phẩm.');
      }
      final path = '${session.user.id}/$requestId.${validated.extension}';
      // A bucket handle copies headers, so account changes cannot change the
      // identity of this in-flight upload or the subsequent signing request.
      final bucket = client.storage.from('product-images')
        ..setHeader('Authorization', 'Bearer ${session.accessToken}');
      final storedKey = await bucket
          .uploadBinary(
            path,
            validated.bytes,
            fileOptions: FileOptions(
              contentType: validated.contentType,
              upsert: false,
            ),
            retryAttempts: 0,
          )
          .timeout(const Duration(seconds: 30));
      checkSession();
      if (storedKey != 'product-images/$path') {
        throw const CatalogFailure('Máy chủ chưa xác nhận đúng ảnh đã tải.');
      }
      final url = await bucket
          .createSignedUrl(path, 3600)
          .timeout(const Duration(seconds: 15));
      checkSession();
      return UploadedProductImage(path: path, previewUrl: url);
    } on CatalogFailure {
      rethrow;
    } on StorageException catch (error) {
      if (error.statusCode == '403' || error.statusCode == '401') {
        throw const CatalogFailure('Bạn không có quyền tải ảnh sản phẩm.');
      }
      throw const CatalogFailure('Không thể tải ảnh lên. Vui lòng thử lại.');
    } catch (_) {
      throw const CatalogFailure('Không thể tải ảnh lên. Vui lòng thử lại.');
    }
  }
}
