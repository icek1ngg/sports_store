import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../domain/models/operational_failure.dart';
import 'operational_read_access.dart';

final operationalReadAccessProvider =
    Provider.autoDispose<OperationalReadAccess>((ref) {
      final access = OperationalReadAccess(ref.watch(supabaseClientProvider));
      ref.onDispose(() => unawaited(access.dispose()));
      return access;
    });

final operationalSessionProvider =
    StreamProvider.autoDispose<OperationalSession>((ref) {
      return ref.watch(operationalReadAccessProvider).watchSession();
    });

/// Invalidates delivery and COD read epochs together, also retrying auth errors.
void refreshOperationalReads(Ref ref) =>
    ref.read(operationalReadAccessProvider).refreshSession();

/// Never forward Riverpod's previous data on reload/error across auth epochs.
AsyncValue<T> withoutPreviousOperationalData<T>(AsyncValue<T> value) {
  if (value.isLoading) return const AsyncLoading();
  if (value.hasError) {
    return AsyncError(
      mapOperationalFailure(value.error!),
      value.stackTrace ?? StackTrace.empty,
    );
  }
  return AsyncData(value.requireValue);
}

OperationalFailure? operationalSessionFailure(
  AsyncValue<OperationalSession> state,
) {
  if (state.hasError) return mapOperationalFailure(state.error!);
  final session = state.asData?.value;
  if (!state.isLoading && session?.userId == null) {
    return session?.failure ??
        const OperationalFailure(OperationalFailureCode.sessionExpired);
  }
  return session?.failure;
}
