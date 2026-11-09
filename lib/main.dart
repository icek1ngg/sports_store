import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/sports_store_app.dart';
import 'app/integration/production_feature_composition.dart';
import 'app/localization/app_localization.dart';
import 'core/config/auth_startup_options.dart';
import 'core/config/load_supabase_config.dart';
import 'features/auth/presentation/view_models/auth_providers.dart';
import 'features/auth/data/email_confirmation_callback.dart';
import 'features/auth/data/oauth_sign_in_callback.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The SDK consumes and clears auth URL parameters during initialize().
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
    // Avoid logging configuration values or restored session tokens.
    debugPrint('Application startup failed: ${error.runtimeType}');
    runApp(const StartupFailureApp());
  }
}

class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Sports Store',
      locale: AppLocalization.locale,
      supportedLocales: AppLocalization.supportedLocales,
      localizationsDelegates: AppLocalization.delegates,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Text('Không thể khởi động ứng dụng. Vui lòng thử lại.'),
        ),
      ),
    );
  }
}
