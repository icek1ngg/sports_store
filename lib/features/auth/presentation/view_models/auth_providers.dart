import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
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
