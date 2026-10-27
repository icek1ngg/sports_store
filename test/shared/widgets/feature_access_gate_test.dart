import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/shared/widgets/async_content.dart';
import 'package:sports_store/shared/widgets/feature_access_gate.dart';

void main() {
  Future<void> show(WidgetTester tester, ProviderContainer container) =>
      tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: FeatureAccessGate(
                roles: {'manager'},
                child: Text('Private manager content'),
              ),
            ),
          ),
        ),
      );

  testWidgets('unresolved role and wrong role never build manager content', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        featureSessionScopeProvider.overrideWithValue(
          const SessionScope.unresolved(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await show(tester, container);
    expect(find.byType(LoadingState), findsOneWidget);
    expect(find.text('Private manager content'), findsNothing);
    container.updateOverrides([
      featureSessionScopeProvider.overrideWithValue(
        const SessionScope(userId: 'A', role: 'customer', generation: 1),
      ),
    ]);
    await tester.pump();
    expect(find.byType(SessionUnavailableState), findsOneWidget);
    expect(find.text('Private manager content'), findsNothing);
  });

  testWidgets(
    'another resource observing expiry removes private page content',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          featureSessionScopeProvider.overrideWithValue(
            const SessionScope(userId: 'A', role: 'manager', generation: 1),
          ),
        ],
      );
      addTearDown(container.dispose);
      await show(tester, container);
      expect(find.text('Private manager content'), findsOneWidget);
      final cache = container.read(epochCacheProvider);
      cache.begin('private/order');
      cache.blockSession();
      await tester.pump();
      expect(find.text('Private manager content'), findsNothing);
      expect(find.byType(SessionExpiredState), findsOneWidget);
    },
  );
}
