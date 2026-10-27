import 'package:sports_store/features/orders/data/models/order_dto.dart';
import 'package:sports_store/features/orders/domain/models/cod_summary.dart';
import 'package:sports_store/features/orders/domain/models/order.dart';
import 'package:sports_store/features/orders/domain/models/order_capabilities.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';

import '../../../../../fixtures/order_notification_fixtures.dart';

export 'mh09_test_support.dart';

OrderCapabilities mh09Capabilities({
  bool confirm = false,
  bool reject = false,
  bool cancel = false,
  bool assign = false,
  bool reassign = false,
  bool retry = false,
  bool earlyReturn = false,
  bool receive = false,
  bool customerCancel = false,
  bool returnCreation = false,
}) => OrderCapabilities(
  canCancelCustomer: customerCancel,
  canConfirm: confirm,
  canReject: reject,
  canCancelExceptional: cancel,
  canAssign: assign,
  canReassign: reassign,
  canArrangeSecondAttempt: retry,
  canRequestEarlyReturn: earlyReturn,
  canReceiveUndelivered: receive,
  canOpenReturnCreation: returnCreation,
);

/// Test-only arithmetic constructs valid model snapshots, never UI totals.
Order mh09FinancialOrder({
  int subtotalVnd = 3450000,
  OrderStatus status = OrderStatus.pendingConfirmation,
}) => OrderDto.fromJson({
  ...fixtureOrderJson(status: status.wireValue),
  'subtotal_vnd': subtotalVnd,
  'total_cod_vnd': subtotalVnd + 30000,
}).domain;

CodSummary mh09Cod(Order order, {CodStatus status = CodStatus.uncollected}) =>
    CodSummary(
      orderId: order.id,
      shipperId: fixtureShipperId,
      status: status,
      expectedAmountVnd: order.totalCodVnd,
      collectedAmountVnd: status == CodStatus.uncollected
          ? 0
          : order.totalCodVnd,
      receivedAmountVnd: status == CodStatus.received ? order.totalCodVnd : 0,
      collectedAt: status == CodStatus.uncollected
          ? null
          : DateTime.utc(2026, 10, 9, 3),
      collectedBy: status == CodStatus.uncollected ? null : fixtureShipperId,
      handedOverAt: null,
      receivedAt: status == CodStatus.received
          ? DateTime.utc(2026, 10, 9, 5)
          : null,
      receivedBy: status == CodStatus.received ? fixtureManagerId : null,
    );
