import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_action_footer.dart';

import 'presentation/widgets/mh09/mh09_02b_test_support.dart';

void main() {
  testWidgets(
    'preparation dispatch action is visible and gated by fresh manager scope',
    (tester) async {
      var calls = 0;
      Future<void> pump({
        bool fresh = true,
        bool busy = false,
        bool inScope = true,
      }) => pumpMh09(
        tester,
        Mh09ActionFooter(
          capabilities: mh09Capabilities(assign: true),
          isActionStateFresh: fresh,
          canActInCurrentScope: inScope,
          isBusy: busy,
          onPrepareAndAssign: () => calls++,
        ),
      );
      await pump();
      expect(find.text('Chuẩn bị xong & phân công giao'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('mh09-action-prepare-dispatch')),
      );
      expect(calls, 1);
      await pump(fresh: false);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await pump(busy: true);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await pump(inScope: false);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    },
  );
}
