import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/auth_startup_options.dart';
import '../../core/config/load_supabase_config.dart';
import '../../features/auth/data/email_confirmation_callback.dart';
import '../../features/auth/data/oauth_sign_in_callback.dart';
import '../../features/auth/presentation/view_models/auth_providers.dart';
import '../integration/production_feature_composition.dart';
import '../router/app_router.dart';
import '../sports_store_app.dart';

/// The application has one backend and one application widget. Supabase must
/// finish initialization before any session or business repository is created.
Future<void> bootstrapSportsStore() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The SDK consumes and clears Auth URL parameters during initialization.
  final incomingUri = Uri.base;
  final confirmingEmail = EmailConfirmationCallback.isCallback(incomingUri);
  final oauthError = confirmingEmail
      ? null
      : OAuthSignInCallback.errorMessage(incomingUri);
  try {
    final config = await loadSupabaseConfig();
    await Supabase.initialize(
      url: config.url,
      publishableKey: config.publishableKey,
      authOptions: startupAuthClientOptions,
    );
    runApp(
      ProviderScope(
        overrides: [
          ...productionFeatureOverrides,
          if (oauthError != null)
            initialOAuthErrorProvider.overrideWithValue(oauthError),
          if (confirmingEmail)
            initialEmailConfirmationProvider.overrideWithValue(
              EmailConfirmationCallback.resolveAfterSdkInitialization(
                incomingUri,
                Supabase.instance.client.auth.currentSession,
              ),
            ),
        ],
        child: const FeatureSessionLifecycle(child: SportsStoreApp()),
      ),
    );
  } catch (error) {
    // Configuration values and restored access tokens never enter logs.
    debugPrint('Application startup failed: ${error.runtimeType}');
    runApp(
      ProviderScope(
        overrides: [appStartupFailureProvider.overrideWithValue(true)],
        child: const SportsStoreApp(),
      ),
    );
  }
}
