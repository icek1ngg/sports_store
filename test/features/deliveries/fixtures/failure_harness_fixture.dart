// P07.3 TEST-ONLY Riverpod/UI bridge. Not registered in the application.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_failure_command.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';

import 'failure_panel_fixture.dart';
import 'outbound_failure_fixture.dart';

class FailureHarnessFixture extends ConsumerWidget {
  const FailureHarnessFixture({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = fixtureOutboundFailureViewModelProvider(taskId);
    final state = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    final revision = vm.sessionRevisionForFixture;
    return FailurePanelFixture(
      details: state.details.asData?.value,
      eligible: state.eligible,
      busy: state.busy,
      sessionRevision: revision,
      onConfirmed: (reason, description) async {
        if (!context.mounted || revision != vm.sessionRevisionForFixture) {
          return;
        }
        await vm.submit(
          reason: OutboundFailureReason.fromValue(reason),
          description: description,
        );
      },
      errorMessage: state.error == null
          ? null
          : _failureText(state.error!.code),
      resultLabel: !state.reported || state.disposition == null
          ? null
          : switch (state.disposition!) {
              OutboundFailureDisposition.managerDecision =>
                'Chờ quản lý quyết định',
              OutboundFailureDisposition.storeReturnPending =>
                'Chờ hoàn về cửa hàng',
            },
      onRetry:
          !state.actionsDenied &&
              !state.busy &&
              (state.pendingCommand != null ||
                  state.requiresReadRetry ||
                  state.error != null)
          ? vm.retry
          : null,
      retryLabel: state.pendingCommand != null
          ? 'Thử lại cùng yêu cầu'
          : 'Đọc lại dữ liệu',
    );
  }
}

String _failureText(OutboundCommandFailureCode code) => switch (code) {
  OutboundCommandFailureCode.timeout || OutboundCommandFailureCode.network => 'Kết nối bị gián đoạn. Kết quả có thể chưa được xác định; thử lại theo yêu cầu đang giữ.',
  OutboundCommandFailureCode.permissionDenied =>
    'Bạn không có quyền báo thất bại.',
  OutboundCommandFailureCode.staleState =>
    'Trạng thái đã thay đổi. Cần đọc lại dữ liệu.',
  OutboundCommandFailureCode.staleAssignment => 'Phân công đã thay đổi.',
  OutboundCommandFailureCode.sessionExpired => 'Phiên đăng nhập đã hết hạn.',
  OutboundCommandFailureCode.dependencyUnavailable =>
    'API báo giao thất bại chưa sẵn sàng.',
  OutboundCommandFailureCode.invalidData =>
    'Dữ liệu yêu cầu hoặc phản hồi không hợp lệ.',
  OutboundCommandFailureCode.unexpected =>
    'Không thể thực hiện yêu cầu. Vui lòng thử lại.',
};
