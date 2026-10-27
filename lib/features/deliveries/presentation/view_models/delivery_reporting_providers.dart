import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/operational_providers.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../data/repositories/supabase_delivery_reporting_repository.dart';
import '../../domain/models/delivery_reporting.dart';
import '../../domain/repositories/delivery_reporting_repository.dart';
import 'delivery_providers.dart';
import 'outbound_action_providers.dart';

/// The production reporting adapter used by MH11.
///
/// The repository owns the reporting-context RPC and the two P07.4 write
/// RPCs.  The presentation layer never reads reporting tables or calls
/// Supabase directly.
final deliveryReportingRepositoryProvider =
    Provider.autoDispose<DeliveryReportingRepository>((ref) {
      return SupabaseDeliveryReportingRepository(
        access: ref.watch(operationalReadAccessProvider),
      );
    });

/// Request IDs are generated once per submitted command.  A ViewModel keeps
/// the generated ID in its pending command, so an uncertain retry never asks
/// this provider for a replacement key.
final deliveryReportingRequestIdProvider = Provider<String Function()>(
  (ref) => ref.watch(outboundTaskRequestIdProvider),
);

final deliveryReportingContextReloadProvider =
    Provider<Future<ReportingContext> Function(String)>((ref) {
      return (taskId) =>
          ref.read(deliveryReportingRepositoryProvider).getContext(taskId);
    });

/// Refreshes the normal MH11 detail projection after a committed report.
///
/// A reporting context is deliberately independent of the detail scope, so a
/// restricted failed/cancelled task can still report when the server allows
/// it.  This refresh is reconciliation only; it is never used to decide
/// whether a report was committed.
final deliveryReportingDetailsReloadProvider =
    Provider<Future<DeliveryTaskDetails> Function(String)>((ref) {
      return (taskId) => refetchDeliveryTaskAfterCommand(ref, taskId);
    });

/// Refreshes MH10 after a report.  The list provider remains the shared source
/// of truth and can be overridden by production/widget tests.
final deliveryReportingTaskListReloadProvider =
    Provider<Future<void> Function()>((ref) {
      return ref.watch(outboundTaskListReloadProvider);
    });

/// Short aliases for code that uses the feature-qualified vocabulary.
final reportingRepositoryProvider = deliveryReportingRepositoryProvider;
final reportingRequestIdProvider = deliveryReportingRequestIdProvider;
