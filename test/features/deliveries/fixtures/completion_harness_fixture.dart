// P05.2 TEST-ONLY provider/widget bridge. No runtime routes import this file.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/delivery_phone_dialer.dart';

import 'completion_panel_fixture.dart';
import 'outbound_completion_fixture.dart';

class CompletionHarnessFixture extends ConsumerWidget {
  const CompletionHarnessFixture({
    super.key,
    required this.taskId,
    this.dialer,
  });
  final String taskId;
  final DeliveryPhoneDialer? dialer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = fixtureOutboundCompletionViewModelProvider(taskId);
    final state = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    final revision = vm.sessionRevisionForFixture;
    return CompletionPanelFixture(
      key: ValueKey((taskId, state.session)),
      details: state.details.asData?.value,
      canComplete: state.canComplete,
      busy: state.busy,
      errorMessage: state.error == null
          ? null
          : completionFailureText(
              state.error!.code,
              uncertain: state.pendingCommand != null,
            ),
      onRetry:
          !state.actionsDenied &&
              (state.pendingCommand != null ||
                  state.error != null ||
                  state.requiresReadRetry)
          ? vm.retry
          : null,
      retryLabel: state.pendingCommand != null
          ? 'Thử lại cùng yêu cầu'
          : 'Đọc lại dữ liệu',
      onConfirmed:
          ({
            required receivedAllItems,
            required receivedFullCod,
            required displayedAmountVnd,
          }) async {
            if (!context.mounted || vm.sessionRevisionForFixture != revision) {
              return;
            }
            await vm.submit(
              receivedAllItems: receivedAllItems,
              receivedFullCod: receivedFullCod,
              displayedAmountVnd: displayedAmountVnd,
            );
          },
      dialer: state.session.active && !state.actionsDenied ? dialer : null,
    );
  }
}

String completionFailureText(
  OutboundCommandFailureCode code, {
  required bool uncertain,
}) => switch (code) {
  OutboundCommandFailureCode.timeout || OutboundCommandFailureCode.network =>
    uncertain
        ? 'Chưa xác định kết quả. Thử lại cùng request ID và số tiền đã xác nhận.'
        : 'Không thể đọc lại task/cache. Thử lại thao tác đọc.',
  OutboundCommandFailureCode.permissionDenied =>
    'Bạn không có quyền giao thành công.',
  OutboundCommandFailureCode.staleAssignment => 'Phân công đã thay đổi.',
  OutboundCommandFailureCode.staleState =>
    'Trạng thái đã thay đổi. Cần đọc lại dữ liệu.',
  OutboundCommandFailureCode.sessionExpired => 'Phiên đăng nhập đã hết hạn.',
  OutboundCommandFailureCode.dependencyUnavailable =>
    'Completion API live chưa sẵn sàng.',
  OutboundCommandFailureCode.invalidData =>
    'Thông tin xác nhận hoặc số tiền đã thay đổi.',
  OutboundCommandFailureCode.unexpected => 'Không thể thực hiện yêu cầu.',
};
