import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../domain/models/return_request_context.dart';
import '../../domain/models/return_request_failure.dart';
import '../view_models/create_return_state.dart';
import '../view_models/return_request_flow_view_model.dart';
import '../view_models/return_request_providers.dart';
import '../widgets/create_return_sections.dart';
import 'create_return_page.dart';
import 'return_request_details_page.dart';

/// Route entry for MH13 (`/customer/orders/:orderId/return`).
///
/// Loads the owned order from Supabase, renders step 1 and pushes step 2 on
/// top so that going back keeps both steps' input.
class ReturnRequestFlowPage extends ConsumerWidget {
  const ReturnRequestFlowPage({
    required this.orderId,
    required this.onExit,
    super.key,
  });

  final String orderId;

  /// Leaves the flow (back from step 1, or "Xong" after success).
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contextValue = ref.watch(returnRequestContextProvider(orderId));
    // Keep the draft alive for the whole flow, including while step 2 is
    // pushed on top of this page.
    final flow = ref.watch(returnRequestFlowProvider(orderId));

    return contextValue.when(
      skipLoadingOnRefresh: true,
      loading: () => const _FlowStatus(
        key: ValueKey('mh13-loading'),
        child: CircularProgressIndicator(),
      ),
      error: (error, _) => _FlowStatus(
        key: const ValueKey('mh13-load-error'),
        onBack: onExit,
        message: _loadErrorMessage(error),
        actionLabel: 'Thử lại',
        onAction: () => ref.invalidate(returnRequestContextProvider(orderId)),
      ),
      data: (data) {
        final overview = returnOrderOverviewFromContext(data);
        final blocked = flow.phase != ReturnSubmitPhase.succeeded
            ? switch (data.eligibility) {
                ReturnEligibility.notDelivered =>
                  'Đơn chưa giao thành công nên chưa thể trả hàng.',
                ReturnEligibility.activeReturnExists =>
                  'Đơn này đã có yêu cầu trả hàng đang được xử lý.',
                _ => null,
              }
            : null;
        if (overview == null || blocked != null) {
          return _FlowStatus(
            key: const ValueKey('mh13-blocked'),
            onBack: onExit,
            message:
                blocked ?? 'Đơn chưa giao thành công nên chưa thể trả hàng.',
            actionLabel: 'Quay lại',
            onAction: onExit,
          );
        }
        return CreateReturnPage(
          order: overview,
          initialReason: flow.draft.reason,
          onBack: onExit,
          onContinue: (reason) {
            ref
                .read(returnRequestFlowProvider(orderId).notifier)
                .setReason(reason);
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ReturnRequestDetailsPage(
                  orderId: orderId,
                  totalPaidVnd: data.totalPaidVnd,
                  onFinished: onExit,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

String _loadErrorMessage(Object error) {
  if (error is ReturnRequestFailure) {
    return switch (error.code) {
      ReturnRequestFailureCode.unexpected =>
        'Không tải được thông tin đơn hàng.',
      _ => error.message,
    };
  }
  return 'Không tải được thông tin đơn hàng.';
}

class _FlowStatus extends StatelessWidget {
  const _FlowStatus({
    super.key,
    this.child,
    this.message,
    this.actionLabel,
    this.onAction,
    this.onBack,
  }) : assert(child != null || message != null);

  final Widget? child;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return AppTheme.notificationsScope(
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Column(
            children: [
              CreateReturnHeader(
                stepLabel: CreateReturnPage.stepLabel,
                onBack: onBack ?? () => Navigator.maybePop(context),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child:
                        child ??
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              message!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.45,
                                color: AppColors.charcoal,
                              ),
                            ),
                            if (actionLabel != null) ...[
                              const SizedBox(height: 16),
                              OutlinedButton(
                                onPressed: onAction,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.ink,
                                  shape: const StadiumBorder(),
                                ),
                                child: Text(actionLabel!),
                              ),
                            ],
                          ],
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
