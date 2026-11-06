import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../cod/presentation/view_models/cod_read_refresh.dart';
import '../../data/repositories/operational_providers.dart';
import '../../data/repositories/supabase_outbound_completion_repository.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../domain/repositories/outbound_completion_repository.dart';
import 'delivery_providers.dart';
import 'outbound_action_providers.dart';

final outboundCompletionRepositoryProvider =
    Provider<OutboundCompletionRepository>((ref) {
      return SupabaseOutboundCompletionRepository(
        access: ref.watch(operationalReadAccessProvider),
      );
    });

final outboundCompletionRequestIdProvider = Provider<String Function()>((ref) {
  final random = Random.secure();
  return () {
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  };
});

final outboundCompletionDetailsReloadProvider =
    Provider<Future<DeliveryTaskDetails> Function(String)>((ref) {
      return (taskId) => refetchDeliveryTaskAfterCommand(ref, taskId);
    });

final outboundCompletionTaskListReloadProvider =
    Provider<Future<void> Function()>((ref) {
      return () => ref.read(outboundTaskListReloadProvider)();
    });

final outboundCompletionCodReloadProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    refreshCodReadsAfterConfirmedWrite(ref);
  },
);
