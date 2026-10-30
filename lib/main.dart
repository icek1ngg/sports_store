import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/sports_store_app.dart';
import 'app/localization/app_localization.dart';
import 'core/config/load_supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final config = await loadSupabaseConfig();
    await Supabase.initialize(
      url: config.url,
      publishableKey: config.publishableKey,
    );
    runApp(const ProviderScope(child: SportsStoreApp()));
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
