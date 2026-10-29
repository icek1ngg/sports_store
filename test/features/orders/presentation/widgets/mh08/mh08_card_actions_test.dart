import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_card_actions.dart';

import 'mh08_test_support.dart';

void main() {
  testWidgets('enabled decisions forward only their respective callback', (
    tester,
  ) async {
    var confirms = 0;
    var rejects = 0;
    await pumpMh08(
      tester,
      Mh08CardActions(
        canConfirm: true,
        canReject: true,
        isFresh: true,
        onConfirm: () => confirms++,
        onReject: () => rejects++,
      ),
    );
    await tester.tap(find.text('Từ chối'));
    expect(rejects, 1);
    expect(confirms, 0);
    await tester.tap(find.text('Xác nhận'));
    expect(confirms, 1);
    expect(rejects, 1);
  });

  for (final gate in [
    'eligibility',
    'freshness',
    'enabled',
    'busy',
    'callback',
  ]) {
    testWidgets('$gate disables actions and never dispatches callbacks', (
      tester,
    ) async {
      var calls = 0;
      await pumpMh08(
        tester,
        Mh08CardActions(
          canConfirm: gate != 'eligibility',
          canReject: gate != 'eligibility',
          isFresh: gate != 'freshness',
          enabled: gate != 'enabled',
          isBusy: gate == 'busy',
          onConfirm: gate == 'callback' ? null : () => calls++,
          onReject: gate == 'callback' ? null : () => calls++,
        ),
      );
      for (final key in ['mh08-confirm', 'mh08-reject']) {
        final finder = find.byKey(ValueKey(key));
        expect(tester.widget<FilledButton>(finder).onPressed, isNull);
        await tester.tap(finder);
      }
      expect(calls, 0);
    });
  }

  testWidgets('confirm and reject eligibility stay independent', (
    tester,
  ) async {
    var calls = 0;
    await pumpMh08(
      tester,
      Mh08CardActions(
        canConfirm: false,
        canReject: true,
        isFresh: true,
        onConfirm: () => calls++,
        onReject: () => calls++,
      ),
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('mh08-confirm')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Từ chối'));
    expect(calls, 1);
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('decision targets fit width$width scale$scale', (
        tester,
      ) async {
        await pumpMh08(
          tester,
          Mh08CardActions(
            canConfirm: true,
            canReject: true,
            isFresh: true,
            onConfirm: () {},
            onReject: () {},
          ),
          width: width,
          scale: scale,
        );
        for (final key in ['mh08-confirm', 'mh08-reject']) {
          final size = tester.getSize(find.byKey(ValueKey(key)));
          expect(size.height, greaterThanOrEqualTo(48));
          expect(size.width, greaterThanOrEqualTo(48));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('unwired action communicates integration unavailable', (
    tester,
  ) async {
    await pumpMh08(
      tester,
      const Mh08CardActions(canConfirm: true, canReject: true, isFresh: true),
    );
    expect(find.byTooltip('Thao tác hiện chưa khả dụng'), findsNWidgets(2));
    final confirmStyle = tester
        .widget<FilledButton>(find.byKey(const ValueKey('mh08-confirm')))
        .style!;
    expect(confirmStyle.minimumSize!.resolve({}), const Size(48, 48));
  });

  testWidgets(
    'busy state is visible without long press and blocks both actions',
    (tester) async {
      var calls = 0;
      await pumpMh08(
        tester,
        Mh08CardActions(
          canConfirm: true,
          canReject: true,
          isFresh: true,
          isBusy: true,
          onConfirm: () => calls++,
          onReject: () => calls++,
        ),
      );
      expect(find.text('Đang xử lý đơn hàng'), findsOneWidget);
      for (final label in ['Xác nhận', 'Từ chối']) {
        await tester.tap(find.text(label));
      }
      expect(calls, 0);
    },
  );
}
