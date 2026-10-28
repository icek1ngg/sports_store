import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';

import '../../tool/ui_preview/mh08_manager_data.dart';
import '../../tool/ui_preview/mh09_preview_fixtures.dart';
import '../../tool/ui_preview/mh09_preview_scenario.dart';

void main() {
  final records = buildMh08ManagerRecords();

  test(
    'canonical detail and summary keep all ten MH08 snapshots identical',
    () {
      expect(records, hasLength(10));
      for (final record in records) {
        final details = record.details;
        final summary = record.summary;
        expect(
          identical(
            Mh09PreviewFixtures.detail(details, Mh09PreviewScenario.canonical),
            details,
          ),
          isTrue,
        );
        expect(
          identical(Mh09PreviewFixtures.summary(summary, details), summary),
          isTrue,
        );
      }
    },
  );

  test(
    'large detail partitions the original subtotal into forty snapshots',
    () {
      final record = records[8];
      final base = record.details;
      final large = Mh09PreviewFixtures.detail(base, Mh09PreviewScenario.large);
      final summary = Mh09PreviewFixtures.summary(record.summary, large);

      expect(identical(large.order, base.order), isTrue);
      expect(large.items, hasLength(40));
      expect(large.items.every((item) => item.quantity == 1), isTrue);
      expect(
        large.items.every((item) => item.lineTotalVnd == item.unitPriceVnd),
        isTrue,
      );
      expect(
        large.items.fold<int>(0, (sum, item) => sum + item.lineTotalVnd),
        base.order.subtotalVnd,
      );
      expect(large.items.map((item) => item.id).toSet(), hasLength(40));
      expect(large.items.map((item) => item.productId).toSet(), hasLength(40));
      expect(large.items.map((item) => item.variantId).toSet(), hasLength(40));
      expect(
        large.items.every((item) => item.orderId == base.order.id),
        isTrue,
      );
      expect(large.items.every((item) => item.productName.length > 30), isTrue);
      expect(summary.itemPreview, hasLength(2));
      expect(summary.itemPreview, orderedEquals(large.items.take(2)));
      expect(summary.itemLineCount, 40);
      expect(summary.itemQuantityTotal, 40);
      expect(summary.capabilities.toMap(), large.capabilities.toMap());
    },
  );

  test('normal delivered fixture adds a collected COD return event', () {
    final record = records[4];
    final base = record.details;
    expect(base.order.status, OrderStatus.delivered);
    expect(base.codSummary?.status, CodStatus.collected);

    final details = Mh09PreviewFixtures.detail(
      base,
      Mh09PreviewScenario.normal,
    );
    final summary = Mh09PreviewFixtures.summary(record.summary, details);
    final returned = details.returnSummaries.single;
    final event = details.timeline.singleWhere(
      (entry) => entry.eventKind == 'return_submitted',
    );

    expect(returned.status, ReturnRequestStatus.pendingReview);
    expect(returned.orderId, base.order.id);
    expect(event.source, TimelineSource.actualEvent);
    expect(event.sourceEntityType, TimelineEntityType.returnRequest);
    expect(event.sourceEntityId, returned.returnId);
    expect(event.eventId, isNotNull);
    expect(event.occurredAt.isAfter(base.order.deliveredAt!), isTrue);
    expect(
      details.timeline.every(
        (entry) => !entry.occurredAt.isAfter(details.asOf),
      ),
      isTrue,
    );
    expect(!returned.submittedAt.isAfter(details.asOf), isTrue);
    expect(
      details.timeline.any((entry) => entry.eventKind == 'refund_recorded'),
      isFalse,
    );
    expect(summary.returnSummary?.returnId, returned.returnId);
    expect(summary.returnSummary?.status, ReturnRequestStatus.pendingReview);
    expect(summary.codSummary?.status, CodStatus.collected);
    expect(summary.capabilities.toMap(), details.capabilities.toMap());
  });

  test(
    'missing projections are independent and empty returns are explicit',
    () {
      final base = records[4].details;
      final withoutDelivery = Mh09PreviewFixtures.detail(
        base,
        Mh09PreviewScenario.missingDelivery,
      );
      final withoutCod = Mh09PreviewFixtures.detail(
        base,
        Mh09PreviewScenario.missingCod,
      );
      final withoutBuyer = Mh09PreviewFixtures.detail(
        base,
        Mh09PreviewScenario.missingBuyer,
      );
      final emptyReturns = Mh09PreviewFixtures.detail(
        base,
        Mh09PreviewScenario.emptyReturns,
      );

      expect(withoutDelivery.deliverySummary, isNull);
      expect(identical(withoutDelivery.codSummary, base.codSummary), isTrue);
      expect(identical(withoutDelivery.buyer, base.buyer), isTrue);
      expect(withoutCod.codSummary, isNull);
      expect(
        identical(withoutCod.deliverySummary, base.deliverySummary),
        isTrue,
      );
      expect(identical(withoutCod.buyer, base.buyer), isTrue);
      expect(withoutBuyer.buyer, isNull);
      expect(
        identical(withoutBuyer.deliverySummary, base.deliverySummary),
        isTrue,
      );
      expect(identical(withoutBuyer.codSummary, base.codSummary), isTrue);
      expect(emptyReturns.returnSummaries, isEmpty);
    },
  );

  test('capability scenes expose only the valid operation family', () {
    final pending = records.first.details;
    final confirm = Mh09PreviewFixtures.detail(
      pending,
      Mh09PreviewScenario.confirmOnly,
    ).capabilities;
    final reject = Mh09PreviewFixtures.detail(
      pending,
      Mh09PreviewScenario.rejectOnly,
    ).capabilities;
    expect(confirm.canConfirm, isTrue);
    expect(confirm.canReject, isFalse);
    expect(reject.canConfirm, isFalse);
    expect(reject.canReject, isTrue);

    final preparing = records[2].details;
    final exceptional = Mh09PreviewFixtures.detail(
      preparing,
      Mh09PreviewScenario.exceptionalCancel,
    ).capabilities;
    final operations = Mh09PreviewFixtures.detail(
      preparing,
      Mh09PreviewScenario.operations,
    ).capabilities;
    expect(exceptional.canCancelExceptional, isTrue);
    expect(exceptional.canConfirm, isFalse);
    expect(operations.canAssign, isTrue);
    expect(operations.canReassign, isTrue);
    expect(operations.canArrangeSecondAttempt, isFalse);
    expect(operations.canRequestEarlyReturn, isFalse);

    final retry = Mh09PreviewFixtures.detail(
      records[5].details,
      Mh09PreviewScenario.operations,
    ).capabilities;
    expect(retry.canAssign, isFalse);
    expect(retry.canReassign, isFalse);
    expect(retry.canArrangeSecondAttempt, isTrue);
    expect(retry.canRequestEarlyReturn, isTrue);

    final denied = Mh09PreviewFixtures.detail(
      pending,
      Mh09PreviewScenario.commandsDenied,
    ).capabilities;
    expect(denied.toMap().values.every((value) => !value), isTrue);
  });

  test('fixture calls are immutable and repeatable', () {
    final base = records[8].details;
    final before = base.toMap();
    final first = Mh09PreviewFixtures.detail(base, Mh09PreviewScenario.large);
    final second = Mh09PreviewFixtures.detail(base, Mh09PreviewScenario.large);

    expect(base.toMap(), before);
    expect(
      first.items.map((item) => item.toMap()).toList(),
      second.items.map((item) => item.toMap()).toList(),
    );
    expect(first.timeline, base.timeline);
    expect(first.order, base.order);
  });
}
