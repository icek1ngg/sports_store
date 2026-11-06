import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/config/supabase_config.dart';
import 'package:sports_store/main.dart' show StartupFailureApp;

import 'session_page.dart';

/// Developer entry point using the real backend, shared router and client.
/// No embedded accounts, fake products or persisted test login credentials.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final config = SupabaseConfig.fromEnvironment();
    config.validate();
    await Supabase.initialize(
      url: config.url,
      publishableKey: config.publishableKey,
      authOptions: const FlutterAuthClientOptions(persistSession: false),
    );
    runApp(
      ProviderScope(
        overrides: [
          landingPageBuilderProvider.overrideWithValue(
            (context) => const CatalogLiveSessionPage(),
          ),
        ],
        child: const SportsStoreApp(),
      ),
    );
  } catch (_) {
    runApp(const StartupFailureApp());
  }
}
