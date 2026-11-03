import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/app/localization/app_localization.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/returns/presentation/pages/return_tracking_page.dart';
import 'package:sports_store/features/returns/presentation/view_models/return_tracking_view_model.dart';

import 'mh14_preview_data.dart';

/// Debug-only MH14 preview (390 × 884, DEMO data, no Auth/Supabase).
/// The scenario picker sits outside the phone frame and is not part of the
/// customer UI.
void main() {
  if (!kDebugMode) {
    throw UnsupportedError('UI preview chỉ được chạy trong debug mode.');
  }
  runApp(const Mh14PreviewApp());
}

class Mh14PreviewApp extends StatefulWidget {
  const Mh14PreviewApp({super.key});

  static const frame = Size(390, 884);

  @override
  State<Mh14PreviewApp> createState() => _Mh14PreviewAppState();
}

class _Mh14PreviewAppState extends State<Mh14PreviewApp> {
  Mh14Scenario _scenario = Mh14Scenario.values.firstWhere(
    (s) =>
        s.name ==
        (Uri.base.queryParameters['scenario'] ??
            const String.fromEnvironment('MH14_SCENARIO')),
    orElse: () => Mh14Scenario.awaitingPickupAssigned,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MH14 — UI Preview (DEMO)',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: AppLocalization.locale,
      supportedLocales: AppLocalization.supportedLocales,
      localizationsDelegates: AppLocalization.delegates,
      home: Builder(
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xffdadadc),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ScenarioPicker(
                    value: _scenario,
                    onChanged: (value) => setState(() => _scenario = value),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: Mh14PreviewApp.frame.width,
                    height: Mh14PreviewApp.frame.height,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(color: Color(0x33000000), blurRadius: 24),
                      ],
                    ),
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        size: Mh14PreviewApp.frame,
                        padding: EdgeInsets.zero,
                        viewPadding: EdgeInsets.zero,
                      ),
                      // A fresh scope per scenario: no state leaks between
                      // demo cases.
                      child: ProviderScope(
                        key: ValueKey(_scenario),
                        overrides: [
                          returnTrackingRepositoryProvider.overrideWith(
                            (ref) => Mh14DemoTrackingRepository(_scenario),
                          ),
                        ],
                        child: _ScenarioPage(scenario: _scenario),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScenarioPage extends ConsumerStatefulWidget {
  const _ScenarioPage({required this.scenario});

  final Mh14Scenario scenario;

  @override
  ConsumerState<_ScenarioPage> createState() => _ScenarioPageState();
}

class _ScenarioPageState extends ConsumerState<_ScenarioPage> {
  @override
  void initState() {
    super.initState();
    if (widget.scenario == Mh14Scenario.staleAfterError) {
      // Demo: first load succeeds, the automatic refresh then fails.
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted) {
          ref.read(returnTrackingProvider(mh14DemoReturnId).notifier).refresh();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ReturnTrackingPage(
      returnId: mh14DemoReturnId,
      onBack: () {},
      onCall: (phone) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('DEMO: mở trình gọi điện tới $phone')),
      ),
    );
  }
}

class _ScenarioPicker extends StatelessWidget {
  const _ScenarioPicker({required this.value, required this.onChanged});

  final Mh14Scenario value;
  final ValueChanged<Mh14Scenario> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: Mh14PreviewApp.frame.width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Mh14Scenario>(
          key: const ValueKey('mh14-scenario'),
          isExpanded: true,
          value: value,
          items: [
            for (final s in Mh14Scenario.values)
              DropdownMenuItem(value: s, child: Text('DEMO · ${s.label}')),
          ],
          onChanged: (s) => s == null ? null : onChanged(s),
        ),
      ),
    );
  }
}
