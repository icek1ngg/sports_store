import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/state/session_scope.dart';
import '../../data/repositories/supabase_auth_repository.dart';
import '../../data/email_confirmation_callback.dart';
import '../../domain/models/app_profile.dart';
import '../../domain/models/email_confirmation_result.dart';
import '../../domain/repositories/auth_repository.dart';
import 'trusted_feature_session.dart';

export '../../domain/models/app_profile.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(
    ref.watch(supabaseClientProvider),
    emailRedirectTo: kIsWeb
        ? Uri.base.resolve(EmailConfirmationCallback.path).toString()
        : null,
  ),
);

/// Result of the SDK's initial web callback exchange; contains no URL tokens.
final initialEmailConfirmationProvider = Provider<EmailConfirmationResult?>(
  (ref) => null,
);

/// Safe startup notice for a failed OAuth redirect, never raw URL diagnostics.
final initialOAuthErrorProvider = Provider<String?>((ref) => null);

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

String homeRouteForRole(AppRole role) => switch (role) {
  AppRole.customer => '/customer/home',
  AppRole.manager => '/manager/orders',
  AppRole.shipper => '/shipper/tasks',
};
