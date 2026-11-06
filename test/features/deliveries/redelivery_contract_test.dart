import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/deliveries/data/models/redelivery_command_dto.dart';
import 'package:sports_store/features/deliveries/domain/models/redelivery_command.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_failure_command.dart';

const task = '11111111-1111-4111-8111-111111111111';
const order = '22222222-2222-4222-8222-222222222222';
const request = '33333333-3333-4333-8333-333333333333';
const key = '44444444-4444-4444-8444-444444444444';
const event = '55555555-5555-4555-8555-555555555555';
const at = '2026-10-28T08:00:00Z';
void main() {
  for (final op in RedeliveryOperation.values) {
    test('strict authoritative ${op.name} acknowledgement', () {
      final command = RedeliveryCommand(
        taskId: task,
        requestId: key,
        returnRequestId: request,
        orderId: order,
        operation: op,
        items: op == RedeliveryOperation.accept
            ? [const RedeliveryItem(itemId: event, quantity: 2)]
            : [],
        receivedAllItems: op == RedeliveryOperation.complete ? true : null,
        reason: op == RedeliveryOperation.fail
            ? OutboundFailureReason.other
            : null,
        description: op == RedeliveryOperation.fail ? 'Required reason' : null,
      );
      final json = <String, dynamic>{
        'task_id': task,
        'order_id': order,
        'return_request_id': request,
        'request_id': key,
        'event_id': event,
        'operation': op.value,
        'occurred_at': at,
        'task_status': switch (op) {
          RedeliveryOperation.accept => 'accepted',
          RedeliveryOperation.start => 'in_transit',
          RedeliveryOperation.complete => 'delivered',
          RedeliveryOperation.fail => 'manager_action_required',
        },
        'return_status': op == RedeliveryOperation.complete
            ? 'rejected_after_inspection'
            : op == RedeliveryOperation.fail
            ? 'manager_action_required'
            : 'awaiting_redelivery',
        if (op == RedeliveryOperation.accept ||
            op == RedeliveryOperation.start) ...{
          'kind': 'redelivery',
          'amount_to_collect_vnd': 0,
          'accepted_at': at,
          'started_at': op == RedeliveryOperation.start ? at : null,
        },
        if (op == RedeliveryOperation.complete) ...{
          'completed_at': at,
          'closed_at': at,
        },
        if (op == RedeliveryOperation.fail) ...{
          'failed_at': at,
          'custody_open': true,
          'reason_code': 'other',
          'description': 'Required reason',
        },
      };
      final ack = RedeliveryCommandAckDto.fromJson(
        json,
        command: command,
      ).toDomain();
      expect(ack.matches(command), isTrue);
      expect(
        () => RedeliveryCommandAckDto.fromJson({
          ...json,
          'request_id': event,
        }, command: command),
        throwsFormatException,
      );
      expect(
        () => RedeliveryCommandAckDto.fromJson({
          ...json,
          'bank_name': 'private',
        }, command: command),
        throwsFormatException,
      );
      if (op == RedeliveryOperation.accept || op == RedeliveryOperation.start) {
        expect(
          () => RedeliveryCommandAckDto.fromJson({
            ...json,
            'amount_to_collect_vnd': 30000,
          }, command: command),
          throwsFormatException,
        );
      }
    });
  }
  test('other reason requires description and item payload is immutable', () {
    expect(
      RedeliveryCommand.fail(
        taskId: task,
        requestId: key,
        returnRequestId: request,
        orderId: order,
        reason: OutboundFailureReason.other,
      ).isValid,
      isFalse,
    );
    final items = [const RedeliveryItem(itemId: event, quantity: 2)];
    final command = RedeliveryCommand.accept(
      taskId: task,
      requestId: key,
      returnRequestId: request,
      orderId: order,
      items: items,
    );
    items.clear();
    expect(command.items.length, 1);
    expect(() => command.items.clear(), throwsUnsupportedError);
  });
}
