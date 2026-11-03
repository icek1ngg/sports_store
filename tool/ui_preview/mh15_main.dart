import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/app/localization/app_localization.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/returns/presentation/pages/manager_return_detail_page.dart';
import 'package:sports_store/features/returns/presentation/pages/manager_returns_page.dart';
import 'package:sports_store/features/returns/presentation/view_models/manager_return_view_models.dart';

import 'mh15_preview_data.dart';

/// Debug-only preview of "Quản lý yêu cầu trả hàng" (390 × 884, DEMO data,
/// no Auth/Supabase). List → detail → approve/reject are clickable; the
/// in-memory DEMO repository applies the change.
void main() {
  if (!kDebugMode) {
    throw UnsupportedError('UI preview chỉ được chạy trong debug mode.');
  }
  runApp(const Mh15PreviewApp());
}

class Mh15PreviewApp extends StatefulWidget {
  const Mh15PreviewApp({super.key});

  static const frame = Size(390, 884);

  @override
  State<Mh15PreviewApp> createState() => _Mh15PreviewAppState();
}

class _Mh15PreviewAppState extends State<Mh15PreviewApp> {
  bool _offline = false;
  int _generation = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quản lý yêu cầu trả hàng — Preview (DEMO)',
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
                  Container(
                    width: Mh15PreviewApp.frame.width,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Expanded(child: Text('DEMO · dữ liệu giả lập')),
                        const Text('Mất mạng'),
                        Switch(
                          value: _offline,
                          onChanged: (v) => setState(() {
                            _offline = v;
                            _generation++;
                          }),
                        ),
                        IconButton(
                          tooltip: 'Đặt lại dữ liệu DEMO',
                          onPressed: () => setState(() => _generation++),
                          icon: const Icon(Icons.restart_alt),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: Mh15PreviewApp.frame.width,
                    height: Mh15PreviewApp.frame.height,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(color: Color(0x33000000), blurRadius: 24),
                      ],
                    ),
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        size: Mh15PreviewApp.frame,
                        padding: EdgeInsets.zero,
                        viewPadding: EdgeInsets.zero,
                      ),
                      child: ProviderScope(
                        key: ValueKey(_generation),
                        overrides: [
                          managerReturnRepositoryProvider.overrideWithValue(
                            Mh15DemoRepository(failLoads: _offline),
                          ),
                        ],
                        child: const _PreviewNavigator(),
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

/// List and detail in one phone frame, like the app route pair
/// /manager/returns → /manager/returns/:id.
class _PreviewNavigator extends StatelessWidget {
  const _PreviewNavigator();

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (context) => ManagerReturnsPage(
          onOpen: (id) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => ManagerReturnDetailPage(
                returnId: id,
                onBack: () => Navigator.of(context).pop(),
                openUrl: (url) async => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('DEMO: mở video $url'))),
                onCall: (phone) => ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('DEMO: gọi $phone'))),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
