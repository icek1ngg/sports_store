import 'package:sports_store/features/orders/data/models/order_dto.dart';
import 'package:sports_store/features/orders/domain/models/order_details.dart';

import '../../../../../fixtures/order_notification_fixtures.dart';

export '../../../../../fixtures/order_notification_fixtures.dart';

OrderDetails mh09Details({
  Object? buyer,
  String status = 'pending_confirmation',
  Map<String, Object?>? capabilities,
  Object? deliverySummary,
  Object? codSummary,
  List<Object?>? returnSummaries,
  List<Object?>? timeline,
  bool historyComplete = true,
}) {
  final json = fixtureOrderDetailsJson(buyer: buyer, timeline: timeline)
    ..['order'] = {...fixtureOrderJson(status: status)}
    ..['capabilities'] = capabilities ?? fixtureCapabilitiesJson()
    ..['delivery_summary'] = deliverySummary
    ..['cod_summary'] = codSummary
    ..['return_summaries'] = returnSummaries ?? <Object?>[]
    ..['history_complete'] = historyComplete;
  return OrderDetailsDto.fromJson(json).domain;
}

Map<String, Object?> mh09Capabilities({
  bool confirm = false,
  bool reject = false,
  bool managerCancel = false,
  bool assign = false,
  bool reassign = false,
  bool retry = false,
  bool earlyReturn = false,
  bool receive = false,
}) {
  return {
    'can_cancel_customer': false,
    'can_confirm': confirm,
    'can_reject': reject,
    'can_cancel_exceptional': managerCancel,
    'can_assign': assign,
    'can_reassign': reassign,
    'can_arrange_second_attempt': retry,
    'can_request_early_return': earlyReturn,
    'can_receive_undelivered': receive,
    'can_open_return_creation': false,
  };
}

Map<String, Object?> mh09DeliverySummary() => {
  'task_id': fixtureTaskId,
  'kind': 'outbound',
  'task_status': 'failed',
  'assigned_shipper_id': fixtureShipperId,
  'assigned_shipper_name': 'Shipper minh họa',
  'assigned_at': '2026-10-08T03:50:00Z',
  'accepted_at': '2026-10-08T03:55:00Z',
  'started_at': '2026-10-08T04:00:00Z',
  'completed_at': '2026-10-08T06:00:00Z',
  'amount_to_collect_vnd': 3480000,
  'attempt_count': 1,
  'latest_attempt': {
    'id': fixtureAttemptId,
    'task_id': fixtureTaskId,
    'order_id': fixtureOrderId,
    'attempt_number': 1,
    'task_kind': 'outbound',
    'result': 'failed',
    'reason': 'Không liên lạc được người nhận',
    'occurred_at': '2026-10-08T06:00:00Z',
    'shipper_id': fixtureShipperId,
  },
  'failure_reason': 'Không liên lạc được người nhận',
};

Map<String, Object?> mh09CodSummary() => {
  'order_id': fixtureOrderId,
  'shipper_id': fixtureShipperId,
  'status': 'collected',
  'expected_amount_vnd': 3480000,
  'collected_amount_vnd': 3480000,
  'received_amount_vnd': 0,
  'collected_at': '2026-10-08T06:00:00Z',
  'collected_by': fixtureShipperId,
  'handed_over_at': null,
  'received_at': null,
  'received_by': null,
};

Map<String, Object?> mh09ReturnSummary() => {
  'return_id': fixtureReturnId,
  'order_id': fixtureOrderId,
  'status': 'pending_review',
  'submitted_at': '2026-10-08T07:00:00Z',
  'closed_at': null,
  'decision_reason': null,
  'is_active': true,
  'can_submit_return': false,
  'eligibility_reason': 'active_return',
  'return_deadline': null,
};
