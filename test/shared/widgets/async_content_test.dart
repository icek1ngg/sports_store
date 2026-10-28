import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/core/state/read_snapshot.dart';
import 'package:sports_store/shared/widgets/async_content.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SizedBox(width: 320, height: 640, child: child)),
  );
}

void main() {
  testWidgets('renders initial loading without fake content', (tester) async {
    await tester.pumpWidget(
      _host(
        const AsyncContent(
          isInitialLoading: true,
          isEmpty: true,
          child: Text('private data'),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('private data'), findsNothing);
  });

  testWidgets('renders empty state and optional action', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      _host(
        AsyncContent(
          hasData: true,
          isEmpty: true,
          emptyMessage: 'Bạn chưa có đơn hàng',
          emptyActionLabel: 'Mở danh mục',
          onEmptyAction: () => pressed = true,
          child: const Text('private data'),
        ),
      ),
    );

    expect(find.text('Bạn chưa có đơn hàng'), findsOneWidget);
    await tester.tap(find.text('Mở danh mục'));
    expect(pressed, isTrue);
  });

  testWidgets('keeps data visible with a stale notice after refresh error', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const AsyncContent(
          hasData: true,
          isStale: true,
          isRefreshing: true,
          errorMessage: 'Không thể kết nối',
          child: Text('last known order'),
        ),
      ),
    );

    expect(find.text('last known order'), findsOneWidget);
    expect(find.text('Dữ liệu có thể chưa cập nhật'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('renders safe error state when no data is available', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AsyncContent(
          isEmpty: true,
          errorMessage: 'Kiểm tra mạng và thử lại.',
          onRetry: () {},
          child: const Text('private data'),
        ),
      ),
    );

    expect(find.text('Kiểm tra mạng và thử lại.'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
    expect(find.text('private data'), findsNothing);
  });

  testWidgets('maps a null loading snapshot to initial loading', (
    tester,
  ) async {
    const snapshot = ReadSnapshot<List<String>>(loading: true);
    await tester.pumpWidget(
      _host(
        AsyncContent(
          hasData: snapshot.data != null,
          isInitialLoading: snapshot.isInitialLoading,
          isEmpty: snapshot.empty,
          child: const Text('private data'),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('private data'), findsNothing);
  });

  testWidgets('maps a null failure snapshot to error state', (tester) async {
    const snapshot = ReadSnapshot<List<String>>(
      failure: AppFailure(code: AppFailure.network),
    );
    await tester.pumpWidget(
      _host(
        AsyncContent(
          hasData: snapshot.data != null,
          isInitialLoading: snapshot.isInitialLoading,
          isEmpty: snapshot.empty,
          errorMessage: 'Kiểm tra mạng và thử lại.',
          child: const Text('private data'),
        ),
      ),
    );

    expect(find.text('Kiểm tra mạng và thử lại.'), findsOneWidget);
    expect(find.text('private data'), findsNothing);
  });

  testWidgets('keeps an accepted empty snapshot distinct from no data', (
    tester,
  ) async {
    const snapshot = ReadSnapshot<List<String>>(data: <String>[], empty: true);
    await tester.pumpWidget(
      _host(
        AsyncContent(
          hasData: snapshot.data != null,
          isEmpty: snapshot.empty,
          child: const Text('private data'),
        ),
      ),
    );

    expect(find.text('Chưa có dữ liệu'), findsOneWidget);
    expect(find.text('private data'), findsNothing);
  });

  testWidgets('renders session expiry instead of an empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const AsyncContent(isSessionExpired: true, child: Text('private data')),
      ),
    );

    expect(find.byType(SessionExpiredState), findsOneWidget);
    expect(find.text('Phiên đăng nhập đã hết hạn'), findsOneWidget);
    expect(find.text('Chưa có dữ liệu'), findsNothing);
    expect(find.text('private data'), findsNothing);
  });

  testWidgets('renders unavailable session instead of an empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const AsyncContent(
          isSessionUnavailable: true,
          child: Text('private data'),
        ),
      ),
    );

    expect(find.byType(SessionUnavailableState), findsOneWidget);
    expect(find.text('Không thể truy cập dữ liệu'), findsOneWidget);
    expect(find.text('Chưa có dữ liệu'), findsNothing);
    expect(find.text('private data'), findsNothing);
  });

  testWidgets('maps normalized auth failure to expiry state', (tester) async {
    await tester.pumpWidget(
      _host(
        const AsyncContent(
          failure: AppFailure(code: AppFailure.unauthenticated),
          child: Text('private data'),
        ),
      ),
    );

    expect(find.byType(SessionExpiredState), findsOneWidget);
    expect(find.text('Phiên đăng nhập đã hết hạn'), findsOneWidget);
  });
}
