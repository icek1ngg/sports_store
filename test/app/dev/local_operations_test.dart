import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/demo/data/local_demo_store.dart';
import 'package:sports_store/app/dev/data/local_operations.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/returns/domain/models/return_reason.dart';
import 'package:sports_store/features/returns/domain/models/return_request_submission.dart';

void main() {
  test('assigned shipper projection shares order/COD snapshots and denies customer/foreign task', () async {
    final store = LocalDemoStore(account: DemoAccount.shipper);
    final ops = LocalOperations(store);
    final tasks = await ops.listTasks();
    expect(tasks, isNotEmpty);
    final task = await ops.getTaskDetails(tasks.first.taskId);
    final canonical = store.localOperationalOrder(task.task.orderId!);
    expect(task.task.destination!.address, canonical.order.addressDetail);
    expect(task.items.first.productName, canonical.items.first.productName);
    final cod = await ops.listCollections();
    expect(cod, isNotEmpty);
    await expectLater(
      ops.getTaskDetails('90000000-0000-4000-8000-000000000001'),
      throwsA(anything),
    );
    store.switchAccount(DemoAccount.customerA);
    await expectLater(ops.listTasks(), throwsA(anything));
  });
  test('return submission, manager decision and customer tracking share state without erasing COD', () async {
    final store = LocalDemoStore()..enableLocalReturns = true;
    final returns = LocalReturns(store);
    final id = LocalDemoStore.orderId(7);
    const request = '93000000-0000-4000-8000-000000000001';
    final before = await store.orders.getOrderDetails(id);
    expect((await returns.requests.loadContext(id)).canSubmitReturn, isTrue);
    final path = await returns.requests.uploadVideo(
      orderId: id,
      requestId: request,
      video: ReturnVideoFile(
        name: 'unit_fixture.mp4',
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'video/mp4',
      ),
    );
    final command = ReturnRequestCommand(
      orderId: id,
      requestId: request,
      reason: ReturnReason.defective,
      description: 'Kiểm tra hàng bị lỗi',
      videoObjectPath: path,
      bankName: 'Ngân hàng kiểm thử',
      accountNumber: '00000000',
      accountHolder: 'Khách hàng',
    );
    final ack = await returns.requests.submit(command);
    expect(
      (await returns.requests.submit(command)).returnRequestId,
      ack.returnRequestId,
    );
    expect(
      (await store.orders.getOrderDetails(id)).returnSummaries.single.returnId,
      ack.returnRequestId,
    );
    store.switchAccount(DemoAccount.customerC);
    await expectLater(
      returns.tracking.load(ack.returnRequestId),
      throwsA(anything),
    );
    store.switchAccount(DemoAccount.managerB);
    expect(
      (await returns.manager.list()).items.single.returnId,
      ack.returnRequestId,
    );
    await returns.manager.reject(
      returnId: ack.returnRequestId,
      requestId: '94000000-0000-4000-8000-000000000001',
      reason: 'Thông tin chưa hợp lệ',
    );
    store.switchAccount(DemoAccount.customerA);
    expect(
      (await returns.tracking.load(ack.returnRequestId)).decisionReason,
      'Thông tin chưa hợp lệ',
    );
    final after = await store.orders.getOrderDetails(id);
    expect(after.order.status, OrderStatus.delivered);
    expect(
      after.codSummary!.collectedAmountVnd,
      before.codSummary!.collectedAmountVnd,
    );
  });
}
