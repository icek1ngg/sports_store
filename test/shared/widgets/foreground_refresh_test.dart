import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/shared/widgets/foreground_refresh.dart';

void main() {
  testWidgets('a covered route stops polling and refreshes on return', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    var reads = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: ForegroundRefresh(
          onRefresh: () => reads++,
          canRefresh: () => true,
          child: const Text('Content'),
        ),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other page')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(reads, 0);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(reads, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'polls every 3s, refuses busy reads, pauses background and resumes',
    (tester) async {
      var reads = 0;
      var busy = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ForegroundRefresh(
            onRefresh: () => reads++,
            canRefresh: () => !busy,
            child: const Text('Content'),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(reads, 1);
      busy = true;
      await tester.pump(const Duration(seconds: 3));
      expect(reads, 1);
      busy = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 3));
      expect(reads, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(reads, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      expect(reads, 2);
    },
  );
}
