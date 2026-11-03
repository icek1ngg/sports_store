import 'return_reason.dart';
import 'return_tracking.dart' show ReturnRequestStatus;

export 'return_tracking.dart' show ReturnRequestStatus;

/// One row of the manager list.
class ManagerReturnSummary {
  const ManagerReturnSummary({
    required this.returnId,
    required this.orderId,
    required this.status,
    required this.reason,
    required this.submittedAt,
    required this.customerName,
    required this.totalVnd,
    required this.lineCount,
    this.firstItemName,
  });

  final String returnId;
  final String orderId;
  final ReturnRequestStatus status;
  final ReturnReason reason;
  final DateTime submittedAt;
  final String customerName;

  /// Original merchandise + delivery fee paid by COD.
  final int totalVnd;
  final int lineCount;
  final String? firstItemName;
}

/// List page: rows for the active filter plus counts for every status that
/// matches the search (so tab badges do not depend on the selected tab).
class ManagerReturnList {
  const ManagerReturnList({
    required this.items,
    required this.counts,
    required this.serverNow,
  });

  final List<ManagerReturnSummary> items;
  final Map<ReturnRequestStatus, int> counts;
  final DateTime serverNow;

  int get total => counts.values.fold(0, (a, b) => a + b);
}

class ManagerReturnOrderItem {
  const ManagerReturnOrderItem({
    required this.orderItemId,
    required this.productName,
    required this.quantity,
    required this.unitPriceVnd,
    required this.lineTotalVnd,
    this.variantLabel,
    this.imageUrl,
  });

  final String orderItemId;
  final String productName;
  final String? variantLabel;
  final int quantity;
  final int unitPriceVnd;
  final int lineTotalVnd;
  final String? imageUrl;
}

/// Goods the manager decided to collect (exists from pickup approval on).
class ManagerReturnItem {
  const ManagerReturnItem({
    required this.returnItemId,
    required this.name,
    required this.quantityToCollect,
    required this.quantityCollected,
    required this.sellableQuantity,
    required this.damagedQuantity,
    this.orderItemId,
  });

  final String returnItemId;
  final String? orderItemId;
  final String name;
  final int quantityToCollect;
  final int quantityCollected;
  final int sellableQuantity;
  final int damagedQuantity;
}

class ManagerReturnBank {
  const ManagerReturnBank({
    required this.bankName,
    required this.accountNumber,
    required this.accountHolder,
  });

  final String bankName;
  final String accountNumber;
  final String accountHolder;
}

class ManagerReturnPickupTask {
  const ManagerReturnPickupTask({
    required this.taskId,
    required this.status,
    required this.shipperName,
    this.shipperId,
    this.shipperPhone,
    this.assignedAt,
    this.completedAt,
    this.failureReason,
    this.handoverReported = false,
  });

  final String taskId;

  /// Raw delivery_task_status wire value.
  final String status;
  final String? shipperId;
  final String shipperName;
  final String? shipperPhone;
  final DateTime? assignedAt;
  final DateTime? completedAt;
  final String? failureReason;

  /// The shipper reported handing the goods to the store (pickup only).
  final bool handoverReported;

  bool get isActive =>
      const {'assigned', 'accepted', 'in_transit'}.contains(status);
}

class ManagerInfoRequest {
  const ManagerInfoRequest({
    required this.message,
    required this.requestedAt,
    this.responseText,
    this.responseVideoPath,
    this.respondedAt,
  });

  final String message;
  final DateTime requestedAt;
  final String? responseText;
  final String? responseVideoPath;
  final DateTime? respondedAt;

  bool get isOpen => respondedAt == null;
}

class ManagerRefundRecord {
  const ManagerRefundRecord({
    required this.amountVnd,
    required this.refundedAt,
    required this.evidencePath,
  });

  final int amountVnd;

  /// Actual transfer time entered by the manager.
  final DateTime refundedAt;
  final String evidencePath;
}

class ManagerShipperOption {
  const ManagerShipperOption({
    required this.shipperId,
    required this.name,
    this.phone,
  });

  final String shipperId;
  final String name;
  final String? phone;
}

class ManagerReturnContact {
  const ManagerReturnContact({required this.name, this.phone, this.address});

  final String name;
  final String? phone;
  final String? address;
}

/// Everything MH15 needs to decide one request. Private data (bank, video)
/// is only returned to managers by the server.
class ManagerReturnDetail {
  const ManagerReturnDetail({
    required this.returnId,
    required this.orderId,
    required this.status,
    required this.reason,
    required this.description,
    required this.submittedAt,
    required this.customer,
    required this.recipient,
    required this.subtotalVnd,
    required this.deliveryFeeVnd,
    required this.totalVnd,
    required this.orderItems,
    required this.returnItems,
    required this.videoPaths,
    required this.shippers,
    required this.serverNow,
    this.deliveredAt,
    this.decisionReason,
    this.decisionAt,
    this.closedAt,
    this.inspectionStartedAt,
    this.inspectedAt,
    this.bank,
    this.pickupTask,
    this.redeliveryTask,
    this.refund,
    this.infoRequests = const [],
    this.inspectionEvidencePaths = const [],
  });

  final String returnId;
  final String orderId;
  final ReturnRequestStatus status;
  final ReturnReason reason;
  final String description;
  final DateTime submittedAt;
  final DateTime? deliveredAt;
  final String? decisionReason;
  final DateTime? decisionAt;
  final DateTime? closedAt;
  final ManagerReturnContact customer;
  final ManagerReturnContact recipient;
  final int subtotalVnd;
  final int deliveryFeeVnd;
  final int totalVnd;
  final List<ManagerReturnOrderItem> orderItems;
  final List<ManagerReturnItem> returnItems;

  /// Original video first, then any additional videos (private bucket paths).
  final List<String> videoPaths;
  final ManagerReturnBank? bank;
  final ManagerReturnPickupTask? pickupTask;
  final ManagerReturnPickupTask? redeliveryTask;
  final ManagerRefundRecord? refund;
  final List<ManagerInfoRequest> infoRequests;
  final List<String> inspectionEvidencePaths;
  final List<ManagerShipperOption> shippers;
  final DateTime serverNow;
  final DateTime? inspectionStartedAt;
  final DateTime? inspectedAt;

  ManagerReturnDetail copyWith({
    ReturnRequestStatus? status,
    String? decisionReason,
    DateTime? decisionAt,
    DateTime? closedAt,
    DateTime? inspectionStartedAt,
    DateTime? inspectedAt,
    List<ManagerReturnItem>? returnItems,
    List<String>? videoPaths,
    ManagerReturnPickupTask? pickupTask,
    ManagerReturnPickupTask? redeliveryTask,
    ManagerRefundRecord? refund,
    List<ManagerInfoRequest>? infoRequests,
    List<String>? inspectionEvidencePaths,
    DateTime? serverNow,
  }) => ManagerReturnDetail(
    returnId: returnId,
    orderId: orderId,
    status: status ?? this.status,
    reason: reason,
    description: description,
    submittedAt: submittedAt,
    customer: customer,
    recipient: recipient,
    subtotalVnd: subtotalVnd,
    deliveryFeeVnd: deliveryFeeVnd,
    totalVnd: totalVnd,
    orderItems: orderItems,
    returnItems: returnItems ?? this.returnItems,
    videoPaths: videoPaths ?? this.videoPaths,
    shippers: shippers,
    serverNow: serverNow ?? this.serverNow,
    deliveredAt: deliveredAt,
    decisionReason: decisionReason ?? this.decisionReason,
    decisionAt: decisionAt ?? this.decisionAt,
    closedAt: closedAt ?? this.closedAt,
    inspectionStartedAt: inspectionStartedAt ?? this.inspectionStartedAt,
    inspectedAt: inspectedAt ?? this.inspectedAt,
    bank: bank,
    pickupTask: pickupTask ?? this.pickupTask,
    redeliveryTask: redeliveryTask ?? this.redeliveryTask,
    refund: refund ?? this.refund,
    infoRequests: infoRequests ?? this.infoRequests,
    inspectionEvidencePaths:
        inspectionEvidencePaths ?? this.inspectionEvidencePaths,
  );

  ManagerInfoRequest? get openInfoRequest =>
      infoRequests.where((r) => r.isOpen).lastOrNull;

  /// Full merchandise + original delivery fee (the only refundable amount).
  int get refundAmountVnd => totalVnd;

  /// Actions the manager may take now. The server re-checks every one.
  Set<ManagerReturnAction> get availableActions {
    final infoOpen = openInfoRequest != null;
    return switch (status) {
      ReturnRequestStatus.pendingReview => {
        ManagerReturnAction.approveCollection,
        ManagerReturnAction.reject,
        if (!infoOpen) ManagerReturnAction.requestInfo,
      },
      ReturnRequestStatus.returningToStore =>
        pickupTask?.handoverReported == true
            ? const {ManagerReturnAction.receive}
            : const {},
      ReturnRequestStatus.underInspection =>
        infoOpen
            ? const {}
            : const {
                ManagerReturnAction.acceptInspection,
                ManagerReturnAction.rejectInspection,
                ManagerReturnAction.requestInfo,
              },
      ReturnRequestStatus.awaitingRefund => const {
        ManagerReturnAction.recordRefund,
      },
      ReturnRequestStatus.awaitingRedelivery =>
        redeliveryTask == null ||
                (!redeliveryTask!.isActive &&
                    redeliveryTask!.status != 'delivered')
            ? const {ManagerReturnAction.assignRedelivery}
            : const {},
      _ => const {},
    };
  }
}

enum ManagerReturnAction {
  approveCollection,
  reject,
  requestInfo,
  receive,
  acceptInspection,
  rejectInspection,
  recordRefund,
  assignRedelivery,
}

/// Inspection result for one received line: sellable goods go back to
/// stock once, damaged goods stay out of sellable stock.
class ManagerInspectionLine {
  const ManagerInspectionLine({
    required this.returnItemId,
    required this.sellableQuantity,
    required this.damagedQuantity,
  });

  final String returnItemId;
  final int sellableQuantity;
  final int damagedQuantity;
}

/// A local file chosen as inspection or transfer evidence.
class ManagerEvidenceFile {
  const ManagerEvidenceFile({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  static const maxBytes = 10 * 1024 * 1024;
  static const extensions = ['jpg', 'jpeg', 'png', 'webp', 'pdf'];

  final String name;
  final List<int> bytes;
  final String mimeType;
}

enum ManagerEvidenceKind { inspection, refund }

/// One line of the collection plan sent with "Duyệt lấy hàng".
class ManagerCollectionLine {
  const ManagerCollectionLine({
    required this.orderItemId,
    required this.quantity,
  });

  final String orderItemId;
  final int quantity;
}
