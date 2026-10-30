import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/catalog/domain/models/managed_product.dart';
import 'package:sports_store/features/catalog/domain/models/product_image.dart';
import 'package:sports_store/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sports_store/features/catalog/domain/repositories/product_image_repository.dart';
import 'package:sports_store/features/catalog/presentation/view_models/product_management_view_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/operational_supabase_fixture.dart';

class _Catalog implements CatalogRepository {
  @override
  Future<CatalogSnapshot> loadManagement() async =>
      const CatalogSnapshot(categories: [], products: []);
  @override
  Future<String> saveProduct(
    ManagedProduct product, {
    required String requestId,
  }) => throw UnimplementedError();
}

class _Picker implements ProductImagePicker {
  Future<SelectedProductImage?> Function() select = () async => null;
  @override
  Future<SelectedProductImage?> pickImage() => select();
}

class _Uploads implements ProductImageRepository {
  int calls = 0;
  @override
  Future<UploadedProductImage> uploadImage(
    SelectedProductImage image, {
    required String requestId,
  }) async {
    calls++;
    return const UploadedProductImage(
      path: 'uploaded.png',
      previewUrl: 'https://preview.invalid/uploaded.png',
    );
  }
}

void main() {
  late SupabaseClient client;
  late ProviderContainer container;
  late _Picker picker;
  late _Uploads uploads;
  setUp(() async {
    client = await fixtureClient((request) async => jsonResponse(request, {}));
    picker = _Picker();
    uploads = _Uploads();
    container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        catalogRepositoryProvider.overrideWithValue(_Catalog()),
        productImagePickerProvider.overrideWithValue(picker),
        productImageRepositoryProvider.overrideWithValue(uploads),
      ],
    );
    container.listen(productManagementViewModelProvider, (_, _) {});
    await container.read(productManagementViewModelProvider.future);
    // Allow the identity stream's initial event to settle before the user opens
    // the editor, matching the visible catalog page.
    await Future<void>.delayed(Duration.zero);
    await container.read(productManagementViewModelProvider.future);
  });
  tearDown(() async {
    container.dispose();
    await client.dispose();
  });

  test(
    'closing the native picker leaves image and storage untouched',
    () async {
      expect(
        await container
            .read(productManagementViewModelProvider.notifier)
            .pickAndUploadImage(),
        isNull,
      );
      expect(uploads.calls, 0);
    },
  );

  test(
    'selecting image uploads via injected repository without reloading catalog',
    () async {
      picker.select = () async =>
          SelectedProductImage.fromBytes(Uint8List.fromList([255, 216, 255]));
      final result = await container
          .read(productManagementViewModelProvider.notifier)
          .pickAndUploadImage();
      expect(result!.path, 'uploaded.png');
      expect(uploads.calls, 1);
      expect(
        container.read(productManagementViewModelProvider).hasValue,
        isTrue,
      );
    },
  );

  test(
    'account switch while picker is open cannot upload old account selection',
    () async {
      final selection = Completer<SelectedProductImage?>();
      picker.select = () => selection.future;
      final pending = container
          .read(productManagementViewModelProvider.notifier)
          .pickAndUploadImage();
      final checked = expectLater(pending, throwsA(isA<CatalogFailure>()));
      await recoverFixtureSession(client, shipperB);
      selection.complete(
        SelectedProductImage.fromBytes(Uint8List.fromList([255, 216, 255])),
      );
      await checked;
      expect(uploads.calls, 0);
    },
  );
}
