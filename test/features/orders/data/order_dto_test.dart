import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/core/errors/unsupported_data_exception.dart';
import 'package:sports_store/features/orders/data/models/order_dto.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/domain/models/order_query.dart';
import 'package:sports_store/features/orders/domain/models/order_command.dart';

import '../../../fixtures/order_notification_fixtures.dart';

void main() {
  test('client command cannot represent server automatic confirmation', () {
    expect(
      () => StableOrderCommand(
        orderId: fixtureOrderId,
        requestId: fixtureMutationRequestId,
        operation: OrderOperation.autoConfirm,
      ),
      throwsArgumentError,
    );
  });

  test('successful envelope decodes real data', () {
    final dto = decodeOrderRpcEnvelope({
      'ok': true,
      'data': fixtureOrderJson(),
      'error': null,
    }, OrderDto.fromJson);
    expect(dto.domain.id, fixtureOrderId);
  });

  test('HTTP-success business error never invokes the success mapper', () {
    var called = false;
    expect(
      () => decodeOrderRpcEnvelope(
        {
          'ok': false,
          'data': null,
          'error': {
            'code': AppFailure.outcomeUnknownCode,
            'message_key': null,
            'retryable': false,
            'current_order': null,
          },
        },
        (json) {
          called = true;
          return json;
        },
      ),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.outcomeUnknown,
          'unknown outcome',
          isTrue,
        ),
      ),
    );
    expect(called, isFalse);
  });

  for (final envelope in <Map<String, Object?>>[
    {'ok': true, 'data': null, 'error': null},
    {'ok': false, 'data': fixtureOrderJson(), 'error': null},
    {'ok': true, 'data': fixtureOrderJson()},
    {'ok': 'true', 'data': fixtureOrderJson(), 'error': null},
  ]) {
    test(
      'invalid discriminated envelope ${envelope.keys}/${envelope['ok']}/${envelope['data'] == null}',
      () {
        expect(
          () => decodeOrderRpcEnvelope(envelope, OrderDto.fromJson),
          throwsA(isA<UnsupportedDataException>()),
        );
      },
    );
  }
  group('OrderDto', () {
    test('maps the full 21-key order and keeps nullable keys', () {
      final dto = OrderDto.fromJson(fixtureOrderJson());

      expect(dto.domain.id, fixtureOrderId);
      expect(dto.domain.status, OrderStatus.pendingConfirmation);
      expect(dto.domain.confirmedAt, isNull);
      expect(dto.domain.source, isNull);
      expect(dto.toJson().containsKey('cancel_reason'), isTrue);
      expect(dto.toJson()['cancel_reason'], isNull);
    });

    test('rejects an unknown status without defaulting to pending', () {
      final json = fixtureOrderJson()..['status'] = 'future_state';

      expect(
        () => OrderDto.fromJson(json),
        throwsA(
          isA<UnsupportedDataException>().having(
            (error) => error.rawValue,
            'rawValue',
            'future_state',
          ),
        ),
      );
    });

    test('rejects omitted nullable keys', () {
      final json = fixtureOrderJson()..remove('cancel_reason');

      expect(
        () => OrderDto.fromJson(json),
        throwsA(isA<UnsupportedDataException>()),
      );
    });

    test('accepts canonical UUIDs generated after UUID v5', () {
      final json = fixtureOrderJson()
        ..['id'] = '10000000-0000-7000-8000-000000000001';

      expect(
        OrderDto.fromJson(json).domain.id,
        startsWith('10000000-0000-7000'),
      );
    });

    test(
      'requires integer VND values rather than silently truncating doubles',
      () {
        final json = fixtureOrderJson()..['subtotal_vnd'] = 3450000.0;

        expect(
          () => OrderDto.fromJson(json),
          throwsA(isA<UnsupportedDataException>()),
        );
      },
    );

    test('requires an explicit timestamp offset', () {
      final json = fixtureOrderJson()..['placed_at'] = '2026-10-08T03:32:00';

      expect(
        () => OrderDto.fromJson(json),
        throwsA(isA<UnsupportedDataException>()),
      );
    });

    test('rejects normalized invalid calendar dates and offsets', () {
      final invalidDate = fixtureOrderJson()
        ..['placed_at'] = '2026-02-30T03:32:00Z';
      final invalidOffset = fixtureOrderJson()
        ..['placed_at'] = '2026-10-08T03:32:00+24:00';

      expect(
        () => OrderDto.fromJson(invalidDate),
        throwsA(isA<UnsupportedDataException>()),
      );
      expect(
        () => OrderDto.fromJson(invalidOffset),
        throwsA(isA<UnsupportedDataException>()),
      );
    });

    test('deep freezes attributes in order items', () {
      final attributes = <String, Object?>{
        'size': 'M',
        'options': <Object?>['red'],
      };
      final json = fixtureOrderItemJson()..['attributes'] = attributes;
      final item = OrderItemDto.fromJson(json).domain;
      attributes['size'] = 'XL';
      (attributes['options']! as List<Object?>).add('large');

      expect(item.attributes['size'], 'M');
      expect(item.attributes['options'], ['red']);
      expect(
        () => (item.attributes['options']! as List<Object?>).add('x'),
        throwsUnsupportedError,
      );
    });

    test('allows a customer-safe failed attempt with redacted reason', () {
      final attempt = AttemptSummaryDto.fromJson({
        'id': fixtureAttemptId,
        'task_id': fixtureTaskId,
        'order_id': fixtureOrderId,
        'attempt_number': 1,
        'task_kind': 'outbound',
        'result': 'failed',
        'reason': null,
        'occurred_at': '2026-10-08T06:00:00Z',
        'shipper_id': null,
      }).domain;

      expect(attempt.result, DeliveryAttemptResult.failed);
      expect(attempt.reason, isNull);
      expect(attempt.shipperId, isNull);
    });

    test('keeps an unknown warning code as a generic no-action warning', () {
      final summary = fixtureOrderSummaryJson()
        ..['warnings'] = [
          {
            'code': 'future_warning',
            'source_id': fixtureOrderId,
            'message': 'A newer server warning',
          },
        ];

      final mapped = OrderSummaryDto.fromJson(summary).domain;
      expect(mapped.warnings.single.code, WarningCode.unknown);
      expect(mapped.warnings.single.rawCode, 'future_warning');
    });

    test('rejects a preview item belonging to another order', () {
      final item = fixtureOrderItemJson()..['order_id'] = fixtureCustomerId;
      final summary = fixtureOrderSummaryJson()..['item_preview'] = [item];

      expect(
        () => OrderSummaryDto.fromJson(summary),
        throwsA(isA<UnsupportedDataException>()),
      );
    });

    test('rejects current_order on an error code without a state snapshot', () {
      final json = {
        'code': AppFailure.forbiddenOrUnavailable,
        'message_key': 'MSG-08',
        'retryable': false,
        'current_order': {'id': fixtureOrderId, 'status': 'preparing'},
      };

      expect(
        () => AppErrorDto.fromJson(json),
        throwsA(isA<UnsupportedDataException>()),
      );
    });

    test('rejects an unknown status in an error reference', () {
      final json = {
        'code': AppFailure.stateChanged,
        'message_key': 'MSG-26',
        'retryable': false,
        'current_order': {'id': fixtureOrderId, 'status': 'future_state'},
      };

      expect(
        () => AppErrorDto.fromJson(json),
        throwsA(isA<UnsupportedDataException>()),
      );
    });

    test('preserves a blank authorized actor label', () {
      final timeline = fixtureTimelineEntryJson()..['actor_label'] = '';
      final details = OrderDetailsDto.fromJson(
        fixtureOrderDetailsJson(timeline: [timeline]),
      ).domain;

      expect(details.timeline.single.actorLabel, isEmpty);
    });

    test('rejects a timeline event kind paired with the wrong entity', () {
      final timeline = fixtureTimelineEntryJson()
        ..['source_entity_type'] = 'cod';

      expect(
        () => OrderDetailsDto.fromJson(
          fixtureOrderDetailsJson(timeline: [timeline]),
        ),
        throwsA(isA<UnsupportedDataException>()),
      );
    });

    test('rejects actual events without an event id', () {
      final timeline = fixtureTimelineEntryJson()..['event_id'] = null;

      expect(
        () => OrderDetailsDto.fromJson(
          fixtureOrderDetailsJson(timeline: [timeline]),
        ),
        throwsA(isA<UnsupportedDataException>()),
      );
    });

    test(
      'coalesces identical timeline rows but rejects conflicting duplicates',
      () {
        final first = fixtureTimelineEntryJson();
        final identical = fixtureTimelineEntryJson();
        final detail = OrderDetailsDto.fromJson(
          fixtureOrderDetailsJson(timeline: [first, identical]),
        ).domain;
        expect(detail.timeline, hasLength(1));

        final conflicting = fixtureTimelineEntryJson()
          ..['reason'] = 'changed facts';
        expect(
          () => OrderDetailsDto.fromJson(
            fixtureOrderDetailsJson(timeline: [first, conflicting]),
          ),
          throwsA(isA<UnsupportedDataException>()),
        );
      },
    );

    test('rejects a buyer projection that names another customer', () {
      final details = fixtureOrderDetailsJson(
        buyer: {'id': fixtureManagerId, 'full_name': 'Manager'},
      );

      expect(
        () => OrderDetailsDto.fromJson(details),
        throwsA(isA<UnsupportedDataException>()),
      );
    });

    test('rejects full detail items whose totals disagree with the order', () {
      final item = fixtureOrderItemJson()
        ..['unit_price_vnd'] = 1
        ..['line_total_vnd'] = 1;
      final details = fixtureOrderDetailsJson()..['items'] = [item];

      expect(
        () => OrderDetailsDto.fromJson(details),
        throwsA(isA<UnsupportedDataException>()),
      );
    });

    test('rejects a COD projection for another order or amount', () {
      final cod = {
        'order_id': fixtureCustomerId,
        'shipper_id': null,
        'status': 'uncollected',
        'expected_amount_vnd': 3480000,
        'collected_amount_vnd': 0,
        'received_amount_vnd': 0,
        'collected_at': null,
        'collected_by': null,
        'handed_over_at': null,
        'received_at': null,
        'received_by': null,
      };
      final details = fixtureOrderDetailsJson()..['cod_summary'] = cod;

      expect(
        () => OrderDetailsDto.fromJson(details),
        throwsA(isA<UnsupportedDataException>()),
      );
      cod['order_id'] = fixtureOrderId;
      cod['expected_amount_vnd'] = 100;
      expect(
        () => OrderDetailsDto.fromJson(details),
        throwsA(isA<UnsupportedDataException>()),
      );
      final summary = fixtureOrderSummaryJson()..['cod_summary'] = cod;
      expect(
        () => OrderSummaryDto.fromJson(summary),
        throwsA(isA<UnsupportedDataException>()),
      );
    });

    test('rejects a page count smaller than its item page', () {
      final page = fixtureOrderListJson()..['total_count'] = 0;

      expect(
        () => OrderListResponseDto.fromJson(page),
        throwsA(isA<UnsupportedDataException>()),
      );
    });
  });

  group('OrderQuery', () {
    test('normalizes Unicode contract whitespace and compares by value', () {
      final first = OrderQuery(
        search: '\u0085\u2003shoe\u00a0',
        statuses: const [OrderStatus.preparing],
      );
      final second = OrderQuery(
        search: 'shoe',
        statuses: const [OrderStatus.preparing],
      );

      expect(first.search, 'shoe');
      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });
}
