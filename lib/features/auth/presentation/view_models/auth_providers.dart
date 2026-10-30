import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/state/session_scope.dart';
import '../../data/repositories/supabase_auth_repository.dart';
import '../../domain/models/app_profile.dart';
import '../../domain/repositories/auth_repository.dart';

export '../../domain/models/app_profile.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(ref.watch(supabaseClientProvider)),
);

final authSessionProvider = StreamProvider<AuthSession>((ref) {
  return ref.watch(authRepositoryProvider).watchSession();
});

final currentProfileProvider = FutureProvider<AppProfile?>(
  retry: (_, _) => null,
  (ref) async {
    final session = ref.watch(authSessionProvider);
    if (session.isLoading) return null;
    if (session.hasError) {
      throw const AuthenticationFailure('Không thể kiểm tra phiên đăng nhập.');
    }
    if (session.asData?.value.signedIn != true) return null;
    return ref.watch(authRepositoryProvider).getCurrentProfile();
  },
);

/// Bridges server-owned Auth profiles to the shared feature cache boundary.
/// Every identity/profile rebuild creates a new generation, including refreshes.
final trustedFeatureSessionProvider =
    NotifierProvider<TrustedFeatureSession, SessionScope>(
      TrustedFeatureSession.new,
    );

class TrustedFeatureSession extends Notifier<SessionScope> {
  int _generation = 0;

  @override
  SessionScope build() {
    final generation = ++_generation;
    final session = ref.watch(authSessionProvider);
    final profile = ref.watch(currentProfileProvider);
    if (session.isLoading || session.hasError) {
      return SessionScope(
        userId: null,
        role: null,
        generation: generation,
        roleResolved: false,
      );
    }
    final identity = session.asData?.value;
    if (identity?.signedIn != true) {
      return SessionScope(userId: null, role: null, generation: generation);
    }
    final value = profile.asData?.value;
    if (profile.isLoading ||
        profile.hasError ||
        value?.id != identity!.userId) {
      return SessionScope(
        userId: identity!.userId,
        role: null,
        generation: generation,
        roleResolved: false,
      );
    }
    return SessionScope(
      userId: value!.id,
      role: value.role.name,
      generation: generation,
    );
  }
}

String homeRouteForRole(AppRole role) => switch (role) {
  AppRole.customer => '/customer/products',
  AppRole.manager => '/manager/orders',
  AppRole.shipper => '/shipper/tasks',
};
