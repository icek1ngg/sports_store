import 'package:sports_store/features/returns/domain/models/manager_return.dart';
import 'package:sports_store/features/returns/domain/models/return_reason.dart';
import 'package:sports_store/features/returns/domain/models/return_request_failure.dart';
import 'package:sports_store/features/returns/domain/repositories/manager_return_repository.dart';

/// DEMO-only in-memory return management backend for the UI preview.
/// Same repository contract as Supabase; nothing here touches the network.
/// Every action changes the in-memory state so the whole flow can be
/// clicked through: approve → (shipper, simulated) → receive → inspect →
/// refund or reject → redelivery.
class Mh15DemoRepository implements ManagerReturnRepository {
  Mh15DemoRepository({this.failLoads = false}) {
    final now = DateTime.now().toUtc();
    ManagerReturnDetail add(ManagerReturnDetail d) => _detail[d.returnId] = d;

    add(
      _make(
        id: '15000000-0000-4000-8000-000000000028',
        customer: 'DEMO Nguyễn Minh Anh',
        status: ReturnRequestStatus.pendingReview,
        reason: ReturnReason.defective,
        description: 'Đường may ở vai áo bị bung khi mở kiện hàng.',
        submitted: now.subtract(const Duration(hours: 3)),
        items: const [('Áo thể thao Performance Core', 'Đen / M', 2, 275000)],
      ),
    );
    add(
      _make(
        id: '15000000-0000-4000-8000-000000000029',
        customer: 'DEMO Trần Bảo Ngọc',
        status: ReturnRequestStatus.pendingReview,
        reason: ReturnReason.wrongItem,
        description: 'Nhận bóng tennis màu cam thay vì màu vàng như đơn.',
        submitted: now.subtract(const Duration(hours: 20)),
        items: const [
          ('Bóng đá tập luyện', 'Tiêu chuẩn', 1, 250000),
          ('Bóng tennis', 'Tiêu chuẩn', 2, 65000),
        ],
      ).copyWith(
        infoRequests: [
          ManagerInfoRequest(
            message: 'Vui lòng quay rõ nhãn màu trên hộp bóng.',
            requestedAt: now.subtract(const Duration(hours: 10)),
            responseText: 'Em gửi thêm video quay cận nhãn hộp bóng ạ.',
            responseVideoPath: 'demo/extra.mp4',
            respondedAt: now.subtract(const Duration(hours: 6)),
          ),
        ],
        videoPaths: const ['demo/return-video.mp4', 'demo/extra.mp4'],
      ),
    );
    add(
      _make(
        id: '15000000-0000-4000-8000-000000000027',
        customer: 'DEMO Lê Hoàng Phúc',
        status: ReturnRequestStatus.returningToStore,
        reason: ReturnReason.missingItems,
        description: 'Thiếu một đôi tất trong combo đã đặt.',
        submitted: now.subtract(const Duration(days: 2)),
        items: const [('Combo tất thể thao', '3 đôi', 1, 120000)],
        collect: 1,
        collected: true,
        task: 'in_transit',
        handover: true,
      ),
    );
    add(
      _make(
        id: '15000000-0000-4000-8000-000000000025',
        customer: 'DEMO Vũ Thanh Tâm',
        status: ReturnRequestStatus.underInspection,
        reason: ReturnReason.defective,
        description: 'Đế giày bong keo sau lần mang thử đầu tiên.',
        submitted: now.subtract(const Duration(days: 3)),
        items: const [('Giày chạy bộ Pace', '42', 1, 1290000)],
        collect: 1,
        collected: true,
        task: 'returned_to_store',
      ),
    );
    add(
      _make(
        id: '15000000-0000-4000-8000-000000000024',
        customer: 'DEMO Đỗ Khánh Linh',
        status: ReturnRequestStatus.awaitingRefund,
        reason: ReturnReason.defective,
        description: 'Khóa kéo balo bị kẹt, không kéo được.',
        submitted: now.subtract(const Duration(days: 4)),
        items: const [('Balo thể thao 25L', 'Xám', 1, 450000)],
        collect: 1,
        collected: true,
        task: 'returned_to_store',
        inspected: (1, 0),
      ),
    );
    add(
      _make(
        id: '15000000-0000-4000-8000-000000000023',
        customer: 'DEMO Hoàng Gia Bảo',
        status: ReturnRequestStatus.awaitingRedelivery,
        reason: ReturnReason.wrongItem,
        description: 'Nhận găng tay size M thay vì L.',
        submitted: now.subtract(const Duration(days: 5)),
        items: const [('Găng tay bóng chày', 'M', 1, 450000)],
        collect: 1,
        collected: true,
        task: 'returned_to_store',
      ).copyWith(inspectionEvidencePaths: const ['demo/inspection.jpg']),
    );
    add(
      _make(
        id: '15000000-0000-4000-8000-000000000026',
        customer: 'DEMO Phạm Thu Hà',
        status: ReturnRequestStatus.initiallyRejected,
        reason: ReturnReason.defective,
        description: 'Vợt bị trầy nhẹ ở cán.',
        submitted: now.subtract(const Duration(days: 6)),
        items: const [('Vợt tennis cơ bản', 'Tiêu chuẩn', 1, 850000)],
      ).copyWith(
        decisionReason:
            'Vết trầy là dấu hiệu sử dụng, không phải lỗi sản xuất.',
        decisionAt: now.subtract(const Duration(days: 5)),
        closedAt: now.subtract(const Duration(days: 5)),
      ),
    );
  }

  final bool failLoads;
  final _detail = <String, ManagerReturnDetail>{};
  final _seenKeys = <String>{};

  static const _latency = Duration(milliseconds: 400);
  static const _shippers = [
    ManagerShipperOption(
      shipperId: '15000000-0000-4000-8000-0000000000a1',
      name: 'DEMO Shipper Hùng',
      phone: '0900000001',
    ),
    ManagerShipperOption(
      shipperId: '15000000-0000-4000-8000-0000000000a2',
      name: 'DEMO Shipper Lan',
      phone: '0900000002',
    ),
  ];

  static String _sub(String base, int n) =>
      '${base.substring(0, 24)}${n.toString().padLeft(12, '0')}';

  static ManagerReturnPickupTask _task(
    String id,
    String status, {
    bool handover = false,
    DateTime? at,
  }) => ManagerReturnPickupTask(
    taskId: id,
    status: status,
    shipperId: _shippers.first.shipperId,
    shipperName: _shippers.first.name,
    shipperPhone: _shippers.first.phone,
    assignedAt: at ?? DateTime.now().toUtc(),
    handoverReported: handover,
  );

  static ManagerReturnDetail _make({
    required String id,
    required String customer,
    required ReturnRequestStatus status,
    required ReturnReason reason,
    required String description,
    required DateTime submitted,
    required List<(String, String, int, int)> items,
    int collect = 0,
    bool collected = false,
    String? task,
    bool handover = false,
    (int, int)? inspected,
  }) {
    final order = _sub(id, 100 + int.parse(id.substring(34)));
    final orderItems = [
      for (final (i, (name, variant, qty, price)) in items.indexed)
        ManagerReturnOrderItem(
          orderItemId: _sub(order, 900 + i),
          productName: name,
          variantLabel: variant,
          quantity: qty,
          unitPriceVnd: price,
          lineTotalVnd: price * qty,
        ),
    ];
    final subtotal = orderItems.fold(0, (a, i) => a + i.lineTotalVnd);
    final decided = status != ReturnRequestStatus.pendingReview;
    return ManagerReturnDetail(
      returnId: id,
      orderId: order,
      status: status,
      reason: reason,
      description: description,
      submittedAt: submitted,
      deliveredAt: submitted.subtract(const Duration(days: 1)),
      decisionAt: decided ? submitted.add(const Duration(hours: 2)) : null,
      inspectionStartedAt: collected && task == 'returned_to_store'
          ? submitted.add(const Duration(days: 1))
          : null,
      inspectedAt: inspected == null
          ? null
          : submitted.add(const Duration(days: 1, hours: 2)),
      customer: ManagerReturnContact(name: customer, phone: '0912345678'),
      recipient: ManagerReturnContact(
        name: customer,
        phone: '0912345678',
        address: 'DEMO · Cổng Văn Miếu, 58 Quốc Tử Giám, Đống Đa, Hà Nội',
      ),
      subtotalVnd: subtotal,
      deliveryFeeVnd: 30000,
      totalVnd: subtotal + 30000,
      orderItems: orderItems,
      returnItems: [
        if (collect > 0)
          ManagerReturnItem(
            returnItemId: _sub(id, 999),
            orderItemId: orderItems.first.orderItemId,
            name: orderItems.first.productName,
            quantityToCollect: collect,
            quantityCollected: collected ? collect : 0,
            sellableQuantity: inspected?.$1 ?? 0,
            damagedQuantity: inspected?.$2 ?? 0,
          ),
      ],
      videoPaths: const ['demo/return-video.mp4'],
      bank: const ManagerReturnBank(
        bankName: 'DEMO Vietcombank',
        accountNumber: '0011004392819',
        accountHolder: 'DEMO KHACH HANG',
      ),
      pickupTask: task == null
          ? null
          : _task(_sub(id, 777), task, handover: handover),
      shippers: _shippers,
      serverNow: DateTime.now().toUtc(),
    );
  }

  Future<ManagerReturnDetail> _mutate(
    String returnId,
    String requestId,
    ReturnRequestStatus expected,
    ManagerReturnDetail Function(ManagerReturnDetail d, DateTime now) change,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final d = _detail[returnId]!;
    if (!_seenKeys.add(requestId)) return d; // idempotent replay
    if (d.status != expected) {
      throw const ReturnRequestFailure(ReturnRequestFailureCode.stateConflict);
    }
    final now = DateTime.now().toUtc();
    return _detail[returnId] = change(d, now).copyWith(serverNow: now);
  }

  @override
  Future<ManagerReturnList> list({
    ReturnRequestStatus? status,
    String? query,
  }) async {
    await Future<void>.delayed(_latency);
    if (failLoads) {
      throw const ReturnRequestFailure(ReturnRequestFailureCode.network);
    }
    final q = query?.trim().toLowerCase() ?? '';
    final hex = q
        .replaceAll(RegExp(r'^#?\s*(th|dh)\s*-?'), '')
        .replaceAll(RegExp('[^0-9a-f]'), '');
    final searched = _detail.values.where(
      (d) =>
          q.isEmpty ||
          d.customer.name.toLowerCase().contains(q) ||
          (hex.length >= 4 &&
              (d.returnId.replaceAll('-', '').contains(hex) ||
                  d.orderId.replaceAll('-', '').contains(hex))),
    );
    final counts = <ReturnRequestStatus, int>{};
    for (final d in searched) {
      counts[d.status] = (counts[d.status] ?? 0) + 1;
    }
    final rows =
        searched.where((d) => status == null || d.status == status).toList()
          ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    return ManagerReturnList(
      items: [
        for (final d in rows)
          ManagerReturnSummary(
            returnId: d.returnId,
            orderId: d.orderId,
            status: d.status,
            reason: d.reason,
            submittedAt: d.submittedAt,
            customerName: d.customer.name,
            totalVnd: d.totalVnd,
            lineCount: d.orderItems.length,
            firstItemName: d.orderItems.first.productName,
          ),
      ],
      counts: counts,
      serverNow: DateTime.now().toUtc(),
    );
  }

  @override
  Future<ManagerReturnDetail> load(String returnId) async {
    await Future<void>.delayed(_latency);
    if (failLoads) {
      throw const ReturnRequestFailure(ReturnRequestFailureCode.network);
    }
    final detail = _detail[returnId];
    if (detail == null) {
      throw const ReturnRequestFailure(ReturnRequestFailureCode.returnNotFound);
    }
    return detail;
  }

  @override
  Future<Uri> videoUrl(String objectPath) async =>
      Uri.parse('https://example.invalid/$objectPath');

  @override
  Future<Uri> evidenceUrl(ManagerEvidenceKind kind, String objectPath) async =>
      Uri.parse('https://example.invalid/${kind.name}/$objectPath');

  @override
  Future<String> uploadEvidence({
    required String returnId,
    required ManagerEvidenceKind kind,
    required String objectName,
    required ManagerEvidenceFile file,
  }) async {
    await Future<void>.delayed(_latency);
    return '$returnId/$objectName';
  }

  @override
  Future<void> approveCollection({
    required String returnId,
    required String requestId,
    required List<ManagerCollectionLine> lines,
    required String shipperId,
  }) =>
      _mutate(returnId, requestId, ReturnRequestStatus.pendingReview, (d, now) {
        final shipper = _shippers.firstWhere((s) => s.shipperId == shipperId);
        return d.copyWith(
          status: ReturnRequestStatus.awaitingReturnPickup,
          decisionAt: now,
          returnItems: [
            for (final (i, l) in lines.indexed)
              ManagerReturnItem(
                returnItemId: _sub(d.returnId, 800 + i),
                orderItemId: l.orderItemId,
                name: d.orderItems
                    .firstWhere((o) => o.orderItemId == l.orderItemId)
                    .productName,
                quantityToCollect: l.quantity,
                quantityCollected: 0,
                sellableQuantity: 0,
                damagedQuantity: 0,
              ),
          ],
          pickupTask: ManagerReturnPickupTask(
            taskId: _sub(d.returnId, 778),
            status: 'assigned',
            shipperId: shipper.shipperId,
            shipperName: shipper.name,
            shipperPhone: shipper.phone,
            assignedAt: now,
          ),
        );
      });

  @override
  Future<void> reject({
    required String returnId,
    required String requestId,
    required String reason,
  }) => _mutate(
    returnId,
    requestId,
    ReturnRequestStatus.pendingReview,
    (d, now) => d.copyWith(
      status: ReturnRequestStatus.initiallyRejected,
      decisionReason: reason,
      decisionAt: now,
      closedAt: now,
    ),
  );

  @override
  Future<void> requestInfo({
    required String returnId,
    required String requestId,
    required String message,
  }) async {
    final d = _detail[returnId]!;
    await _mutate(
      returnId,
      requestId,
      d.status,
      (d, now) => d.copyWith(
        infoRequests: [
          ...d.infoRequests,
          ManagerInfoRequest(message: message, requestedAt: now),
        ],
      ),
    );
  }

  @override
  Future<void> receive({
    required String returnId,
    required String taskId,
    required String requestId,
    required List<ManagerReturnItem> items,
  }) => _mutate(
    returnId,
    requestId,
    ReturnRequestStatus.returningToStore,
    (d, now) => d.copyWith(
      status: ReturnRequestStatus.underInspection,
      inspectionStartedAt: now,
      pickupTask: _task(
        d.pickupTask!.taskId,
        'returned_to_store',
        handover: true,
      ),
    ),
  );

  @override
  Future<void> acceptInspection({
    required String returnId,
    required String requestId,
    required List<ManagerInspectionLine> lines,
    required List<String> evidencePaths,
  }) => _mutate(
    returnId,
    requestId,
    ReturnRequestStatus.underInspection,
    (d, now) => d.copyWith(
      status: ReturnRequestStatus.awaitingRefund,
      inspectedAt: now,
      inspectionEvidencePaths: evidencePaths,
      returnItems: [
        for (final i in d.returnItems)
          ManagerReturnItem(
            returnItemId: i.returnItemId,
            orderItemId: i.orderItemId,
            name: i.name,
            quantityToCollect: i.quantityToCollect,
            quantityCollected: i.quantityCollected,
            sellableQuantity: lines
                .firstWhere((l) => l.returnItemId == i.returnItemId)
                .sellableQuantity,
            damagedQuantity: lines
                .firstWhere((l) => l.returnItemId == i.returnItemId)
                .damagedQuantity,
          ),
      ],
    ),
  );

  @override
  Future<void> rejectInspection({
    required String returnId,
    required String requestId,
    required String reason,
    required List<String> evidencePaths,
  }) => _mutate(
    returnId,
    requestId,
    ReturnRequestStatus.underInspection,
    (d, now) => d.copyWith(
      status: ReturnRequestStatus.awaitingRedelivery,
      inspectedAt: now,
      decisionReason: reason,
      inspectionEvidencePaths: evidencePaths,
    ),
  );

  @override
  Future<void> recordRefund({
    required String returnId,
    required String requestId,
    required int amountVnd,
    required DateTime transferredAt,
    required String evidencePath,
  }) async {
    final d = _detail[returnId]!;
    if (amountVnd != d.refundAmountVnd) {
      throw const ReturnRequestFailure(ReturnRequestFailureCode.amountMismatch);
    }
    await _mutate(
      returnId,
      requestId,
      ReturnRequestStatus.awaitingRefund,
      (d, now) => d.copyWith(
        status: ReturnRequestStatus.refunded,
        closedAt: now,
        refund: ManagerRefundRecord(
          amountVnd: amountVnd,
          refundedAt: transferredAt.toUtc(),
          evidencePath: evidencePath,
        ),
      ),
    );
  }

  @override
  Future<void> assignRedelivery({
    required String returnId,
    required String requestId,
    required String shipperId,
  }) => _mutate(
    returnId,
    requestId,
    ReturnRequestStatus.awaitingRedelivery,
    (d, now) => d.copyWith(
      redeliveryTask: ManagerReturnPickupTask(
        taskId: _sub(d.returnId, 779),
        status: 'assigned',
        shipperId: shipperId,
        shipperName: _shippers.firstWhere((s) => s.shipperId == shipperId).name,
        assignedAt: now,
      ),
    ),
  );
}
