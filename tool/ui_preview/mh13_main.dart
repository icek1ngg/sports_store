import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/app/localization/app_localization.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/returns/domain/models/return_reason.dart';
import 'package:sports_store/features/returns/presentation/pages/create_return_page.dart';
import 'package:sports_store/features/returns/presentation/pages/return_request_details_page.dart';
import 'package:sports_store/features/returns/presentation/view_models/return_request_flow_view_model.dart';
import 'package:sports_store/features/returns/presentation/view_models/return_request_providers.dart';

import 'mh13_preview_data.dart';

/// Debug-only MH13 preview (390 × 884, DEMO data, no Auth/Supabase).
///
/// Mirrors [ReturnRequestFlowPage] (step 1 → push step 2, shared draft) but
/// uses the approved mock-up order and a DEMO repository so the layout can be
/// compared without logging in. The real file picker is used for the video.
void main() {
  if (!kDebugMode) {
    throw UnsupportedError('UI preview chỉ được chạy trong debug mode.');
  }
  runApp(
    ProviderScope(
      overrides: [
        returnRequestRepositoryProvider.overrideWith(
          (ref) => Mh13DemoReturnRepository(),
        ),
      ],
      child: const Mh13PreviewApp(),
    ),
  );
}

class Mh13PreviewApp extends StatelessWidget {
  const Mh13PreviewApp({super.key});

  static const frame = Size(390, 884);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MH13 — UI Preview (DEMO)',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: AppLocalization.locale,
      supportedLocales: AppLocalization.supportedLocales,
      localizationsDelegates: AppLocalization.delegates,
      home: Scaffold(
        backgroundColor: const Color(0xffdadadc),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: frame.width,
              height: frame.height,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Color(0x33000000), blurRadius: 24),
                ],
              ),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: frame,
                  padding: EdgeInsets.zero,
                  viewPadding: EdgeInsets.zero,
                ),
                // A nested navigator keeps step 2 inside the phone frame.
                child: Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => const _Mh13PreviewFlow(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Mh13PreviewFlow extends ConsumerWidget {
  const _Mh13PreviewFlow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = mh13DemoOrder;
    final flow = ref.watch(returnRequestFlowProvider(order.orderId));
    void restart() {
      Navigator.of(context).popUntil((route) => route.isFirst);
      ref.invalidate(returnRequestFlowProvider(order.orderId));
    }

    return CreateReturnPage(
      order: order,
      // Same pre-selected reason as the approved mock-up.
      initialReason: flow.draft.reason ?? ReturnReason.defective,
      onBack: () {},
      onContinue: (reason) {
        ref
            .read(returnRequestFlowProvider(order.orderId).notifier)
            .setReason(reason);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReturnRequestDetailsPage(
              orderId: order.orderId,
              totalPaidVnd: order.totalPaidVnd,
              onOpenReturn: (_) => restart(),
            ),
          ),
        );
      },
    );
  }
}
