import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../deliveries/data/repositories/operational_read_access.dart';
import '../../data/repositories/file_selector_return_video_picker.dart';
import '../../data/repositories/supabase_return_request_repository.dart';
import '../../domain/models/return_request_context.dart';
import '../../domain/repositories/return_request_repository.dart';
import '../../domain/repositories/return_video_picker.dart';

/// Returns use their own access epoch with a longer timeout: a video upload
/// can legitimately take longer than the 20 s operational read budget.
final returnRequestRepositoryProvider =
    Provider.autoDispose<ReturnRequestRepository>((ref) {
      final access = OperationalReadAccess(
        ref.watch(supabaseClientProvider),
        readTimeout: const Duration(minutes: 5),
      );
      ref.onDispose(() => unawaited(access.dispose()));
      return SupabaseReturnRequestRepository(access: access);
    });

final returnVideoPickerProvider = Provider<ReturnVideoPicker>(
  (ref) => const FileSelectorReturnVideoPicker(),
);

final returnRequestContextProvider = FutureProvider.autoDispose
    .family<ReturnRequestContext, String>(
      (ref, orderId) =>
          ref.watch(returnRequestRepositoryProvider).loadContext(orderId),
      retry: (count, error) => null,
    );
